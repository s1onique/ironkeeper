# GREEN witnesses

Every witness below is produced by the **production path**, and every
command shown was actually run.

## The production gates

```
$ tools/gate_build_test.sh
gate: ok   typecheck-main
gate: ok   typecheck-unit
gate: ok   typecheck-contract
gate: ok   typecheck-integration
gate: ok   build
ok   cli-args (15 checks, 0 ms)
ok   config-semantics (16 checks, 0 ms)
ok   strictjson (82 checks, 65 ms)
ok   validator-adapter (49 checks, 30 ms)
ok   unit-suites
gate: ok   test-unit
ok   contracts (56 checks, 277 ms)
ok   version-contract (6 checks, 0 ms)
ok   contract-suites
gate: ok   test-contract
ok   integration (81 checks, 509 ms)
ok   integration-suites
gate: ok   test-integration
gate: PASS build-test
```

```
$ tools/gate_schema_drift.sh
embed_schemas: OK (6 schemas, no drift)
gate: ok   schema-drift
gate: PASS schema-drift
```

```
$ tools/gate_independent_check.sh
gate: ok   metaschema-config
gate: ok   metaschema-report
gate: ok   metaschema-error
gate: ok   metaschema-version
gate: ok   example-config
gate: ok   generate-config-report (/tmp/irk-ev-out/config-report.json)
gate: ok   generate-version (/tmp/irk-ev-out/version.json)
gate: ok   crosscheck-config-report
gate: ok   crosscheck-version
gate: ok   generate-schemaindex (/tmp/irk-ev-out/schemaindex.json)
gate: ok   crosscheck-schemaindex
gate: PASS independent-check
```

## The fault-injection harness

`tools/gate_fault_injection.sh` exercises the **actual production gate
scripts** with controlled failing executables. It does not reimplement
the gates.

```
=== the gate scripts are present and executable ===
ok   tools/gate.sh
ok   tools/gate_build_test.sh
ok   tools/gate_schema_drift.sh
ok   tools/gate_independent_check.sh
ok   tools/gate_secret_scan.sh
=== the gate scripts contain no failure-masking constructs ===
ok   no continue-on-error in the gate scripts
=== secret-scan gate: controlled scanner fixtures ===
ok   secret-scan-finding: the gate exited 1
ok   secret-scan-clean: the gate exited 0
ok   secret-scan-broken: the gate exited 1
ok   secret-scan-noreport: the gate exited 1
ok   secret-scan-missing: the gate exited 1
=== schema-drift gate: a failing drift check must fail the gate ===
ok   schema-drift-failure: the gate exited 1
=== build-test gate: a failing mandatory step must fail the gate ===
ok   build-test-typecheck-failure: the gate exited 1
ok   build-test-build-failure: the gate exited 1
ok   build-test-unit-test-failure: the gate exited 1
=== independent-check gate: a failing validation must fail the gate ===
ok   independent-check-validation-failure: the gate exited 1
ok   independent-check-missing-validator: the gate exited 1
=== summary ===
passed: 17  failed: 0
RESULT: PASS — every injected fault was detected by the production gate
```

The build-test cases run against an **isolated copy** of the repository,
so that a stand-in compiler can never overwrite a source file in the
working tree.

## The numeric contract

```
$ /tmp/red-f3/numeric_probe
      9007199254740992 OK   kind=  JInt value=9007199254740992
      9007199254740993 FAIL integer magnitude exceeds the exact binary64 range (2^53): 9007199254740993
    9007199254740993.0 FAIL integer magnitude exceeds the exact binary64 range (2^53): 9007199254740993.0
  9.007199254740993e15 FAIL integer magnitude exceeds the exact binary64 range (2^53): 9.007199254740993e15
   -9007199254740993.0 FAIL integer magnitude exceeds the exact binary64 range (2^53): -9007199254740993.0
   1.00000000000000001 FAIL number is not an integer and cannot be represented exactly: 1.00000000000000001
                1e-400 FAIL number is not an integer and cannot be represented exactly: 1e-400
  -9223372036854775808 FAIL integer magnitude exceeds the exact binary64 range (2^53): -9223372036854775808
  18446744073709551615 FAIL integer does not fit in a 64-bit signed integer: 18446744073709551615
    9007199254740993e0 FAIL integer magnitude exceeds the exact binary64 range (2^53): 9007199254740993e0
  9.007199254740993E15 FAIL integer magnitude exceeds the exact binary64 range (2^53): 9.007199254740993E15
                 1e309 FAIL integer does not fit in a 64-bit signed integer: 1e309
                   0.1 FAIL number is not an integer and cannot be represented exactly: 0.1
                   1.0 OK   kind=  JInt value=1
```

The process no longer terminates: the signed minimum is rejected as a
*value*.

### Equivalent representations agree

```
== 2^53
   9007199254740992 -> JInt(9007199254740992)
   9007199254740992.0 -> JInt(9007199254740992)
   9.007199254740992e15 -> JInt(9007199254740992)
   9007199254740992e0 -> JInt(9007199254740992)
   0.9007199254740992e16 -> JInt(9007199254740992)
== 2^53+1 (all forms)
   9007199254740993 -> REJECTED
   9007199254740993.0 -> REJECTED
   9.007199254740993e15 -> REJECTED
   9007199254740993e0 -> REJECTED
== -(2^53+1) (all forms)
   -9007199254740993 -> REJECTED
   -9007199254740993.0 -> REJECTED
   -9.007199254740993e15 -> REJECTED
== 1
   1 -> JInt(1)      1.0 -> JInt(1)      1e0 -> JInt(1)
   10e-1 -> JInt(1)   0.1e1 -> JInt(1)
== 0
   0 -> JInt(0)      0.0 -> JInt(0)      0e0 -> JInt(0)
   -0 -> JInt(0)      0.000e10 -> JInt(0)
== 100
   100 -> JInt(100)   100.0 -> JInt(100)   1e2 -> JInt(100)
   10e1 -> JInt(100)  1000e-1 -> JInt(100)
```

## The schema policy

```
            unknown keyword: additionalPropeties -> INTERNAL ERROR: the schema is outside the supported schema policy: /additionalPropeties: the keyword 'additionalPropeties' is not supported by Ironkeeper
                           typo keyword: minimun -> INTERNAL ERROR: the schema is outside the supported schema policy: /minimun: the keyword 'minimun' is not supported by Ironkeeper
                          unknown nested keyword -> INTERNAL ERROR: the schema is outside the supported schema policy: /properties/a/minimumx: the keyword 'minimumx' is not supported by Ironkeeper
                  prohibited dialect declaration -> INTERNAL ERROR: unsupported JSON Schema dialect: https://json-schema.org/draft-07/schema
                      nested dialect declaration -> INTERNAL ERROR: the schema is outside the supported schema policy: /properties/a/$schema: a nested '$schema' declaration is not permitted
                                     $dynamicRef -> INTERNAL ERROR: the schema is outside the supported schema policy: /$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper
                            $dynamicRef external -> INTERNAL ERROR: the schema is outside the supported schema policy: /$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper
                                   $ref external -> INTERNAL ERROR: external schema reference is not permitted: https://example.invalid/schema
                 $ref external in nested position -> INTERNAL ERROR: external schema reference is not permitted: https://example.invalid/x
                 $ref unresolvable local pointer -> REJECTED: cannot resolve reference #/$defs/missing
            unknown keyword inside const object -> REJECTED: value does not match const
                  unknown keyword inside example -> REJECTED: expected type "integer"
                unknown keyword as property NAME -> ACCEPTED (no issue)
```

The last line is the important one: a property whose *name* looks like a
keyword is still accepted, and its own schema is still applied.

## Report semantics

```
impossible month  rc=6  valid/struct/sem=False True False
impossible day    rc=6  valid/struct/sem=False True False
impossible hour   rc=6  valid/struct/sem=False True False
impossible minute rc=6  valid/struct/sem=False True False
impossible second rc=6  valid/struct/sem=False True False
non-leap Feb 29   rc=6  valid/struct/sem=False True False
leap day 2024     rc=0  valid/struct/sem=True True True
invalid offset    rc=6  valid/struct/sem=False True False
offset +14:00 ok  rc=0  valid/struct/sem=True True True
offset -12:00 ok  rc=0  valid/struct/sem=True True True
UTC Z ok          rc=0  valid/struct/sem=True True True
UTC frac ok       rc=0  valid/struct/sem=True True True
```

A failed execution with a `PASS` assessment:

```
$ ./build/ironkeeper report validate --file failed_pass.json --json
{
  "schema_version": 1,
  "valid": false,
  "structural_valid": true,
  "semantic_valid": false,
  "issues": [
    {
      "location": "/assessment/verdict",
      "keyword_location": "",
      "message": "a FAILED execution must not carry a PASS assessment"
    }
  ]
}
rc=6
```

An unsupported schema version:

```
$ ./build/ironkeeper report validate --file /tmp/rv.json --json
{ "schema_version": 1, "valid": false, "structural_valid": false, "issues": [ ... ] }
rc=7
stderr: error code: unsupported_schema_version
```

## Bounded ingestion

```
$ /usr/bin/time -l ./build/ironkeeper config validate --file /tmp/red-f5/big.json --json
rc= 3
stdout: {"schema_version":1,"error":{"code":"input_unavailable",
        "message":"the document exceeds the maximum size of 4194304 bytes: ..."}}
             8536064  maximum resident set size
```

The 40 MiB document is rejected with a classified result, and the peak
resident set size is **8.5 MB**, against the unbounded read at the entry
commit. The baseline for a small document is 8.8 MB.

A FIFO and a directory are both classified without hanging:

```
fifo_rc=3 (124 would mean it hung)
{"schema_version":1,"error":{"code":"input_unavailable","message":"file not found: ..."}}
```

## The secret scan

A genuine clean-history scan of the final subject with the pinned
scanner:

```
$ GITLEAKS=<gitleaks 8.30.1> tools/gate_secret_scan.sh
INF 29 commits scanned.
INF scanned ~777989 bytes (777.99 KB) in 147ms
INF no leaks found
gate: scanner exit status = 0
gate: PASS secret-scan: no findings
```

The report was `[]`.

The scanner archive digest was verified against the pinned value:

```
$ shasum -a 256 gitleaks_8.30.1_linux_x64.tar.gz
551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb  gitleaks_8.30.1_linux_x64.tar.gz
```

## The validator qualification

```
$ tools/qualify_validator.sh --suite <path>
validator_commit=a936862556f24fde475059c560c1a13f00291457
validator_tree_sha256=323f47f85dba93a0f96bd3ffd6ec964abe2663e260c988596d7a49a0d68573a8
suite_revision=245a45abc90190c0bff04d97e6d2b541b4bb9f12
draft=2020-12
mandatory_total=1337
mandatory_passed=1337
mandatory_failed=0
optional_total=1037
optional_passed=1031
optional_failed=6
  optional_failure: optional/ecmascript-regex.json / ascii digits -> ckError
  optional_failure: optional/ecmascript-regex.json / ascii non-digits -> ckError
  optional_failure: optional/ecmascript-regex.json / non-ascii digits (BENGALI DIGIT FOUR, BENGALI DIGIT TWO) -> ckError
  optional_failure: optional/ecmascript-regex.json / ascii digits -> ckError
  optional_failure: optional/ecmascript-regex.json / ascii non-digits -> ckError
  optional_failure: optional/ecmascript-regex.json / non-ascii digits (BENGALI DIGIT FOUR, BENGALI DIGIT TWO) -> ckError
adapter_policy_rejected=312
unexplained=0
```

All six optional failures are in `optional/ecmascript-regex.json`, the
documented ECMA-262-versus-PCRE gap. The 312 adapter rejections are the
supported schema policy at work, classified as such and not counted as
unexplained.
