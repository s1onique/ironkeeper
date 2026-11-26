#!/bin/sh
# Payload executed inside the Linux VM: build and test Ironkeeper natively.
#
# Everything runs unprivileged apart from the one-time `apk add` of the
# offline toolchain packages, which is a guest-local operation.
set -eu

export PATH=/mnt/toolshare/nim-2.4.2/bin:$PATH
export HOME=/root
export XDG_CACHE_HOME=/root/.cache
export NIMBLE_DIR=/root/.nimble

echo "=== ENVIRONMENT ==="
uname -a
cat /etc/alpine-release
nim --version | head -2
nimble --version | head -2
gcc --version | head -1

echo "=== INSTALL TOOLCHAIN PACKAGES (offline) ==="
if ! command -v gcc >/dev/null 2>&1; then
  apk add --no-cache --force-non-repository /mnt/toolshare/apks/*.apk >/dev/null 2>&1 || true
fi
gcc --version | head -1

echo "=== STAGE jschema ==="
mkdir -p /root/.nimble/pkgs2/jschema-0.1.0
cp -R /mnt/toolshare/jschema/src /root/.nimble/pkgs2/jschema-0.1.0/src
cp /mnt/toolshare/jschema/LICENSE /root/.nimble/pkgs2/jschema-0.1.0/
cp /mnt/toolshare/jschema/jschema.nimble /root/.nimble/pkgs2/jschema-0.1.0/ 2>/dev/null || \
  printf '%s\n' '# Package' 'version       = "0.1.0"' 'author        = "Leon Lysak (Niminem)"' \
    'description   = "spec-compliant JSON Schema (draft 2020-12) validator and builder for Nim"' \
    'license       = "MIT"' 'srcDir        = "src"' '' '# Dependencies' 'requires "nim >= 2.2.10"' > \
    /root/.nimble/pkgs2/jschema-0.1.0/jschema.nimble
printf '%s\n' 'requires "jschema == 0.1.0"' > /root/.nimble/pkgs2/jschema-0.1.0/nimble.paths

echo "=== BUILD ==="
cd /mnt/repo
mkdir -p build
nim c -d:release --mm:orc --opt:speed --path:/root/.nimble/pkgs2/jschema-0.1.0 \
  -o:build/ironkeeper src/ironkeeper.nim
./build/ironkeeper --version

echo "=== DONE ==="
