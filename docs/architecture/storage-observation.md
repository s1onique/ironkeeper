# Storage observation (milestone M1)

This document describes the read-only storage observation subsystem: what
it observes, how it establishes identity, how it acquires telemetry, and
what it explicitly does **not** claim.

It is authoritative. Where it disagrees with the code, the code is wrong.

## The data flow

```text
Linux discovery
       |
       v
Device/path observations
       |
       v
Identity reconciliation
       |
       v
Explicit target selection
       |
       v
Read-only backend execution
       |
       v
Raw evidence + normalized observations
       |
       v
Strict report validation
       |
       v
CLI output / evidence bundle
```

Each arrow is a boundary owned by exactly one module:

| Stage | Module | Owner of the side effect |
|---|---|---|
| Discovery | `src/ironkeeper/storage/sysfs.nim` | reads the filesystem only |
| Identity | `src/ironkeeper/storage/identity.nim` | none |
| Selection | `src/ironkeeper/storage/identity.nim` | none |
| Execution | `src/ironkeeper/storage/procexec.nim` | **runs the process** |
| Ingestion | `src/ironkeeper/storage/externaljson.nim` | none |
| Normalisation | `src/ironkeeper/storage/smartnorm.nim`, `scsicap.nim`, `sasphy.nim` | none |
| Rendering | `src/ironkeeper/storage/documents.nim` | none |
| Evidence | `src/ironkeeper/storage/evidence.nim` | **writes the files** |

A backend adapter never decides admission or qualification policy. It
observes; it does not judge.

## Passive versus active

**Passive** means: the kernel's and udev's own view of the device, read
from the filesystem. A passive operation opens no physical block device
and runs no observation tool. `ironkeeper inventory list` and
`ironkeeper device inspect` without `--smart`/`--capacity` are passive.

**Active** means: a read-only interrogation of a selected device with an
external tool. An active operation may **wake** a sleeping device. That
is why `--allow-wake` is required: the operator states the intent
explicitly. Ironkeeper does not implement or advertise a guaranteed
no-wake mode. `smartctl`'s low-power checks are unsupported for many
devices and behave differently across protocols and controller paths, so
a no-wake promise could not be kept.

Read-only does **not** mean physically side-effect-free. A SMART
acquisition can wake a disk and cause internal device activity.

Ironkeeper never deliberately spins a disk down, resets it, changes its
standby policy, starts or aborts a self-test, resets a PHY counter, or
writes to a block device.

## Observation semantics

An observation is not an assessment. Five domains are kept apart:

1. **Execution outcome** - did the process run? (`ExecOutcome`)
2. **Observation completeness** - what was actually seen?
   (`ObservationStatus`: `observed`, `derived`, `unavailable`,
   `unsupported`, `invalid`, `conflicting`)
3. **Device-reported health** - an ordinary observation value
4. **Identity confidence** - `authoritative`, `probable`, `ambiguous`,
   `unresolved`
5. **Qualification verdict** - **not assigned in M1**

A successfully collected SMART response may describe a failing disk: the
CLI exits successfully and reports `device_reported_health: fail`. An
unavailable SMART status is never converted into "SMART OK". A missing
counter is never fabricated as zero.

## Discovery

The authoritative inputs are:

* `/sys/class/block/<name>/` - the kernel's view of the device
* `/sys/dev/block/<major>:<minor>/` - the same, keyed by device number
* `/run/udev/data/b<major>:<minor>` - udev's recorded properties
* `/dev/disk/by-id/`, `/dev/disk/by-path/` - the persistent aliases

`lsblk` and `lsscsi` are **not** used as the inventory implementation:
their output is a presentation layer, not a stable interface. They are
acceptable as an operator cross-check.

### The sector convention

The `size` attribute of a Linux block device is expressed in **512-byte
sectors**, regardless of the device's own logical block size. The
capacity is therefore `sectors * 512` and never `sectors * logical block
size`. A 4Kn device therefore reports its true byte capacity, not a
quarter of it. The multiplication is checked.

### Device classification

The classes are `physical`, `partition`, `device_mapper`, `raid`, `loop`,
`ram`, `optical`, `virtual` and `unknown`. Only `physical` devices are
active-interrogation targets. A partition is never mistaken for a disk:
the presence of the `partition` attribute decides it, and a name whose
stem is another discovered device corroborates it.

### Failure handling

* A missing discovery root is an **incomplete** inventory with an explicit
  finding. An enumeration failure is never turned into a successful empty
  inventory.
* A device that disappears during the enumeration produces a finding and
  an incomplete inventory.
* A missing attribute produces an explicit finding and an absent field.
* A malformed attribute is reported; it is never coerced.

## Identity

The following concepts are never collapsed into one another:

* **storage identity** - the disk itself: a SCSI logical unit, an ATA
  device, an NVMe namespace
* **namespace / logical unit identity** - the addressed unit
* **controller identity** - the adapter
* **access path** - `/dev/sdX`, an alias, a multipath path
* **transport endpoint** - the SAS port address, the SCSI target

A **persistent device identifier** is an identifier intended to survive
ordinary path changes. M1 introduces **no** persistent enrollment state
and **no** durable identity registry: the identifiers are observed on
every pass and are not stored anywhere except in the evidence bundle that
an operator explicitly asked for.

### Per protocol

* **SAS/SCSI** - the logical-unit WWN is preferred. The SAS target-port
  address and the expander attachment are preserved separately: a SAS
  port address is **not** the disk's logical-unit identifier.
* **SATA/ATA** - a valid ATA WWN is preferred. The serial, the model and
  the firmware are preserved independently. A serial-only identity is a
  *probable* identity; it never becomes globally authoritative.
* **NVMe** - the controller identity, the namespace identity, the
  namespace id, the NGUID, the EUI-64 and the UUID are distinct. Two
  namespaces behind one controller are two storage namespaces: a
  controller serial is never a namespace identity. The NVMe health log is
  **controller-wide**, so its counters are attributed to the controller
  and never presented as namespace-specific measurements.

### Reconciliation

* Identifier formats are canonicalised (`naa.5000cca0570377c4`,
  `0x5000cca0570377c4` and the bare hex digits denote the same
  identifier), and the original value is preserved alongside it.
* Aliases are deduplicated.
* Conflicting identifiers, duplicated serials and duplicated WWNs are
  detected and make the identity **ambiguous**.
* Two devices are never merged because their model or serial matches.
* `/dev/sdX` is never treated as a stable physical identifier.
* A multipath device is not probed repeatedly through every alias.

An ambiguous identity **refuses** the active interrogation. Full
multipath management is not implemented in M1.

### Identity changes during an interrogation

The identity and the access paths are captured immediately before and
immediately after each backend invocation, and the major/minor and disk
sequence information are compared where they are available. A detected
change invalidates the attribution of the affected observations: the raw
response is retained as **unbound** evidence and is not attached to the
originally selected disk.

**The limitation is explicit.** The tools are executed by pathname, so
the pre/post checks do **not** provide handle-bound identity guarantees
and do not eliminate every time-of-check/time-of-use race. Handle-bound
authority for intrusive operations remains a mandatory future gate
(IRK-05/IRK-07).

## Bounded backend execution

`src/ironkeeper/storage/procexec.nim` is the only module that runs an
external process.

* The executable is an **absolute path**; there is no PATH search and no
  shell interpolation.
* The arguments are an **argument vector**.
* The environment is **controlled**: the child receives exactly the
  variables the caller specified, plus `LC_ALL=C` and `LANG=C`.
* stdout and stderr are captured **separately** and bounded
  **independently**.
* Both streams are drained concurrently, so a tool that fills one pipe
  while the parent fills the other cannot deadlock.
* A **monotonic** wall-clock deadline is enforced.
* On a timeout or an output-limit violation the whole **process group**
  is terminated, so no descendant is left running, and the child is
  always **reaped**.
* The outcome is classified: `succeeded`, `non_zero_exit`, `timed_out`,
  `launch_failed`, `output_limit_exceeded`, `signalled`.

| Limit | Value |
|---|---|
| Per-command deadline | 30 s |
| Maximum stdout | 4 MiB |
| Maximum stderr | 256 KiB |
| Active interrogation concurrency | 1 |

A timeout or an output-limit violation is **never** a successful
complete observation.

The executable paths are fixed (`/usr/sbin/smartctl`,
`/usr/bin/sg_readcap`). The test harness injects a controlled executable
through the `IRONKEEPER_TEST_TOOL_DIR` seam; no CLI option or
configuration file can make an ordinary invocation execute an arbitrary
program.

## SMART acquisition

The acquisition command is:

```bash
smartctl -x --json=o DEVICE
```

The `-jv` spelling of the `-j` option is ambiguous in smartctl 7.x and
is refused by the tool, so the explicit `--json=o` form is used. The
supported tool version range is smartctl 7.2 to 7.5; the version that
produced a response is recorded from the document itself.

The **complete** original response is preserved, including the fields
that M1 does not normalise.

### Exit status

The exit status of `smartctl` is a **bitmask**, and all eight bits are
decoded while the original numeric status is preserved:

| Bit | Meaning (as documented by the tool) |
|---|---|
| 0 | the command line did not parse |
| 1 | the device could not be opened, or the device is not a SMART device |
| 2 | some SMART or other ATA command failed |
| 3 | the device reported a failing (prefail) condition |
| 4 | a prefail attribute is above its threshold |
| 5 | the SMART error log contains errors |
| 6 | the SMART self-test log contains errors |
| 7 | other, lower-level errors |

The tool documents bits 3 to 6 in the terms of the ATA protocol. They do
**not** mean the same thing for SCSI and NVMe, so the decoded bits are
observations with a protocol caveat, not verdicts. Bit 7 is decoded as
"other lower-level errors" and is not interpreted further.

A nonzero status may accompany useful, successfully acquired health
evidence: exit bit 3 reports a *device-reported failing condition*, which
is a health observation and not a collection failure. A status embedded in
the JSON document that contradicts the actual subprocess status is a
**contradiction** to report, not a value to reconcile by preferring the
healthier answer.

## Lossless external JSON ingestion

The internal strict reader enforces Ironkeeper's own exact-number policy:
an integer that does not fit in `int64`, or that exceeds 2^53, is
rejected. That policy is **not** applied to complete third-party
payloads. NVMe SMART data can contain counters larger than an unsigned
64-bit integer.

`src/ironkeeper/storage/externaljson.nim` therefore implements a
separate, lossless reader that:

1. preserves the raw response bytes in the evidence bundle;
2. validates the encoding (strict UTF-8) and the JSON syntax;
3. detects **duplicate object member names** before information is lost;
4. retains the **exact source lexeme** of every number, so no value ever
   passes through a binary64 conversion;
5. extracts the supported telemetry fields;
6. verifies the companion representations where they are consumed;
7. reports inconsistencies explicitly;
8. produces strictly valid normalised Ironkeeper documents.

### The UTF-8 collision follow-up

The foundation left one open item: two distinct external member names
that repair to the same text were not distinguished. This boundary closes
it by **never repairing** an external member name. A name that is not
valid UTF-8 is a rejected document, not a repaired one, so two distinct
names can never collapse into one. Names are also compared *after* JSON
unescaping, so `"a"` and `"a"` are the same name and are rejected
as a duplicate.

### Companion representations

`smartctl` writes a large counter in more than one form: as a decimal
string, and - when the value does not fit into a 64-bit integer - as a
hexadecimal companion such as `data_units_read_raw: "0x1000..."`. The
normalisation layer compares the representations. A disagreement is
reported as a **conflicting** observation and a finding; it is never
silently resolved in favour of one of them.

The numeric witnesses exercised by the test suite are `0`,
`9007199254740991`, `9007199254740992`, `9007199254740993`,
`18446744073709551615`, `18446744073709551616` and
`340282366920938463463374607431768211455`, together with a large number
in an unrelated vendor field, a numeric and decimal-string companion
agreement, a companion disagreement, a missing companion, an invalid
decimal representation, duplicate JSON keys, invalid UTF-8 and
conflicting normalised identifier fields.

## SCSI capacity and protection

The capacity backend uses `sg_readcap --readonly --long --json DEVICE`.
The JSON support is version-dependent, so the decoder accepts the member
names of the supported versions (`read_capacity_16_parameter_data`,
`read_capacity`) and the field names of both (`returned_logical_block_address`
and `last_lba`, `logical_block_length_in_bytes` and `block_length`).
No arbitrary human-readable output is parsed with uncontrolled
heuristics.

The arithmetic is checked and exact:

```text
logical_blocks = last_lba + 1
capacity_bytes = logical_blocks * logical_block_length
```

### The protection mapping

The raw `PROT_EN` and `P_TYPE` fields are **not** the protection type:

| PROT_EN | Raw P_TYPE | Normalized protection |
|---|---|---|
| 0 | any | Type 0 |
| 1 | 0 | Type 1 |
| 1 | 1 | Type 2 |
| 1 | 2 | Type 3 |
| 1 | 3-7 | reserved / unsupported |

Both raw fields are retained next to the derived value, and a reserved
combination is reported as **unsupported**: it is never silently mapped
onto Type 0.

`sg_format` and every other modifying operation are never invoked.

## Protocol coverage

| Protocol | Implemented | Synthetic fixture | Native CI | Live hardware |
|---|---|---|---|---|
| SCSI/SAS | yes | yes | yes | yes |
| SATA/ATA | yes | yes | yes | yes (read-only, on the lab host) |
| NVMe | yes | yes | yes | yes (read-only, on the lab host) |

Only SAS required live hardware qualification in this milestone.

### What is normalised

**SCSI/SAS.** Vendor, model, serial and firmware; the logical-unit
identifier; capacity and block sizes; the rotation rate; the
device-reported SMART health; the current and trip temperature; the
accumulated power-on time; the start-stop and load-unload counters; the
grown defect count; the corrected and uncorrected read, write and verify
errors; the correction algorithm invocations; the processed-data
counters; the non-medium error count; the self-test log entries; the
current self-test state (reported as **unsupported**, because the tool
reports the log and not the running state); the background scan count;
and the SAS PHY observations.

The correction algorithm invocations are kept **distinct** from the
corrected-error counts: they count something different.

**SATA/ATA.** Identity and firmware; the device-reported SMART health;
the temperature; the power-on hours; the power-cycle count; the presence
of the SMART attribute table; the error-log and self-test-log
observations.

The attribute records themselves are not normalised into a universal
ontology: an ATA attribute name and id are vendor-specific, and no
semantic meaning is inferred from them. No SSD endurance percentage is
invented where the device does not provide authoritative semantics.

**NVMe.** Controller and namespace identity; the critical warning; the
temperature; the available spare and its threshold; the percentage used;
the data units read and written; the host read and write commands; the
power cycles; the power-on hours; the unsafe shutdowns; the media and
data-integrity errors; and the error information log entry count. The
original counter units are preserved: the data units are *units*, not
bytes. A byte count is therefore **not** derived from them, because the
rounding semantics of such a conversion would be an invention.

## SAS PHY observations

The PHY counters are read from the sysfs SAS PHY class and from the
`scsi_sas_port_N` members of the SMART document. Every PHY observation
stays associated with the port and the PHY it came from, the counters of
unrelated PHYs are never aggregated, and the counters are never reset.

A 12 Gbit negotiation between a drive and an expander says nothing about
the upstream path. Ironkeeper records the link it observed; it does not
construct an expander graph and does not diagnose a shared transport
bottleneck. IRK-12 remains partially implemented.

## Evidence bundles

An evidence bundle is an **invocation-scoped directory** that the
operator asked for. It is not a database, and nothing is written unless
`--evidence-dir` was given.

```text
observation.json
manifest.json
smartctl.stdout
smartctl.stderr
capacity.stdout
capacity.stderr
```

The bundle lives in a **unique, invocation-owned** directory below the
supplied parent. A caller-owned file is never overwritten and a
caller-owned directory is never removed. The files are written with
restrictive permissions. The manifest is published **after** the
artefacts it references are finalised, and it records the exact byte
length and the SHA-256 digest of every artefact.

A digest is an **integrity check** over the preserved bytes. It is not a
cryptographic proof of provenance or of authenticity. Malformed or
incomplete tool output is preserved and marked as such in the manifest.

Real device identities and raw homelab telemetry are never committed to
the public repository.
