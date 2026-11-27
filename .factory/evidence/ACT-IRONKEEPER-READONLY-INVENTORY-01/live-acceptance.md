# Live SAS acceptance

The live acceptance was executed on the Proxmox storage host with the
HBA and the two SAS expanders, using a release build of the M1 subject
compiled with the pinned toolchain (Nim 2.4.2) on the host itself.

The observations stayed **on the host**. Only sanitised counts and
classifications are recorded here: no serial number, no WWN, no host
name and no raw capture is committed to the public repository.

## The execution environment

| Item | Value |
|---|---|
| Host | the Proxmox storage host (the name is not recorded here) |
| Kernel | Linux 6.x/7.x x86_64, `mpt2sas`/`mpt3sas` HBA drivers |
| `smartctl` | 7.5 (2025-04-30, r5714) |
| `sg_readcap` | sg3_utils 4.13 (20230519) |
| Toolchain | Nim 2.4.2, the pinned version |
| Build | release mode, ORC memory manager |

## Stage A — passive inventory

```text
ironkeeper inventory list --json
```

The enumeration completed with the exit status 0 and reported
`complete: true`.

| Observation | Result |
|---|---|
| Block devices enumerated | 55 |
| Physical disk candidates | 15 |
| Partitions | 24 |
| Loop devices | 8 |
| Virtual (ZFS) volumes | 8 |
| Transports of the physical disks | 8 SAS, 5 SATA, 2 NVMe |
| Identity confidence of the physical disks | 15 authoritative |
| Persistent aliases per physical disk | 3 or 4 |
| Findings | none |

The independent cross-check with `lsblk` agreed on the device set and on
the capacities. No partition, device-mapper, RAID, loop or ZFS device was
reported as a physical disk, and every physical disk appeared exactly
once despite its aliases.

**No SMART or SCSI capacity command was launched in this stage.** The
passive command runs no tool: the non-vacuity gate and the integration
suite both assert that the controlled `smartctl` is never executed by a
passive command.

## Stage B — one explicitly selected SAS drive

```text
sudo ironkeeper device inspect \
  --wwn "$EXPECTED_WWN" --smart --capacity --allow-wake \
  --evidence-dir "$EVIDENCE_PARENT" --json
```

Two explicitly selected SAS drives were inspected sequentially. Both
commands exited with the status 0.

| Quantity | Observed |
|---|---|
| Normalised observations per device | 53 |
| Attribution | `bound` |
| Completeness | `complete` |
| Device-reported health | `pass` on both devices |
| Capacity | 900 185 481 216 bytes, computed exactly |
| Protection format | `prot_en=0`, `p_type=0`, normalised `type_0` |
| Grown defects | 0 on one device, 2 on the other |
| Temperature | reported, in degrees Celsius |
| Corrected and uncorrected errors | reported per direction |
| Correction algorithm invocations | reported, **distinct** from the corrected-error counts |
| SAS PHY observations | 2 ports, per-PHY counters and link rates |

The observations were cross-checked against `smartctl -x --json=o` and
`sg_readcap --readonly --long` on the same devices. The capacity, the
protection fields, the health status, the temperature, the grown defect
count and the error counters agreed.

### The defect the live run exposed

The first live run reported the rotation rate of a SAS drive as `1 rpm`
instead of `10000 rpm`, and the load-unload counter as `3` instead of
`30`. The cause was in the exact decimal arithmetic of the ingestion
path: the leading-zero strip of the result removed the **trailing**
zeros as well.

The defect was fixed, the regression witnesses were added, and the live
values are now correct. This is recorded in `regression-witnesses.md`.

## The evidence bundles

Each invocation created its own directory below the supplied parent:

```text
observation.json
manifest.json
smartctl.stdout
smartctl.stderr
capacity.stdout
capacity.stderr
```

* The files were written with the restrictive permissions `-rw-------`.
* The manifest recorded 5 artefacts (the two tool streams and the
  normalised document are written as well), each with its exact byte
  length and its SHA-256 digest.
* Every recorded digest and every recorded byte length matched the
  preserved file, checked independently after the collection.
* Two invocations produced two separate directories: the caller-owned
  parent directory was not disturbed.

## The public documents

The live inventory document and the live observation document were
validated against the repository contracts with an **independent**
validator (`check-jsonschema` 0.31.2, the implementation the CI gate
uses):

```text
ok -- validation done   (schemas/v1/inventory.schema.json)
ok -- validation done   (schemas/v1/observation.schema.json)
```

## What was not done

* No self-test was started, aborted or modified.
* No surface read was initiated.
* No device was qualified, admitted, retired or erased.
* No PHY counter was reset.
* No Proxmox configuration was changed.

Every operation that was executed is read-only by construction: the
inventory reads the filesystem, and the interrogation runs
`smartctl -x --json=o` and `sg_readcap --readonly --long --json`.
