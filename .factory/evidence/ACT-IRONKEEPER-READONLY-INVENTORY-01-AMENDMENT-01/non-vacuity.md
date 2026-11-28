# Non-vacuity

A test that passes whether or not the behaviour it is meant to pin down
proves nothing. The repository gate reverses each critical check, shows
that the corresponding witness **fails**, and restores the
implementation:

```sh
tools/gate_storage_non_vacuity.sh
```

## The checks of this amendment

| Check | Reversed correction | Witness that must fail |
|---|---|---|
| `production-seam` | the discovery-root seam of the production build | the production binary does not read the synthetic tree |
| `pipe-stream-identity` | the stream identity of the poll descriptor | the standard error keeps its own data |
| `capacity-trailing-zero` | the trailing zero of the capacity arithmetic | the capacity conserves every digit |
| `missing-protection` | the mapping of an absent protection field | a missing protection field is never Type 0 |
| `smart-bitmask-2` | the decoding of the failing-status bit | the bit 8 is decoded independently |

The checks of the predecessor are retained and still pass:
`identity-conflict`, `exact-precision`, `missing-counter`,
`backend-timeout`, `smart-bitmask` and `scsi-protection`.

## The observed result

```text
gate: ok   identity-conflict (the witness failed as expected)
gate: ok   exact-precision (the witness failed as expected)
gate: ok   missing-counter (the witness failed as expected)
gate: ok   backend-timeout (the witness failed as expected)
gate: ok   smart-bitmask (the witness failed as expected)
gate: ok   scsi-protection (the witness failed as expected)
gate: ok   production-seam (the witness failed as expected)
gate: ok   pipe-stream-identity (the witness failed as expected)
gate: ok   capacity-trailing-zero (the witness failed as expected)
gate: ok   missing-protection (the witness failed as expected)
gate: ok   smart-bitmask-2 (the witness failed as expected)
gate: ok   restored-implementation (the suite is green)
gate: PASS storage-non-vacuity
```

The gate restores every mutated file from its saved copy and reruns the
suite at the end, so it never leaves a deliberately broken implementation
behind.

## The witness must be deterministic

A witness that detects its defect only sometimes is not a witness. The
native run `46031059134` showed exactly that: the pipe stream identity
phase reported that the mutation did not make the suite fail.

The cause was a race in the **witness**, not in the implementation. The
witness closed the standard output and wrote to the standard error
immediately afterwards. The defect that the witness pins down is only
observable while the standard error is the *only* stream left in the
poll descriptor array, so the write has to arrive strictly after the
parent observed the end of file. Whether that happened depended on the
scheduling of the child against the parent, and on a loaded runner the
mutation went unnoticed.

The witness now delays the write, which fixes the ordering. The
determinism was measured against the **mutated** implementation, where
the witness must fail:

| Implementation | Runs | The witness failed |
|---|---|---|
| the mutated one, the delay in place | 15 | 15 |
| the restored one | the gate | the suite is green |

The reason of a failing phase is reported as a workflow annotation as
well as in the gate log. The annotation is part of the public
check-run record, so the failure of a native run is diagnosable without
the administrative rights that the job log requires.

