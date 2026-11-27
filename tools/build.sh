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
# The dependency path is taken from the environment when it is set, and
# otherwise from the default Nimble location that the dependency-resolution
# step installs into. Deriving it here means the build does not depend on
# the caller having exported an environment variable.
DEPS_PATH=${IRK_DEPS_PATH:-$HOME/.nimble/pkgs2/jschema-0.1.0/src}

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
#
# ## The two application variants
#
# The application is built **twice**, and the two binaries are different
# artefacts:
#
#   * `build/ironkeeper` is the **production** build. It has no test
#     seams: it does not read `IRONKEEPER_TEST_TOOL_DIR` and it does not
#     read the discovery-root overrides, so an environment variable cannot
#     make it execute an arbitrary program or point it at a synthetic
#     tree.
#   * `build/ironkeeper-testing` is the **test-enabled** build. It is
#     compiled with the `ironkeeperTesting` definition and therefore
#     honours the controlled fixture seams. It exists so that the
#     *production* code path can be exercised against fixtures; it is
#     never shipped and never used for hardware qualification.
#
# The two binaries are never interchangeable: each one reports its own
# variant through `ironkeeper version --json`, and the evidence manifest
# records it.
build_one src/ironkeeper.nim build/ironkeeper "-d:release --opt:speed"
build_one src/ironkeeper.nim build/ironkeeper-testing \
  "-d:release --opt:speed -d:ironkeeperTesting"
build_one tests/unit/all_unit_tests.nim build/unit_tests
build_one tests/contract/all_contract_tests.nim build/contract_tests
build_one tests/integration/all_integration_tests.nim build/integration_tests

echo "==> build complete"
