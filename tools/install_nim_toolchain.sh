#!/usr/bin/env bash
# Install the pinned Nim toolchain and put it on PATH.
#
# This script is the single implementation of the toolchain bootstrap. CI
# calls it, and the regression check calls it, so that the bootstrap is
# exercised by the same code that production uses.
#
# The toolchain is pinned by version and by the sha256 of the official
# distribution. The digest is verified *before* the archive is extracted,
# and the extracted compiler is verified before it is used.
#
# Environment:
#   NIM_VERSION          the pinned version (default: 2.4.2)
#   NIM_SHA256_AMD64     the pinned digest of the x86-64 distribution
#   NIM_SHA256_ARM64     the pinned digest of the aarch64 distribution
#   RUNNER_TEMP          the writable scratch directory (required)
#   GITHUB_PATH          the file that later steps read PATH from; when it
#                        is set, the toolchain directory is appended to it
#   NIM_ARCHIVE_URL      the download base (default: the official site)
#   IRK_NIM_TOOLCHAIN_DIR
#                        use an already-extracted toolchain in this
#                        directory instead of downloading one. This is the
#                        development and regression-check path; the digest
#                        is then not applicable and is not checked.
#
# Exit status:
#   0  the toolchain is installed and on PATH
#   1  the toolchain could not be installed or verified

set -euo pipefail

NIM_VERSION="${NIM_VERSION:-2.4.2}"
NIM_SHA256_AMD64="${NIM_SHA256_AMD64:-0ee5b16e81852a956d4fddb4aa44b5958c645c992132fa43be45f489573ee325}"
NIM_SHA256_ARM64="${NIM_SHA256_ARM64:-58e86d84e679d003ec04320b2411cd10aefd942132f9eaf6c583012b22be3595}"
NIM_ARCHIVE_URL="${NIM_ARCHIVE_URL:-https://nim-lang.org/download}"

if [ -z "${RUNNER_TEMP:-}" ]; then
  echo "install_nim_toolchain: RUNNER_TEMP is not set" >&2
  exit 1
fi

# ---- the toolchain directory ------------------------------------------------
# The directory is derived from the version, and it is checked for
# existence and executability before it is put on PATH. A PATH entry that
# does not exist is worse than no entry at all: every later command would
# report "command not found" for a tool that is not installed.
if [ -n "${IRK_NIM_TOOLCHAIN_DIR:-}" ]; then
  nim_bin="$IRK_NIM_TOOLCHAIN_DIR"
else
  case "$(uname -m)" in
    x86_64)  nim_arch=x64;   nim_sha="$NIM_SHA256_AMD64" ;;
    aarch64) nim_arch=arm64; nim_sha="$NIM_SHA256_ARM64" ;;
    *) echo "install_nim_toolchain: unsupported runner architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  archive="nim-${NIM_VERSION}-linux_${nim_arch}.tar.xz"
  mkdir -p "$RUNNER_TEMP/nim"
  cd "$RUNNER_TEMP/nim"
  curl -fsSLO "${NIM_ARCHIVE_URL}/${archive}"
  echo "${nim_sha}  ${archive}" | sha256sum -c -
  tar xf "${archive}"
  nim_bin="$RUNNER_TEMP/nim/nim-${NIM_VERSION}/bin"
fi

# ---- verify the extracted toolchain -----------------------------------------
if [ ! -d "$nim_bin" ]; then
  echo "install_nim_toolchain: the toolchain directory does not exist: $nim_bin" >&2
  exit 1
fi
if [ ! -x "$nim_bin/nim" ]; then
  echo "install_nim_toolchain: the compiler is not executable: $nim_bin/nim" >&2
  exit 1
fi

# ---- put the toolchain on PATH ----------------------------------------------
# PATH is a *shell variable* holding a colon-separated directory list. It
# is not an environment file, and appending to it with `>>` does not add a
# directory to it: it creates a file whose name is the whole value of
# PATH. The directory is therefore exported as a variable, and the later
# steps are told about it through `$GITHUB_PATH`, which *is* a file.
export PATH="$nim_bin:$PATH"
if [ -n "${GITHUB_PATH:-}" ]; then
  printf '%s\n' "$nim_bin" >> "$GITHUB_PATH"
fi

# ---- prove the toolchain works ----------------------------------------------
# The version is checked, not merely printed: a compiler from a different
# version would pass unnoticed otherwise.
reported="$(nim --version | head -1)"
case "$reported" in
  *"Nim Compiler Version ${NIM_VERSION}"*) ;;
  *)
    echo "install_nim_toolchain: unexpected compiler version: $reported" >&2
    exit 1
    ;;
esac
echo "nim_bin=$nim_bin"
echo "$reported"
