#!/usr/bin/env bash
# The independent validation gate.
#
# A *second*, independent implementation (`check-jsonschema`) validates:
#
#   1. every repository schema against the Draft 2020-12 metaschema, and
#   2. the machine-readable documents the binary produces against the
#      repository schemas.
#
# The independent implementation is what makes the runtime validator's
# result trustworthy: if the two disagree, the disagreement fails the gate.
#
# Every mandatory command is run through `gate_run`, so a failing
# validation fails the gate even when later validations succeed.
#
# Environment:
#   IRK_VALIDATOR   path to the independent validator executable
#                   (default: check-jsonschema from PATH)

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# shellcheck source=tools/gate.sh
. "$ROOT/tools/gate.sh"

VALIDATOR="${IRK_VALIDATOR:-check-jsonschema}"
OUT_DIR="${IRK_CHECK_OUT_DIR:-$ROOT/out}"
mkdir -p "$OUT_DIR"

FAILED=()

record() {
  local label="$1"
  shift
  if gate_run "$label" "$@"; then
    return 0
  fi
  FAILED+=("$label")
  return 0
}

# The independent validator must exist. A missing validator is a gate
# failure, never a silently skipped check.
if ! command -v "$VALIDATOR" > /dev/null 2>&1; then
  if [ ! -x "$VALIDATOR" ]; then
    echo "gate: FAIL independent-validator: executable not found: ${VALIDATOR}" >&2
    exit 1
  fi
fi

echo "=== repository schemas are valid Draft 2020-12 schemas ==="
# Every repository schema is meta-validated, not a hand-picked subset.
# The list is derived from the schemas directory, so a new schema cannot
# be added without being covered.
for schema_path in schemas/v1/*.schema.json; do
  name=$(basename "$schema_path" .schema.json)
  record "metaschema-${name}" "$VALIDATOR" --check-metaschema "$schema_path"
done

echo "=== the example configuration satisfies the configuration contract ==="
record example-config "$VALIDATOR" --schemafile schemas/v1/config.schema.json examples/ironkeeper.json

echo "=== the generated machine-readable output satisfies its contract ==="
# The binary is a prerequisite. If it is missing the gate fails; it is not
# treated as "nothing to check".
if [ ! -x "$ROOT/build/ironkeeper" ]; then
  echo "gate: FAIL independent-validator: build/ironkeeper is missing; run tools/build.sh first" >&2
  exit 1
fi

# The documents are generated *outside* `gate_run`, because `gate_run`
# redirects the command's stdout into a log file. A generation failure is
# itself a failure.
# generate <label> <output> <expected-exit-status> <command> ...
#
# The command's stdout is the generated document and its stderr is the
# log. The *expected exit status* is part of the contract: a command that
# was expected to succeed and did not is a failure, and so is a command
# that was expected to fail and did not. A generated document that is
# missing or empty is a failure.
generate() {
  local label="$1"
  local output="$2"
  local expected="$3"
  shift 3
  local log="$GATE_LOG_DIR/${label}.log"
  set +e
  "$@" > "$output" 2> "$log"
  local status=$?
  set -e
  cat "$log" || true
  if [ "$status" -ne "$expected" ]; then
    echo "gate: FAIL ${label} (exit ${status}, expected ${expected}); log: ${log}" >&2
    FAILED+=("$label")
    return 0
  fi
  if [ ! -s "$output" ]; then
    echo "gate: FAIL ${label} produced no document; log: ${log}" >&2
    FAILED+=("$label")
    return 0
  fi
  echo "gate: ok   ${label} (${output}, exit ${status})"
  return 0
}

generate generate-config-report "$OUT_DIR/config-report.json" 0 \
  "$ROOT/build/ironkeeper" config validate --file examples/ironkeeper.json --json
generate generate-version "$OUT_DIR/version.json" 0 \
  "$ROOT/build/ironkeeper" version --json

# The generated storage documents are validated independently as well. The
# documents are produced by the binary against the repository-owned
# synthetic fixture tree, so the check needs no storage device.
STORAGE_ENV=(IRONKEEPER_SYSFS_ROOT="$ROOT/tests/fixtures/storage/sys"
             IRONKEEPER_DEV_ROOT="$ROOT/tests/fixtures/storage/dev"
             IRONKEEPER_UDEV_ROOT="$ROOT/tests/fixtures/storage/run/udev/data"
             IRONKEEPER_TEST_TOOL_DIR="$ROOT/tests/fixtures/storage/tools")

generate generate-inventory "$OUT_DIR/inventory.json" 0 \
  env "${STORAGE_ENV[@]}" "$ROOT/build/ironkeeper" inventory list --json
record crosscheck-inventory "$VALIDATOR" --schemafile schemas/v1/inventory.schema.json "$OUT_DIR/inventory.json"

generate generate-observation "$OUT_DIR/observation.json" 0 \
  env "${STORAGE_ENV[@]}" "$ROOT/build/ironkeeper" device inspect \
    --wwn 5000c500a1b2c3d4 --smart --capacity --allow-wake --json
record crosscheck-observation "$VALIDATOR" --schemafile schemas/v1/observation.schema.json "$OUT_DIR/observation.json"

if [ "${#FAILED[@]}" -eq 0 ]; then
  # The output of `config validate --json` is a *report*, so it is
  # validated against the report contract.
  record crosscheck-config-report "$VALIDATOR" --schemafile schemas/v1/report.schema.json "$OUT_DIR/config-report.json"
  record crosscheck-version "$VALIDATOR" --schemafile schemas/v1/version.schema.json "$OUT_DIR/version.json"
  # The schema index is a public machine-readable output too, and is
  # covered by its own contract.
  generate generate-schemaindex "$OUT_DIR/schemaindex.json" 0 \
    "$ROOT/build/ironkeeper" schema list --json
  record crosscheck-schemaindex "$VALIDATOR" --schemafile schemas/v1/schemaindex.schema.json "$OUT_DIR/schemaindex.json"

  # The configuration report that the gate just generated is fed back
  # into `report validate --json`. The result is a *validation* document,
  # and it is validated against the validation contract. No second,
  # approximate producer is used: the same binary produces both.
  generate generate-validation "$OUT_DIR/validation.json" 0 \
    "$ROOT/build/ironkeeper" report validate --file "$OUT_DIR/config-report.json" --json
  record crosscheck-validation "$VALIDATOR" --schemafile schemas/v1/validation.schema.json "$OUT_DIR/validation.json"

  # A **truncated** report is validated independently as well. The
  # configuration below carries more unknown members than the findings
  # collection can hold, so the produced report is truncated: one slot is
  # reserved for the marker, and the rest are dropped. The independent
  # implementation checks that the truncated document still satisfies the
  # report contract, and that it does not claim PASS.
  python3 - "$OUT_DIR/many-findings.json" <<'PYGEN'
import json, sys
doc = {
  "schema_version": 1,
  "daemon": {"state_directory": "/var/lib/ironkeeper", "socket_path": "/run/ironkeeper.sock"},
  "safety": {
    "require_explicit_enrollment": True,
    "allow_destructive_operations": False,
    "allow_tests_on_in_use_devices": False,
  },
}
for i in range(1100):
    doc["unknown_member_%04d" % i] = i
with open(sys.argv[1], "w") as handle:
    json.dump(doc, handle)
PYGEN
  generate generate-truncated-report "$OUT_DIR/truncated-report.json" 5 \
    "$ROOT/build/ironkeeper" config validate --file "$OUT_DIR/many-findings.json" --json
  record crosscheck-truncated-report "$VALIDATOR" --schemafile schemas/v1/report.schema.json "$OUT_DIR/truncated-report.json"
  # A truncated report must not carry an unsupported PASS claim.
  if grep -q '"verdict": "PASS"' "$OUT_DIR/truncated-report.json"; then
    echo "gate: FAIL truncated-report: a truncated report claims PASS" >&2
    FAILED+=("truncated-report-verdict")
  else
    echo "gate: ok   truncated-report (no unsupported PASS claim)"
  fi
  if grep -q '"findings.truncated"' "$OUT_DIR/truncated-report.json"; then
    echo "gate: ok   truncated-report (the truncation is marked)"
  else
    echo "gate: FAIL truncated-report: the truncation is not marked" >&2
    FAILED+=("truncated-report-marker")
  fi

  # The classified failure output is a public document too. A missing
  # file is a classified failure, and the error document it produces must
  # satisfy the error contract.
  # A missing input is a classified failure: the exit status is the
  # documented input-unavailable status, and the document on stdout is
  # the error contract.
  generate generate-error "$OUT_DIR/error.json" 3 \
    "$ROOT/build/ironkeeper" config validate --file "$OUT_DIR/does-not-exist.json" --json
  record crosscheck-error "$VALIDATOR" --schemafile schemas/v1/error.schema.json "$OUT_DIR/error.json"
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  gate_summarise "independent-check" "${FAILED[@]}" || exit 1
  exit 1
fi
gate_summarise "independent-check"
