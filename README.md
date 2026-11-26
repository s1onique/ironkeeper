# Ironkeeper

Ironkeeper is a lightweight, evidence-driven storage fleet housekeeping
daemon for SAS, SATA and NVMe devices on Linux hosts.

It will eventually automate the discovery, qualification, health
assessment, preventive maintenance and lifecycle management of storage
devices. Its first practical deployment target is a Linux storage host
with multiple SAS expanders, used enterprise HDDs, SSDs and ZFS pools.

**This repository is at milestone M0 — Foundations.** The application
foundation is implemented, tested and documented. No hardware has been
touched, no device has been discovered, and no daemon or job engine exists
yet. See [EPICS.md](EPICS.md) for the board and
[docs/architecture/overview.md](docs/architecture/overview.md) for the
architecture.

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
| Device discovery | Not started |
| SMART backend | Not started |
| Job engine and scheduler | Not started |
| Control socket | Not started |
| systemd integration and packaging | Not started |

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
nothing beyond the Nim standard library. The dependency decision and the
validator qualification results are recorded in
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

ironkeeper report validate --file <path>
```

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

Every object boundary rejects unknown properties. The schema bytes
embedded in the binary are byte-for-byte identical to the files in the
repository; a contract test enforces this.

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
| [docs/adr/](docs/adr) | Architecture decision records |

## Licence

MIT. See [LICENSE](LICENSE).
