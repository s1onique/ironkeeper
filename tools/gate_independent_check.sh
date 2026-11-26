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
for s in config report error version; do
  record "metaschema-${s}" "$VALIDATOR" --check-metaschema "schemas/v1/${s}.schema.json"
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
generate() {
  local label="$1"
  local output="$2"
  shift 2
  local log="$GATE_LOG_DIR/${label}.log"
  set +e
  "$@" > "$output" 2> "$log"
  local status=$?
  set -e
  cat "$log" || true
  if [ "$status" -ne 0 ]; then
    echo "gate: FAIL ${label} (exit ${status}); log: ${log}" >&2
    FAILED+=("$label")
    return 0
  fi
  echo "gate: ok   ${label} (${output})"
  return 0
}

generate generate-config-report "$OUT_DIR/config-report.json" \
  "$ROOT/build/ironkeeper" config validate --file examples/ironkeeper.json --json
generate generate-version "$OUT_DIR/version.json" \
  "$ROOT/build/ironkeeper" version --json

if [ "${#FAILED[@]}" -eq 0 ]; then
  # The output of `config validate --json` is a *report*, so it is
  # validated against the report contract.
  record crosscheck-config-report "$VALIDATOR" --schemafile schemas/v1/report.schema.json "$OUT_DIR/config-report.json"
  record crosscheck-version "$VALIDATOR" --schemafile schemas/v1/version.schema.json "$OUT_DIR/version.json"
  # The schema index is a public machine-readable output too, and is
  # covered by its own contract.
  generate generate-schemaindex "$OUT_DIR/schemaindex.json" \
    "$ROOT/build/ironkeeper" schema list --json
  record crosscheck-schemaindex "$VALIDATOR" --schemafile schemas/v1/schemaindex.schema.json "$OUT_DIR/schemaindex.json"
  # The validation result document is produced against a *valid* report.
  # The repository does not carry one, so the document is validated
  # against its own contract by the contract test suite instead.
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  gate_summarise "independent-check" "${FAILED[@]}" || exit 1
  exit 1
fi
gate_summarise "independent-check"
