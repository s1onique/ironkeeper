#!/usr/bin/env bash
# The Ironkeeper build, test and type-check gate.
#
# This is the authoritative gate. It is invoked by CI *and* by a developer
# workstation, so there is only one implementation of the rule.
#
# Every mandatory command is run through `gate_run`, which returns that
# command's own exit status. The gate keeps a list of failed labels and
# reports it at the end; the verdict is derived from that list, so a
# later successful command can never mask an earlier failure.
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
DEPS_PATH="${IRK_DEPS_PATH:-}"
PATHS="--path:$ROOT/src --path:$ROOT/tests/unit --path:$ROOT/tests/contract --path:$ROOT/tests/integration"
if [ -n "$DEPS_PATH" ]; then
  PATHS="$PATHS --path:$DEPS_PATH"
fi

FAILED=()

# record <label> <command> [args...]
#
# Run a mandatory command and remember its label when it fails.
record() {
  local label="$1"
  shift
  if gate_run "$label" "$@"; then
    return 0
  fi
  FAILED+=("$label")
  return 0
}

echo "=== type-check ==="
record typecheck-main nim check --mm:orc --path:src ${DEPS_PATH:+--path:"$DEPS_PATH"} src/ironkeeper.nim
record typecheck-unit nim check --mm:orc --path:src --path:tests/unit ${DEPS_PATH:+--path:"$DEPS_PATH"} tests/unit/all_unit_tests.nim
record typecheck-contract nim check --mm:orc --path:src --path:tests/unit --path:tests/contract ${DEPS_PATH:+--path:"$DEPS_PATH"} tests/contract/all_contract_tests.nim
record typecheck-integration nim check --mm:orc --path:src --path:tests/unit --path:tests/integration ${DEPS_PATH:+--path:"$DEPS_PATH"} tests/integration/all_integration_tests.nim

echo "=== build ==="
record build tools/build.sh

echo "=== test suites ==="
record test-unit ./build/unit_tests
record test-contract ./build/contract_tests
record test-integration ./build/integration_tests

if [ "${#FAILED[@]}" -gt 0 ]; then
  gate_summarise "build-test" "${FAILED[@]}" || exit 1
  exit 1
fi
gate_summarise "build-test"
