# Ironkeeper

Ironkeeper is a lightweight, evidence-driven storage fleet housekeeping
daemon for SAS, SATA and NVMe devices on Linux hosts.

It will eventually automate the discovery, qualification, health
assessment, preventive maintenance and lifecycle management of storage
devices. Its first practical deployment target is a Linux storage host
with multiple SAS expanders, used enterprise HDDs, SSDs and ZFS pools.

**This repository is at milestone M1 — Read-only inventory and SMART
observations.** The application foundation of M0 is implemented, tested
and documented. M1 adds the first operational storage capabilities: the
Linux block-device discovery, the identity reconciliation, the bounded
read-only interrogation of an explicitly selected device, and the strict
inventory and observation contracts.

Everything that M1 does to a device is **read-only**. No self-test is
started or aborted, no surface is scanned, nothing is written to a block
device, and no PHY counter is reset. M1 assigns **no** admission or
health verdict: it reports what the device said.

See [EPICS.md](EPICS.md) for the board,
[docs/architecture/overview.md](docs/architecture/overview.md) for the
architecture and
[docs/architecture/storage-observation.md](docs/architecture/storage-observation.md)
for the observation subsystem.

## Design principles

* **Evidence-driven.** Every conclusion is derived from preserved
  observations. An assessment can be recomputed from the evidence and the
  policy revision that produced it.
* **Non-destructive by default.** Nothing in the current milestone writes
  to a device, and the safety policy that forbids destructive operations
  cannot be configured away.
* **Deterministic and auditable.** Strict, versioned JSON contracts.
  Duplicate member names, invalid UTF-8, trailing content and non-finite
  numbers are rejected rather than silently absorbed.
* **Honest about limits.** An operation that could not obtain the evidence
  it needed reports `INCONCLUSIVE`, never `PASS`. Missing information is
  never confused with a zero value.

## Current state

| Area | State |
|---|---|
| CLI foundation | Implemented, tested |
| Strict JSON ingestion | Implemented, tested |
| Configuration and report contracts | Implemented, tested |
| Schema validation | Implemented, qualified against the official test suite |
| Continuous integration | In use: native Linux amd64 and arm64 |
| Device discovery | Implemented, tested (Linux sysfs and udev) |
| SMART backend | Implemented, tested (SCSI/SAS, ATA, NVMe) |
| SCSI capacity and protection | Implemented, tested |
| Evidence bundles | Implemented, tested |
| Job engine and scheduler | Not started |
| Control socket | Not started |
| systemd integration and packaging | Not started |

The foundation milestone is complete and is verified natively on Linux
amd64 and Linux arm64. See
[EPICS.md](EPICS.md) for the board and
[`.factory/evidence/`](.factory/evidence/) for the evidence.

## Building

Ironkeeper is written in Nim and builds with a pinned Nim 2.x toolchain.
The authoritative version of the toolchain is recorded in
[docs/architecture/overview.md](docs/architecture/overview.md#toolchain).

```sh
nimble build      # build the executable
nimble test       # unit and contract tests
nimble check      # type-check every module
```

If your Nimble cannot expose those exact task names, the equivalent
repository-owned commands are:

```sh
tools/build.sh                 # build every artefact
./build/unit_tests             # unit tests
./build/contract_tests         # contract tests
./build/integration_tests      # integration tests (needs the binary)
```

The only external dependency is [`jschema`](https://github.com/Niminem/jschema),
an MIT-licensed JSON Schema Draft 2020-12 validator that depends on
nothing beyond the Nim standard library. On Linux the binary also needs
the PCRE shared library at run time, because the validator uses
`std/re` for the `pattern` keyword.

The dependency decision and the validator qualification results are
recorded in
[docs/architecture/overview.md](docs/architecture/overview.md#validator-qualification).

## Using the CLI

```sh
ironkeeper --help
ironkeeper --version
ironkeeper version --json

ironkeeper config validate --file examples/ironkeeper.json
ironkeeper config validate --file examples/ironkeeper.json --json

ironkeeper schema list
ironkeeper schema config
ironkeeper schema report
ironkeeper schema inventory
ironkeeper schema device
ironkeeper schema observation
ironkeeper schema evidence

ironkeeper report validate --file <path>

# Passive: no device is opened and no tool is run.
ironkeeper inventory list
ironkeeper inventory list --json
ironkeeper inventory list --transport sas --json

# Passive inspection of one explicitly selected device.
ironkeeper device inspect --wwn <wwn> --json

# Active, read-only inspection of one explicitly selected device.
ironkeeper device inspect \
  --wwn <wwn> \
  --smart \
  --capacity \
  --allow-wake \
  --evidence-dir <parent-directory> \
  --json
```

`--allow-wake` is required for an active interrogation: a read-only SMART
acquisition may wake a sleeping device. The passive commands never need
it, because they never run a tool.

An active inspection refuses an **ambiguous** target: a selector that
matches more than one device, or a device whose identity observations
contradict each other, is never resolved arbitrarily.

A successfully acquired observation of an **unhealthy** device is not a
command failure: the command exits successfully and the document reports
the device's own assessment of itself.

Human-readable output goes to stdout. Machine-readable output (`--json`)
also goes to stdout, and stdout then carries exactly one JSON document.
Diagnostics go to stderr. Exit codes are stable and documented:

| Code | Meaning |
|---|---|
| 0 | success |
| 2 | invalid command line invocation |
| 3 | input unavailable |
| 4 | invalid JSON syntax |
| 5 | schema validation failure |
| 6 | semantic validation failure |
| 7 | unsupported schema version |
| 8 | unsupported operation |
| 70 | internal application failure |

## Contracts

The public JSON contracts live in [`schemas/v1`](schemas/v1) and use JSON
Schema Draft 2020-12:

| Schema | Purpose |
|---|---|
| `config.schema.json` | The daemon configuration document |
| `report.schema.json` | The report document produced by every operation |
| `error.schema.json` | The machine-readable error document |
| `version.schema.json` | The version identity of a build |
| `validation.schema.json` | The result of `report validate --json` |
| `schemaindex.schema.json` | The result of `schema list --json` |
| `inventory.schema.json` | The passive inventory document |
| `device.schema.json` | One discovered block device |
| `observation.schema.json` | The normalised observations of one device |
| `evidence.schema.json` | The manifest of an evidence bundle |

Every object boundary rejects unknown properties. The schema bytes
embedded in the binary are byte-for-byte identical to the files in the
repository; a contract test enforces this.

A schema must also satisfy Ironkeeper's **supported schema policy**: every
keyword in a schema-bearing position must be one of the documented,
supported keywords. A misspelled keyword is a *valid* Draft 2020-12
schema, so meta-validation alone would accept it and the keyword's intent
would be silently lost. The policy is recorded in
[docs/architecture/overview.md](docs/architecture/overview.md#the-supported-schema-policy).

## Documentation

| Document | Contents |
|---|---|
| [AGENTS.md](AGENTS.md) | The engineering rules that apply to every change |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [SECURITY.md](SECURITY.md) | Reporting a vulnerability |
| [EPICS.md](EPICS.md) | The project board |
| [docs/architecture/overview.md](docs/architecture/overview.md) | Architecture, toolchain and validator qualification |
| [docs/architecture/invariants.md](docs/architecture/invariants.md) | The invariants the code must preserve |
| [docs/architecture/threat-model.md](docs/architecture/threat-model.md) | What Ironkeeper defends against |
| [docs/architecture/lifecycle.md](docs/architecture/lifecycle.md) | Execution, assessment and device lifecycle vocabularies |
| [docs/architecture/storage-observation.md](docs/architecture/storage-observation.md) | The M1 discovery, identity, ingestion and observation model |
| [docs/labs/LAB-IRK-SAS-INVENTORY-01.md](docs/labs/LAB-IRK-SAS-INVENTORY-01.md) | The live SAS qualification runbook |
| [docs/adr/](docs/adr) | Architecture decision records |

## Licence

MIT. See [LICENSE](LICENSE).
