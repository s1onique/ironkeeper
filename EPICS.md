# Epic board

This board is the authoritative record of project work. It tracks what is
planned and what has been done; it is **not** a record of the state of any
storage device.

## Conventions

* **Status** is one of `planned`, `in progress`, `done`, `deferred`.
* **Evidence** links to the artefact that proves the status. A status of
  `done` without evidence is not `done`.
* **Next step** is the single most useful thing to do next. A board whose
  next steps are vague is a board nobody acts on.
* Completed ACTs and superseded decisions are **archived**, not deleted.
  History is evidence. See [Archive](#archive).

## Milestones

| Milestone | Scope | Status |
|---|---|---|
| M0 — Foundations | Architecture, contracts, CLI, tests, CI | **done** (re-established by ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02, closed by ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-03) |
| M1 — Read-only inventory and SMART observations | Discovery, identity, SMART acquisition | planned |
| M2 — Operational qualification daemon | Qualification profiles, assessment engine, job engine | planned |
| M3 — Autonomous housekeeping and observability | Scheduling, metrics, production workloads | planned |
| M4 — Advanced lifecycle management | Admission, retirement, multi-host aggregation | planned |

## Epics

### IRK-01 — Architecture, invariants and ADRs

* **Status:** done
* **Priority:** P0
* **Dependencies:** none
* **Owning ACT:** ACT-IRONKEEPER-FOUNDATION-01;
  ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02 (CI gate authority)
* **Evidence:**
  `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01/`,
  `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02/`
* **Acceptance criteria:** The nine subsystem boundaries are documented;
  ADRs 0001–0008 are accepted; the invariants and the threat model exist;
  proposed decisions are recorded separately from accepted ones.
* **Evidence:**
  [docs/architecture/overview.md](docs/architecture/overview.md),
  [docs/architecture/invariants.md](docs/architecture/invariants.md),
  [docs/architecture/threat-model.md](docs/architecture/threat-model.md),
  [docs/architecture/lifecycle.md](docs/architecture/lifecycle.md),
  [docs/adr/](docs/adr/),
  `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01/`
* **Next step:** Extend the ADR set when IRK-03 introduces the identity
  persistence format.

### IRK-02 — Strict configuration and report schemas

* **Status:** done (foundation) / planned (storage schemas)
* **Priority:** P0
* **Dependencies:** IRK-01
* **Owning ACT:** ACT-IRONKEEPER-FOUNDATION-01 (foundation);
  ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02 (numeric contract, supported
  schema policy, report semantics, output contracts); future ACTs
  (storage contracts)
* **Note:** The status covers the configuration, report, error and version
  contracts and their runtime enforcement. The storage observation and
  inventory contracts remain a separate deliverable and are **not**
  covered by it.
* **Acceptance criteria:** Configuration, report, error and version
  schemas exist at version 1, are Draft 2020-12, reject unknown
  properties, and are embedded byte-for-byte. Runtime validation is
  performed by the shipped binary. The mandatory safety values cannot be
  configured away. Storage-specific schemas are a **separate deliverable**
  and are not covered by this status.
* **Evidence:**
  [schemas/v1/](schemas/v1),
  `src/ironkeeper/contracts/`,
  `src/ironkeeper/json/exactnumber.nim`,
  `tests/contract/schema_contract_tests.nim`,
  `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01/`,
  `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02/`
* **Next step:** Define the storage observation and inventory report
  contracts when IRK-03 and IRK-04 have concrete output to model. The
  numeric convention for byte counters beyond 2^53 is already decided and
  recorded in the architecture overview.

### IRK-03 — Linux discovery and persistent device identity

* **Status:** planned
* **Priority:** P0
* **Dependencies:** IRK-02
* **Acceptance criteria:** Devices are enumerated through sysfs and udev;
  each device gets a persistent identity record built from separate
  observations (WWN, serial, model, transport, topology); aliases are
  recorded; multipath aliases are reconciled; ambiguous identity prevents
  intrusive operations; identity verification binds to the opened handle.
* **Next step:** Specify the identity record schema and its persistence
  format. ADR-0003 fixes the rules; the format is still open.

### IRK-04 — SMART backend and protocol normalization

* **Status:** planned
* **Priority:** P0
* **Dependencies:** IRK-03
* **Acceptance criteria:** `smartctl -x -j` output is captured and
  normalised; the `smartctl` exit-status bitmask is preserved as part of
  the observation, not collapsed to a boolean; SCSI protection and
  capacity discovery are available; observations distinguish observed,
  derived and unavailable values.
* **Next step:** Build the adapter against synthetic `smartctl` fixtures
  before any real device is involved.

### IRK-05 — Safety and device ownership detection

* **Status:** planned
* **Priority:** P0
* **Dependencies:** IRK-03
* **Acceptance criteria:** Mounted filesystems, partitions, swap, device
  mapper, LVM, MD RAID, ZFS membership, multipath and open handles are
  all accounted for; unavailable or incomplete ownership evidence is
  treated as "not proven unused"; intrusive operations require proof.
* **Next step:** Define the ownership-evidence model and its
  unavailable/partial states.

### IRK-06 — Durable job engine and restart reconciliation

* **Status:** planned
* **Priority:** P0
* **Dependencies:** IRK-02, IRK-05
* **Acceptance criteria:** The job lifecycle in
  [lifecycle.md](docs/architecture/lifecycle.md) is durable across process
  restarts; restart reconciliation resolves every persisted job into a
  definite state; an interrupted intrusive operation is not resumed
  blindly; scheduled and on-demand execution share one engine.
* **Next step:** Choose the persistence technology. The candidates and
  the open questions are in
  [overview.md](docs/architecture/overview.md#proposed-future-decisions).

### IRK-07 — Native full-surface read scanner

* **Status:** planned
* **Priority:** P0
* **Dependencies:** IRK-03, IRK-05
* **Acceptance criteria:** A native read-only scanner performs aligned,
  bounded, concurrent reads and accounts for per-region errors; it opens
  devices `O_RDONLY` only; it never writes, flushes or modifies a
  partition table.
* **Next step:** Define the read-error accounting format, so that a scan
  result is an observation rather than a boolean.

### IRK-08 — Qualification profiles and assessment engine

* **Status:** planned
* **Priority:** P0
* **Dependencies:** IRK-04, IRK-06, IRK-07
* **Acceptance criteria:** Assessment is a pure function of preserved
  evidence and a policy revision; a missing mandatory observation yields
  `INCONCLUSIVE`, never `PASS`; verdicts are reproducible from the
  evidence; the policy revision is recorded with the verdict.
* **Next step:** Define the first qualification profile as data, not as
  code.

### IRK-09 — Unix socket API and CLI

* **Status:** planned
* **Priority:** P0
* **Dependencies:** IRK-06
* **Acceptance criteria:** An `AF_UNIX`/`SOCK_STREAM` control socket
  carries JSON-RPC 2.0 over newline-delimited framing; requests and
  responses are bounded; `SO_PEERCRED` identifies the peer; filesystem
  permissions are the authorisation boundary; systemd socket activation
  with `Accept=no` is used.
* **Next step:** Not started. The foundation CLI is **not** the control
  socket; IRK-09 remains open.
* **Note:** The foundation CLI in M0 does not satisfy this epic.

### IRK-10 — Systemd integration and Debian packaging

* **Status:** planned
* **Priority:** P0
* **Dependencies:** IRK-06, IRK-09
* **Acceptance criteria:** A systemd unit and socket unit are packaged; a
  Debian package installs the binary, the configuration and the schema
  documentation; the service starts unprivileged where possible and
  escalates only where it must.
* **Next step:** Decide the privilege model of the running service.

### IRK-11 — Persistent scheduler

* **Status:** planned
* **Priority:** P1
* **Dependencies:** IRK-06
* **Acceptance criteria:** Scheduled runs produce ordinary jobs through
  the ordinary engine; the schedule is durable; a missed schedule is
  reconciled on restart rather than silently skipped.
* **Next step:** None until the job engine exists.

### IRK-12 — SAS topology and PHY diagnostics

* **Status:** planned
* **Priority:** P1
* **Dependencies:** IRK-04
* **Acceptance criteria:** Expander and PHY state are observable as
  topology evidence; link errors are recorded as observations with their
  provenance.
* **Next step:** None until the SMART backend exists.

### IRK-13 — Production workload-aware maintenance

* **Status:** planned
* **Priority:** P1
* **Dependencies:** IRK-08, IRK-11
* **Acceptance criteria:** Maintenance windows respect observed workload;
  an operation that would interfere with production use is deferred
  rather than forced.
* **Next step:** None until qualification and scheduling exist.

### IRK-14 — Prometheus/VictoriaMetrics integration

* **Status:** planned
* **Priority:** P1
* **Dependencies:** IRK-08
* **Acceptance criteria:** Metrics are exported in a form VictoriaMetrics
  can scrape; the metric names carry the device identity and the policy
  revision; no metric implies a verdict that the evidence does not
  support.
* **Next step:** None until verdicts exist.

### IRK-15 — Real hardware qualification lab

* **Status:** planned
* **Priority:** P0
* **Dependencies:** IRK-04, IRK-07, IRK-08
* **Acceptance criteria:** The lab hardware exercises the full pipeline
  against real devices; the results are reproducible; the synthetic
  fixtures used in CI are validated against the real behaviour.
* **Next step:** Select the lab hardware and define the expected results
  for each scenario, including deliberately degraded devices.

### IRK-16 — Destructive operations and authorization

* **Status:** planned
* **Priority:** P2
* **Dependencies:** IRK-05, IRK-08, IRK-09
* **Acceptance criteria:** Destructive operations require explicit
  authorisation, proven device ownership and handle-bound identity
  verification; the safety policy that forbids them in M0 is relaxed
  only through an explicit, audited change.
* **Next step:** None. This is deliberately last.

### IRK-17 — Multi-host fleet aggregation

* **Status:** planned
* **Priority:** P2
* **Dependencies:** IRK-09, IRK-10
* **Acceptance criteria:** Reports from several hosts can be aggregated
  without weakening per-host evidence; host identity is part of the
  evidence provenance.
* **Next step:** None.

### IRK-18 — Historical health and predictive analysis

* **Status:** planned
* **Priority:** P2
* **Dependencies:** IRK-08, IRK-14
* **Acceptance criteria:** Historical evidence supports trend and
  prediction analysis; a prediction is distinguishable from an
  observation and from a verdict.
* **Next step:** None.

## Execution environment

The foundation milestone established the Linux-native execution path.
See `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01/linux-native.md`.

| Environment | Role | Status |
|---|---|---|
| GitHub Actions `ubuntu-24.04` | native Linux amd64, authoritative | in use |
| GitHub Actions `ubuntu-24.04-arm` | native Linux arm64 | in use |
| macOS workstation | editing, portable build and tests, static analysis | in use |

A local Linux guest under QEMU was attempted and abandoned as an
unjustified diversion once native runners were identified. It is
recorded as `SUPERSEDED_EXECUTION_ENVIRONMENT`, not as an
implementation failure. No product code depends on it.

**One orphaned QEMU process from that attempt remains** and could not be
signalled from the sandbox: `kill -TERM` and `kill -KILL` are both
denied for it. It is idle at 0.0% CPU and the guest image it depends on
no longer exists, so it cannot perform any further work and cannot
interfere with the build, the tests or the CI runs. The exact blocker
and the operator action are recorded in
`.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01/linux-native.md`. It is
an **environment-cleanup item**, not a product defect.

## First real-world use case

### LAB-IRK-SAS-ADMISSION-01

Automate qualification of a five-drive enterprise SAS RAIDZ2 candidate
fleet behind a multi-expander SAS topology.

This scenario is **registered**, not executed. No part of it has been
performed.

The eventual workflow:

1. Discover devices.
2. Establish physical identity.
3. Check capacity and sector/protection format.
4. Capture baseline SMART and transport evidence.
5. Execute bounded concurrent full-surface reads.
6. Compare health and transport counters.
7. Execute and reconcile extended self-tests.
8. Generate independently reproducible qualification verdicts.
9. Preserve evidence and device admission state.

**Depends on:** IRK-03, IRK-04, IRK-05, IRK-06, IRK-07, IRK-08, IRK-15.
**Owning ACT:** not yet assigned.

## Archive

Completed ACTs and superseded decisions are archived, not deleted. The
archive convention is:

* An ACT's evidence bundle stays at
  `.factory/evidence/<ACT-ID>/` permanently.
* When an ACT is superseded, its board entry moves to
  `.factory/archive/ACT-<ID>.md` with a line stating what replaced it
  and why.
* A superseded ADR is marked `Superseded by ADR-NNNN` at the top of the
  file and keeps its original text. It is never rewritten.
* History is not removed to reduce the size of the active board.

### ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-03

* **Status:** done
* **Scope:** Restore the remaining acceptance authority and close M0:
  the validator conformance oracle, the secret-scan report authority,
  the public output contracts, the bounded ingestion, the supported
  reference policy and the qualification workspace ownership.
* **Evidence:**
  `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-03/`
* **Supersedes:** the conformance counts of
  ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02. Its harness loaded the
  expected verdict and never compared it with the observed one, so its
  counts measured activity rather than conformance. The historical
  observation is retained; it is not evidence of conformance.
* **Next:** ACT-IRONKEEPER-READONLY-INVENTORY-01.

### ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02

* **Status:** done
* **Scope:** Restore the acceptance authority that independent review
  found defective: the mandatory CI gate authority, the secret-scan gate
  authority, the strict numeric contract, the supported schema policy,
  the report semantics, the public output contracts, the bounded
  ingestion and the reproducible validator qualification.
* **Evidence:**
  `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02/`
* **Replaces:** ACT-IRONKEEPER-FOUNDATION-01, whose `GO_FOUNDATION`
  verdict was withheld by review with the disposition
  `PARTIAL_FOUNDATION`. The predecessor's evidence bundle is **not**
  erased; its contradictions are corrected in place and marked.
