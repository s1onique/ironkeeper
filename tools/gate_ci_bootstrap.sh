#!/usr/bin/env bash
# The regression check of the CI toolchain bootstrap.
#
# Two defects had the same shape, and both are checked here.
#
# The first was that the bootstrap appended the toolchain directory to
# `$PATH` with `>>`. PATH is a shell variable holding a colon-separated
# directory list, not an environment file, so the redirection created a
# file whose name was the whole value of PATH.
#
# The second was that the bootstrap is *executed*, so its exported PATH
# belongs to the child process and does not survive it. The later steps
# of a workflow learn about the toolchain through `$GITHUB_PATH`, which
# the runner reads for every following step.
#
# The third was that `$GITHUB_PATH` is a **per-step** file: the
# verification step receives a new, empty one. The installation
# directory is therefore derived from the deterministic installation
# path, not reconstructed from the environment-command file.
#
# The witness below establishes the *production path* exactly:
#
#   1. a synthetic toolchain is constructed under the deterministic
#      installation path;
#   2. the bootstrap is executed in a child process;
#   3. the installation step's `$GITHUB_PATH` file is consumed to
#      establish the effective PATH of the following step, exactly as
#      the runner does;
#   4. a fresh, empty `$GITHUB_PATH` file is allocated for the
#      verification step;
#   5. the development override is absent from the verification
#      environment; and
#   6. the actual production verifier runs.
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
  mkdir -p "$dir"
  cat > "$dir/nim" <<EOF
#!/bin/sh
echo "Nim Compiler Version ${version} [Test: amd64]"
EOF
  chmod +x "$dir/nim"
  if [ "$with_nimble" = "yes" ]; then
    cat > "$dir/nimble" <<'EOF'
#!/bin/sh
echo "Nimble Version 0.14.2 [Test: amd64]"
EOF
    chmod +x "$dir/nimble"
  fi
}

echo "=== the production path: the following step verifies the installation ==="
# The deterministic installation path of the bootstrap.
PROD_VERSION="9.9.9"
export NIM_VERSION="$PROD_VERSION"
export RUNNER_TEMP="$WORK/runner-temp"
rm -rf "$RUNNER_TEMP"
mkdir -p "$RUNNER_TEMP"
INSTALL_DIR="$RUNNER_TEMP/nim/nim-${PROD_VERSION}/bin"
make_toolchain "$INSTALL_DIR" "$PROD_VERSION"

# (2) The installation step: the bootstrap is executed in a child
#     process, with its own environment-command file.
INSTALL_GITHUB_PATH="$WORK/install_github_path"
: > "$INSTALL_GITHUB_PATH"
set +e
env IRK_NIM_TOOLCHAIN_DIR="$INSTALL_DIR" GITHUB_PATH="$INSTALL_GITHUB_PATH" \
  RUNNER_TEMP="$RUNNER_TEMP" NIM_VERSION="$PROD_VERSION" \
  "$ROOT/tools/install_nim_toolchain.sh" > "$WORK/install.out" 2>&1
INSTALL_STATUS=$?
set -e
if [ "$INSTALL_STATUS" -eq 0 ]; then
  ok "the bootstrap succeeds for the pinned version"
else
  no "the bootstrap succeeds for the pinned version"
  cat "$WORK/install.out"
fi
if grep -q "^nim_version=$PROD_VERSION$" "$WORK/install.out"; then
  ok "the bootstrap reports the exact pinned version"
else
  no "the bootstrap reports the exact pinned version"
  cat "$WORK/install.out"
fi
if grep -qx "$INSTALL_DIR" "$INSTALL_GITHUB_PATH"; then
  ok "the installation step appends the toolchain directory to its own file"
else
  no "the installation step appends the toolchain directory to its own file"
fi

# (3) The runner consumes the installation step's file and updates the
#     PATH of every following step.
EFFECTIVE_PATH="$PATH"
while IFS= read -r entry; do
  [ -n "$entry" ] && EFFECTIVE_PATH="$entry:$EFFECTIVE_PATH"
done < "$INSTALL_GITHUB_PATH"

# (4) The verification step receives a new, empty environment-command
#     file.
VERIFY_GITHUB_PATH="$WORK/verify_github_path"
: > "$VERIFY_GITHUB_PATH"

# (5) and (6) The production verifier runs, with the development
#     override absent from its environment.
set +e
env -u IRK_NIM_TOOLCHAIN_DIR PATH="$EFFECTIVE_PATH" \
  GITHUB_PATH="$VERIFY_GITHUB_PATH" RUNNER_TEMP="$RUNNER_TEMP" \
  NIM_VERSION="$PROD_VERSION" \
  "$ROOT/tools/verify_nim_toolchain.sh" > "$WORK/verify.out" 2>&1
VERIFY_STATUS=$?
set -e
if [ "$VERIFY_STATUS" -eq 0 ]; then
  ok "the verification step succeeds on the production path"
else
  no "the verification step succeeds on the production path"
  cat "$WORK/verify.out"
fi
if grep -q "^nim_path=$INSTALL_DIR/nim$" "$WORK/verify.out"; then
  ok "nim resolves to the intended toolchain"
else
  no "nim resolves to the intended toolchain"
  cat "$WORK/verify.out"
fi
if grep -q "^nimble_path=$INSTALL_DIR/nimble$" "$WORK/verify.out"; then
  ok "nimble resolves to the intended toolchain"
else
  no "nimble resolves to the intended toolchain"
  cat "$WORK/verify.out"
fi

echo
echo "=== the per-step environment-command file cannot carry the identity ==="
# The root cause of the remote failure: the verification step's file is
# new and empty, so the predecessor's discovery rule found nothing.
if grep -q "$INSTALL_DIR" "$VERIFY_GITHUB_PATH"; then
  no "the verification step's file does not carry the installation directory"
else
  ok "the verification step's file does not carry the installation directory"
fi
predecessor_intended="$(tail -n 1 "$VERIFY_GITHUB_PATH" 2>/dev/null || true)"
if [ -z "$predecessor_intended" ]; then
  ok "the predecessor's discovery rule finds no installation directory"
else
  no "the predecessor's discovery rule finds no installation directory"
fi
# And the predecessor's rule would therefore have refused the
# correctly populated PATH.
if [ -z "$predecessor_intended" ] && [ "$predecessor_intended" != "$INSTALL_DIR" ]; then
  ok "the predecessor's rule would refuse the correctly populated PATH"
else
  no "the predecessor's rule would refuse the correctly populated PATH"
fi

echo
echo "=== the verifier derives the installation path deterministically ==="
if grep -q 'RUNNER_TEMP/nim/nim-' tools/verify_nim_toolchain.sh; then
  ok "the verifier derives the installation directory from RUNNER_TEMP"
else
  no "the verifier derives the installation directory from RUNNER_TEMP"
fi
if grep -v '^[[:space:]]*#' tools/verify_nim_toolchain.sh | \
     grep -q 'GITHUB_PATH'; then
  no "the verifier does not read the environment-command file"
else
  ok "the verifier does not read the environment-command file"
fi

echo
echo "=== an unrelated preinstalled toolchain is not accepted ==="
OTHER="$WORK/other-toolchain"
make_toolchain "$OTHER" "$PROD_VERSION"
set +e
env -u IRK_NIM_TOOLCHAIN_DIR PATH="$OTHER:$EFFECTIVE_PATH" \
  GITHUB_PATH="$VERIFY_GITHUB_PATH" RUNNER_TEMP="$RUNNER_TEMP" \
  NIM_VERSION="$PROD_VERSION" \
  "$ROOT/tools/verify_nim_toolchain.sh" > "$WORK/unrelated.out" 2>&1
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
set +e
env IRK_NIM_TOOLCHAIN_DIR="$WRONG" NIM_VERSION="$PROD_VERSION" \
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
set +e
env IRK_NIM_TOOLCHAIN_DIR="$WORK/does-not-exist/bin" NIM_VERSION="$PROD_VERSION" \
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
NO_NIMBLE_ROOT="$WORK/runner-temp-nonimble"
NO_NIMBLE="$NO_NIMBLE_ROOT/nim/nim-${PROD_VERSION}/bin"
make_toolchain "$NO_NIMBLE" "$PROD_VERSION" no
set +e
env -u IRK_NIM_TOOLCHAIN_DIR PATH="$NO_NIMBLE:$PATH" \
  GITHUB_PATH="$VERIFY_GITHUB_PATH" RUNNER_TEMP="$NO_NIMBLE_ROOT" \
  NIM_VERSION="$PROD_VERSION" \
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
