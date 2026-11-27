# Non-vacuity witnesses

Each repair was reverted or disabled in turn, the suite was run, and the
failure was observed. The implementation was then restored and the suite
was rerun.

The rule from `AGENTS.md` is followed: a check was temporarily disabled,
the relevant test was shown to fail, and the implementation was restored.
No deliberately broken implementation is committed.

## F3 — the numeric contract

**Disabled:** the exact classification in `parseNumber` was replaced with
the old lossy binary64 path.

**Observed:**

```
ok   cli-args (15 checks, 0 ms)
ok   config-semantics (16 checks, 0 ms)
FAIL strictjson (21 of 82 checks failed)
  - T: parses an integer member: expected 1 but got 1.0
  - T: expected rejects 2^53 + 1
  - T: expected rejects a negative value beyond the bound
  - T: explains the precision bound: expected to find 2^53 in
  - T: expected rejects the out-of-range value {"a":9007199254740993}
  - T: expected rejects the out-of-range value {"a":9007199254740993.0}
  - T: expected rejects the out-of-range value {"a":9.007199254740993e15}
  - T: expected rejects the out-of-range value {"a":9.007199254740993E15}
  - T: expected rejects the out-of-range value {"a":9007199254740993e0}
  - T: expected rejects the out-of-range value {"a":-9007199254740993}
  - T: expected rejects the out-of-range value {"a":-9007199254740993.0}
  - T: expected rejects the out-of-range value {"a":-9.007199254740993e15}
  - T: expected rejects a noninteger with 17 significant digits
  - T: expected rejects a nonzero number that underflows binary64
  - T: expected rejects a fractional number
  - T: represents it exactly as 100: expected 100 but got 0
  - T: represents it exactly as 100: expected 100 but got 0
  - T: represents it exactly as 100: expected 100 but got 0
  - T: represents it exactly as 100: expected 100 but got 0
  - T: represents it exactly as 100: expected 100 but got 0
  - T: represents it as an integer, not a float: expected JInt but got JFloat
ok   validator-adapter (49 checks, 33 ms)
```

**21 of 82 checks fail.** The repair is load-bearing.

## F4a — the supported schema policy

**Disabled:** the supported-schema-policy gate in `validateAgainst` was
removed.

**Observed:**

```
ok   cli-args (15 checks, 0 ms)
ok   config-semantics (16 checks, 0 ms)
ok   strictjson (82 checks, 52 ms)
FAIL validator-adapter (6 of 48 checks failed)
  - T: expected rejects an unknown keyword
  - T: expected reports an unknown keyword as a schema defect
  - T: expected rejects a misspelled numeric bound keyword
  - T: expected rejects an unknown keyword in a nested schema position
  - T: expected rejects a nested dialect declaration
  - T: expected rejects a dynamic anchor
FAIL unit-suites (1 suite(s) failed)
```

**6 checks fail.** The repair is load-bearing.

This demonstration also exposed a defect in the *test*, not in the
product: the assertion dereferenced `outcome.error.msg` unconditionally,
so with the gate disabled the test binary terminated with `SIGSEGV`
instead of reporting the failure. The assertion was guarded, and the
guard was committed separately. That change makes the failure
observable rather than crashing the observer.

## F4b — the execution/assessment consistency check

**Disabled:** the `PASS`-on-a-failed-execution check in
`validateReportSemantics` was made unreachable.

**Observed:**

```
FAIL integration (3 of 81 checks failed)
  - T: expected report validate rejects a PASS verdict on a failed execution
  - T: expected report validate reports it as a semantic failure
  - T: the reason is named: expected to find PASS assessment in {
  "schema_version": 1,
  "valid": true,
  "structural_valid": true,
  "semantic_valid": true,
  "issues": []
}
FAIL integration-suites (1 suite(s) failed)
```

**3 checks fail.** The repair is load-bearing.

A separate probe confirmed the check itself was disabled, rather than
merely unreachable:

```
$ /tmp/probe_pass
ok=true issues=0
```

## F5 — the bounded-ingestion overflow check

**Disabled:** the `total > limit` check in `readDocument` was removed.

**Observed:**

```
FAIL integration (2 of 81 checks failed)
  - T: an oversized document exits with the input-unavailable status: expected 3 but got 4
  - T: expected the oversized document produces a classified result
FAIL integration-suites (1 suite(s) failed)
```

**2 checks fail.** The repair is load-bearing.

## The CI gates

**Disabled:** each gate's mandatory command was replaced with a
controlled failing executable, and the *actual production gate scripts*
were run.

**Observed:** all 17 injected faults were detected — see
`green-witnesses.md`, "The fault-injection harness". Every injected fault
produced a nonzero terminal result:

| Injected fault | Gate | Result |
|---|---|---|
| a scanner that reports a finding | secret-scan | exit 1 |
| a scanner that finds nothing | secret-scan | exit 0 |
| a scanner that cannot execute | secret-scan | exit 1 |
| a scanner that produces no report | secret-scan | exit 1 |
| a missing scanner | secret-scan | exit 1 |
| a failing schema drift check | schema-drift | exit 1 |
| a failing type-check | build-test | exit 1 |
| a failing build | build-test | exit 1 |
| a failing unit-test binary | build-test | exit 1 |
| a failing independent report validation | independent-check | exit 1 |
| a missing independent validator | independent-check | exit 1 |

## The GitHub Actions negative witness

See `ci-qualification.md`. A deliberately failing test assertion was
pushed to a temporary branch, and the workflow concluded `failure`.
