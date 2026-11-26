# ADR-0008: External storage tooling and native implementation boundaries

* **Status:** Accepted
* **Date:** 2026-11-26
* **Milestone:** M0 — Foundations (recorded for IRK-04 and IRK-07)
* **Deciders:** Ironkeeper maintainers

## Context

Storage tooling is a mature field with a great deal of hard-won
knowledge in it: SCSI command handling, ATA pass-through, NVMe log
pages, SMART attribute interpretation, SCSI protection information, SAS
expander and PHY state. Reimplementing that work is slow, risky and
rarely better than the existing tools.

But some things are better done natively. A full-surface read that shells
out to `dd` per chunk is slow and imprecise; a purpose-built aligned
read-only scanner is neither.

## Decision

Ironkeeper **prefers proven external storage tooling** over
reimplementing protocol-specific hardware support, and uses **native
implementation only where there is a demonstrated requirement**.

### External tooling

| Tool | Purpose |
|---|---|
| `smartctl -x -j` | SMART and device information, as JSON |
| SCSI inquiry / capacity | Protection information, logical block size |
| Linux sysfs and udev | Device enumeration and topology |
| SAS PHY and expander tools | Topology and link state |

The **`smartctl` exit status is a bitmask and is a mandatory part of the
backend contract**:

| Bit | Meaning |
|---|---|
| 0 | Command line did not parse |
| 1 | Device open failed, or device did not return an IDENTIFY DEVICE structure |
| 2 | Some SMART or other ATA command to the disk failed |
| 3 | The disk reports that it has failed SMART |
| 4 | The disk reports that it has a possible impending failure in its SMART attribute table |
| 5 | The SMART attribute table could not be read |
| 6 | The SMART attribute table contains errors |
| 7 | The SMART command was sent to the device and the device did not respond |

A backend that collapses this into a single success/failure loses the
distinction between "the tool failed" and "the device reported a problem"
— which is exactly the distinction Ironkeeper exists to preserve. The
backend records the bitmask, not a boolean.

### Native implementation

| Area | Why native |
|---|---|
| Full-surface read-only scanning | Needs aligned, bounded, concurrent reads with per-region error accounting. Shelling out per chunk is neither precise nor efficient. |

A native scanner is **read-only**. It opens the device `O_RDONLY` and
performs no write, no flush and no partition or filesystem operation.

### Boundaries

* An **adapter** translates a tool's output into Ironkeeper's normalised
  observation model. It does not judge.
* The **assessment layer** judges. It performs no I/O and knows nothing
  about `smartctl`'s exit codes or sysfs layout.
* An adapter that cannot determine a value records it as **unavailable**,
  never as a default.
* Tool versions are captured with the observations.

## Rationale

`smartctl` encodes two decades of work on ATA, SCSI and NVMe quirks. A
reimplementation would be worse in every way that matters, and would be
maintained by one project instead of many.

Native code is justified where the requirement is specific and
demonstrable — an aligned, bounded, concurrent reader is not something
`dd` does well — and not where it is merely a preference.

The bitmask rule is the practical heart of this decision. A tool that
reports "the disk failed" and a tool that reports "I could not read the
disk" must not look the same to Ironkeeper, because the operator's
response to each is completely different.

## Consequences

* Ironkeeper depends on external tools at runtime. Their versions must be
  captured and, in a packaged deployment, pinned.
* Adapter output needs normalising, and the normal form is part of the
  contract.
* The native scanner is a separate component with a narrow,
  read-only responsibility.
* The `smartctl` exit-status contract must be tested against a
  synthetic fixture, since it cannot be produced by a real failing disk
  in a test environment.

## Status

Accepted. Not implemented in milestone M0; it belongs to IRK-04 and
IRK-07.
