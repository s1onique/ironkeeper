# Negative witnesses

Every mandatory negative witness required by the ACT is listed here with
the mechanism that rejects it and the test that proves it.

The witnesses are **not** a list of intentions: each one is exercised by
a test that fails when the corresponding check is removed. The
non-vacuity demonstration is in `non-vacuity.md`.

## Summary

| # | Witness | Rejected by | Test |
|---|---|---|---|
| 1 | Unknown schema version | strict reader / schema `const` | `tests/contract/schema_contract_tests.nim` |
| 2 | Unknown nested property | schema `additionalProperties: false` | `tests/contract/schema_contract_tests.nim` |
| 3 | Missing mandatory property | schema `required` | `tests/contract/schema_contract_tests.nim` |
| 4 | Duplicate key at the top level | strict reader | `tests/unit/strictjson_tests.nim` |
| 5 | Duplicate key in a nested object | strict reader | `tests/unit/strictjson_tests.nim` |
| 6 | Duplicate key via equivalent escapes | strict reader | `tests/unit/strictjson_tests.nim` |
| 7 | Wrong primitive type | strict reader / schema `type` | `tests/unit/strictjson_tests.nim`, `tests/unit/validator_tests.nim` |
| 8 | String in place of a boolean | schema `type` | `tests/contract/schema_contract_tests.nim`, `tests/unit/validator_tests.nim` |
| 9 | Forbidden destructive-operation policy | schema `const: false` + semantic layer | `tests/unit/config_semantics_tests.nim`, `tests/contract/schema_contract_tests.nim` |
| 10 | Malformed JSON | strict reader | `tests/unit/strictjson_tests.nim` |
| 11 | Invalid UTF-8 | strict reader | `tests/unit/strictjson_tests.nim` |
| 12 | Trailing content | strict reader | `tests/unit/strictjson_tests.nim` |
| 13 | Oversized document | strict reader size limit | `tests/unit/strictjson_tests.nim` |
| 14 | Excessively nested document | strict reader depth limit | `tests/unit/strictjson_tests.nim` |
| 15 | Numeric overflow / precision loss | strict reader 2^53 bound | `tests/unit/strictjson_tests.nim` |
| 16 | Unsupported schema keyword | meta-validation | `tests/unit/validator_tests.nim` |
| 17 | Unresolvable / prohibited external reference | validator reference policy | `tests/unit/validator_tests.nim` |
| 18 | Unknown CLI argument | argument parser | `tests/unit/cli_args_tests.nim`, `tests/integration/cli_tests.nim` |
| 19 | Missing configuration file | CLI input handling | `tests/integration/cli_tests.nim` |

## Observed results

### Strict ingestion

```
$ ./build/unit_tests
ok   cli-args (15 checks, 0 ms)
ok   config-semantics (16 checks, 0 ms)
ok   strictjson (54 checks, 16 ms)
ok   validator-adapter (37 checks, 5 ms)
ok   unit-suites
```

Each rejection below is asserted by a named check in
`tests/unit/strictjson_tests.nim`:

| Check name | Input | Observed |
|---|---|---|
| rejects a truncated object | `{"a":` | rejected |
| rejects a truncated array | `[1,2` | rejected |
| rejects an unquoted member name | `{a:1}` | rejected |
| rejects a single-quoted string | `{'a':1}` | rejected |
| rejects a trailing comma | `{"a":1,}` | rejected |
| rejects a leading zero | `{"a":01}` | rejected |
| rejects a leading plus | `{"a":+1}` | rejected |
| rejects a bare minus | `{"a":-}` | rejected |
| rejects a missing fraction | `{"a":1.}` | rejected |
| rejects a missing exponent | `{"a":1e}` | rejected |
| rejects an unescaped control character | `{"a":"x\ty"}` | rejected |
| rejects an invalid escape | `{"a":"\q"}` | rejected |
| rejects an unpaired high surrogate | `{"a":"\ud83d"}` | rejected |
| rejects an unpaired low surrogate | `{"a":"\ude00"}` | rejected |
| rejects trailing content | `{} {}` | rejected |
| rejects trailing garbage | `{}x` | rejected |
| rejects a duplicate top-level member | `{"a":1,"a":2}` | rejected |
| rejects a duplicate nested member | `{"o":{"a":1,"a":2}}` | rejected |
| rejects a duplicate member written with an escape | `{"a":1,"\u0061":2}` | rejected |
| rejects a duplicate nested member written with an escape | `{"o":{"a":1,"\u0061":2}}` | rejected |
| rejects invalid UTF-8 | lead byte without continuation | rejected |
| rejects an overlong UTF-8 encoding | `C0 AF` | rejected |
| rejects a UTF-8 encoded surrogate | `ED A0 80` | rejected |
| rejects NaN | `{"a":NaN}` | rejected |
| rejects Infinity | `{"a":Infinity}` | rejected |
| rejects -Infinity | `{"a":-Infinity}` | rejected |
| rejects a hex literal | `{"a":0x10}` | rejected |
| accepts 2^53 | `{"a":9007199254740992}` | **accepted** (boundary) |
| rejects 2^53 + 1 | `{"a":9007199254740993}` | rejected |
| rejects a negative value beyond the bound | `{"a":-9007199254740993}` | rejected |
| rejects a float beyond the bound | `{"a":1e300}` | rejected |
| rejects a document above the size limit | > 4 MiB | rejected |
| rejects a document above the nesting limit | > 64 levels | rejected |
| accepts a document at the nesting limit | exactly 64 levels | **accepted** (boundary) |

### Validation

```
$ ./build/contract_tests
ok   contracts (35 checks, 49 ms)
ok   version-contract (5 checks, 0 ms)
ok   contract-suites
```

### CLI

```
$ ./build/integration_tests
ok   integration (54 checks, 241 ms)
ok   integration-suites
```

## Observed exit codes

The failure taxonomy was exercised against the compiled binary:

| Invocation | Exit | Observed stderr |
|---|---|---|
| `config validate --file /nonexistent/ironkeeper.json` | 3 | `error: file not found: ...` |
| `config validate --file <malformed>` | 4 | `error: ...` |
| `config validate --file <duplicate member>` | 4 | `error: duplicate object member name: ...` |
| `config validate --file <destructive policy>` | 5 | `error: value does not match const` |
| `config validate --file <unknown property>` | 5 | `error: ...` |
| `not-a-command` | 2 | `error: unknown command: not-a-command` |
| `config validate --not-an-option x` | 2 | `error: unknown option: --not-an-option` |
| `config validate` (missing `--file`) | 2 | `error: missing required option: --file` |
| `daemon` | 8 | `error: the daemon is not implemented in this build` |

No invocation produced an exception trace. The integration suite asserts
this explicitly:

```nim
t.checkNotContains("a missing file does not print a stack trace",
  r.stderrText, "Traceback")
```

## The report on failure

A configuration-validation failure produces a proper report, not an
error message alone. Observed:

```
$ ./build/ironkeeper config validate --file <tmp>/destructive.json --json
{
  "schema_version": 1,
  "report_type": "configuration_validation",
  "report_id": { "id": "...", "created_at": "..." },
  "producer": { "name": "ironkeeper", "version": "0.1.0-dev" },
  "execution": {
    "state": "SUCCEEDED",
    "started_at": "...",
    "finished_at": "..."
  },
  "assessment": {
    "verdict": "FAIL",
    "summary": "the configuration document does not satisfy the configuration contract"
  },
  "findings": [
    {
      "code": "config.schema_violation",
      "severity": "error",
      "message": "value does not match const",
      "location": "/safety/allow_destructive_operations"
    }
  ],
  "subject": { "kind": "configuration_file", "identifier": "..." }
}
$ echo $?
5
```

Note the separation the report makes visible: the **execution**
`SUCCEEDED` — the validation ran correctly — while the **assessment** is
`FAIL` — the configuration is not acceptable. The process exit status is
nonzero.
