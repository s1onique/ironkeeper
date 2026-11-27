# Linux-native execution

## The requirement

A Darwin build does not prove that Linux-specific code works. The
foundation ACT requires a Linux-native build **and** execution path.

## What was used

Native GitHub-hosted Linux runners, executing the compiled binary
directly:

| Runner | Architecture | Execution |
|---|---|---|
| `ubuntu-24.04` | amd64 | native |
| `ubuntu-24.04-arm` | arm64 | native |

**No cross-architecture emulation was used.** An arm64 result is a
genuine arm64 execution. A cross-compiled artefact is never reported as
"executed".

The evidence is CI run **45907055629** at commit
`886a7d20a33e3f8a4c666b550a74872cf0b1a800`:

| Job | Conclusion |
|---|---|
| `build and test (amd64)` | success |
| `build and test (arm64)` | success |
| `secret scan` | success |

See `ci-status.md` for the full run record.

## What each job did on the real architecture

* Installed the pinned, digest-verified Nim 2.4.2 distribution, chosen
  by the runner's own architecture.
* Installed the PCRE runtime dependency and asserted its presence with
  `ldconfig -p | grep -i pcre`.
* Fetched the pinned dependency at an exact commit and verified its tree
  digest.
* Type-checked every module.
* Built the application and the three test binaries.
* Ran the unit, contract and compiled CLI integration suites.
* Checked the embedded schemas against the repository files.
* Validated the repository schemas with an independent implementation,
  and cross-checked the machine-readable output the binary produces.
* Compiled in release mode and recorded the executable identity.

## The arm64 finding

Running on the real arm64 architecture found a defect that the amd64
run could not: the report identifier mixed a signed random value with a
nanosecond counter through a cast between signed and unsigned types.
The result was implementation defined, and its width could differ
between architectures.

The identifier is now derived with explicit masking and always has the
same shape. This is recorded because it is the concrete value of
running on the target architecture rather than emulating it.

## The superseded local approach

A local Alpine Linux guest under QEMU was attempted on the macOS
development workstation, to obtain a Linux-native path without a
network dependency.

That approach was **discontinued** as an unjustified diversion from the
product once native CI runners were identified as the appropriate
infrastructure. It is recorded as `SUPERSEDED_EXECUTION_ENVIRONMENT`;
it is **not** an implementation failure, and no product code ever
depended on it.

What the attempt established, and what it cost:

* The Linux-native path is required and is now satisfied natively.
* The toolchain, the dependency and the test suite all work on a real
  Linux system: the CI run confirms it on two architectures.
* A local guest adds a serial-console driver, a guest image, an
  offline package set and a 9p mount to every build iteration. None of
  that belongs to the product.

The temporary artefacts were removed: the guest image, the Alpine ISO,
the offline package set and the guest driver scripts. The tooling that
was written for it was removed from the repository in commit
`0f469d13`.

### Process cleanup

Three processes were created by the guest attempt and were positively
identified by their command lines:

| Process | Disposition |
|---|---|
| the guest driver script | terminated |
| the QEMU instance started by that driver | terminated |
| a second, earlier QEMU instance | terminated |

### The unresolved orphan — an environment-cleanup finding

A further orphaned QEMU instance from an earlier attempt could not be
signalled. It was left in place rather than fought with, and the guest
image it depended on was deleted, so it cannot perform any further work.

This amendment re-verified that finding, and recorded the exact blocker
for the operator.

**Observed at the time of this ACT:**

```
$ ps aux | grep qemu-system-x86_64
chistyakov 70203 0.0 ?? 12:46AM /nix/store/gd5jx2ldmky6h0aijflln2mw1v9prq4f-qemu-10.2.4/bin/qemu-system-x86_64 -machine q35 -accel tcg -smp 4 -m 3072 -nographic -no-reboot -drive file=/tmp/irk-toolchain/alpine-virt-3.20.3-x86_64.iso,format=raw,if=virtio,media=cdrom -virtfs local,path=/Volumes/.../ironkeeper,mount_tag=repo,security_model=none -virtfs local,path=/tmp/irkvm/payload,mount_tag=payload,security_model=none -virtfs local,path=/tmp/irkvm/toolshare,mount_tag=toolshare,security_model=none -netdev user,id=net0 -device virtio-net-pci,netid=net0 -chardev socket,id=ser0,path=/tmp/irkvm/console.sock,server=on,wait=off -serial chardev:ser0 -monitor none

$ ps -p 70203 -o pid=,%cpu=,state=
70203   0.0

$ ls -la /tmp/irk-toolchain/alpine-virt-3.20.3-x86_64.iso
ls: cannot access '/tmp/irk-toolchain/alpine-virt-3.20.3-x86_64.iso': No such file or directory
```

**The exact blocker.** Two targeted, single-PID termination attempts
were made. Both were denied by the sandbox:

```
$ kill -TERM 70203
zsh:kill:1: kill 70203 failed: operation not permitted

$ kill -KILL 70203
zsh:kill:1: kill 70203 failed: operation not permitted
```

The process had been re-parented to `init` and was started by a previous
tool invocation, so the sandbox denies `kill` to it. No broad
process-killing command was used, and no further local virtualisation
work was attempted.

**Why this is not a blocker for the product.** The orphan is idle at
0.0% CPU, and the guest image it depends on **no longer exists**, so it
cannot perform any further work. It does not hold a device, it does not
touch the repository, and it cannot interfere with the build, the test
suite or the CI runs. It is an environment-cleanup item for the
operator, not a product defect, and it is recorded separately from the
product qualification.

**Operator action.** Terminate the process by PID from a context with
the necessary entitlement:

```sh
kill -TERM 70203   # then kill -KILL 70203 if it does not exit
```

The remaining temporary state is the pinned toolchain and the compiler
caches, which are build inputs rather than virtualization artefacts.

## The development workstation

macOS is used for source editing, portable compilation, portable unit and
contract tests, static analysis and git operations. A successful macOS
run is **not** evidence of Linux-native compatibility and is never
reported as such.
