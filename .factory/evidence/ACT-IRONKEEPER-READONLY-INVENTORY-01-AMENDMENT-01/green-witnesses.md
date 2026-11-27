# GREEN — the witnesses that establish the repairs

Every witness is a test of the **production** path. The command that
runs them is the repository gate:

```sh
tools/gate_build_test.sh        # build, unit, contract and integration suites
tools/gate_storage_non_vacuity.sh
```

## The witnesses

| Work item | Witness | Where |
|---|---|---|
| W1 | the production binary does not execute the marker executable | `tests/integration/storage_cli_tests.nim` |
| W1 | the production binary does not read the synthetic tree | `tests/integration/storage_cli_tests.nim` |
| W1 | the two binaries identify their own variant | `tests/integration/storage_cli_tests.nim` |
| W2 | the closed standard output is captured as empty | `tests/unit/storage_witness_tests.nim` |
| W2 | the standard error keeps its own data | `tests/unit/storage_witness_tests.nim` |
| W2 | the standard output keeps its own data | `tests/unit/storage_witness_tests.nim` |
| W2 | both saturated streams are classified as an output limit | `tests/unit/storage_witness_tests.nim` |
| W2 | a single oversized stream is classified as an output limit | `tests/unit/storage_witness_tests.nim` |
| W2 | a child that closes both streams is still bound by the deadline | `tests/unit/storage_witness_tests.nim` |
| W2 | an invalid executable is a launch failure | `tests/unit/storage_witness_tests.nim` |
| W2 | a program that exits with 127 is not a launch failure | `tests/unit/storage_witness_tests.nim` |
| W2 | a signalled child is classified as a signal | `tests/unit/storage_witness_tests.nim` |
| W3 | a disappearing device refuses the attribution | `tests/integration/storage_cli_tests.nim` |
| W3 | a replaced device refuses the attribution | `tests/integration/storage_cli_tests.nim` |
| W3 | a failed rediscovery refuses the attribution | `tests/integration/storage_cli_tests.nim` |
| W3 | a contradicting tool identity refuses the attribution | `tests/integration/storage_cli_tests.nim` |
| W3 | a stable identity stays bound | `tests/integration/storage_cli_tests.nim` |
| W4 | a missing mandatory observation makes the acquisition incomplete | `tests/unit/storage_witness_tests.nim` |
| W4 | a refused attribution makes the acquisition incomplete | `tests/unit/storage_witness_tests.nim` |
| W4 | the incomplete state is named | `tests/unit/storage_witness_tests.nim` |
| W5 | the bit N is decoded independently | `tests/unit/storage_witness_tests.nim` |
| W5 | a synthetic status yields no bit observations | `tests/unit/storage_witness_tests.nim` |
| W5 | an agreeing decimal companion is accepted | `tests/unit/storage_witness_tests.nim` |
| W5 | a disagreeing decimal companion is a conflict | `tests/unit/storage_witness_tests.nim` |
| W5 | the little-endian companion agrees | `tests/unit/storage_witness_tests.nim` |
| W5 | a contradictory little-endian companion is a conflict | `tests/unit/storage_witness_tests.nim` |
| W5 | a malformed little-endian companion is invalid | `tests/unit/storage_witness_tests.nim` |
| W5 | a 128-bit counter keeps every digit | `tests/unit/storage_witness_tests.nim` |
| W5 | an unrelated vendor field does not affect the value | `tests/unit/storage_witness_tests.nim` |
| W6 | the capacity conserves every digit | `tests/unit/storage_witness_tests.nim` |
| W6 | a missing protection field is never Type 0 | `tests/unit/storage_witness_tests.nim` |
| W6 | an out-of-range protection field is invalid | `tests/unit/storage_witness_tests.nim` |
| W6 | an observed disabled protection is Type 0 | `tests/unit/storage_witness_tests.nim` |
| W6 | a reserved combination is reserved | `tests/unit/storage_witness_tests.nim` |
| W7 | a shared controller serial is not a contradiction | `tests/unit/storage_witness_tests.nim` |
| W7 | a conflicting world-wide name is ambiguous | `tests/unit/storage_witness_tests.nim` |
| W7 | an all-zero identifier is not usable | `tests/unit/storage_witness_tests.nim` |
| W8 | the bundle contains every artefact | `tests/integration/storage_cli_tests.nim` |
| W8 | the caller-owned file is preserved | `tests/integration/storage_cli_tests.nim` |
| W8 | the manifest carries the completeness | `tests/integration/storage_cli_tests.nim` |
| W8 | the stored document carries the same completeness | `tests/integration/storage_cli_tests.nim` |

## The observed results

The unit suite, the contract suite and the compiled-CLI suite were run
against the repaired implementation:

```text
ok   boundedread (23 checks)
ok   cli-args (15 checks)
ok   config-semantics (16 checks)
ok   outputbounds (35 checks)
ok   qualification (27 checks)
ok   schemapolicy (24 checks)
ok   storage (74 checks)
ok   storage-witness (81 checks)
ok   strictjson (82 checks)
ok   validator-adapter (51 checks)
ok   unit-suites
ok   integration (102 checks)
ok   storage-integration (73 checks)
ok   integration-suites
```

The exact numbers are those of the local run; the authoritative native
run is recorded in `native-ci.md`.
