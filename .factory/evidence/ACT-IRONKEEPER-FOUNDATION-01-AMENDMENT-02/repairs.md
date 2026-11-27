# Repairs

Each repair names the production path it changed and the invariant it
restores. Every repair is exercised by the production path, not by a
reimplementation.

## F1 — authoritative CI gates

### Production path

`tools/gate.sh` provides the shared helper. `tools/gate_build_test.sh`,
`tools/gate_schema_drift.sh`, `tools/gate_independent_check.sh` and
`tools/gate_secret_scan.sh` are the gates. `.github/workflows/ci.yml`
calls them and contains no gate logic of its own.

### What changed

* Every mandatory command runs through `gate_run`, which executes exactly
  **one** command and returns *that command's* exit status. `set -e` is
  suspended only around the command itself, so there is no later command
  whose success can overwrite an earlier failure.
* Each gate accumulates the labels of the failed steps and derives its
  verdict from that list.
* Diagnostics are collected by a separate, explicitly non-mandatory call
  under `if: always()`. They never influence the verdict.
* No mandatory step uses `continue-on-error`.
* The generated documents are produced by a `generate` helper that writes
  to the output file, rather than by `gate_run`, which redirects stdout
  into a log. This was found by the gate itself during the first CI run.

### Invariant restored

> No mandatory command failure may be converted into a successful CI gate
> by subsequent execution, logging, report generation or artifact
> collection.

## F2 — secret scan authority

### Production path

`tools/gate_secret_scan.sh`.

### What changed

The gate now decides the verdict from the scanner's own exit status and
from the contents of the report it produced:

| Situation | Verdict |
|---|---|
| a clean scan with no findings | **pass** |
| the scanner reports findings | **fail** |
| the scanner is missing or not executable | **fail** |
| the scanner cannot execute (nonzero status other than 1) | **fail** |
| the mandatory report was not produced | **fail** |
| the mandatory report is empty | **fail** |
| the mandatory report is not a JSON array | **fail** |
| the report is rendered for diagnosis | the verdict is **not** changed |

The report is removed before the scan, so a report left over from an
earlier run can never be mistaken for the result of this one. The
redacted findings are printed on failure.

The pinned scanner version and the sha256 integrity check are unchanged.

## F3 — the strict numeric contract

### Production path

`src/ironkeeper/json/exactnumber.nim` (new) and
`src/ironkeeper/json/strictjson.nim`.

### What changed

Every JSON number is now classified **exactly, from its source text**,
with decimal string arithmetic only. The classification is:

| Form | Condition | Result |
|---|---|---|
| integer | magnitude fits in `int64` | exact `JInt` |
| integer | magnitude does not fit in `int64` | **rejected** |
| fraction / exponent | the value is not an integer | **rejected** |
| fraction / exponent | integral value, magnitude ≤ 2^53 | exact `JInt` |
| fraction / exponent | integral value, magnitude > 2^53 | **rejected** |

No binary64 conversion happens before the range decision. The magnitude
is compared as a `uint64`, and the signed minimum is never negated, so
`abs(int64.low)` is never evaluated.

Every mathematically equivalent spelling of the same value is accepted
or rejected **together**.

### Invariant restored

A value can no longer be rounded into the accepted range, a noninteger
can no longer become an integer, a nonzero number can no longer become
zero, and the signed minimum is rejected as a value rather than
terminating the process.

### The policy is documented, not implicit

`docs/architecture/overview.md`, "Numeric representation", states the
rule, the defect it prevents, what it does **not** claim (that binary64
represents every decimal fraction exactly), and the distinction between
the two policies:

1. **Strict internal Ironkeeper JSON contracts** — this rule.
2. **External hardware JSON acquisition and lossless normalisation** —
   the original telemetry is preserved exactly and is never routed
   through the strict reader; large counters are carried as canonical
   decimal strings.

`docs/adr/0002-…` records the reasoning. SMART acquisition is **not**
implemented by this amendment.

## F4a — the supported schema policy

### Production path

`src/ironkeeper/contracts/schemapolicy.nim` (new) and
`src/ironkeeper/contracts/validator.nim`.

### What changed

The adapter applies three gates before a schema is used to validate data:

1. **Meta-validation** against the bundled Draft 2020-12 metaschema.
2. **The supported schema policy**: every keyword in a schema-bearing
   position must be one of the documented `SupportedKeywords`; a nested
   `$schema` declaration, `$dynamicRef` and `$dynamicAnchor` are
   prohibited; a reference must be a local JSON Pointer or the bundled
   metaschema URI.
3. **The reference policy**, which prohibits any other reference.

A keyword is **not** a keyword when it is a property *name*, a member of
a `const` object, a member of an `examples` array or a `default` value.
Those are values, and their member names are never rejected.

A schema outside the policy is a defect **in the schema**, not an
invalid instance, so it is reported as an internal failure with the
documented `internal_failure` classification.

The offline behaviour is preserved: the policy check performs no I/O,
resolves no reference and evaluates no schema.

### Invariant restored

Meta-validation alone is no longer relied upon as an unknown-keyword
rejection mechanism.

## F4b — report semantics

### Production path

`src/ironkeeper/contracts/reportsemantics.nim` (new) and
`src/ironkeeper/cli/app.nim`.

### What changed

The semantic layer establishes:

* a timestamp must denote a real calendar time — the month is 1..12, the
  day must exist in that month (29 February only in a leap year), the
  hour is 0..23, the minute and second are 0..59, and the offset hour is
  0..23 with the offset minute 0..59;
* the execution state and the assessment verdict must agree: a `FAILED`,
  `CANCELLED`, `INTERRUPTED` or incomplete execution must not carry a
  `PASS` assessment.

The three concerns are reported separately in the machine-readable
output: `structural_valid`, `semantic_valid`, and the *absence* of any
claim about the authenticity of the cited evidence. `report validate`
reports on the document and says nothing about whether the evidence it
cites is real.

No speculative device-qualification semantics were implemented.

## F4c — public output contracts

### Production path

`schemas/v1/validation.schema.json` and
`schemas/v1/schemaindex.schema.json` (new), and
`src/ironkeeper/cli/app.nim`.

### What changed

The two uncovered outputs now have authoritative schemas:

| Output | Contract |
|---|---|
| `version --json` | `schemas/v1/version.schema.json` |
| `schema list --json` | `schemas/v1/schemaindex.schema.json` |
| `report validate --json` | `schemas/v1/validation.schema.json` |
| `config validate --json` | `schemas/v1/report.schema.json` |
| a classified failure | `schemas/v1/error.schema.json` |

A document that declares an unsupported `schema_version` now receives
the documented `unsupported_schema_version` classification and exit
status 7, instead of an ordinary schema-violation status.

The contract test suite asserts that each output shape satisfies its
contract, and that an oversized diagnostic or a large finding set cannot
produce a document that violates the output contract.

## F5 — bounded ingestion

### Production path

`src/ironkeeper/cli/app.nim`.

### What changed

`readDocument` no longer uses `readFile`. It now:

* opens the input and checks that the **opened handle** refers to a
  regular file, so a FIFO, a device node or a socket cannot block the
  command;
* reads at most the limit **plus one** byte, the extra byte being the
  overflow discriminator;
* returns a classified `input_unavailable` result when the document
  exceeds the limit.

The strict parser's own bounds are unchanged and remain independent.

## F6 — reproducible validator qualification

### Production path

`tools/validator_conformance.nim` and `tools/qualify_validator.sh`
(new).

### What changed

The qualification harness is now repository-owned, with every input
pinned:

| Input | Pin |
|---|---|
| Validator | `jschema` at `a936862556f24fde475059c560c1a13f00291457`, tree digest verified |
| Test suite | `JSON-Schema-Test-Suite` at `245a45abc90190c0bff04d97e6d2b541b4bb9f12` |
| Draft | Draft 2020-12 |
| Mandatory corpus | every file directly under `tests/draft2020-12/` |
| Optional corpus | every file under `tests/draft2020-12/optional/`, classified individually |

The harness measures and reports **separately**:

1. upstream raw-validator conformance;
2. Ironkeeper adapter conformance;
3. Ironkeeper contract policy — the cases the adapter rejects because
   of the supported schema policy.

A case the adapter rejects for a reason that is neither the upstream
defect nor the supported policy is an **unexplained** result. Unexplained
results are counted, reported individually, and fail the qualification.

The deterministic command is `tools/qualify_validator.sh`. The suite is
not required for routine developer iteration; it is required to
requalify, which is necessary whenever the dependency revision, the
adapter, the numeric policy or the supported keyword set changes.

The upstream crash workaround was audited: the regression witness
`tests/unit/validator_tests.nim` exercises the **real adapter**, not the
library directly, and the qualification harness drives the library
directly for the upstream measurement and through the adapter for the
adapter measurement.
