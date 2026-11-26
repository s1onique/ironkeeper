# Dependency decisions

## Runtime dependencies

| Dependency | Version | Licence | Why | Used for |
|---|---|---|---|---|
| `jschema` | 0.1.0 (commit `a9368625`) | MIT | Only qualified Draft 2020-12 validator for Nim | Runtime schema validation |
| Nim standard library | 2.4.2 | MIT | Everything else | JSON, CLI, filesystem, process |
| `libpcre3` (shared library) | 3.x | BSD-3-Clause | PCRE runtime for `std/re`, used by the validator for `pattern` | Regex evaluation in schema validation |

No other runtime dependency exists. There is no database server, no
container runtime, no web framework and no network service.

## Build dependencies

| Dependency | Why |
|---|---|
| A C compiler and linker | Nim compiles to C |
| `git` | The dependency is fetched at a pinned commit |
| Python 3 with `check-jsonschema` | **CI only**, for the independent schema cross-check |

The independent validator is a CI dependency, not a runtime dependency.
The shipped binary performs its own validation with the bundled
validator.

## The PCRE runtime dependency

`jschema` implements the JSON Schema `pattern` keyword with `std/re`,
which is a binding to PCRE. On Linux, Nim's `std/re` loads
`libpcre.so.3` (or `libpcre.so.1`) **dynamically at run time**. The Nim
distribution does not bundle the library, and the binding is not linked
statically.

This makes `libpcre3` a real runtime dependency of the Ironkeeper binary
on Linux:

```sh
apt-get install -y libpcre3
```

This was found by CI rather than by inspection: the first build on
`ubuntu-24.04` linked and loaded without PCRE being present, and the
type-check step passed because `nim check` does not compile or load C
code. The CI workflow now installs `libpcre3` explicitly and asserts its
presence before the build:

```sh
sudo apt-get install -y --no-install-recommends libpcre3
ldconfig -p | grep -i pcre
```

A deployment that omits `libpcre3` builds successfully and then fails
when a schema uses `pattern`. The dependency is therefore stated in
`docs/architecture/overview.md` rather than left to chance, and the
packaging milestone (IRK-10) must carry it.

## Why `jschema` was chosen

The alternatives were evaluated and rejected on measurable grounds; see
`validator-qualification.md` for the full table.

| Candidate | Licence | Draft support | Verdict |
|---|---|---|---|
| `Niminem/jschema` | MIT | 2020-12 (complete mandatory corpus) | **Selected** |
| `Vindaar/JsonSchemaValidator` | MIT | draft-04/06 era | Rejected: no `unevaluatedProperties`, no `$dynamicRef`, no `$defs`, no `prefixItems` |
| `PMunch/jsonschema` | MIT | not a JSON Schema validator | Rejected: a TypeScript-style schema DSL |
| `Nycto/NimJsonSchemaImporter` | MIT | compile-time import | Rejected: no runtime validation |

## Licensing

| Component | Licence | Compatible with MIT distribution? |
|---|---|---|
| Ironkeeper | MIT | yes |
| `jschema` | MIT | yes |
| Nim standard library | MIT | yes |
| `libpcre3` | BSD-3-Clause | yes |

The `gitleaks` binary used for secret scanning in CI is MIT licensed.
It is a CI tool and is not distributed with Ironkeeper.

No copyleft licence is present in the dependency tree, so the MIT
licence of this repository is compatible with every dependency.

## Dependency locking

`ironkeeper.nimble` pins the single external dependency exactly:

```nim
requires "nim >= 2.2.10"
requires "jschema == 0.1.0"
```

The CI workflow does not rely on Nimble's package registry. It fetches
the dependency at an exact commit and verifies the tree digest:

| Item | Value |
|---|---|
| Repository | `https://github.com/Niminem/jschema.git` |
| Commit | `a936862556f24fde475059c560c1a13f00291457` |
| Tree sha256 | `323f47f85dba93a0f96bd3ffd6ec964abe2663e260c988596d7a49a0d68573a8` |

The tree digest pins every file, so a rewritten tag or a changed file is
detected. The same approach is used for the Nim toolchain, whose
published `sha256` is verified, and for the `gitleaks` binary, whose
official release checksum is verified.

## Licence of the Nimble manifest version

Nimble accepts only a version made of numbers and dots. The manifest
therefore carries `0.1.0`, the numeric part of the application version,
while the authoritative version, including the `-dev` pre-release
marker, is the `Version` constant in `src/ironkeeper/core/version.nim`.
The contract test `tests/contract/version_contract_tests.nim` asserts
that the two agree and that the manifest version is a bare dotted
number.
