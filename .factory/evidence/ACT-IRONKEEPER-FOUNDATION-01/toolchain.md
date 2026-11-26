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
| Nim compiler | **2.4.2** | Official `linux_x64` distribution |
| Nimble | 0.20.1 | Bundled with the distribution |
| Memory manager | **ORC** | Set explicitly: `--mm:orc` |
| C compiler | gcc 13.2.1 (Alpine `x86_64`) | Used for the Linux builds |
| Linux kernel | 6.6.49-0-virt (Alpine 3.20.3) | Guest in the Linux VM |
| Git | 2.45.4 (Alpine) | Guest |

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

Nimble's own lock file records the resolved artefact. The lock file is
committed, so that a build resolves the same dependency every time.

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

A Linux amd64 cross-compilation path was established and verified during
the ACT:

```sh
nim c --os:linux --cpu:amd64 --cc:gcc \
  --gcc.exe:<zig-wrapper> --gcc.linkerexe:<zig-wrapper> \
  --passC:"-target x86_64-linux-musl" --passL:"-target x86_64-linux-musl" \
  -o:p_amd64 p.nim
```

The resulting artefact was a Linux ELF x86-64 executable. This path is a
convenience; the authoritative Linux build is the native one inside the
Linux guest, and the authoritative arm64 build is the cross-compilation
in CI.
