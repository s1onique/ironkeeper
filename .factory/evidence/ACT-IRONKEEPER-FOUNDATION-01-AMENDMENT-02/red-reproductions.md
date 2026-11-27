# RED reproductions

Every counterexample in the review was reproduced against the **real
production path** at the entry commit `aeb10ae`, before any repair. The
inputs, the observed results and the intended invariant are recorded here.

## F1 — CI failure masking

### Method

The step structure of `.github/workflows/ci.yml` at the entry commit was
reproduced verbatim: the same `set +e`, the same compound command group,
the same `PIPESTATUS` capture and the same `exit 0`.

### Observed

```
step=typecheck     step_rc=0  outcome=success  recorded=status=0
step=buildtest     step_rc=0  outcome=success  recorded=status=0
step=contract      step_rc=0  outcome=success  recorded=status=0
step=integration   step_rc=0  outcome=success  recorded=status=0
step=schemacheck  step_rc=0  outcome=success  recorded=status=1
step=crosscheck    step_rc=0  outcome=success  recorded=status=0
```

Every counterexample concluded **success**:

| # | Counterexample | Observed | Intended invariant |
|---|---|---|---|
| 1 | a type-check command fails, followed by a successful command | step `success`, `status=0` | the gate must fail |
| 2 | unit tests fail while subsequent suites pass | step `success`, `status=0` | the gate must fail |
| 3 | contract tests fail while integration tests pass | step `success`, `status=0` | the gate must fail |
| 4 | integration tests fail, followed by successful log rendering | step `success`, `status=0` | the gate must fail |
| 5 | embedded-schema drift verification fails | step `success`, `status=1` recorded but never read | the gate must fail |
| 6 | independent validation of a generated report fails | step `success`, `status=0` | the gate must fail |

Case 5 is the sharpest: the step *recorded* `status=1` and then exited
`0`, and the enforcement step that read `status` had already been
superseded by the `outcome` check, which saw `success`.

### The invariant

> No mandatory command failure may be converted into a successful CI gate
> by subsequent execution, logging, report generation or artifact
> collection.

## F2 — secret scan forced success

### Method

The `secret-scan` job's step body was reproduced verbatim, with a
controlled stand-in scanner that behaves like the real one under
`--exit-code 1`: it writes a report and exits 1.

### Observed

```
step_rc=0
--- GITHUB_OUTPUT ---
gitleaks_status=1
--- report present? ---
-rw-r--r--  1 user  staff  66 gitleaks-report.json
[{"RuleID":"generic-api-key","File":"fixture.txt","StartLine":1}]
```

The scanner **detected a finding** and exited 1. The step captured that
status and then ran `exit 0`, so the step's outcome was `success`. The
enforcement step was guarded by `if: steps.gitleaks.outcome == 'failure'`,
which therefore never fired. The finding was **silently discarded**.

### The invariant

A detected secret must fail the gate. A missing or malformed mandatory
report must never be represented as a clean scan.

## F3 — precision loss before validation

### Method

The compiled production reader was exercised with the exact inputs from
the review, plus mathematically equivalent spellings.

### Observed

```
      9007199254740992 OK   kind=  JInt value=9007199254740992
      9007199254740993 FAIL integer magnitude exceeds the exact binary64 range (2^53): 9007199254740993
    9007199254740993.0 OK   kind=JFloat value=9007199254740992.0
  9.007199254740993e15 OK   kind=JFloat value=9007199254740992.0
   -9007199254740993.0 OK   kind=JFloat value=-9007199254740992.0
   1.00000000000000001 OK   kind=JFloat value=1.0
                1e-400 OK   kind=JFloat value=0.0
```

and then the process **terminated**:

```
Error: unhandled exception: over- or underflow [OverflowDefect]
    strictjson.nim(308) parseNumber
```

Four distinct defects:

| Input | Observed | Defect |
|---|---|---|
| `9007199254740993.0` | `9007199254740992.0` | an out-of-range value was **rounded into the accepted range** |
| `9.007199254740993e15` | `9007199254740992.0` | the same value, the same corruption |
| `-9007199254740993.0` | `-9007199254740992.0` | the same, with the sign |
| `1.00000000000000001` | `1.0` | a **noninteger became an integer** |
| `1e-400` | `0.0` | a **nonzero number became zero** |
| `-9223372036854775808` | `OverflowDefect`, process terminated | an **unhandled overflow defect** |

The overflow was located precisely. The reader computed
`abs(v) > MaxExactIntMagnitude` on a parsed `int64`, and `abs(int64.low)`
overflows:

```
$ nim c --mm:orc --hints:off -o:int_probe int_probe.nim && ./int_probe
parseBiggestInt ok: -9223372036854775808
abs(v) computed ->
OverflowDefect: over- or underflow
```

### The invariant

The numeric range must be decided from the source text, before any lossy
conversion. A value must never be rounded into the accepted range, a
noninteger must never become an integer, a nonzero number must never
become zero, and the signed minimum must be rejected as a *value* rather
than terminating the process.

## F4a — unsupported schema constructs

### Method

The compiled production validator adapter was exercised with the schemas
from the review.

### Observed

```
            unknown keyword: additionalPropeties -> ACCEPTED (no issue)
                           typo keyword: minimun -> REJECTED: expected type "integer"
                          unknown nested keyword -> ACCEPTED (no issue)
                  prohibited dialect declaration -> INTERNAL ERROR: unsupported JSON Schema dialect
                      nested dialect declaration -> REJECTED: expected type "string"
                                     $dynamicRef -> REJECTED: cannot resolve reference #meta
                            $dynamicRef external -> REJECTED: cannot resolve reference ...
                                   $ref external -> INTERNAL ERROR: external schema reference is not permitted
                 $ref external in nested position -> INTERNAL ERROR: external schema reference is not permitted
                 $ref unresolvable local pointer -> REJECTED: cannot resolve reference #/$defs/missing
            unknown keyword inside const object -> REJECTED: value does not match const
                  unknown keyword inside example -> REJECTED: expected type "integer"
                unknown keyword as property NAME -> ACCEPTED (no issue)
```

The decisive results are the first and the third:

* `{"type": "object", "additionalPropeties": false}` was **ACCEPTED**.
  The misspelled keyword is a *valid* Draft 2020-12 schema, so
  meta-validation accepts it, and the intent — a closed object boundary
  — is silently lost.
* `{"type": "object", "properties": {"a": {"type": "integer",
  "minimumx": 5}}}` was **ACCEPTED**, for the same reason.

The `minimun` case was rejected only *incidentally*: the schema
`{"type": "integer", "minimun": 10}` failed the data check, not the
keyword check. `10` is not an integer, so the rejection had nothing to
do with the misspelled keyword.

### The invariant

Meta-validation alone is not an unknown-keyword rejection mechanism. An
explicit policy over the schema constructs Ironkeeper actually supports
is required, and it must distinguish a keyword from a *name*.

## F4b — report semantics

### Method

The compiled CLI was exercised with report documents carrying impossible
timestamps and with a failed execution carrying a `PASS` assessment.

### Observed

```
impossible month  ts=2026-13-02T03:04:05Z  rc=0  {"schema_version":1,"valid":true,"issues":[]}
impossible day    ts=2026-02-30T03:04:05Z  rc=0  {"schema_version":1,"valid":true,"issues":[]}
impossible hour   ts=2026-01-02T25:04:05Z  rc=0  {"schema_version":1,"valid":true,"issues":[]}
impossible minute ts=2026-01-02T03:61:05Z  rc=0  {"schema_version":1,"valid":true,"issues":[]}
impossible second ts=2026-01-02T03:04:61Z  rc=0  {"schema_version":1,"valid":true,"issues":[]}
non-leap Feb 29   ts=2026-02-29T00:00:00Z  rc=0  {"schema_version":1,"valid":true,"issues":[]}
invalid offset    ts=2026-01-02T03:04:05+25:00  rc=0  {"schema_version":1,"valid":true,"issues":[]}
```

and:

```
failed-execution-with-PASS rc=0 out={"schema_version":1,"valid":true,"issues":[]}
```

Every impossible timestamp was reported **valid**, and a `FAILED`
execution with a `PASS` assessment was reported **valid**.

### The invariant

A timestamp must represent a valid supported calendar time. A failed or
incomplete mandatory evidence acquisition must not produce an accepted
`PASS` assessment. `report validate` must not imply that a structurally
valid report has authentic evidence.

## F4c — public output contracts

### Method

Every machine-readable CLI output was inspected against the repository
schemas.

### Observed

`schemas/v1/` held four schemas: `config`, `report`, `error` and
`version`. Three public outputs had **no schema at all**:

| Output | Shape | Schema |
|---|---|---|
| `version --json` | `{name, version, schema_versions, contract}` | `version` — covered |
| `schema list --json` | `{schema_version, schemas[]}` | **none** |
| `report validate --json` | `{schema_version, valid, issues[]}` | **none** |
| `config validate --json` | a report | `report` — covered |
| a classified failure | `{schema_version, error}` | `error` — covered |

The unsupported schema version was also misclassified:

```
$ ./build/ironkeeper report validate --file /tmp/rv.json --json   # {"schema_version": 99}
{ ... "valid": false, "issues": [ ... ] }
rc=5
```

Exit 5 is `schema_validation_failed`. The documented classification for
an unsupported version is `unsupported_schema_version`, exit **7**.

### The invariant

Every machine-readable output must have an authoritative strict schema
or an explicitly documented existing contract. Unsupported schema
versions must receive the documented classification.

## F5 — resource limits applied after reading

### Method

A 40 MiB syntactically valid JSON document was written to a synthetic
ordinary file and passed to the compiled CLI. The peak resident set size
of the child process was measured.

### Observed

At the entry commit:

```
rc= 4 wall_ms= 13
peak_child_rss_bytes= 46774878208
stdout: {"schema_version":1,"error":{"code":"invalid_json_syntax",
         "message":"document exceeds the maximum size of 4194304 bytes", ...}}
```

The whole 40 MiB document was read into memory **first**, and only then
was the size checked. The limit was enforced on the *result*, not on the
*consumption*.

The reader also had no check on the type of the opened input. A FIFO and
`/dev/zero` were rejected, but only incidentally: `fileExists` returns
false for them on this platform, not because the code checks the file
type. Nothing prevented an unbounded stream from a source that
`fileExists` accepts.

### The invariant

The byte limit must be enforced **before** consuming an unbounded input.
At most the limit plus the overflow discriminator may be read. The
opened input type must be validated. Oversized or unavailable input must
return a classified result, and an unexpected special file must not hang
the command.
