# Architecture overview

This document describes the shape of Ironkeeper: the boundaries between
subsystems, the contracts that cross those boundaries, the toolchain the
project is built with, and the evidence behind the decisions that were
made in milestone M0.

It is authoritative. Where it disagrees with the code, the code is wrong.

## Table of contents

* [Principles](#principles)
* [Subsystem boundaries](#subsystem-boundaries)
* [Contracts](#contracts)
* [Strict JSON ingestion](#strict-json-ingestion)
* [Numeric representation](#numeric-representation)
* [Resource limits](#resource-limits)
* [Error taxonomy and exit codes](#error-taxonomy-and-exit-codes)
* [Toolchain](#toolchain)
* [Validator qualification](#validator-qualification)
* [Dependency decisions](#dependency-decisions)
* [Proposed future decisions](#proposed-future-decisions)
* [Deviations from the suggested layout](#deviations-from-the-suggested-layout)

## Principles

1. **Evidence before conclusion.** Nothing is concluded without preserved
   observations that support it.
2. **Non-destructive by default.** The application observes; it does not
   modify devices unless a future milestone explicitly enables that with
   the authorisation and ownership checks in place.
3. **Deterministic assessment.** Given the same evidence and the same
   policy revision, the assessment is the same.
4. **Fail closed.** When a required check cannot be performed, the
   operation fails. It does not assume the permissive answer.
5. **Honest separation of concerns.** Execution state, assessment verdict
   and device lifecycle state are three different things and are never
   collapsed into one another.

## Subsystem boundaries

The nine boundaries below are architectural. They describe where
responsibility lies; they do not imply that every subsystem exists in
milestone M0.

### 1. CLI and control-plane transport

Owns the command surface, argument parsing, output conventions and the
mapping from failure to exit code. It owns no device access and no policy.

The future control plane is a local Unix domain socket. The CLI of
milestone M0 is a *separate* transport that happens to share the command
vocabulary; the socket API is not implemented and `ironkeeper daemon`
returns an explicit unsupported-operation result rather than pretending
to exist.

*Present:* `src/ironkeeper/cli/`.

### 2. Configuration and contracts

Owns the shape of the configuration document and the rules that a schema
cannot express. Structural validation (JSON Schema) and semantic
validation are separate passes with separate failure classes.

*Present:* `src/ironkeeper/config/`, `src/ironkeeper/contracts/`.

### 3. Device identity and inventory

Owns the mapping between transient access paths (`/dev/sdX`) and physical
device identity (WWN, serial, model, transport, topology). These are
distinct observations and are recorded as such. Multipath aliases are
reconciled before any physical-device operation.

*Not present in M0.*

### 4. Protocol-specific adapters

Owns the translation of a protocol's output into Ironkeeper's normalised
observation model. `smartctl -x -j`, SCSI inquiry data, NVMe
health logs and SAS PHY state each have an adapter. An adapter observes
and normalises; it does not judge.

Prefer proven external tooling over reimplementing protocol-specific
hardware support. See
[ADR-0008](adr/0008-external-tooling-and-native-boundaries.md).

*Not present in M0.*

### 5. Safety and ownership detection

Owns the question "may this operation be performed on this device right
now?" It accounts for mounted filesystems, partitions, swap, device
mapper, LVM, MD RAID, ZFS membership, multipath and open handles.
Absence of evidence of usage is not evidence that a device is unused.

*Not present in M0. The M0 configuration contract already fixes the
mandatory safety policy values that the subsystem will enforce.*

### 6. Job execution and scheduling

Owns the durable job lifecycle: queued, preflight, running, waiting,
verifying, succeeded, failed, cancelled, interrupted. Scheduling and
on-demand execution are two producers into the same engine.

*Not present in M0.*

### 7. Qualification and assessment

Owns the deterministic mapping from evidence to a verdict: `PASS`, `WARN`,
`FAIL` or `INCONCLUSIVE`. Assessment is a pure function of the preserved
evidence and the policy revision. It never performs I/O.

*Not present in M0. The vocabulary is established in
[docs/architecture/lifecycle.md](lifecycle.md) and is exercised by the
report contract.*

### 8. Persistence and evidence

Owns durable state, the evidence store and the guarantee that a
finalised evidence record cannot be silently replaced. Persistence is
still an open decision; see
[Proposed future decisions](#proposed-future-decisions).

*Not present in M0.*

### 9. Observability

Owns logs, metrics and the human-facing rendering of reports. The CLI's
human-readable output is the first observability surface.

*Partially present in M0: the CLI renders reports and findings. No
metrics exporter exists.*

## Contracts

All public documents are JSON Schema Draft 2020-12 and live in
`schemas/v1/`.

| Contract | File | Notes |
|---|---|---|
| Configuration | `schemas/v1/config.schema.json` | Deliberately small |
| Report | `schemas/v1/report.schema.json` | The foundation report type |
| Error | `schemas/v1/error.schema.json` | Machine-readable failures |
| Version | `schemas/v1/version.schema.json` | Build identity |

### Contract invariants

These hold for every contract and are enforced by the contract tests:

* Every public document has an explicit `schema_version`.
* Every object boundary sets `additionalProperties: false`.
* Every required property is listed explicitly.
* Numeric ranges and units are explicit.
* Unknown schema versions are rejected.
* Implicit type coercion is prohibited: `"true"` is not a boolean and
  `1` is not `true`.
* Structural validation and semantic validation are distinct.
* The schema bytes embedded in the binary are byte-for-byte identical to
  the repository files.

### Schema resolution never touches the network

The runtime validator resolves references only against documents that are
already registered. The Draft 2020-12 metaschema and its vocabulary
metaschemas are bundled with the validator. Any `$ref` that is neither a
local JSON Pointer nor the bundled metaschema URI is rejected before
validation is attempted. There is no code path in Ironkeeper that fetches
a schema.

### Unsupported schema keywords must not silently become no-ops

Every schema in the repository is itself meta-validated against the
Draft 2020-12 metaschema before it is used. A schema that uses a keyword
in a way the metaschema rejects is refused, rather than being partially
understood.

## Strict JSON ingestion

`std/json` is permissive: it accepts duplicate member names (last one
wins), ignores trailing content, and produces `NaN`/`Infinity` from
non-standard literals. Ironkeeper replaces it with a strict reader in
`src/ironkeeper/json/strictjson.nim`, which enforces in order:

1. The document is well-formed UTF-8 — no overlong forms, no surrogate
   code points, nothing above U+10FFFF.
2. The document contains exactly one JSON value.
3. No trailing non-whitespace content follows that value.
4. No object contains the same member name twice. Names are compared
   *after* unescaping, so `"a"` and `"a"` collide.
5. No number is non-finite, and no number exceeds the exact-integer range
   of binary64.

The reader is a recursive-descent parser over the raw bytes. It does not
use `std/json` at all, so there is no permissive fallback underneath it.

## Numeric representation

JSON Schema numeric semantics are defined over IEEE-754 binary64. Values
that exceed the exactly representable integer range therefore cannot
participate in exact numeric comparison.

**Rule.** Ironkeeper represents numbers as follows:

* An integer literal whose magnitude is at most 2^53 is represented
  exactly and is validated exactly.
* An integer literal whose magnitude exceeds 2^53 is **rejected** by the
  strict reader, with the message naming the 2^53 bound.
* A fractional or exponent literal whose magnitude exceeds 2^53 is
  **rejected** for the same reason.

**Why reject rather than round.** A storage capacity of 16 EiB expressed
as `17592186044416` is exactly representable, but `17592186044417` is
not: as a binary64 it rounds to `17592186044416`. Silently accepting it
would let a report claim a capacity the device does not have. The bound
is a hard limit precisely so that no such silent corruption is possible.

**Future storage reports.** Byte counters that can exceed 2^53 (for
example lifetime bytes read on a large device) will be carried as
*decimal strings* in the storage report contract, with an explicit
`format` marker, and compared with decimal-string arithmetic. That
convention is a proposal for the storage-report milestone, not an
implemented feature.

## Resource limits

| Limit | Value | Enforced by |
|---|---|---|
| Maximum document size | 4 MiB | strict reader, before parsing |
| Maximum nesting depth | 64 | strict reader, during parsing |
| Maximum exact integer magnitude | 2^53 | strict reader, during parsing |
| Maximum schema `$id` resolution | local only | validator adapter |
| Maximum findings per report | 1024 | report schema |
| Maximum evidence records per report | 4096 | report schema |

These limits are part of the public contract. They are documented here so
that a consumer can predict the outcome of a given input.

## Error taxonomy and exit codes

Every failure the application can report is one of eight kinds. The kind
determines the exit code and the machine-readable `code`.

| Kind | `code` | Exit | Meaning |
|---|---|---|---|
| `EInvalidInvocation` | `invalid_invocation` | 2 | The command line could not be interpreted |
| `EInputUnavailable` | `input_unavailable` | 3 | A required input could not be obtained |
| `EInvalidJsonSyntax` | `invalid_json_syntax` | 4 | Strict ingestion rejected the document |
| `ESchemaValidation` | `schema_validation_failed` | 5 | Schema validation rejected the document |
| `ESemanticValidation` | `semantic_validation_failed` | 6 | Semantic validation rejected the document |
| `EUnsupportedSchemaVersion` | `unsupported_schema_version` | 7 | The document declares an unsupported version |
| `EUnsupportedOperation` | `unsupported_operation` | 8 | The operation is not implemented by this build |
| `EInternalFailure` | `internal_failure` | 70 | An unexpected internal condition |

An ordinary input error never produces an exception trace. The CLI
catches classified failures and renders them; anything that escapes is
reported as an internal failure without a trace.

### Output discipline

* stdout carries the result. In `--json` mode stdout carries **exactly
  one** JSON document.
* stderr carries diagnostics. A failure in `--json` mode that has already
  produced a report writes the diagnostic to stderr only, so that stdout
  stays parseable.

## Toolchain

| Component | Version | Notes |
|---|---|---|
| Nim compiler | 2.4.2 | Official `linux_x64` distribution |
| Nimble | 0.20.1 (bundled) | Dependency resolution |
| Memory manager | ORC (`--mm:orc`) | Explicit, for reproducible behaviour |
| C compiler | gcc 13.2.1 (Alpine) | Linux builds |
| Git | 2.45.4 (Alpine) | |

The toolchain is pinned by digest rather than by version alone:

```
nim-2.4.2-linux_x64.tar.xz
  sha256 0ee5b16e81852a956d4fddb4aa44b5958c645c992132fa43be45f489573ee325
```

The published `sha256` file at
`https://nim-lang.org/download/nim-2.4.2-linux_x64.tar.xz.sha256` carries
the same digest.

### Bootstrap procedure

The bootstrap does not modify the global workstation environment. It
installs into a local prefix:

```sh
mkdir -p "$IRK_TOOLCHAIN"
cd "$IRK_TOOLCHAIN"
curl -fsSLO https://nim-lang.org/download/nim-2.4.2-linux_x64.tar.xz
echo "0ee5b16e81852a956d4fddb4aa44b5958c645c992132fa43be45f489573ee325  nim-2.4.2-linux_x64.tar.xz" \
  | sha256sum -c -
tar xf nim-2.4.2-linux_x64.tar.xz
export PATH="$IRK_TOOLCHAIN/nim-2.4.2/bin:$PATH"
nim --version
```

### Reproducible commands

```sh
nimble build      # release build of the executable
nimble test       # unit and contract tests
nimble check      # type-check every module
```

If Nimble cannot expose those exact task names, the repository-owned
equivalents are `tools/build.sh` and the three test binaries it produces.
The Nimble manifest declares the same tasks, so both paths drive the same
compiler invocations.

### Linux-native execution path

A Darwin build does not prove that Linux-specific code works, so a
Linux-native path is mandatory. The authoritative Linux verification is
**native execution on GitHub-hosted Linux runners**:

| Runner | Architecture | Status |
|---|---|---|
| `ubuntu-24.04` | amd64 | mandatory |
| `ubuntu-24.04-arm` | arm64 | preferred |

Both runners execute the compiled binary natively. No cross-architecture
emulation is used, so an arm64 result is a genuine arm64 execution and a
cross-compiled artefact is never reported as "executed".

The CI workflow installs the same pinned, digest-verified Nim
distribution that the local procedure uses, resolves the same pinned
dependency, and drives the same repository-owned commands
(`tools/build.sh` and the three test binaries it produces). There is no
second implementation of the test suite for CI.

A macOS workstation is used for source editing, portable compilation,
portable unit and contract tests, static analysis and git operations. A
successful macOS run is **not** evidence of Linux-native compatibility,
and is never reported as such.

## Validator qualification

Ironkeeper needs a JSON Schema Draft 2020-12 validator that is
permissively licensed, actively maintained, small in dependency footprint,
and correct. Four candidates were investigated:

| Candidate | Licence | Draft support | Verdict |
|---|---|---|---|
| `Niminem/jschema` | MIT | 2020-12 (complete) | **Selected** |
| `Vindaar/JsonSchemaValidator` | MIT | draft-04/06 era | Rejected: no `unevaluatedProperties`, no `$dynamicRef`, no `$defs`, no `prefixItems` |
| `PMunch/jsonschema` | MIT | not a JSON Schema validator | Rejected: a TypeScript-style schema DSL, not a JSON Schema implementation |
| `Nycto/NimJsonSchemaImporter` | MIT | compile-time import | Rejected: generates Nim types at compile time; no runtime validation |

### Measured conformance

`jschema` was evaluated against the official JSON Schema Test Suite, at
the `legacy` branch revision `245a45a`, draft 2020-12 corpus:

| Corpus | Total | Passed | Failed |
|---|---|---|---|
| Mandatory draft 2020-12 tests | 1300 | 1300 | 0 |
| Mandatory plus optional | 2374 | 1843 | 531 |

Every failure in the optional corpus is in a directory the specification
itself marks optional (`optional/format/`, `optional/bignum.json`,
`optional/ecmascript-regex.json`, `optional/float-overflow.json`,
`optional/dependencies-compatibility.json`, `optional/cross-draft.json`,
`optional/format-assertion.json`). The mandatory corpus — the part the
specification requires an implementation to pass — is complete.

The keyword coverage required by Ironkeeper's own schemas was checked
explicitly: object boundaries (`additionalProperties`), required
properties, unknown properties, integer and boolean types, enumerations,
constants, numeric bounds, array constraints, local references and
schema composition (`allOf`, `anyOf`, `oneOf`, `not`, `if`/`then`/`else`).

### The known upstream defect, and the adapter that contains it

`jschema` assumes Draft 2020-12 semantics for `exclusiveMaximum` and
`exclusiveMinimum`, which are numbers in that draft. Given the Draft 4
boolean form:

```json
{"maximum": 3.0, "exclusiveMaximum": true}
```

it dereferences the boolean as a number and terminates the process with an
uncaught `FieldDefect`. This was reproduced directly against the upstream
library.

Ironkeeper does not expose that behaviour. The adapter in
`src/ironkeeper/contracts/validator.nim` applies a two-stage, fail-closed
protocol:

1. **Meta-validation.** The schema document is validated against the
   bundled Draft 2020-12 metaschema *before* it is used to validate data.
   A schema that is not a valid 2020-12 schema is refused. This alone
   neutralises the defect, because the boolean form is not a valid
   2020-12 schema.
2. **Evaluation.** The pre-validated schema validates the data. Any
   residual defect is caught and reported as an internal failure rather
   than terminating the process.

The adapter also rejects unsupported dialects and prohibits external
references.

**Conformance claim.** Ironkeeper claims Draft 2020-12 conformance for
the mandatory corpus as measured above, and claims *no* general
Draft 2020-12 conformance beyond that corpus. The optional-corpus gaps
are recorded, not glossed over.

### Independent cross-check

CI validates the repository schemas and the generated machine-readable
output with a second, independent implementation (`check-jsonschema`).
That cross-check is a CI gate, not the runtime: the shipped binary
performs its own validation with the bundled validator.

## Dependency decisions

| Dependency | Version | Licence | Why | Used for |
|---|---|---|---|---|
| `jschema` | 0.1.0 | MIT | Only qualified Draft 2020-12 validator for Nim | Runtime schema validation |
| Nim standard library | 2.4.2 | MIT | Everything else | JSON, CLI, filesystem, process |
| `libpcre3` (shared library) | 3.x | BSD-3-Clause | PCRE runtime for `std/re`, which the validator uses for `pattern` | Regex evaluation in schema validation |

There are no other dependencies.

### The PCRE runtime dependency

`jschema` implements the JSON Schema `pattern` keyword with `std/re`,
which is a binding to PCRE. On Linux, Nim's `std/re` loads
`libpcre.so.3` (or `libpcre.so.1`) **dynamically at run time**; the Nim
distribution does not bundle the library and the binding is not linked
statically.

This makes `libpcre3` a genuine runtime dependency of the Ironkeeper
binary on Linux, and it must be installed on the host:

```sh
apt-get install -y libpcre3
```

It is declared here rather than discovered by accident, and the CI
workflow installs it explicitly and asserts its presence with
`ldconfig -p | grep -i pcre` before the build runs.

A deployment that does not install `libpcre3` will build successfully and
then fail when a schema uses `pattern`. That is a packaging defect, not a
runtime one, and it is why the dependency is stated here and checked in
CI rather than left to chance.

Dependency locking: `ironkeeper.nimble` pins `jschema == 0.1.0` exactly.
Nimble's own lock file (`nimble.lock`) is committed when a dependency is
resolved through the package registry, so that a build resolves the same
artefact every time.

## Proposed future decisions

These are **proposals**, not accepted decisions. They are recorded here so
that the next ACT does not have to re-derive them, and so that no one
mistakes them for settled choices.

### Persistence

Candidates: SQLite with native linking; the embedded SQLite amalgamation;
minimal durable file-based persistence.

Considerations: transactional behaviour, crash consistency, deployment
footprint, recovery semantics. A file-based approach with an append-only
evidence log and a rewritten snapshot is attractive for auditability and
has no native dependency; SQLite is attractive for transactional
integrity but adds a native library and an amalgamation of roughly a
megabyte. Unresolved: how much transactional guarantee the evidence store
actually needs, and whether the deployment footprint matters more than
the query capabilities.

### Control plane

Proposed combination: `AF_UNIX`/`SOCK_STREAM`, JSON-RPC 2.0, explicit
newline-delimited framing, bounded request and response sizes, Linux
`SO_PEERCRED` for peer credentials, filesystem access permissions for
authorisation, and systemd socket activation with `Accept=no`.

Unresolved: whether JSON-RPC 2.0 is worth its envelope overhead against a
simpler typed request/response framing; how requests are authenticated
when the client is not a local user; and the exact bound on request size.

### Storage backends

A future implementation plan exists for `smartctl -x -j`, SCSI protection
and capacity discovery, Linux sysfs and udev, native aligned read-only
surface scanning, NVMe health observations, and SAS PHY and expander
topology.

The `smartctl` exit status is a bitmask and **must** be treated as part
of the backend contract: bit 0 is a command-line parse error, bit 1 is a
device open failure, bit 2 is a SMART command failure, bit 3 is a disk
failure detected by SMART, bit 4 is a possible disk failure in the SMART
attribute table, bit 5 is a failure in the SMART attribute table
themselves, bit 6 is an error while reading the SMART attribute table,
and bit 7 is a SMART command error while writing to the device. A
backend that collapses this bitmask into a single success/failure loses
the distinction between "the tool failed" and "the device reported a
problem" — which is exactly the distinction Ironkeeper exists to
preserve.

## Deviations from the suggested layout

The suggested repository layout was followed with two deliberate
adjustments:

* **`src/ironkeeper/json/`** was added. Strict JSON ingestion is a
  distinct, security-relevant concern with its own invariants and its own
  test suite. Folding it into `core/` would have mixed a general-purpose
  utility with the application's domain types.
* **`tools/build.sh`** was added. Nimble cannot expose the exact task
  names the acceptance criteria require on every toolchain version, and a
  repository-owned script guarantees that CI and a developer workstation
  drive identical compiler invocations. It is a thin wrapper over `nim c`,
  not a second build system.

A local Linux virtual machine was also attempted on the macOS
development host, and was abandoned as an unjustified diversion once
native CI runners were identified as the appropriate infrastructure. The
approach is recorded as `SUPERSEDED_EXECUTION_ENVIRONMENT`; it is not an
implementation failure and no product code depends on it.

`src/ironkeeper/contracts/` holds the schemas, the validation adapter and
the report model together, because they are one concern: the published
contracts and the code that enforces them.
