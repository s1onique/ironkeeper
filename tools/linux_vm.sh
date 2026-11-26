#!/bin/sh
# Run a shell payload inside the Ironkeeper Linux build/test VM.
#
#   usage: tools/linux_vm.sh <payload.sh>
#
# The payload is executed as root inside an Alpine Linux guest. Its combined
# output is written to stdout; the payload's exit status is propagated.
#
# The VM is booted from a local Alpine ISO with the repository, the pinned
# Nim toolchain and the offline Alpine package set attached as 9p shares.
# No privileged operation is performed on the host, no storage device is
# opened, and the guest has no access to the host's block devices.
#
# This script is a *development convenience*. It is not part of the shipped
# product and is not used by CI, which runs natively on Linux.
#
# Required host state (see docs/architecture/overview.md, "Toolchain"):
#   IRK_VM_ISO    path to alpine-virt-*.iso
#   IRK_VM_TOOLS  path to a directory holding nim-2.4.2/ and apks/
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PAYLOAD=${1:?usage: linux_vm.sh <payload.sh>}

IRK_VM_ISO=${IRK_VM_ISO:-/tmp/irk-toolchain/alpine-virt-3.20.3-x86_64.iso}
IRK_VM_TOOLS=${IRK_VM_TOOLS:-/tmp/irkvm/toolshare}
IRK_VM_PAYLOAD_DIR=${IRK_VM_PAYLOAD_DIR:-/tmp/irkvm/payload}
IRK_VM_SOCK=${IRK_VM_SOCK:-/tmp/irkvm/console.sock}

if [ ! -f "$PAYLOAD" ]; then
  echo "linux_vm: payload not found: $PAYLOAD" >&2
  exit 2
fi
if [ ! -f "$IRK_VM_ISO" ]; then
  echo "linux_vm: Alpine ISO not found: $IRK_VM_ISO" >&2
  exit 2
fi

mkdir -p "$IRK_VM_PAYLOAD_DIR"
cp "$PAYLOAD" "$IRK_VM_PAYLOAD_DIR/run.sh"
chmod +x "$IRK_VM_PAYLOAD_DIR/run.sh"

exec python3 "$(dirname "$0")/linux_vm_drive.py" \
  --repo "$REPO_ROOT" \
  --iso "$IRK_VM_ISO" \
  --tools "$IRK_VM_TOOLS" \
  --payload "$IRK_VM_PAYLOAD_DIR" \
  --sock "$IRK_VM_SOCK"
