#!/usr/bin/env bash
# Verify that the pinned Nim toolchain is the one the workflow uses.
#
# The bootstrap (`tools/install_nim_toolchain.sh`) is executed, not
# sourced, so its exported PATH belongs to the child process and does
# not survive the script. The later steps of a workflow learn about the
# toolchain through `$GITHUB_PATH`, which the runner reads for every
# following step.
#
# This script is therefore the *separate* verification step. It checks
# that:
#
#   1. `nim` resolves to the intended toolchain directory;
#   2. `nimble` resolves to the same directory;
#   3. neither of them is an unrelated preinstalled compiler or package
#      manager that happens to be earlier on PATH; and
#   4. the compiler reports exactly the pinned version.
#
# Environment:
#   NIM_VERSION             the pinned version (default: 2.4.2)
#   GITHUB_PATH             the file the runner reads PATH from; the last
#                           entry is the directory the bootstrap appended
#   IRK_NIM_TOOLCHAIN_DIR   the intended toolchain directory; when it is
#                           set it wins over GITHUB_PATH. This is the
#                           development and regression-check path.
#
# Exit status:
#   0  the pinned toolchain is in use
#   1  the toolchain could not be verified

set -euo pipefail

NIM_VERSION="${NIM_VERSION:-2.4.2}"

# ---- the intended toolchain directory ----------------------------------------
# The directory is the one the bootstrap appended to `$GITHUB_PATH`. An
# unrelated compiler that is already on PATH is not accepted: the
# workflow must use the pinned toolchain, not whatever the image
# happens to carry.
intended="${IRK_NIM_TOOLCHAIN_DIR:-}"
if [ -z "$intended" ] && [ -n "${GITHUB_PATH:-}" ] && [ -f "${GITHUB_PATH}" ]; then
  intended="$(tail -n 1 "${GITHUB_PATH}")"
fi
if [ -z "$intended" ]; then
  echo "verify_nim_toolchain: the intended toolchain directory is unknown" >&2
  echo "  neither IRK_NIM_TOOLCHAIN_DIR nor GITHUB_PATH names it" >&2
  exit 1
fi

# ---- the compiler ------------------------------------------------------------
if ! command -v nim > /dev/null 2>&1; then
  echo "verify_nim_toolchain: nim is not on PATH" >&2
  exit 1
fi
nim_path="$(command -v nim)"
nim_dir="$(dirname "$nim_path")"
if [ "$nim_dir" != "$intended" ]; then
  echo "verify_nim_toolchain: nim does not resolve to the intended toolchain" >&2
  echo "  expected: $intended" >&2
  echo "  actual:   $nim_dir" >&2
  exit 1
fi

# ---- the package manager -----------------------------------------------------
# The toolchain is only usable when it carries its own package manager.
# An unrelated Nimble from the image is not accepted either: the pinned
# toolchain and the pinned package manager belong together.
if ! command -v nimble > /dev/null 2>&1; then
  echo "verify_nim_toolchain: nimble is not on PATH" >&2
  exit 1
fi
nimble_path="$(command -v nimble)"
nimble_dir="$(dirname "$nimble_path")"
if [ "$nimble_dir" != "$intended" ]; then
  echo "verify_nim_toolchain: nimble does not resolve to the intended toolchain" >&2
  echo "  expected: $intended" >&2
  echo "  actual:   $nimble_dir" >&2
  exit 1
fi

# ---- the exact version -------------------------------------------------------
reported="$(nim --version | head -1)"
actual_version="$(printf '%s\n' "$reported" | awk '{print $4}')"
if [ "$actual_version" != "$NIM_VERSION" ]; then
  echo "verify_nim_toolchain: unexpected compiler version" >&2
  echo "  expected: $NIM_VERSION" >&2
  echo "  actual:   ${actual_version:-<unparsable>}" >&2
  exit 1
fi

echo "nim_path=$nim_path"
echo "nimble_path=$nimble_path"
echo "nim_version=$actual_version"
echo "$reported"
