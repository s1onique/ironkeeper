#!/usr/bin/env bash
# The regression check of the CI toolchain bootstrap.
#
# The predecessor ACT failed in CI because the bootstrap appended the
# toolchain directory to `$PATH` with `>>`:
#
#   echo "$RUNNER_TEMP/nim/nim-2.4.2/bin" >> "$PATH"
#
# PATH is a shell variable holding a colon-separated directory list, not
# an environment file. The redirection therefore created a file whose
# name was the whole value of PATH, and the shell then tried to execute
# it. The step failed before the compiler was ever used.
#
# This check runs the **production** bootstrap script
# (`tools/install_nim_toolchain.sh`) against a synthetic toolchain and
# asserts the properties the CI job depends on:
#
#   1. the compiler is on PATH afterwards;
#   2. the directory is written to `$GITHUB_PATH`, which is the file the
#      later steps read;
#   3. `$PATH` itself is never written to as a file;
#   4. a toolchain directory that does not exist is refused;
#   5. a compiler that reports the wrong version is refused.
#
# The check needs no network and no hardware.
#
# Exit status:
#   0  every property holds
#   1  at least one property does not hold

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/irk-bootstrap.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0

ok() { echo "ok   $1"; PASSED=$((PASSED + 1)); }
no() { echo "FAIL $1"; FAILED=$((FAILED + 1)); }

# A synthetic toolchain: a directory with an executable `nim` that reports
# the pinned version.
make_toolchain() {
  local dir="$1" version="$2"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/nim" <<EOF
#!/bin/sh
echo "Nim Compiler Version ${version} [Test: amd64]"
EOF
  chmod +x "$dir/bin/nim"
}

echo "=== the bootstrap puts the compiler on PATH and on GITHUB_PATH ==="
TC="$WORK/toolchain"
make_toolchain "$TC" "9.9.9"
export RUNNER_TEMP="$WORK/runner-temp"
mkdir -p "$RUNNER_TEMP"
export GITHUB_PATH="$WORK/github_path"
: > "$GITHUB_PATH"
export IRK_NIM_TOOLCHAIN_DIR="$TC/bin"
export NIM_VERSION="9.9.9"

# The bootstrap is *sourced* rather than executed, because PATH has to
# survive into the caller for the property to be observable.
# shellcheck source=tools/install_nim_toolchain.sh
( . ./tools/install_nim_toolchain.sh > "$WORK/install.out" 2>&1
  if command -v nim > /dev/null 2>&1; then
    echo "nim is on PATH"
  else
    echo "nim is NOT on PATH"
  fi
  if nim --version | grep -q "Nim Compiler Version 9.9.9"; then
    echo "the compiler runs and reports the pinned version"
  else
    echo "the compiler does not report the pinned version"
  fi
) > "$WORK/props.out" 2>&1

if grep -q "nim is on PATH" "$WORK/props.out"; then
  ok "the bootstrap puts the compiler on PATH"
else
  no "the bootstrap puts the compiler on PATH"
fi
if grep -q "the compiler runs and reports the pinned version" "$WORK/props.out"; then
  ok "the compiler runs after the bootstrap"
else
  no "the compiler runs after the bootstrap"
fi
if grep -qx "$TC/bin" "$GITHUB_PATH"; then
  ok "the toolchain directory is written to GITHUB_PATH"
else
  no "the toolchain directory is written to GITHUB_PATH"
fi

echo
echo "=== the bootstrap does not write to PATH as if it were a file ==="
# The defect wrote to a file named after the whole value of PATH. If that
# happened, a file whose name contains the PATH value would appear.
STRAY=$(find "$WORK" -maxdepth 3 -type f -name '*:*' 2>/dev/null | head -1)
if [ -n "$STRAY" ]; then
  no "a file was created by writing to PATH: $STRAY"
else
  ok "no file was created by writing to PATH"
fi
# And the source of the bootstrap must not contain the defective form.
if grep -n '>> *"\$PATH"' tools/install_nim_toolchain.sh; then
  no "the bootstrap still appends to PATH with a redirection"
else
  ok "the bootstrap does not append to PATH with a redirection"
fi

echo
echo "=== the bootstrap refuses a missing toolchain ==="
export IRK_NIM_TOOLCHAIN_DIR="$WORK/does-not-exist/bin"
set +e
( . ./tools/install_nim_toolchain.sh > "$WORK/missing.out" 2>&1 )
MISSING_STATUS=$?
set -e
# The subshell's status is the status of its last command, so the script's
# own exit status is read from the output instead.
if grep -q "the compiler is not executable" "$WORK/missing.out" ||
   grep -q "the toolchain directory does not exist" "$WORK/missing.out"; then
  ok "a missing compiler is refused"
else
  no "a missing compiler is refused"
  cat "$WORK/missing.out"
fi
if [ "$MISSING_STATUS" -ne 0 ]; then
  ok "a missing compiler fails the bootstrap"
else
  no "a missing compiler fails the bootstrap"
fi

echo
echo "=== the bootstrap refuses a compiler with the wrong version ==="
BAD="$WORK/bad-toolchain"
make_toolchain "$BAD" "1.0.0"
export IRK_NIM_TOOLCHAIN_DIR="$BAD/bin"
set +e
( . ./tools/install_nim_toolchain.sh > "$WORK/bad.out" 2>&1 )
set -e
if grep -q "unexpected compiler version" "$WORK/bad.out"; then
  ok "a compiler with the wrong version is refused"
else
  no "a compiler with the wrong version is refused"
  cat "$WORK/bad.out"
fi

echo
echo "=== the CI workflow uses the shared bootstrap ==="
if grep -q 'install_nim_toolchain.sh' .github/workflows/ci.yml; then
  ok "the workflow calls the shared bootstrap"
else
  no "the workflow calls the shared bootstrap"
fi
if grep -n '>> *"\$PATH"' .github/workflows/ci.yml; then
  no "the workflow still appends to PATH with a redirection"
else
  ok "the workflow does not append to PATH with a redirection"
fi

echo
echo "=== summary ==="
echo "passed: ${PASSED}  failed: ${FAILED}"
if [ "$FAILED" -gt 0 ]; then
  echo "RESULT: FAIL — the CI bootstrap does not hold"
  exit 1
fi
echo "RESULT: PASS — the CI bootstrap holds"
exit 0
