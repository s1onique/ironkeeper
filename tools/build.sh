#!/bin/sh
# Build every Ironkeeper artefact with the pinned toolchain.
#
#   usage: tools/build.sh [nimble|nim] ...
#
# The script exists so that CI and a developer workstation run exactly the
# same compiler invocations. It does not introduce a second build system:
# it only drives `nim c` with the flags that the project has chosen.
#
# Environment:
#   NIM              path to the nim binary (default: nim from PATH)
#   IRK_DEPS_PATH    extra --path entries, e.g. the location of a vendored
#                    jschema checkout
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

NIM=${NIM:-nim}
DEPS_PATH=${IRK_DEPS_PATH:-}

# The test harness lives in tests/unit and is shared by every layer.
PATHS="--path:$ROOT/src --path:$ROOT/tests/unit --path:$ROOT/tests/contract --path:$ROOT/tests/integration"
if [ -n "$DEPS_PATH" ]; then
  PATHS="$PATHS --path:$DEPS_PATH"
fi

COMMON="--mm:orc --hints:off $PATHS"

mkdir -p build

build_one() {
  echo "==> building $1 -> $2"
  # shellcheck disable=SC2086
  $NIM c $COMMON ${3:-} -o:"$2" "$1"
}

# The application is built in release mode with the ORC memory manager.
# The test binaries are built in the default mode, so that assertions and
# stack traces remain available when a test fails.
build_one src/ironkeeper.nim build/ironkeeper "-d:release --opt:speed"
build_one tests/unit/all_unit_tests.nim build/unit_tests
build_one tests/contract/all_contract_tests.nim build/contract_tests
build_one tests/integration/all_integration_tests.nim build/integration_tests

echo "==> build complete"
