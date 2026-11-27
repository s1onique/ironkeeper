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
# A later defect had the same shape: the bootstrap is *executed*, so its
# exported PATH belongs to the child process, and the verification of the
# toolchain in the same shell found nothing on PATH. The bootstrap is
# therefore executed here exactly as the workflow executes it, and the
# verification runs as the *following step* does, through `$GITHUB_PATH`.
#
# The check drives the **production** scripts:
# `tools/install_nim_toolchain.sh` and `tools/verify_nim_toolchain.sh`.
# Nothing is reimplemented here.
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

# A synthetic toolchain: a directory with an executable `nim` that
# reports the given version, and an executable `nimble`.
make_toolchain() {
  local dir="$1" version="$2" with_nimble="${3:-yes}"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/nim" <<EOF
#!/bin/sh
echo "Nim Compiler Version ${version} [Test: amd64]"
EOF
  chmod +x "$dir/bin/nim"
  if [ "$with_nimble" = "yes" ]; then
    cat > "$dir/bin/nimble" <<'EOF'
#!/bin/sh
echo "Nimble Version 0.14.2 [Test: amd64]"
EOF
    chmod +x "$dir/bin/nimble"
  fi
}

# run_step <name> <command...>
#
# Runs a command as a *workflow step* would: the PATH of the step is the
# PATH of the runner plus the directories that the earlier steps
# appended to `$GITHUB_PATH`.
run_step() {
  local name="$1"
  shift
  local path="$PATH"
  if [ -f "${GITHUB_PATH:-/dev/null}" ]; then
    while IFS= read -r entry; do
      [ -n "$entry" ] && path="$entry:$path"
    done < "${GITHUB_PATH}"
  fi
  env PATH="$path" "$@" > "$WORK/$name.out" 2>&1
  return $?
}

echo "=== the production invocation installs the toolchain ==="
TC="$WORK/toolchain"
make_toolchain "$TC" "9.9.9"
export RUNNER_TEMP="$WORK/runner-temp"
mkdir -p "$RUNNER_TEMP"
export GITHUB_PATH="$WORK/github_path"
: > "$GITHUB_PATH"
export IRK_NIM_TOOLCHAIN_DIR="$TC/bin"
export NIM_VERSION="9.9.9"

# The bootstrap is *executed*, exactly as the workflow executes it.
set +e
"$ROOT/tools/install_nim_toolchain.sh" > "$WORK/install.out" 2>&1
INSTALL_STATUS=$?
set -e
if [ "$INSTALL_STATUS" -eq 0 ]; then
  ok "the bootstrap succeeds for the pinned version"
else
  no "the bootstrap succeeds for the pinned version"
  cat "$WORK/install.out"
fi
if grep -q "^nim_version=9.9.9$" "$WORK/install.out"; then
  ok "the bootstrap reports the exact pinned version"
else
  no "the bootstrap reports the exact pinned version"
  cat "$WORK/install.out"
fi

echo
echo "=== the following workflow step resolves the intended toolchain ==="
set +e
run_step verify "$ROOT/tools/verify_nim_toolchain.sh"
VERIFY_STATUS=$?
set -e
if [ "$VERIFY_STATUS" -eq 0 ]; then
  ok "the verification step succeeds"
else
  no "the verification step succeeds"
  cat "$WORK/verify.out"
fi
if grep -q "^nim_path=$TC/bin/nim$" "$WORK/verify.out"; then
  ok "nim resolves to the intended toolchain"
else
  no "nim resolves to the intended toolchain"
  cat "$WORK/verify.out"
fi
if grep -q "^nimble_path=$TC/bin/nimble$" "$WORK/verify.out"; then
  ok "nimble resolves to the intended toolchain"
else
  no "nimble resolves to the intended toolchain"
  cat "$WORK/verify.out"
fi

echo
echo "=== an unrelated preinstalled toolchain is not accepted ==="
# A compiler that is earlier on PATH must not satisfy the verification.
OTHER="$WORK/other-toolchain"
make_toolchain "$OTHER" "9.9.9"
set +e
env PATH="$OTHER/bin:$PATH" IRK_NIM_TOOLCHAIN_DIR="$TC/bin" \
  NIM_VERSION="9.9.9" "$ROOT/tools/verify_nim_toolchain.sh" \
  > "$WORK/unrelated.out" 2>&1
UNRELATED_STATUS=$?
set -e
if [ "$UNRELATED_STATUS" -ne 0 ]; then
  ok "an unrelated compiler on PATH is refused"
else
  no "an unrelated compiler on PATH is refused"
  cat "$WORK/unrelated.out"
fi

echo
echo "=== a prefix-matching but incorrect version is refused ==="
# 9.9.90 starts with 9.9.9. A prefix comparison would accept it.
WRONG="$WORK/wrong-toolchain"
make_toolchain "$WRONG" "9.9.90"
: > "$GITHUB_PATH"
set +e
env IRK_NIM_TOOLCHAIN_DIR="$WRONG/bin" NIM_VERSION="9.9.9" \
  "$ROOT/tools/install_nim_toolchain.sh" > "$WORK/wrong.out" 2>&1
WRONG_STATUS=$?
set -e
if [ "$WRONG_STATUS" -ne 0 ]; then
  ok "a prefix-matching but incorrect version fails the bootstrap"
else
  no "a prefix-matching but incorrect version fails the bootstrap"
  cat "$WORK/wrong.out"
fi
if grep -q "unexpected compiler version" "$WORK/wrong.out"; then
  ok "the bootstrap names the version mismatch"
else
  no "the bootstrap names the version mismatch"
fi

echo
echo "=== a missing compiler fails ==="
: > "$GITHUB_PATH"
set +e
env IRK_NIM_TOOLCHAIN_DIR="$WORK/does-not-exist/bin" NIM_VERSION="9.9.9" \
  "$ROOT/tools/install_nim_toolchain.sh" > "$WORK/missing.out" 2>&1
MISSING_STATUS=$?
set -e
if [ "$MISSING_STATUS" -ne 0 ]; then
  ok "a missing compiler fails the bootstrap"
else
  no "a missing compiler fails the bootstrap"
  cat "$WORK/missing.out"
fi
if grep -qE "the compiler is not executable|the toolchain directory does not exist" \
     "$WORK/missing.out"; then
  ok "the bootstrap names the missing toolchain"
else
  no "the bootstrap names the missing toolchain"
fi

echo
echo "=== a missing nimble fails the toolchain verification ==="
NO_NIMBLE="$WORK/no-nimble-toolchain"
make_toolchain "$NO_NIMBLE" "9.9.9" no
: > "$GITHUB_PATH"
set +e
env PATH="$NO_NIMBLE/bin:$PATH" IRK_NIM_TOOLCHAIN_DIR="$NO_NIMBLE/bin" \
  NIM_VERSION="9.9.9" \
  "$ROOT/tools/verify_nim_toolchain.sh" > "$WORK/nonimble.out" 2>&1
NONIMBLE_STATUS=$?
set -e
if [ "$NONIMBLE_STATUS" -ne 0 ]; then
  ok "a missing nimble fails the toolchain verification"
else
  no "a missing nimble fails the toolchain verification"
  cat "$WORK/nonimble.out"
fi
if grep -q "nimble is not on PATH" "$WORK/nonimble.out"; then
  ok "the verification names the missing package manager"
else
  no "the verification names the missing package manager"
fi

echo
echo "=== the bootstrap does not write to PATH as if it were a file ==="
STRAY=$(find "$WORK" -maxdepth 3 -type f -name '*:*' 2>/dev/null | head -1)
if [ -n "$STRAY" ]; then
  no "a file was created by writing to PATH: $STRAY"
else
  ok "no file was created by writing to PATH"
fi
if grep -n '>> *"\$PATH"' tools/install_nim_toolchain.sh; then
  no "the bootstrap still appends to PATH with a redirection"
else
  ok "the bootstrap does not append to PATH with a redirection"
fi

echo
echo "=== the CI workflow uses the shared bootstrap and verifies it ==="
if grep -q 'install_nim_toolchain.sh' .github/workflows/ci.yml; then
  ok "the workflow calls the shared bootstrap"
else
  no "the workflow calls the shared bootstrap"
fi
if grep -q 'verify_nim_toolchain.sh' .github/workflows/ci.yml; then
  ok "the workflow verifies the toolchain in its own step"
else
  no "the workflow verifies the toolchain in its own step"
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
