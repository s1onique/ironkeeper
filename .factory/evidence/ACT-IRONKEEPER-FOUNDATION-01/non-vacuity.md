# Non-vacuity demonstration

A test that passes whether or not the check it exercises is present
proves nothing. For each critical safety and contract check, the
implementation was temporarily disabled and the relevant test was shown
to fail. The implementation was then restored and the whole suite was
rerun.

**No deliberately broken implementation was committed.** Each change was
made in the working tree, observed, and reverted before the next one.

## Witness 1 — the meta-validation gate

The validator adapter validates every schema against the Draft 2020-12
metaschema before it uses it to validate data. This is what contains
the upstream defect.

The gate was disabled:

```nim
  let meta = metaValidate(v, schema)
  if false and not meta.ok:
    return ValidationOutcome(ok: false, issues: meta.issues)
```

Observed:

```
ok   cli-args (15 checks, 0 ms)
ok   config-semantics (16 checks, 0 ms)
ok   strictjson (54 checks, 28 ms)
FAIL validator-adapter (1 of 37 checks failed)
  - T: expected reports it as a validation failure, not a crash
FAIL unit-suites (1 suite(s) failed)
```

The failing check is the regression witness for the upstream crash:
without the gate, `{"maximum": 3.0, "exclusiveMaximum": true}` reaches
the upstream library and terminates the process.

## Witness 2 — the external-reference prohibition

The adapter refuses any `$ref` that is neither a local JSON Pointer nor
the bundled metaschema URI, so that resolution can never reach the
network.

The prohibition was disabled:

```nim
  let externalRefs = collectExternalRefs(schema)
  if false and externalRefs.len > 0:
```

Observed:

```
ok   config-semantics (16 checks, 0 ms)
ok   strictjson (54 checks, 31 ms)
Traceback (most recent call last):
tests/unit/all_unit_tests.nim(25) all_unit_tests
tests/unit/all_unit_tests.nim(17) main
tests/unit/validator_tests.nim(81) runSuite
SIGSEGV: Illegal storage access. (Attempt to read from nil?)
```

The test fails because the unresolved external reference leaves no
error to inspect. The prohibition is load-bearing.

## Witness 3 — the destructive-operation safety rejection

The semantic layer rejects a configuration that asks for destructive
operations. The schema already refuses it; the semantic layer is the
second, independent barrier.

The rejection was disabled:

```nim
    if v.kind == JBool and v.getBool and false:
      issues.add issue("safety.destructive_operations_forbidden",
```

Observed:

```
ok   cli-args (15 checks, 1 ms)
tests/unit/all_unit_tests.nim(25) all_unit_tests
tests/unit/all_unit_tests.nim(15) main
tests/unit/config_semantics_tests.nim(45) runSuite
Error: unhandled exception: index out of bounds, the container is empty [IndexDefect]
```

The test fails because no issue is produced. The safety rejection is
load-bearing.

## Witness 4 — the duplicate-member-name rejection

The strict reader rejects an object that contains the same member name
twice, including names that are equal only after unescaping.

The rejection was disabled:

```nim
    if false and key in fields:
      return fail(r, "duplicate object member name: " & key)
```

Observed:

```
ok   cli-args (15 checks, 0 ms)
ok   config-semantics (16 checks, 0 ms)
FAIL strictjson (5 of 54 checks failed)
  - T: expected rejects a duplicate top-level member
  - T: names the duplicate member: expected to find duplicate in
  - T: expected rejects a duplicate nested member
  - T: expected rejects a duplicate member written with an escape
  - T: expected rejects a duplicate nested member written with an escape
ok   validator-adapter (37 checks, 18 ms)
FAIL unit-suites (1 suite(s) failed)
```

Five distinct checks fail, covering the top-level case, the nested
case, the escape-equivalent case and the nested escape-equivalent case.

## Restoration

After the last witness the implementation was restored and the whole
suite was rerun:

```
$ tools/build.sh && ./build/unit_tests && ./build/contract_tests && ./build/integration_tests
ok   cli-args (15 checks, 0 ms)
ok   config-semantics (16 checks, 0 ms)
ok   strictjson (54 checks, 10 ms)
ok   validator-adapter (37 checks, 4 ms)
ok   unit-suites
ok   contracts (35 checks, 35 ms)
ok   version-contract (6 checks, 0 ms)
ok   contract-suites
ok   integration (54 checks, 188 ms)
ok   integration-suites
```

`git diff` on the three touched source files after the restoration shows
only the legitimate implementation change — the allowance for the
bundled metaschema reference — and no deliberately disabled check.

## Conclusion

Four independent critical checks were shown to be load-bearing: each
one, when removed, causes a specific test to fail. The tests are
therefore witnesses, not decorations.

The CI run independently confirmed the same property for the whole
suite on two real architectures.
