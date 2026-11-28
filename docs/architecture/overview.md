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
* [Storage observation (M1)](storage-observation.md)
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

*Present in M1:* `src/ironkeeper/storage/sysfs.nim`,
`src/ironkeeper/storage/identity.nim`. See
[storage-observation.md](storage-observation.md). The **handle-bound**
identity authority is not implemented; the tools are executed by
pathname, and the pre/post identity comparison narrows but does not
close the race.

### 4. Protocol-specific adapters

Owns the translation of a protocol's output into Ironkeeper's normalised
observation model. `smartctl -x -j`, SCSI inquiry data, NVMe
health logs and SAS PHY state each have an adapter. An adapter observes
and normalises; it does not judge.

Prefer proven external tooling over reimplementing protocol-specific
hardware support. See
[ADR-0008](adr/0008-external-tooling-and-native-boundaries.md).

*Present in M1:* `src/ironkeeper/storage/smartnorm.nim`,
`src/ironkeeper/storage/scsicap.nim`, `src/ironkeeper/storage/sasphy.nim`.
See [storage-observation.md](storage-observation.md).

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
| Validation result | `schemas/v1/validation.schema.json` | The `report validate --json` result |
| Schema index | `schemas/v1/schemaindex.schema.json` | The `schema list --json` result |

Every machine-readable output of the CLI is covered by one of these
contracts. The contract test suite asserts that each output document
satisfies its schema, and that an oversized diagnostic or a large
finding set cannot produce a document that violates the output contract.

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

### The supported schema policy

Meta-validation answers a different question from the one Ironkeeper needs.
It asks "is this a valid Draft 2020-12 schema?". It does **not** ask "is
this a schema whose keywords Ironkeeper understands?".

The two are easy to confuse, and the confusion is dangerous. A schema
with a misspelled keyword:

```json
{"type": "object", "additionalPropeties": false}
```

is a perfectly valid Draft 2020-12 schema. `additionalPropeties` is not a
keyword at all, so the metaschema accepts it, and a validator that only
meta-validates evaluates it happily. The schema then says nothing about
unknown properties, and the *intent* — a closed object boundary — is
silently lost. The same holds for `{"type": "integer", "minimun": 10}`:
`minimun` is not a keyword, so the bound is silently absent.

Ironkeeper therefore enforces an explicit **supported schema policy**, in
`src/ironkeeper/contracts/schemapolicy.nim`:

* Every keyword in a **schema-bearing position** must be one of the
  documented `SupportedKeywords`. A keyword that is not in that list is
  rejected.
* A **prohibited construct** is rejected outright: a nested `$schema`
  declaration, `$dynamicRef` and `$dynamicAnchor`.
* A **reference** must be a local JSON Pointer or the bundled metaschema
  URI. A reference that cannot be resolved is refused, not ignored.

The schema-bearing positions are the root, the values of `properties`,
`patternProperties` and `$defs`, the values of `items`,
`additionalItems`, `contains`, `propertyNames`, `not`, `if`, `then` and
`else`, and the elements of `allOf`, `anyOf`, `oneOf` and `prefixItems`.

A keyword is **not** a keyword when it is a *property name*, a member of a
`const` object, a member of an `examples` array, or a `default` value.
Those are values, not schemas, and their member names are never treated
as keywords. `{"properties": {"minimun": {"type": "integer"}}}` names a
property called `minimun`, and it is accepted.

A schema outside the policy is a defect **in the schema**, not an invalid
instance. It is therefore reported as an internal failure with the
documented `internal_failure` classification, never as an ordinary
instance issue.

The exception boundary is stated honestly: the policy check is a pure
function over a parsed document. It performs no I/O, resolves no
reference, and evaluates no schema. Catching an exception does **not**
contain a native process crash, a segmentation fault or resource
exhaustion in the upstream library; the fail-closed meta-validation gate
and the supported policy exist precisely so that such a case is never
reached.

### Report semantics are a separate layer

A report that satisfies its schema may still be nonsense. The schema can
only match a timestamp against a regular expression; it cannot know that
`2026-02-30` is not a date.

`src/ironkeeper/contracts/reportsemantics.nim` establishes the rules the
schema cannot express:

* a timestamp must denote a real calendar time — the month must be 1..12,
  the day must exist in that month (so 29 February exists only in a leap
  year), the hour must be 0..23, the minute and second 0..59, and the
  offset hour 0..23 with the offset minute 0..59;
* the execution state and the assessment verdict must agree: a `FAILED`,
  `CANCELLED`, `INTERRUPTED` or incomplete execution must not carry a
  `PASS` assessment. Such a report must carry `INCONCLUSIVE`.

Three concerns are kept distinct, and the distinction is visible in the
machine-readable output:

| Concern | Question | Field |
|---|---|---|
| Structural validity | does the document have the right shape? | `structural_valid` |
| Semantic validity | does the document mean something coherent? | `semantic_valid` |
| Evidence authenticity | is the cited evidence real? | **not answered** |

`ironkeeper report validate` reports on the **document**. It does not
verify that the evidence a report cites is authentic, and it never claims
to. A structurally and semantically valid report is a well-formed claim;
it is not proof.

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

JSON Schema does **not** define a universal numeric model. Its
keywords are written over *mathematical* numbers: the specification
constrains the value, not the representation, and it says nothing about
IEEE-754 binary64.

**The restriction below is an Ironkeeper implementation restriction, not a
JSON Schema requirement.** JSON Schema permits a fractional number, a
number beyond 2^53, and a number that no binary64 can hold exactly; the
upstream validator accepts them. Ironkeeper's *own* contracts do not need
them: they carry small integers — schema versions, severities, counts —
so the strict reader refuses what it cannot represent exactly. A contract
that needs such a value must carry it as a canonical decimal *string*.

Ironkeeper therefore chooses binary64 as *its own* numeric model, and
imposes the exact-integer restriction on its own documents. The choice
is a property of this implementation, not of the specification it
implements.

Binary64 cannot represent every decimal exactly, so a contract that
accepts a number must decide, explicitly, what it accepts and what it
refuses.

### The defect this rule prevents

The strict reader used to decide the numeric range *after* converting the
source text to a binary64. That conversion is lossy, and the loss was
silent:

| Source text | What the reader produced |
|---|---|
| `9007199254740993.0` | `9007199254740992.0` — rounded into the accepted range |
| `9.007199254740993e15` | `9007199254740992.0` — the same value, same corruption |
| `1.00000000000000001` | `1.0` — a noninteger became an integer |
| `1e-400` | `0.0` — a **nonzero** number became zero |

Checking the magnitude *after* the conversion cannot repair this: by then
the information is already gone. The range decision must be made from the
source text.

The reader also computed `abs(v)` on a parsed `int64`. For the signed
minimum, `-9223372036854775808`, that expression overflows and raises an
unhandled `OverflowDefect`, terminating the process.

### The rule

Every JSON number is classified **exactly, from its source text**, by
`src/ironkeeper/json/exactnumber.nim`. The classification uses decimal
string arithmetic only; no binary64 conversion happens before the range
decision.

| Form | Condition | Result |
|---|---|---|
| integer | magnitude fits in `int64` | exact `JInt` |
| integer | magnitude does not fit in `int64` | **rejected** |
| fraction / exponent | the value is not an integer | **rejected** |
| fraction / exponent | integral value, magnitude ≤ 2^53 | exact `JInt` |
| fraction / exponent | integral value, magnitude > 2^53 | **rejected** |

Every mathematically equivalent spelling of the same value is accepted or
rejected **together**. `100`, `100.0`, `1e2`, `10e1` and `1000e-1` are all
accepted and all denote 100. `9007199254740993`, `9007199254740993.0`,
`9.007199254740993e15` and `9007199254740993e0` are all rejected.

### What this rule does not claim

Binary64 does not represent every decimal fraction exactly, and this
project does not claim that it does. The strict reader never represents a
fraction at all: a non-integral decimal is *rejected* rather than rounded.
The accepted value set is therefore a strict subset of what binary64 can
hold, and every accepted value is exact in binary64.

### Lexical resource limits and mathematical value limits

The two kinds of limit are different, and they are documented separately.

A **lexical resource limit** bounds the *size* of the source text: how
many bytes a document may occupy, how deeply it may nest, how many digits
a number's exponent may carry. A lexical limit is a resource decision.
It is enforced on the text, before the value is understood, and it never
depends on the mathematical value.

A **mathematical value limit** bounds the *value*: an integer must fit
in a 64-bit signed integer, and an integral value must be exactly
representable in binary64, which bounds its magnitude at 2^53. A
mathematical limit is a representational decision. It is enforced on the
classified number, from its exact decimal digits, never after a lossy
conversion.

| Limit | Kind | Value | Where |
|---|---|---|---|
| Document size | lexical | 4 MiB | `MaxDocumentBytes`, enforced by the bounded reader |
| Nesting depth | lexical | 64 | `MaxNestingDepth`, enforced by the strict reader |
| Exponent digits | lexical | 9 | `MaxExponentDigits`, enforced by the exact classifier |
| Integer magnitude | mathematical | `int64` | `classifyExact` |
| Exact binary64 magnitude | mathematical | 2^53 | `MaxExactIntMagnitude` |

A number that violates a *lexical* limit is refused because the document
is too large or too deeply nested to process. A number that violates a
*mathematical* limit is refused because the document model cannot hold
the value exactly. The two are never conflated: a document that is within
every lexical limit is never refused for being large, and a small
document is refused for a value it cannot represent.

### Two different policies

The distinction matters, and it is deliberate:

1. **Strict internal Ironkeeper JSON contracts.** This is the policy above.
   Ironkeeper's own contracts carry small integers: schema versions,
   severities, counts. A value that cannot be represented exactly is
   refused.
2. **External hardware JSON acquisition and lossless normalisation.** A
   future storage adapter must preserve the *original* telemetry exactly.
   It therefore does **not** route external numerics through the strict
   reader. External byte counters that exceed 2^53 are carried as
   canonical decimal **strings**, with a documented conversion and range
   semantics, and are compared with decimal-string arithmetic.

A future storage report contract carries large counters as decimal strings
with an explicit format marker. That convention is a decision, not an
implemented feature.

## Resource limits

| Limit | Value | Enforced by |
|---|---|---|
| Maximum document size | 4 MiB | bounded reader, *before* an unbounded read |
| Maximum nesting depth | 64 | strict reader, during parsing |
| Maximum exact integer magnitude | 2^53 | exact number classification, from the source text |
| Maximum signed 64-bit magnitude | 2^63 | exact number classification, from the source text |
| Maximum schema `$id` resolution | local only | validator adapter |
| Maximum findings per report | 1024 | report schema |
| Maximum evidence records per report | 4096 | report schema |
| Maximum external document size | 16 MiB | external ingestion reader |
| Maximum external nesting depth | 64 | external ingestion reader |
| Per-command deadline | 30 s | bounded execution boundary |
| Maximum tool stdout | 4 MiB | bounded execution boundary |
| Maximum tool stderr | 256 KiB | bounded execution boundary |
| Active interrogation concurrency | 1 | bounded execution boundary |

These limits are part of the public contract. They are documented here so
that a consumer can predict the outcome of a given input.

The document-size limit is enforced by a *bounded* reader: the input is
read in chunks and the limit is checked against the number of bytes
actually read, with one extra byte as the overflow discriminator. The
reader never materialises an unbounded document in memory, and it refuses
an input that is not a regular file, so a FIFO or a device node cannot
block the command.

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
| Nim compiler | 2.4.2 | Official distribution, per architecture, pinned by sha256 |
| Nimble | 0.26.2 (bundled) | Dependency resolution |
| Memory manager | ORC (`--mm:orc`) | Explicit, for reproducible behaviour |
| C compiler | gcc 13.x (Ubuntu 24.04) | Linux builds, native runners |
| Git | 2.43.x (Ubuntu 24.04) | |

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
(`tools/gate_build_test.sh`, `tools/gate_schema_drift.sh`,
`tools/gate_independent_check.sh` and `tools/gate_secret_scan.sh`).
There is no second implementation of the test suite for CI.

### The CI gates are fail-closed by construction

The governing invariant is:

> No mandatory command failure may be converted into a successful CI gate
> by subsequent execution, logging, report generation or artifact
> collection.

The workflow enforces it structurally, not by convention:

* Every mandatory command runs through `gate_run`, which executes exactly
  one command and returns *that command's* exit status. Nothing else runs
  inside it, so there is no later command whose success could overwrite an
  earlier failure.
* Each gate keeps the list of failed labels and reports it at the end.
  The verdict is derived from that list.
* Diagnostics are collected by a **separate**, explicitly non-mandatory
  call, under `if: always()`. Diagnostics never influence the verdict.
* No mandatory step uses `continue-on-error`.
* A successful artifact upload or a successful log rendering is never a
  gate success.

`tools/gate_fault_injection.sh` proves the property against the **actual
production gate scripts**, using controlled failing executables. It
asserts that every injected fault — a failing type-check followed by a
success, a failing unit test, a failing independent report validation, a
failing schema drift check, a scanner that finds a secret, a scanner that
cannot execute, a scanner that produces no report, a missing scanner — is
propagated to a nonzero terminal result.

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

`jschema` is qualified against the official JSON Schema Test Suite by a
**repository-owned harness**, `tools/validator_conformance.nim`, driven by
`tools/qualify_validator.sh`. Every input is pinned, so a result always
identifies the exact artefacts it was measured against.

| Input | Pin |
|---|---|
| Validator | `jschema` at `a936862556f24fde475059c560c1a13f00291457`, tree digest `323f47f8…` verified |
| Test suite | `JSON-Schema-Test-Suite` at `245a45abc90190c0bff04d97e6d2b541b4bb9f12` (the `legacy` branch) |
| Draft | Draft 2020-12 |
| Mandatory corpus | every file directly under `tests/draft2020-12/` |
| Optional corpus | every file under `tests/draft2020-12/optional/`, classified individually |

The reproducible command is:

```sh
tools/qualify_validator.sh
```

It verifies the validator's tree digest and the suite's revision, and
refuses to run against a different revision. The suite is **not** required
for routine developer iteration: the project's own test suite does not
need it. It is required to **requalify**, which is necessary whenever the
dependency revision, the adapter, the numeric policy or the supported
keyword set changes.

The harness measures three things separately and reports them separately:

1. **Upstream raw-validator conformance** — the library driven directly,
   with no Ironkeeper policy in the way.
2. **Ironkeeper adapter conformance** — the same cases driven through the
   adapter, which adds the supported schema policy, the reference policy
   and the meta-validation gate.
3. **Ironkeeper contract policy** — the cases the adapter rejects
   *because of the supported schema policy*.

A case the adapter rejects for a reason that is neither the upstream
defect nor the supported policy is an **unexplained** result. Unexplained
results are counted, reported individually, and fail the qualification.

#### Results

The counts below are the ones the **corrected** harness produces. The
previous receipt's counts are **superseded**: the harness they came from
loaded `expectedValid` and never compared it with the observed verdict, so
they measured activity, not conformance. The historical observation is
retained here — the harness did produce those counts — but it does not
establish conformance.

```
$ tools/qualify_validator.sh --suite <path>
validator_commit=a936862556f24fde475059c560c1a13f00291457
validator_tree_sha256=323f47f85dba93a0f96bd3ffd6ec964abe2663e260c988596d7a49a0d68573a8
suite_revision=245a45abc90190c0bff04d97e6d2b541b4bb9f12
corpus_digest_sha256=81b3abac420e41bc48c5048e6f80112828972374e332c92190de9c55bc146957
draft=2020-12
corpus_files=80
corpus_cases=2374
mandatory_cases=1300
optional_cases=1074
[raw-upstream]
  denominator=1300
  passed=1300
  failed=0
[ironkeeper-adapter]
  denominator=949
  passed=949
  failed=0
raw_verdict=PASS
adapter_verdict=PASS
```

| Measurement | Corpus | Denominator | Passed | Failed |
|---|---|---|---|---|
| Raw upstream validator | Mandatory draft 2020-12 | 1300 | **1300** | **0** |
| Ironkeeper adapter | Mandatory draft 2020-12, supported subset | 949 | **949** | **0** |

The two denominators differ because they measure different things. The
**raw upstream** measurement covers the whole mandatory corpus: it drives
the library directly, with no Ironkeeper policy in the way, and it is the
measurement of the *library*. The **adapter** measurement covers the
mandatory cases whose schema lies inside Ironkeeper's documented supported
subset: it is the measurement of *Ironkeeper*. The difference — 351
mandatory cases — is the supported subset at work, and every one of them
is excluded with its exact reason recorded, never silently dropped.

The optional corpus (1074 cases) is classified individually and reported
separately. Its membership is derived from the corpus structure — the
official suite places optional tests in a directory named `optional` — and
not from a hand-maintained list of file names.

#### The oracle

A case passes only when the **observed** verdict equals the **expected**
verdict. The harness never counts "the validator returned something" as a
pass. The oracle is witnessed against controlled providers before every
qualification run:

| Provider | Expected verdict |
|---|---|
| always accepts | FAIL |
| always rejects | FAIL |
| inverted verdict | FAIL |
| raises an execution error | FAIL |
| correct verdict | PASS |
| verdict for an explicitly unsupported case | PASS, with the unsupported case explicitly classified |

The witnesses drive the production counting and terminal-verdict logic;
they are not a parallel implementation of it. A harness whose oracle
cannot be shown to reject a wrong answer is not an oracle.

#### The exclusions

An exclusion is only honoured when it is **authorised**:

* the harness itself determined, from the schema document alone, that the
  case lies outside the supported subset; or
* the exact case identity is listed in the repository's authorised
  limitation list, with a reason.

The implementation under test can never exclude its own case. When it
refuses a case the harness considers supported, that refusal is a
**failure**, not an exclusion.

#### The known upstream defect, and the adapter that contains it

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

## Storage observation

The read-only storage observation subsystem of milestone M1 is described
in [storage-observation.md](storage-observation.md). The decisions that
constrain future work are recorded in
[ADR-0009](adr/0009-lossless-external-json-ingestion.md) and
[ADR-0010](adr/0010-observation-identity-and-external-tool-execution.md).

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

#### The library is not available on every distribution

The dependency is a **PCRE1** runtime library. Distributions that have
moved to PCRE2 only — Debian 13 (trixie) among them — do not ship a
`libpcre.so.3` at all, and no `libpcre3` package exists for them. On such
a host the binary does not fail *when a schema uses `pattern*`; it
fails **at start-up**, because the binding loads the library when the
module is initialised:

```
could not load: libpcre.so(.3|.1|)
```

A host that lacks the library therefore needs one of:

* a `libpcre.so.3` provided by the operator (a PCRE1 build), placed
  where the dynamic loader finds it; or
* a distribution that still ships PCRE1.

The Ironkeeper CLI has no command that avoids the dependency, and no
attempt is made to hide it: the dependency is a property of the
validator, and a host that cannot provide it cannot run the binary.
The operator requalification procedure records this as a **host
prerequisite**, not as a step that the operator has to discover.

Dependency locking: there is **one** dependency-resolution mechanism, and
it is the exact-commit resolution that CI performs and that
`tools/qualify_validator.sh` performs. The dependency is fetched at the
exact commit `a936862556f24fde475059c560c1a13f00291457` and its **tree
digest** is verified:

```
git archive HEAD | sha256sum
323f47f85dba93a0f96bd3ffd6ec964abe2663e260c988596d7a49a0d68573a8
```

The digest pins the whole tree, so a rewritten tag or a changed file is
detected. `ironkeeper.nimble` declares `requires "jschema == 0.1.0"`
exactly.

There is **no committed `nimble.lock`**, and none is claimed. The
dependency is not resolved through the Nimble package registry, so
Nimble produces no lock file for it, and a lock file that did not exist
would be a claim without evidence. The exact-commit resolution *is* the
lock.

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
* **`tools/gate*.sh`** were added. The CI gates are repository-owned
  scripts rather than inline workflow logic. A workflow step that runs
  several commands inside a `set +e` block cannot distinguish "the first
  command failed" from "the last command succeeded", and that distinction
  is exactly what a gate must get right. The gate scripts run one
  mandatory command at a time and derive the verdict from the accumulated
  result, so a failure cannot be masked by a later success. The
  workflow calls the scripts; it does not reimplement them.
* **`tools/validator_conformance.nim`** and **`tools/qualify_validator.sh`**
  were added. The validator qualification must be reproducible from the
  repository, with every input pinned, rather than described in prose
  that cannot be re-run.

A local Linux virtual machine was attempted on the macOS development host
during the predecessor ACT and was abandoned as an unjustified diversion
once native CI runners were identified as the appropriate infrastructure.
The approach is recorded as `SUPERSEDED_EXECUTION_ENVIRONMENT`; it is not
an implementation failure and no product code depends on it. One
orphaned process from that attempt could not be signalled from the
sandbox and is recorded as an environment-cleanup finding for the
operator; it is idle, it consumes no CPU, and it cannot affect the
product or its tests.

`src/ironkeeper/contracts/` holds the schemas, the validation adapter and
the report model together, because they are one concern: the published
contracts and the code that enforces them.
