# Contributing to Ironkeeper

Thank you for your interest. This document describes how to build, test
and propose a change.

## Before you start

Read [AGENTS.md](AGENTS.md). It contains the engineering rules that apply
to every change, and a reviewer will check your change against them.

## Prerequisites

* A pinned **Nim 2.x** toolchain. The exact version and the bootstrap
  procedure are in
  [docs/architecture/overview.md](docs/architecture/overview.md#toolchain).
* A C compiler and linker for the target platform.
* `nimble`, which ships with the Nim distribution.
* For schema cross-validation: Python 3 with `check-jsonschema`. This is
  a **CI-only** dependency; the shipped binary performs its own
  validation.

The project deliberately avoids requiring a container runtime, a
database server or any other network service to build and test.

## Building and testing

```sh
nimble build      # build the executable
nimble test       # unit and contract tests
nimble check      # type-check every module
```

If your Nimble cannot expose those task names, the repository-owned
equivalents are:

```sh
tools/build.sh
./build/unit_tests
./build/contract_tests
./build/integration_tests
```

The integration suite runs the compiled binary as a subprocess, so build
the binary first.

### Linux-native testing

A Darwin build does not prove that Linux-specific code works. Push your
branch and let the CI workflow run it natively on Linux:

| Runner | Architecture |
|---|---|
| `ubuntu-24.04` | amd64 |
| `ubuntu-24.04-arm` | arm64 |

Both runners execute the compiled binary natively; no cross-architecture
emulation is used. The workflow installs the same pinned, digest-verified
Nim distribution that the local procedure uses and drives the same
repository-owned commands, so the CI result and your local result are
produced by the same code.

See [docs/architecture/overview.md](docs/architecture/overview.md#linux-native-execution-path).

## Working with the contracts

The JSON Schemas under `schemas/v1/` are the public contracts. They are
embedded into the binary by a generator, and a contract test asserts that
the embedded bytes match the repository files.

After editing a schema:

```sh
nim r tools/embed_schemas.nim
```

`nim r tools/embed_schemas.nim --check` verifies that the embedded copy
is in sync without writing. CI runs the check.

Adding a field to a published contract is a **compatible** change within
the same version. Removing a field, narrowing an accepted value or
changing a required list is **breaking** and requires a new
`schemas/vN/` directory plus a migration note.

## Style

* Prefer small, cohesive modules; see [AGENTS.md](AGENTS.md).
* Every public procedure carries a doc comment that says what it does,
  not how.
* Comments explain *why*. The code already says what.
* Keep the codebase's existing naming: `camelCase` for procedures and
  types, `snake_case` for module-level constants.

## Commit messages

Use a conventional prefix:

```
docs:   documentation only
build:  build system or dependencies
feat:   a new capability
fix:    a bug fix
test:   tests only
ci:     continuous integration
chore:  housekeeping
```

Write the body as *why*, not *what*. The diff already says what changed.

## Pull requests

A pull request should:

1. Reference the epic it advances (`EPICS.md`).
2. State what was verified and how — the actual command and its result,
   not a description of what the command would show.
3. Not contain unrelated changes.
4. Not contain real device identifiers, production captures or
   credentials.

## Evidence

Work that is claimed as complete must leave reviewable evidence. For
milestone work this means an evidence bundle under
`.factory/evidence/<ACT-ID>/`. See the acceptance criteria in the
relevant ACT for the exact contents.

The rule is simple: **never report a command result that was not
observed.** If a background command was launched but its result was not
consumed, it is not evidence.

## Reporting a security issue

Do not open a public issue. See [SECURITY.md](SECURITY.md).

## Licence

Contributions are accepted under the MIT licence that covers the
repository. See [LICENSE](LICENSE).
