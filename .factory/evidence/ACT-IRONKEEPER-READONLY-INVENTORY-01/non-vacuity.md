# Non-vacuity

A test that passes whether or not the behaviour it is meant to pin down
proves nothing. The gate `tools/gate_storage_non_vacuity.sh` therefore
**reverses** each critical check, shows that the corresponding witness
**fails**, and then restores the implementation. The gate is
repository-owned and runs in CI.

## The observed results

```text
=== non-vacuity: identity conflict refusal ===
gate: ok   identity-conflict (the witness failed as expected)
=== non-vacuity: exact counter precision ===
gate: ok   exact-precision (the witness failed as expected)
=== non-vacuity: a missing counter is never a zero ===
gate: ok   missing-counter (the witness failed as expected)
=== non-vacuity: the backend deadline is enforced ===
gate: ok   backend-timeout (the witness failed as expected)
=== non-vacuity: the SMART exit bitmask is decoded ===
gate: ok   smart-bitmask (the witness failed as expected)
=== non-vacuity: the SCSI protection mapping ===
gate: ok   scsi-protection (the witness failed as expected)
=== the restored implementation is green ===
gate: ok   restored-implementation (the suite is green)
gate: PASS storage-non-vacuity
```

## What each mutation reverses

| Mutation | Reverses | Witness that must fail |
|---|---|---|
| `identity.nim`: a conflicting identity becomes `probable` instead of `ambiguous` | the ambiguity refusal | `a duplicated world-wide name is ambiguous` |
| `externaljson.nim`: the decimal result is stripped at both ends instead of the leading end only | the exactness of the counter arithmetic | `a counter with trailing zeros keeps every digit` |
| `smartnorm.nim`: an unavailable field becomes an observed zero | the absence of a zero fabrication | `a missing field is not fabricated as zero` |
| `procexec.nim`: the deadline comparison no longer terminates the child | the bounded execution | `a timeout is classified as a timeout` |
| `smartstatus.nim`: the failing-status bit is never set | the exit-status bitmask | `the failing-status bit is decoded` |
| `scsicap.nim`: a reserved protection combination becomes Type 0 | the protection mapping | `PROT_EN 1 and P_TYPE 3 is reserved` |

The gate restores every mutated file from its saved copy, and it runs the
suite once more at the end to prove that the restored implementation is
green. A deliberately broken implementation is never committed.

## The witnesses that are not mutated

Two witnesses are structural and are exercised by the integration suite
against the compiled binary rather than by a source mutation:

* the **passive discovery** witness: the controlled `smartctl` records
  every execution in a marker file, and the passive commands must never
  create it;
* the **attribution** witness: the identity fingerprint is captured
  before and after the collection, and a change refuses the attribution.

Both are exercised by `tests/integration/storage_cli_tests.nim`.
