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

* Identifier formats are canonicalised (`naa.5000c50001234567`,
  `0x5000c50001234567` and the bare hex digits denote the same
  identifier), and the original value is preserved alongside it.
* The **sysfs** observation of a world-wide name and the **udev**
  observation are kept separately and compared. A disagreement is a
  **contradiction**: it is never resolved by discarding one source.
* An identifier is validated before it is used. A value that is not
  hexadecimal, that is too short, or that consists only of zeros is **not
  a usable identifier**: it earns no authority at all, and the device is
  reported as ambiguous rather than as authoritative.
* Aliases are deduplicated.
* Conflicting identifiers, duplicated serials and duplicated WWNs are
  detected and make the identity **ambiguous**.
* Two devices are never merged because their model or serial matches.
* `/dev/sdX` is never treated as a stable physical identifier.
* A multipath device is not probed repeatedly through every alias.

### The confidence of an identity

An identity is **authoritative** only when a *usable* persistent
identifier was observed: the logical-unit WWN of a SCSI device, the ATA
WWN, or the NGUID, the EUI-64 or the UUID of an NVMe namespace. An
arbitrary nonempty string is not an identity, and the mere presence of a
world-wide name does not confer authority.

The **disk sequence number** names the *registration* of the device, not
the hardware. It is preserved as an identifier of its own kind and never
confers authority; it is compared during an interrogation because it
changes when a device is replaced.

A serial number is a *weak* identifier: it yields a **probable**
identity and never an authoritative one. A serial that two devices carry
makes both of them ambiguous.

For an NVMe device the serial belongs to the **controller**. It is
therefore kept in the controller namespace, it never becomes a namespace
identity, and two namespaces behind one controller are **not** a
contradiction. A physical disk and a partition that inherits its
identifier are not two devices with a duplicate identifier: only the
physical disk candidates take part in the duplicate detection.

An ambiguous identity **refuses** the active interrogation. Full
multipath management is not implemented in M1.

### Identity changes during an interrogation

The identity and the access paths are captured immediately before and
immediately after **each** backend invocation. The comparison covers the
kernel name, the device numbers, the world-wide name, the serial number,
the disk sequence number, the confidence, the identifiers and the path
evidence.

Four outcomes refuse the attribution, and the raw response is retained as
**unbound** evidence in every one of them:

| Outcome | Consequence |
|---|---|
| the device disappeared | the attribution is refused |
| the device was replaced | the attribution is refused |
| the rediscovery did not complete | the attribution is refused: an incomplete rediscovery cannot establish an unchanged identity |
| the tool reported a contradictory identity | the attribution is refused |

A detected change also **prevents** the subsequent active commands: the
collection does not continue against a target whose identity is in
doubt.

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
* A **monotonic** wall-clock deadline is enforced, and it stays
  authoritative **after** the pipes reach end of file: a child that
  closes both streams and keeps running is still terminated at the
  deadline.
* Each poll descriptor carries the **identity of its stream**, so the
  capture of the standard error never ends up in the standard output.
* A **failed launch** is distinguished from a program that ran and
  exited with status 127: the child reports the launch error through a
  close-on-exec pipe, and the parent sees end of file when the program
  started.
* On a timeout or an output-limit violation the whole **process group**
  is terminated, so no descendant is left running, and the child is
  always **reaped**. A child that cannot be reaped within the
  supported policy is reported with an **unresolved process state**; the
  result never claims a clean completion. A `SIGKILL` is a request and
  not a guarantee: a task that is blocked in uninterruptible kernel I/O
  does not die from it.
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
`/usr/bin/sg_readcap`).

### The test seam is a compile-time property

The test harness injects a controlled executable through the
`IRONKEEPER_TEST_TOOL_DIR` seam and points the discovery at a synthetic
tree through `IRONKEEPER_SYSFS_ROOT`, `IRONKEEPER_DEV_ROOT` and
`IRONKEEPER_UDEV_ROOT`. Those seams exist **only** in a binary that was
compiled with the `ironkeeperTesting` definition:

| Build | Definition | Tool seam | Discovery roots | Use |
|---|---|---|---|---|
| `build/ironkeeper` | none | ignored | the real roots | the shipped artefact |
| `build/ironkeeper-testing` | `ironkeeperTesting` | honoured | the synthetic roots | the compiled-CLI tests |

A production binary therefore does not read those variables at all: an
environment variable cannot make it execute an arbitrary program or point
it at a synthetic tree. The two binaries are never interchangeable - each
one reports its own variant through `ironkeeper version --json`, and the
variant is recorded in the CI artefact metadata. All hardware
qualification uses the production variant.

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

| Bit | Upstream name | Meaning |
|---|---|---|
| 0 | `FAILCMD` | the command line did not parse, or an internal error occurred |
| 1 | `FAILDEV` / `FAILPOWER` / `FAILID` | the device could not be opened, identified, or was in a power state that forbids the command |
| 2 | `FAILSMART` | a SMART or other device command failed |
| 3 | `FAILSTATUS` | the device reported a failing SMART status |
| 4 | `FAILATTR` | a prefail attribute is at or below its threshold **now** |
| 5 | `FAILAGE` | an attribute failed **in the past** |
| 6 | `FAILERR` | the error log contains error records |
| 7 | `FAILLOG` | the self-test log contains error records |

These are the definitions of `smartmontools/smartctl.h`. The tool
documents the bits in the terms of the ATA protocol; they do **not** mean
the same thing for SCSI and NVMe, so the decoded bits are observations
with a protocol caveat, not verdicts.

A status that **no process produced** - the synthetic `-1` of a launch
failure or the placeholder of a timeout - carries no bits at all. It is
never decoded as a bitmask; the absence of an exit status is reported as
an unavailable observation, never as eight `false` bits.

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

`smartctl` writes a large counter in more than one form. With the
verbose JSON option it emits the number under `KEY`, the exact decimal
value as a string under `KEY_s`, and - for a value that exceeds 64 bits
- the raw bytes as a little-endian byte array under `KEY_le`
(`smartmontools/json.cpp`). The byte at index `i` carries the weight
`256^i`.

The normalisation layer reads exactly these companions. A disagreement
between the value and any companion that is present is reported as a
**conflicting** observation and a finding; it is never silently resolved
in favour of one of them. A companion that cannot be interpreted is
reported as an **invalid** observation. A member with a different name is
an unrelated field and never participates in the comparison.

The numeric witnesses exercised by the test suite are the agreement of a
value with its `KEY_s` companion, the disagreement of the two, a valid
little-endian companion, a contradictory little-endian companion, a
malformed companion, a 128-bit counter with every representation, and a
large number in an unrelated vendor field.

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

A response that carries **no** `PROT_EN` field carries no protection
information. Such a response is not evidence of disabled protection, and
the decoder therefore distinguishes four states that the earlier
implementation collapsed into one:

| State | Meaning |
|---|---|
| `missing` | the tool did not report the field |
| `invalid` | the tool reported a value outside the defined range |
| `reserved_unsupported` | the tool reported a combination the standard reserves |
| a normalized type | the tool reported a valid combination |

Type 0 is derived **only** from an observed `PROT_EN` of zero.

The arithmetic conserves every digit. The exact decimal primitive of
`src/ironkeeper/json/exactdecimal.nim` trims the **leading** zeros only:
a trailing zero is a significant digit, so the last logical block
address 999 with a block length of 512 is 512000 bytes and not 512.

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
supplied parent, and the ownership is established **atomically**:

* the directory is created with mode 0700 **at creation**, so that it is
  never observable with wider permissions, and the creation is
  exclusive - a name collision is resolved by the kernel and not by a
  check-then-create race;
* every artefact is created with `O_EXCL`, so an existing file is never
  overwritten and a symlink is never followed;
* the identity (device number and inode number) of the parent directory
  is checked before and after the export, so that a caller-controlled
  replacement of the parent cannot silently redirect the write;
* the manifest is published **after** the artefacts it references are
  finalised, and it records the exact byte length and the SHA-256 digest
  of every artefact. A bundle without a manifest is a partial export,
  and it never masquerades as a complete one.

The observation document and the evidence manifest are validated against
the repository contracts at the production boundary, **before** they are
published. The stored observation document and the emitted JSON agree
semantically, and the independent CI check validates the generated
evidence manifest as well.

A digest is an **integrity check** over the preserved bytes. It is not a
cryptographic proof of provenance or of authenticity. Malformed or
incomplete tool output is preserved and marked as such in the manifest.

Real device identities and raw homelab telemetry are never committed to
the public repository.

## The acquisition result

The completeness of a collection is **not** derived from the presence of
an execution record. A record says only that a process ran; it says
nothing about what the process produced.

`src/ironkeeper/storage/acquisition.nim` therefore keeps five things
apart, because collapsing any two of them produces a wrong answer:

1. **execution outcome** - did the process run?
2. **requested observation coverage** - were the requested observations
   obtained?
3. **device-reported health** - what does the device say about itself?
4. **attribution** - are the observations bound to the selected device?
5. **collection completeness** - the authoritative value.

The coverage is incomplete when the tool could not be launched, timed
out or was terminated; when the output was truncated by the configured
bound; when the response could not be ingested; when a **mandatory**
observation of the operation is missing; when the observations contradict
each other; or when the attribution was refused.

The coverage is **not** incomplete because the device reported an
unhealthy status - a failing disk is a device-reported health
observation, and it may accompany a complete acquisition - or because an
**optional** field was unavailable.

The mandatory observations are:

| Operation | Mandatory observations |
|---|---|
| SMART (ATA, SCSI) | `device_reported_health` |
| SMART (NVMe) | `nvme.critical_warning` |
| capacity | `capacity.total_bytes`, `capacity.logical_block_length` |

The authoritative completeness value is the same in the observation
document, the evidence manifest, the human-readable output and the
documented exit-status policy. The dispatcher consumes the exit status
of the command: a collection that did not obtain every requested
observation exits with the documented input-unavailable status, and the
document that was produced is still the machine-readable result.
