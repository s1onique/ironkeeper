# Green witnesses

Every observation below was produced by the repository's own commands at
the subject commit. The commands are named so that each observation can
be reproduced.

## The oracle witnesses (W1, mandatory non-vacuity)

**Command.**

```sh
nim c --mm:orc --hints:off --path:src --path:<deps>/src \
  -o:build/conformance_witnesses tools/validator_conformance_witnesses.nim
./build/conformance_witnesses --corpus tests/fixtures/conformance
```

**Corpus.** `tests/fixtures/conformance/minimal-corpus.json` — four cases:
two valid instances and two invalid instances, in two groups. The second
group's schema carries `contentMediaType`, a keyword Ironkeeper does not
support, so it is the explicitly unsupported case.

**Observed.**

```
witness_corpus_cases=4
witness_corpus_valid=2
witness_corpus_invalid=2
provider=always-accept verdict=FAIL denominator=2 passed=1 failed=1 unauthorised_exclusions=0
ok: the provider 'always-accept' failed as required
provider=always-reject verdict=FAIL denominator=2 passed=1 failed=1 unauthorised_exclusions=0
ok: the provider 'always-reject' failed as required
provider=inverted verdict=FAIL denominator=2 passed=0 failed=2 unauthorised_exclusions=0
ok: the provider 'inverted' failed as required
provider=error verdict=FAIL denominator=2 passed=0 failed=2 unauthorised_exclusions=0
ok: the provider 'error' failed as required
provider=correct verdict=PASS denominator=2 passed=2 failed=0 unauthorised_exclusions=0
ok: the provider 'correct' passed as required
provider=unsupported verdict=PASS denominator=2 passed=2 failed=0 unauthorised_exclusions=0
ok: the provider 'unsupported' passed as required
unsupported_case: minimal-corpus.json#1.0 reason=the schema is outside the supported schema policy: /contentMediaType: the keyword 'contentMediaType' is not supported by Ironkeeper
unsupported_case: minimal-corpus.json#1.1 reason=the schema is outside the supported schema policy: /contentMediaType: the keyword 'contentMediaType' is not supported by Ironkeeper
unsupported_classified=2
known_limitation_classified=0
ok: the unsupported case received an explicit classification
witness_failures=0
RESULT: PASS — every controlled provider was detected correctly
```

The first four providers **fail** the qualification; the correct provider
**passes**; the explicitly unsupported case receives the classification
`clUnsupportedPolicy` with its reason, and it is not counted as a
conformance pass.

These witnesses drive the production counting and terminal-verdict logic:
they call `runCorpus`, `classify`, `countsOf` and `verdictOf` — the same
functions the real qualification uses. They are not a parallel
implementation.

## The qualified result

**Command.**

```sh
tools/qualify_validator.sh --suite <path>
```

**Observed.**

```
validator_commit=a936862556f24fde475059c560c1a13f00291457
validator_tree_sha256=323f47f85dba93a0f96bd3ffd6ec964abe2663e260c988596d7a49a0d68573a8
suite_revision=245a45abc90190c0bff04d97e6d2b541b4bb9f12
corpus_digest_sha256=81b3abac420e41bc48c5048e6f80112828972374e332c92190de9c55bc146957
=== the harness oracle is witnessed against controlled providers ===
RESULT: PASS — every controlled provider was detected correctly
suite_revision=245a45abc90190c0bff04d97e6d2b541b4bb9f12
draft=2020-12
corpus_files=80
corpus_cases=2374
corpus_digest_fnv1a64=7F5B47D94E68318F
mandatory_cases=1300
optional_cases=1074
corpus_representation_limited=9
[raw-upstream]
  denominator=1300
  passed=1300
  failed=0
  unauthorised_exclusions=0
  correct_acceptance=763
  correct_rejection=537
  false_acceptance=0
  false_rejection=0
  execution_error=0
  unsupported_policy=0
  known_limitation=0
  invalid_evidence=0
  verdict=PASS
[ironkeeper-adapter]
  denominator=949
  passed=949
  failed=0
  unauthorised_exclusions=0
  correct_acceptance=570
  correct_rejection=379
  false_acceptance=0
  false_rejection=0
  execution_error=0
  unsupported_policy=0
  known_limitation=0
  invalid_evidence=0
  verdict=PASS
raw_verdict=PASS
adapter_verdict=PASS
raw_mandatory_cases=1300
raw_optional_cases=1074
adapter_mandatory_cases=1300
adapter_optional_cases=1074
```

The per-class counts and the exact exclusions are in
`qualification-results.md`.

## The secret-scan gate witnesses

**Command.**

```sh
tools/gate_fault_injection.sh
```

**Observed** (the secret-scan section):

```
ok   secret-scan-finding: the gate exited 1
ok   secret-scan-clean: the gate exited 0
ok   secret-scan-broken: the gate exited 1
ok   secret-scan-noreport: the gate exited 1
ok   secret-scan-missing: the gate exited 1
ok   secret-scan-nonempty-array: the gate exited 1
ok   secret-scan-trailing-garbage: the gate exited 1
ok   secret-scan-truncated-report: the gate exited 1
ok   secret-scan-report-not-array: the gate exited 1
```

and, for the whole harness:

```
passed: 21  failed: 0
RESULT: PASS — every injected fault was detected by the production gate
```

The scanner-execution and finding witnesses are retained
(`secret-scan-finding`, `secret-scan-broken`, `secret-scan-noreport`,
`secret-scan-missing`), and the four report-validation counterexamples
are added.

### Non-vacuity of the report validation

The report-validation counterexamples were run against the **entry**
revision of the gate (`git show fb9c5f6:tools/gate_secret_scan.sh`) with
the same controlled scanner:

| Report | Entry revision | Repaired revision |
|---|---|---|
| `[{}]` | **exit 0 — passed** | exit 1 |
| `[] trailing garbage` | **exit 0 — passed** | exit 1 |
| `[` (truncated) | **exit 0 — passed** | exit 1 |
| `{"findings": []}` | exit 1 | exit 1 |

The first three passed the entry revision. The repair rejects all four.

## The bounded-ingestion witnesses

**Command.**

```sh
./build/unit_tests
```

**Observed.**

```
ok   boundedread (23 checks, 1 ms)
```

The suite covers an ordinary file, an oversized file, a directory, a
FIFO, a symlink to a regular file, a symlink to a FIFO, a missing file,
the exact limit boundary and the limit-plus-one boundary.

### Non-vacuity of the substitution witness

The substitution witness is **not** vacuous. The descriptor check was
temporarily replaced by the entry revision's pathname pre-check — a
`stat` on the path *before* the open, with the descriptor accepted
without a regularity check — and the suite was rebuilt and rerun:

```
FAIL boundedread (2 of 23 checks failed)
  - T: expected the substituted path does not open as a document
  - T: expected the substitution is refused as not a regular file
```

The implementation was then restored and the suite rerun, green. The
deliberately broken implementation was not committed.

## The reference-policy witnesses

**Command.**

```sh
./build/unit_tests
```

**Observed.**

```
ok   schemapolicy (24 checks, 0 ms)
```

They pin: a `$ref` inside a literal `const` object is data; a `$ref`
inside `examples` is data; a `$ref` inside `default` is data; a
keyword-shaped property name is valid; a local JSON Pointer is permitted;
a local anchor is permitted; the bundled metaschema is permitted; an
external reference is refused; a relative external reference is refused;
a dynamic reference is refused; a dynamic anchor is refused; an
unresolvable local reference is a defect; a reference to a
non-schema-bearing position is refused; a nested `$id` is refused; a
nested `$vocabulary` is refused; a root `$id` and a root `$vocabulary`
are accepted.

## The public output contract witnesses

**Command.**

```sh
./build/integration_tests
```

**Observed.**

```
ok   integration (97 checks, 409 ms)
```

The compiled CLI is exercised with synthetic inputs that produce an
oversized numeric lexeme in a parser diagnostic, an oversized validation
location, an oversized diagnostic message, more validation issues than the
output schema allows, an unsupported schema version, an ordinary valid
configuration document, an ordinary invalid configuration document and
ordinary valid and invalid report documents. Each JSON-mode result is
exactly one JSON document, and every bounded field is within its
contract's limit.

## The independent validation gate

**Command.**

```sh
tools/gate_independent_check.sh
```

**Observed** (with an independent validator that accepts everything, to
show the coverage):

```
gate: ok   metaschema-config
gate: ok   metaschema-error
gate: ok   metaschema-report
gate: ok   metaschema-schemaindex
gate: ok   metaschema-validation
gate: ok   metaschema-version
gate: ok   example-config
gate: ok   generate-config-report (/tmp/icout/config-report.json, exit 0)
gate: ok   generate-version (/tmp/icout/version.json, exit 0)
gate: ok   crosscheck-config-report
gate: ok   crosscheck-version
gate: ok   generate-schemaindex (/tmp/icout/schemaindex.json, exit 0)
gate: ok   crosscheck-schemaindex
gate: ok   generate-validation (/tmp/icout/validation.json, exit 0)
gate: ok   crosscheck-validation
gate: ok   generate-error (/tmp/icout/error.json, exit 3)
gate: ok   crosscheck-error
gate: PASS independent-check
```

All six repository schemas are meta-validated — including `validation`
and `schemaindex`, which the entry revision did not cover. Every
machine-readable CLI command's actual output is validated against its
authoritative contract, the classified failure output is validated
against the error contract, and the expected exit status is checked
alongside the output schema.

The generated documents were additionally validated with an independent
Python `jsonschema` implementation:

```
report: OK
version: OK
schemaindex: OK
validation: OK
error: OK
```

The configuration report that the gate generated is fed back into
`report validate --json`; no second, approximate output producer is used.

## The workspace-ownership witness

**Command.**

```sh
rm -rf /tmp/qualparent && mkdir -p /tmp/qualparent
echo sentinel > /tmp/qualparent/keep-me.txt
mkdir -p /tmp/qualparent/subdir && echo x > /tmp/qualparent/subdir/other.txt
IRK_QUALIFY_WORK=/tmp/qualparent NIM=/bin/false bash tools/qualify_validator.sh
ls -la /tmp/qualparent
```

**Observed.**

```
keep-me.txt
subdir
```

The sentinel file and the caller's own subdirectory survive. The
qualification removed only the workspace it created inside the
caller's directory. The test uses an isolated temporary parent; no real
user-owned project or data directory is touched.
