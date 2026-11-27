#!/usr/bin/env bash
# The non-vacuity gate of the storage observation subsystem.
#
# A test that passes whether or not the behaviour it is meant to pin down
# is present proves nothing. This gate therefore **reverses** each
# critical check, shows that the corresponding witness **fails**, and then
# restores the implementation.
#
# The gate never leaves a broken implementation behind: every mutation is
# reverted from a saved copy, and the suite is run again at the end to
# prove that the restored implementation is green.
#
# Environment:
#   NIM             path to the nim binary (default: nim from PATH)
#   IRK_DEPS_PATH   extra --path entries for the dependency
#   GATE_LOG_DIR    where the diagnostic logs are written

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# shellcheck source=tools/gate.sh
. "$ROOT/tools/gate.sh"

NIM="${NIM:-nim}"
DEPS_PATH="${IRK_DEPS_PATH:-$HOME/.nimble/pkgs2/jschema-0.1.0/src}"
DEPS_ARG=()
if [ -n "$DEPS_PATH" ]; then
  DEPS_ARG=(--path:"$DEPS_PATH")
fi

WORK="$(mktemp -d)"
FAILED=()
MUTATIONS=0

restore() {
  ## Restore every mutated file from its saved copy.
  ##
  ## The original path is recorded next to the saved copy, so the file is
  ## restored where it was, and a stray copy is never left behind.
  for saved in "$WORK"/*.saved; do
    [ -e "$saved" ] || continue
    local base
    base="$(basename "$saved" .saved)"
    if [ -e "$WORK/$base.path" ]; then
      cp "$saved" "$(cat "$WORK/$base.path")"
    fi
  done
}

trap restore EXIT

# mutate <file> <python-expression-file>
#
# The Python snippet receives the path of the file to mutate as its first
# argument. The file is saved before the mutation.
mutate() {
  local file="$1"
  local snippet="$2"
  local base
  base="$(basename "$file")"
  cp "$file" "$WORK/$base.saved"
  echo "$file" > "$WORK/$base.path"
  python3 "$snippet" "$file"
}

# The unit suite is rebuilt for every mutation, because the mutation is in
# the production code that the suite exercises.
build_unit() {
  local nimcache
  nimcache="$(mktemp -d)"
  $NIM c --mm:orc --hints:off --nimcache:"$nimcache" --path:src \
    --path:tests/unit "${DEPS_ARG[@]}" \
    -o:"$WORK/unit_tests" tests/unit/all_unit_tests.nim > "$WORK/build.log" 2>&1
  local status=$?
  rm -rf "$nimcache"
  return $status
}

# expect_unit_failure <label> <expected-witness-phrase>
#
# The mutation must make the suite fail, and the failure must name the
# witness that is expected to catch it.
expect_unit_failure() {
  local label="$1"
  local phrase="$2"
  set +e
  "$WORK/unit_tests" > "$WORK/$label.log" 2>&1
  local status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "gate: FAIL $label: the mutation did not make the suite fail" >&2
    FAILED+=("$label")
    return 0
  fi
  if ! grep -q "$phrase" "$WORK/$label.log"; then
    echo "gate: FAIL $label: the suite failed, but not on the expected witness" >&2
    echo "  expected witness: $phrase" >&2
    tail -20 "$WORK/$label.log" >&2
    FAILED+=("$label")
    return 0
  fi
  echo "gate: ok   $label (the witness failed as expected)"
}

echo "=== non-vacuity: identity conflict refusal ==="
cat > "$WORK/mutate_identity.py" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = """    if identity.conflicts.len > 0:
      identity.confidence = icAmbiguous"""
new = """    if identity.conflicts.len > 0:
      identity.confidence = icProbable"""
assert old in text, "the identity mutation anchor was not found"
open(path, "w").write(text.replace(old, new, 1))
PY
mutate src/ironkeeper/storage/identity.nim "$WORK/mutate_identity.py"
build_unit
expect_unit_failure identity-conflict "a duplicated world-wide name is ambiguous"
restore

echo "=== non-vacuity: exact counter precision ==="
cat > "$WORK/mutate_precision.py" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = """  var lead = 0
  while lead < result.len - 1 and result[lead] == '0':
    inc lead
  let trimmed = result[lead .. ^1]"""
new = """  let trimmed = result.strip(chars = {'0'})"""
assert old in text, "the precision mutation anchor was not found"
open(path, "w").write(text.replace(old, new, 1))
PY
mutate src/ironkeeper/storage/externaljson.nim "$WORK/mutate_precision.py"
build_unit
expect_unit_failure exact-precision "a counter with trailing zeros keeps every digit"
restore

echo "=== non-vacuity: a missing counter is never a zero ==="
cat > "$WORK/mutate_missing.py" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = """  outcomes.add Observation(name: name, status: osUnavailable, value: "",
                           unit: unit, source: source, sourceField: field,
                           collectedAt: collectedAt, reason: reason)"""
new = """  outcomes.add Observation(name: name, status: osObserved, value: "0",
                           unit: unit, source: source, sourceField: field,
                           collectedAt: collectedAt, reason: reason)"""
assert old in text, "the missing-counter mutation anchor was not found"
open(path, "w").write(text.replace(old, new, 1))
PY
mutate src/ironkeeper/storage/smartnorm.nim "$WORK/mutate_missing.py"
build_unit
expect_unit_failure missing-counter "a missing field is not fabricated as zero"
restore

echo "=== non-vacuity: the backend deadline is enforced ==="
cat > "$WORK/mutate_timeout.py" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = """    if now >= deadline:
      # The deadline is authoritative, including after the pipes reached
      # end of file: a child that closed both streams and kept running is
      # still terminated here.
      timedOut = true
      break"""
new = """    if now >= deadline:
      discard"""
assert old in text, "the timeout mutation anchor was not found"
open(path, "w").write(text.replace(old, new, 1))
PY
mutate src/ironkeeper/storage/procexec.nim "$WORK/mutate_timeout.py"
build_unit
expect_unit_failure backend-timeout "a timeout is classified as a timeout"
restore

echo "=== non-vacuity: the SMART exit bitmask is decoded ==="
cat > "$WORK/mutate_bitmask.py" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = """  result.failingStatus = (status and SmartBitFailingStatus) != 0"""
new = """  result.failingStatus = false"""
assert old in text, "the bitmask mutation anchor was not found"
open(path, "w").write(text.replace(old, new, 1))
PY
mutate src/ironkeeper/storage/smartstatus.nim "$WORK/mutate_bitmask.py"
build_unit
expect_unit_failure smart-bitmask "the failing-status bit is decoded"
restore

echo "=== non-vacuity: the SCSI protection mapping ==="
cat > "$WORK/mutate_protection.py" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = """  case pType
  of 0: ptType1
  of 1: ptType2
  of 2: ptType3
  else: ptReserved"""
new = """  case pType
  of 0: ptType1
  of 1: ptType2
  of 2: ptType3
  else: ptType0"""
assert old in text, "the protection mutation anchor was not found"
open(path, "w").write(text.replace(old, new, 1))
PY
mutate src/ironkeeper/storage/scsicap.nim "$WORK/mutate_protection.py"
build_unit
expect_unit_failure scsi-protection "PROT_EN 1 and P_TYPE 3 is reserved"
restore

# The compiled-CLI suite is built for the mutations that change the
# behaviour of the shipped binary.
build_integration() {
  local nimcache
  nimcache="$(mktemp -d)"
  # The compiled-CLI suite exercises the **shipped binaries**, so both
  # variants are rebuilt for the mutation.
  $NIM c --mm:orc --hints:off --nimcache:"$nimcache" --path:src \
    "${DEPS_ARG[@]}" -o:"$WORK/ironkeeper" src/ironkeeper.nim \
    > "$WORK/build.log" 2>&1 || { rm -rf "$nimcache"; return 1; }
  $NIM c --mm:orc --hints:off --nimcache:"$nimcache" -d:ironkeeperTesting \
    --path:src "${DEPS_ARG[@]}" -o:"$WORK/ironkeeper-testing" src/ironkeeper.nim \
    >> "$WORK/build.log" 2>&1 || { rm -rf "$nimcache"; return 1; }
  $NIM c --mm:orc --hints:off --nimcache:"$nimcache" --path:src \
    --path:tests/unit --path:tests/contract --path:tests/integration \
    "${DEPS_ARG[@]}" -o:"$WORK/integration_tests" \
    tests/integration/all_integration_tests.nim >> "$WORK/build.log" 2>&1
  local status=$?
  rm -rf "$nimcache"
  if [ "$status" -eq 0 ]; then
    mkdir -p "$ROOT/build"
    cp "$WORK/ironkeeper" "$ROOT/build/ironkeeper"
    cp "$WORK/ironkeeper-testing" "$ROOT/build/ironkeeper-testing"
  fi
  return $status
}

# expect_integration_failure <label> <expected-witness-phrase>
#
# The mutation must make the compiled-CLI suite fail, and the failure
# must name the witness that is expected to catch it.
expect_integration_failure() {
  local label="$1"
  local phrase="$2"
  set +e
  "$WORK/integration_tests" > "$WORK/$label.log" 2>&1
  local status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "gate: FAIL $label: the mutation did not make the suite fail" >&2
    FAILED+=("$label")
    return 0
  fi
  if ! grep -q "$phrase" "$WORK/$label.log"; then
    echo "gate: FAIL $label: the suite failed, but not on the expected witness" >&2
    echo "  expected witness: $phrase" >&2
    tail -20 "$WORK/$label.log" >&2
    FAILED+=("$label")
    return 0
  fi
  echo "gate: ok   $label (the witness failed as expected)"
}

echo "=== non-vacuity: the production binary has no test seams ==="
# The production build must not honour the test seams. The mutation
# makes the *production* build read the tool seam, and the witness that
# catches it is the seam-isolation witness of the compiled-CLI suite.
cat > "$WORK/mutate_seam.py" <<'PYSEAM'
import sys
path = sys.argv[1]
text = open(path).read()
old = """  when TestingBuild:
    let sysfs = getEnv(SysfsRootEnv)"""
new = """  when true:
    let sysfs = getEnv(SysfsRootEnv)"""
assert old in text, "the seam mutation anchor was not found"
open(path, "w").write(text.replace(old, new, 1))
PYSEAM
mutate src/ironkeeper/cli/storage.nim "$WORK/mutate_seam.py"
build_integration
expect_integration_failure production-seam "the production binary does not read the synthetic tree"
restore

echo "=== non-vacuity: the pipe stream identity is preserved ==="
cat > "$WORK/mutate_stream.py" <<'PYSTREAM'
import sys
path = sys.argv[1]
text = open(path).read()
old = """        let isOut = streamOf[i] == 0"""
new = """        let isOut = i == 0"""
assert old in text, "the stream mutation anchor was not found"
open(path, "w").write(text.replace(old, new, 1))
PYSTREAM
mutate src/ironkeeper/storage/procexec.nim "$WORK/mutate_stream.py"
build_unit
expect_unit_failure pipe-stream-identity "the standard error keeps its own data"
restore

echo "=== non-vacuity: the trailing zero of a capacity is conserved ==="
cat > "$WORK/mutate_capacity.py" <<'PYCAP'
import sys
path = sys.argv[1]
text = open(path).read()
old = """  let product = dec.mulSmall(a, b)
  (ok: product.ok, value: product.value)"""
new = """  let product = dec.mulSmall(a, b)
  var trimmed = product.value
  while trimmed.len > 0 and trimmed[^1] == '0':
    trimmed.setLen(trimmed.len - 1)
  (ok: product.ok, value: trimmed)"""
assert old in text, "the capacity mutation anchor was not found"
open(path, "w").write(text.replace(old, new, 1))
PYCAP
mutate src/ironkeeper/storage/scsicap.nim "$WORK/mutate_capacity.py"
build_unit
expect_unit_failure capacity-trailing-zero "the capacity conserves every digit"
restore

echo "=== non-vacuity: a missing protection field is never Type 0 ==="
cat > "$WORK/mutate_protection.py" <<'PYPROT'
import sys
path = sys.argv[1]
text = open(path).read()
old = """  if not evidence.protEnPresent:
    return ptMissing"""
new = """  if not evidence.protEnPresent:
    return ptType0"""
assert old in text, "the protection mutation anchor was not found"
open(path, "w").write(text.replace(old, new, 1))
PYPROT
mutate src/ironkeeper/storage/scsicap.nim "$WORK/mutate_protection.py"
build_unit
expect_unit_failure missing-protection "a missing protection field is never Type 0"
restore

echo "=== non-vacuity: the SMART exit bitmask is decoded ==="
cat > "$WORK/mutate_bitmask2.py" <<'PYBIT'
import sys
path = sys.argv[1]
text = open(path).read()
old = """  result.failingStatus = (status and SmartBitFailingStatus) != 0"""
new = """  result.failingStatus = false"""
assert old in text, "the bitmask mutation anchor was not found"
open(path, "w").write(text.replace(old, new, 1))
PYBIT
mutate src/ironkeeper/storage/smartstatus.nim "$WORK/mutate_bitmask2.py"
build_unit
expect_unit_failure smart-bitmask-2 "the bit 8 is decoded independently"
restore

echo "=== the restored implementation is green ==="
build_unit
set +e
"$WORK/unit_tests" > "$WORK/restored.log" 2>&1
status=$?
set -e
if [ "$status" -ne 0 ]; then
  echo "gate: FAIL restored-implementation: the suite is not green after the restore" >&2
  tail -20 "$WORK/restored.log" >&2
  FAILED+=("restored-implementation")
else
  echo "gate: ok   restored-implementation (the suite is green)"
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  gate_summarise "storage-non-vacuity" "${FAILED[@]}" || exit 1
  exit 1
fi
gate_summarise "storage-non-vacuity"
