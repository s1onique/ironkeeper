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
