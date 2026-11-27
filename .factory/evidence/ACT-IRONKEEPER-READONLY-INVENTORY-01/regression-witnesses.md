# Regression witnesses

Every witness below exercises the **production** path. The unit tests
live in `tests/unit/storage_tests.nim`, the integration tests in
`tests/integration/storage_cli_tests.nim`, and the contract tests in
`tests/contract/schema_contract_tests.nim`.

| Witness | Where | Behaviour |
|---|---|---|
| Passive discovery | integration | the passive inventory runs no tool and opens no device |
| Missing discovery root | unit, integration | an explicit failure, never a successful empty inventory |
| Disappearing device | unit | a partial observation and an explicit finding |
| Partition and virtual-device inventory | unit, integration | not classified as physical disks |
| Multiple aliases | unit | one reconciled identity where it is justified |
| Duplicate serials | unit | no unsafe merge; the selector refuses |
| Conflicting WWNs | unit | ambiguous identity, the active interrogation is refused |
| NVMe namespaces sharing a controller | unit | distinct namespace identities |
| Target replaced during collection | unit, integration | the attribution is refused when the fingerprint changes |
| Backend nonzero SMART health status | unit, integration | the useful health evidence is preserved and the exit status stays 0 |
| SMART acquisition failure | unit | an incomplete observation, never a healthy one |
| stdout/stderr pipe saturation | unit | no deadlock; the output-limit classification |
| Backend timeout | unit | a bounded termination and a reaped child |
| Oversized output | unit | classified as an incomplete acquisition |
| Malformed external JSON | unit | the raw evidence is preserved, the normalisation is refused |
| Large exact counter | unit, integration | no precision loss beyond 2^53 and beyond 64 bits |
| Duplicate external key | unit | rejected |
| Conflicting exact-number companions | unit | an explicit finding |
| Missing SMART field | unit | unavailable, never a fabricated zero |
| SCSI protection Types 0-3 | unit | the correct normalized mapping |
| Reserved SCSI protection type | unit | unsupported, never silently mapped |
| 4Kn sysfs capacity | unit, integration | the correct 512-byte sector accounting |
| Evidence directory collision | integration | the caller-owned evidence is preserved |
| Public JSON output | contract, integration | independently validated |

## The exact-number witnesses

The numbers exercised by the ingestion path are `0`,
`9007199254740991`, `9007199254740992`, `9007199254740993`,
`18446744073709551615`, `18446744073709551616` and
`340282366920938463463374607431768211455`, together with:

* a large number in an unrelated vendor field;
* a numeric and decimal-string companion agreement;
* a companion disagreement;
* a missing companion;
* an invalid decimal representation;
* duplicate JSON keys;
* invalid UTF-8;
* conflicting normalised identifier fields.

## The defect the trailing-zero witness covers

During the live qualification the rotation rate of a SAS drive was
reported as `1 rpm` instead of `10000 rpm`. The cause was in the exact
decimal arithmetic of the ingestion path: the leading-zero strip of the
result removed the **trailing** zeros as well, so `10000` became `1` and
`30` became `3`.

The defect was fixed in `decMulAddSmall` (only the leading zeros are
removed) and the regression witnesses
`exactIntegerText("10000") == "10000"`,
`exactIntegerText("30") == "30"` and
`hexToDecimal("100000") == "1048576"` were added. The live value is now
correct, which is the observation that confirmed the fix.
