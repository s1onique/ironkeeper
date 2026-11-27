# Toolchain identity

## Development host

The development workstation is macOS. A Darwin build does not prove that
Linux-specific code works, so a Linux-native path is established
separately — see `linux-native.md`.

| Tool | Version | Source |
|---|---|---|
| Nim compiler | 2.2.4 | Nix store (host convenience) |
| Nimble | 0.20.1 | Nix store (host convenience) |
| C compiler | Apple clang 15.0.0 | Xcode toolchain (portable builds only) |
| Git | 2.54.0 | system |
| Python | 3.12.14 | Nix store (CI-side tooling only) |

The host toolchain is used only for fast iteration. The **authoritative**
toolchain is the pinned one below.

## Pinned toolchain

| Component | Version | Notes |
|---|---|---|
| Nim compiler | **2.4.2** | Official distribution, per architecture, pinned by sha256 |
| Nimble | 0.26.2 | Bundled with the distribution |
| Memory manager | **ORC** | Set explicitly: `--mm:orc` |
| C compiler | gcc 13.x (Ubuntu 24.04) | The native CI runners |
| Kernel | Ubuntu 24.04 | The native CI runners |
| Git | 2.43.x (Ubuntu 24.04) | The native CI runners |

> **Corrected.** The authoritative Linux builds ran **natively on
> GitHub-hosted `ubuntu-24.04` (amd64) and `ubuntu-24.04-arm` (arm64)
> runners**. The rows above previously named an Alpine guest, which was
> the abandoned local virtualisation approach. That approach was
> superseded and is not the authoritative environment; the toolchain
> rows now name the environment that actually produced the qualified
> artefacts.

### Why 2.4.2

`jschema`, the selected validator, declares `requires "nim >= 2.2.10"`.
The host's 2.2.4 does not satisfy that constraint, so a newer stable
release was selected. 2.4.2 is the current stable channel release:

```
$ curl -sSL https://nim-lang.org/channels/stable
2.4.2
```

### Pinned by digest, not only by version

```
$ curl -fsSLO https://nim-lang.org/download/nim-2.4.2-linux_x64.tar.xz
$ sha256sum nim-2.4.2-linux_x64.tar.xz
0ee5b16e81852a956d4fddb4aa44b5958c645c992132fa43be45f489573ee325  nim-2.4.2-linux_x64.tar.xz

$ curl -fsSL https://nim-lang.org/download/nim-2.4.2-linux_x64.tar.xz.sha256
0ee5b16e81852a956d4fddb4aa44b5958c645c992132fa43be45f489573ee325  nim-2.4.2-linux_x64.tar.xz
```

The local digest and the published digest are identical.

### Bootstrap procedure

The bootstrap does not modify the global workstation environment; it
installs into a caller-chosen prefix.

```sh
export IRK_TOOLCHAIN="$HOME/.local/irk-toolchain"
mkdir -p "$IRK_TOOLCHAIN"
cd "$IRK_TOOLCHAIN"
curl -fsSLO https://nim-lang.org/download/nim-2.4.2-linux_x64.tar.xz
echo "0ee5b16e81852a956d4fddb4aa44b5958c645c992132fa43be45f489573ee325  nim-2.4.2-linux_x64.tar.xz" \
  | sha256sum -c -
tar xf nim-2.4.2-linux_x64.tar.xz
export PATH="$IRK_TOOLCHAIN/nim-2.4.2/bin:$PATH"
nim --version
```

The same digest check is performed by the CI workflow before the
toolchain is used.

## Memory manager

ORC is selected explicitly on every compilation:

```sh
nim c -d:release --mm:orc --opt:speed ...
```

The choice is explicit rather than inherited so that the memory
behaviour is a property of the project and not of whichever Nim release
happens to be current. `AGENTS.md` and ADR-0001 record the reasoning.

## Dependency locking

`ironkeeper.nimble` pins the single external dependency exactly:

```nim
requires "nim >= 2.2.10"
requires "jschema == 0.1.0"
```

There is **no committed `nimble.lock`**, and none is claimed. The
dependency is resolved at an exact commit with its **tree digest**
verified, and that exact-commit resolution *is* the lock. The claim that
a lock file was committed was false.

## Reproducible commands

```sh
nimble build      # release build of the executable
nimble test       # unit and contract tests
nimble check      # type-check every module
```

The equivalent repository-owned commands are `tools/build.sh` and the
three test binaries it produces. Both paths drive the same compiler
invocations; `tools/build.sh` exists so that CI and a developer machine
cannot drift apart.

## Cross-compilation

> **Corrected.** The authoritative Linux build is **native execution on
> GitHub-hosted runners**, for both architectures:
> `ubuntu-24.04` for amd64 and `ubuntu-24.04-arm` for arm64. Neither
> result comes from a cross-compiled artefact, and no cross-architecture
> emulation is used. An arm64 result is a genuine arm64 execution.
>
> The cross-compilation recipe below was an experiment during the
> abandoned local virtualisation approach. It is retained as a record of
> what was tried; it is **not** the authoritative build path, and the
> earlier claim that "the authoritative arm64 build is the
> cross-compilation in CI" was wrong. The arm64 build is native.

The recipe that was tried:

```sh
nim c --os:linux --cpu:amd64 --cc:gcc \
  --gcc.exe:<zig-wrapper> --gcc.linkerexe:<zig-wrapper> \
  --passC:"-target x86_64-linux-musl" --passL:"-target x86_64-linux-musl" \
  -o:p_amd64 p.nim
```

A cross-compiled artefact is never reported as "executed".
