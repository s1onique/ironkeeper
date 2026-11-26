# Validator qualification

Ironkeeper needs a JSON Schema Draft 2020-12 validator that is
permissively licensed, actively maintained, small in dependency footprint,
offline, and correct. This file records how the candidates were evaluated
and what was actually measured.

## Candidates evaluated

### 1. `Niminem/jschema` — SELECTED

| Property | Value |
|---|---|
| Repository | https://github.com/Niminem/jschema |
| Licence | MIT |
| HEAD at evaluation | `a936862556f24fde475059c560c1a13f00291457`, 2026-07-10 |
| Stars | 5 |
| Declared support | Draft 2020-12 |
| Dependency footprint | Nim standard library only (`std/re` for `pattern`) |
| Network access | None. The registry never fetches; the eight official 2020-12 metaschemas are bundled |
| Reference resolution | `$id`, `$anchor`, `$defs`, `$ref`, `$dynamicRef`, `$dynamicAnchor`; RFC 3986 resolution |
| Numeric handling | JSON Schema semantics over IEEE-754 binary64 |
| Format validation | `format` is annotation-only, as the specification requires |
| Error reporting | `ValidationResult` with `instanceLocation`, `keywordLocation` and a message per error |
| Known gap | Infinite recursion is detected and raises rather than overflowing the stack |

### 2. `Vindaar/JsonSchemaValidator` — REJECTED

| Property | Value |
|---|---|
| Repository | https://github.com/Vindaar/JsonSchemaValidator |
| Licence | MIT |
| HEAD at evaluation | 2023-12-20 |
| Source size | 898 lines in one module |
| Declared support | Draft 4 / draft-06 era |

Rejected: the implemented keyword set has no `unevaluatedProperties`, no
`unevaluatedItems`, no `$dynamicRef`, no `$defs` and no `prefixItems`.
It cannot express the contracts that Ironkeeper's own schemas use, and
it cannot be described as a Draft 2020-12 validator.

### 3. `PMunch/jsonschema` — REJECTED

| Property | Value |
|---|---|
| Repository | https://github.com/PMunch/jsonschema |
| Licence | MIT (declared in the manifest; the repository carries no `LICENSE` file) |
| HEAD at evaluation | 2021-07-12 |
| Source size | 487 lines |

Rejected: it is a TypeScript-style schema DSL that generates Nim
verifiers at compile time. It is not a JSON Schema implementation and
cannot validate a document against a runtime-supplied schema, which is
what Ironkeeper needs.

### 4. `Nycto/NimJsonSchemaImporter` — REJECTED

| Property | Value |
|---|---|
| Repository | https://github.com/Nycto/NimJsonSchemaImporter |
| Licence | MIT |
| HEAD at evaluation | 2026-09-25 |

Rejected: it parses schema files with macros to generate Nim types at
compile time. There is no runtime validation, so a schema cannot be
chosen at runtime and cannot validate an arbitrary document.

## Conformance measurement

`jschema` was evaluated against the **official JSON Schema Test Suite**,
cloned from https://github.com/json-schema-org/JSON-Schema-Test-Suite.

The suite was taken from the `legacy` branch, revision
`245a45a test: add missing RFC 3987 coverage to iri and iri-reference
(#1249)`, which is the branch that carries the per-draft corpus at
`tests/draft2020-12/`.

The harness was a small Nim program that loads each test group, calls
`validate(data, schema, registry)` and compares `result.valid` with the
expected `valid` field. Remote schemas were registered from the suite's
`remotes/` directory, matching the `http://localhost:1234/` base URI
that the suite's remote-reference tests use.

### Results

```
$ ./suite /tmp/suite-mandatory /tmp/suite2020/remotes
TOTAL=1300 PASSED=1300 FAILED=0

$ ./suite /tmp/suite2020/tests/draft2020-12 /tmp/suite2020/remotes
TOTAL=2374 PASSED=1843 FAILED=531
```

| Corpus | Total | Passed | Failed |
|---|---|---|---|
| Mandatory draft 2020-12 | 1300 | **1300** | **0** |
| Mandatory + optional | 2374 | 1843 | 531 |

Every one of the 531 failures is inside `optional/`. The specification
marks that directory as optional. The failing files are:

```
optional/bignum.json
optional/cross-draft.json
optional/dependencies-compatibility.json
optional/ecmascript-regex.json
optional/float-overflow.json
optional/format-assertion.json
optional/format/date-time.json
optional/format/format.json
optional/format/... (the remaining optional/format cases)
```

The gaps are real and are not glossed over:

* `optional/bignum.json` — integers beyond binary64 precision.
* `optional/ecmascript-regex.json` — ECMA-262 regular expression
  semantics, which `std/re` (PCRE) does not implement; `\p{...}` and
  `\P{...}` are rejected outright.
* `optional/float-overflow.json` — optional overflow handling.
* `optional/dependencies-compatibility.json` and
  `optional/cross-draft.json` — historical draft compatibility.
* `optional/format/...` — format *assertion* behaviour. `format` is an
  annotation by default in Draft 2020-12, so these are optional.

### Keyword coverage required by Ironkeeper's own schemas

Every keyword and combination that Ironkeeper's schemas use was tested
explicitly, both against the official suite and against Ironkeeper's own
corpus:

| Keyword / feature | Covered by the official suite | Covered by Ironkeeper's tests |
|---|---|---|
| Object boundaries (`additionalProperties`) | yes | yes |
| `required` | yes | yes |
| Unknown properties | yes | yes |
| `type: integer` | yes | yes |
| `type: boolean` | yes | yes |
| `type: string`, `number`, `array`, `object` | yes | yes |
| `enum` | yes | yes |
| `const` | yes | yes |
| Numeric bounds (`minimum`, `maximum`) | yes | yes |
| Array constraints (`minItems`, `maxItems`, `uniqueItems`) | yes | yes |
| String constraints (`minLength`, `maxLength`, `pattern`) | yes | yes |
| Local references (`$ref` to `#/...` and `#/$defs/...`) | yes | yes |
| Composition (`allOf`, `anyOf`, `oneOf`, `not`) | yes | yes |
| `if`/`then`/`else` | yes | yes |

### Conformance claim

Ironkeeper claims **Draft 2020-12 conformance for the mandatory corpus**,
as measured above. It claims **no** general Draft 2020-12 conformance
beyond that corpus. The optional-corpus gaps are recorded here and in
`docs/architecture/overview.md`.

## The known upstream defect, and the mitigation

### Reproduction

`jschema` assumes Draft 2020-12 semantics for `exclusiveMaximum` and
`exclusiveMinimum`, which are **numbers** in that draft. Given the Draft
4 boolean form it dereferences a boolean as a number:

```
$ nim c --path:src probe2.nim && ./probe2
=== testing exclusiveMaximum boolean ===
SCHEMA {"maximum": 3.0, "exclusiveMaximum": true}
.../src/jschema.nim(1055) validate
.../src/jschema.nim(769) evalSchema
.../src/jschema.nim(455) numLess
.../src/jschema.nim(450) asFloat
Error: unhandled exception: field 'fnum' is not accessible for type
'JsonNodeObj' using 'kind = JBool' [FieldDefect]
```

The process is terminated by an uncaught `FieldDefect`. A `Defect` is
not a `CatchableError`, so ordinary `except` clauses do not contain it.

This was also found through the *newer* `main` branch of the test suite,
whose `validation/tests/maximum.json` and `validation/tests/minimum.json`
contain the Draft 4 boolean form:

```
$ ./suite /tmp/suite-main/validation/tests
Error: unhandled exception: field 'fnum' is not accessible ...
```

### Mitigation

Ironkeeper does not expose this behaviour. The adapter in
`src/ironkeeper/contracts/validator.nim` applies a two-stage, fail-closed
protocol.

**Stage 1 — meta-validation.** The schema document is validated against
the bundled Draft 2020-12 metaschema *before* it is used to validate
data. The offending schema is not a valid 2020-12 schema, so it is
refused:

```
$ ./probe4
{"maximum": 3.0, "exclusiveMaximum": true} -> META-REJECT(1): expected type "number"
{"maximum": 3.0}                           -> META-OK
{"type":"string"}                          -> META-OK
{"type":"nonsense"}                        -> META-REJECT(1): value does not match any subschema
{"exclusiveMaximum": false}                -> META-REJECT(1): expected type "number"
```

**Stage 2 — evaluation.** The pre-validated schema validates the data.
Any residual defect is caught by an `except Exception` clause and
reported as an internal failure rather than terminating the process.

**Stage 3 — reference policy.** Any `$ref` that is neither a local JSON
Pointer nor the bundled metaschema URI is rejected before validation is
attempted, so resolution can never reach the network.

The regression witness for this is
`tests/unit/validator_tests.nim`:

```nim
let badExclusive = parseJson("""{"maximum": 3.0, "exclusiveMaximum": true}""")
let outcome = v.validateAgainst(parseJson("3"), badExclusive)
t.check("rejects a schema with a boolean exclusiveMaximum", not outcome.ok)
t.check("reports it as a validation failure, not a crash",
  outcome.error == nil)
```

### Independent cross-check

CI validates the repository schemas and the machine-readable output that
the binary produces with a second, independent implementation,
`check-jsonschema`. That is a CI gate, not the runtime: the shipped
binary performs its own validation with the bundled validator.

The runtime and the independent implementation must agree on the
supported corpus; a divergence fails the CI job.

## Conclusion

A qualified, MIT-licensed, offline, standard-library-only Draft 2020-12
validator was found and its conformance was measured rather than
assumed. The runtime validation guarantees required by the ACT are
therefore established, and the known upstream defect is contained by a
fail-closed adapter with a regression witness.

The verdict for this ACT is `GO_FOUNDATION` with respect to the schema
validator; the optional-corpus gaps are recorded as a known limitation
rather than as a blocker.
