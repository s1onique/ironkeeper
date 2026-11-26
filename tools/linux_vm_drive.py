#!/usr/bin/env python3
"""Drive the Ironkeeper Linux build/test VM over a UNIX-domain serial socket.

The guest is an Alpine Linux system booted from a local ISO. Three 9p
shares are attached: the repository under test, the payload directory and a
directory holding the pinned Nim toolchain plus offline Alpine packages.

The driver logs in as root on the serial console, mounts the shares, runs
``run.sh`` from the payload share, captures everything the payload printed
and propagates the payload's exit status.

This script is a development convenience for macOS hosts. CI builds and
tests natively on Linux and does not use it.
"""

import argparse
import os
import re
import shutil
import socket
import subprocess
import sys
import time


def boot_qemu(repo: str, iso: str, tools: str, payload: str, sock: str) -> subprocess.Popen:
    """Start QEMU with the serial console on a UNIX socket."""
    qemu = shutil.which("qemu-system-x86_64")
    if qemu is None:
        raise SystemExit("linux_vm_drive: qemu-system-x86_64 not found in PATH")
    if os.path.exists(sock):
        os.unlink(sock)
    cmd = [
        qemu,
        "-machine", "q35",
        "-accel", "tcg",
        "-smp", "4",
        "-m", "3072",
        "-nographic", "-no-reboot",
        "-drive", f"file={iso},format=raw,if=virtio,media=cdrom",
        "-virtfs", f"local,path={repo},mount_tag=repo,security_model=none",
        "-virtfs", f"local,path={payload},mount_tag=payload,security_model=none",
        "-virtfs", f"local,path={tools},mount_tag=toolshare,security_model=none",
        "-netdev", "user,id=net0",
        "-device", "virtio-net-pci,netdev=net0",
        "-chardev", f"socket,id=ser0,path={sock},server=on,wait=off",
        "-serial", "chardev:ser0",
        "-monitor", "none",
    ]
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--iso", required=True)
    ap.add_argument("--tools", required=True)
    ap.add_argument("--payload", required=True)
    ap.add_argument("--sock", default="/tmp/irkvm/console.sock")
    args = ap.parse_args()

    proc = boot_qemu(args.repo, args.iso, args.tools, args.payload, args.sock)

    for _ in range(900):
        if os.path.exists(args.sock):
            break
        time.sleep(0.1)
    else:
        proc.kill()
        raise SystemExit("linux_vm_drive: console socket never appeared")

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(args.sock)
    sock.settimeout(0.5)

    transcript: list[str] = []

    def pump(until: str | None = None, deadline: float = 300.0) -> str:
        end = time.time() + deadline
        buf = ""
        while time.time() < end:
            try:
                data = sock.recv(65536)
            except socket.timeout:
                if until and until in buf:
                    break
                continue
            except OSError:
                break
            if not data:
                break
            text = data.decode("utf-8", "replace")
            transcript.append(text)
            buf += text
            if until and until in buf:
                break
        return buf

    def send(line: str) -> None:
        sock.sendall((line + "\r").encode())
        time.sleep(0.4)

    try:
        if "login:" not in pump("login:", deadline=600):
            print("".join(transcript)[-3000:])
            raise SystemExit("linux_vm_drive: login prompt never appeared")
        send("root")
        pump("#", deadline=180)

        for cmd, tag in [
            ("mkdir -p /mnt/repo /mnt/payload /mnt/toolshare", None),
            ("mount -t 9p -o trans=virtio,version=9p2000.L repo /mnt/repo", None),
            ("mount -t 9p -o trans=virtio,version=9p2000.L payload /mnt/payload", None),
            ("mount -t 9p -o trans=virtio,version=9p2000.L toolshare /mnt/toolshare", None),
            ("echo DRIVE_MOUNT_OK", "DRIVE_MOUNT_OK"),
        ]:
            send(cmd)
            out = pump(tag, deadline=90)
            if tag and tag not in out:
                print("".join(transcript)[-3000:])
                raise SystemExit(f"linux_vm_drive: step failed: {cmd}")

        send("sh /mnt/payload/run.sh 2>&1; echo DRIVE_PAYLOAD_RC=$?")
        out = pump("DRIVE_PAYLOAD_RC=", deadline=2400)
        rc = re.search(r"DRIVE_PAYLOAD_RC=(\d+)", out)
        text = "".join(transcript)
        # Strip the console echo of the command line and the trailing prompt.
        print(text, flush=True)
        send("poweroff")
        time.sleep(3)
        proc.kill()
        return int(rc.group(1)) if rc else 3
    finally:
        try:
            proc.kill()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
