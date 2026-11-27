# The validator qualification of the executable subject

The qualification was executed with the repository-owned script
`tools/qualify_validator.sh`, which pins every input.

## The pinned inputs

| Input | Pin | Observed |
|---|---|---|
| Validator | `jschema` commit `a936862556f24fde475059c560c1a13f00291457` | tree digest `323f47f8…73a8`, verified |
| Test suite | `JSON-Schema-Test-Suite` revision `245a45abc90190c0bff04d97e6d2b541b4bb9f12` | verified |
| Corpus and remote tree | digest over both trees | `45bf30e6bc639547d4b7a75fe152fce5451e523fa976ff82f0576e9c6fcd1322`, verified |
| Remote schemas | 79 files | digest `F18EE856D4C17EF4` |

`qualification_authoritative=true`: no caller-supplied digest override
was used. An override, when used, classifies the result as
non-authoritative unless the caller also states that the result is
authoritative.

## The witnesses

The harness's own oracle is witnessed before the corpus is measured. Every
controlled provider is detected:

| Provider | Verdict | Denominator | Passed | Failed |
|---|---|---|---|---|
| always-accept | FAIL | 4 | 2 | 2 |
| always-reject | FAIL | 4 | 2 | 2 |
| inverted | FAIL | 4 | 0 | 4 |
| error | FAIL | 4 | 0 | 4 |
| correct | PASS | 4 | 4 | 0 |
| unsupported | PASS | 4 | 4 | 0 |

The accounting witnesses follow: a wrong raw answer outside the adapter
subset is a raw failure; the adapter's refusal of a supported case is a
failure; a stale exclusion produces invalid evidence and fails the
qualification; an empty effective denominator cannot establish a PASS; a
correct measurement satisfies `denominator = passed + failed`; and an
authorised policy exclusion is honoured and reported with its reason. An
authorised upstream limitation is accepted for the product, and the same
failure without the authorisation is not.

`witness_failures=0`.

## The two measurements

| Measurement | Denominator | Passed | Failed | Verdict |
|---|---|---|---|---|
| Raw upstream (the library) | 1300 | 1300 | 0 | PASS |
| Ironkeeper adapter (the supported subset) | 949 | 949 | 0 | PASS |
| Product qualification | — | — | — | PASS |

The corpus holds 2374 cases: 1300 mandatory and 1074 optional. The
optional results are reported separately and do not block the product
qualification; they are not described as measured successful conformance.

351 mandatory cases lie outside the supported subset. Each is excluded
with its reason recorded — an unsupported keyword (`unevaluatedProperties`,
`unevaluatedItems`, `dependencies`, `$dynamicRef`, `$dynamicAnchor`,
`contentMediaType`, `contentEncoding`, `contentSchema`, …) or a dialect
this build does not implement. No exclusion was unauthorised, stale,
duplicated or malformed, and no exclusion was counted as a pass.

The exit status of the qualification was 0.
