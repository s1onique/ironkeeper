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
| M0 — Foundations | Architecture, contracts, CLI, tests, CI | **accepted** — the qualified commit `b85fa0bb9b7f50e3ce170cf6ab9ae776207a4336` passed all four CI jobs (runs `45935432045` and `45935427044`); the tree is identical to the current `main` (`c2c34e34721fced22080a3b6ead6d7c3c77041bd`), so M0 is accepted on the basis of the qualified identical tree. The later main-run failure (`45935586165`) was an external environment failure: the amd64 dependency installation step received HTTP 403 from `packages.microsoft.com`. The other three jobs succeeded. |
| M1 — Read-only inventory and SMART observations | Discovery, identity, SMART acquisition | **implementation repaired, live acceptance pending** — the amendment ACT-IRONKEEPER-READONLY-INVENTORY-01-AMENDMENT-01 repaired the safety, attribution and observation-correctness defects of the implementation: the test seams are compile-time properties, the exit status uses the upstream bit definitions and the real numeric companions, the capacity arithmetic conserves every digit, the collection completeness follows the requested observation coverage, and the attribution is refused when the device disappears, is replaced, cannot be rediscovered or contradicts the tool. The live acceptance is executed by the operator against the qualified production artefact; the procedure is in `.factory/evidence/ACT-IRONKEEPER-READONLY-INVENTORY-01-AMENDMENT-01/live-requalification.md`. The public-history privacy status is **unresolved** and needs an operator-authorised remediation. |
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

* **Status:** done (foundation and the current storage scope)
* **Priority:** P0
* **Dependencies:** IRK-01
* **Owning ACT:** ACT-IRONKEEPER-FOUNDATION-01 (foundation);
  ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02 (numeric contract, supported
  schema policy, report semantics, output contracts); future ACTs
  (storage contracts)
* **Note:** The status covers the configuration, report, error and version
  contracts and their runtime enforcement, **and** the storage contracts
  of the current M1 scope: `inventory.schema.json`,
  `device.schema.json`, `observation.schema.json` and
  `evidence.schema.json`. A future storage contract (for example a
  qualification-profile document) remains a separate deliverable and is
  **not** covered by it.
* **Acceptance criteria:** Configuration, report, error and version
  schemas exist at version 1, are Draft 2020-12, reject unknown
  properties, and are embedded byte-for-byte. Runtime validation is
  performed by the shipped binary. The mandatory safety values cannot be
  configured away. The storage contracts of the current M1 scope exist
  under the same rules and are validated independently in CI.
* **Evidence:**
  [schemas/v1/](schemas/v1),
  `src/ironkeeper/contracts/`,
  `src/ironkeeper/storage/documents.nim`,
  `src/ironkeeper/json/exactnumber.nim`,
  `tests/contract/schema_contract_tests.nim`,
  `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01/`,
  `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02/`
* **Next step:** Define the qualification-profile contract when IRK-08
  has a concrete profile to model. The numeric convention for byte
  counters beyond 2^53 is already decided and recorded in the
  architecture overview, and the storage contracts now follow it.

### IRK-03 — Linux discovery and persistent device identity

* **Status:** in progress (the current discovery scope is implemented)
* **Priority:** P0
* **Dependencies:** IRK-02
* **Acceptance criteria:** Devices are enumerated through sysfs and udev;
  each device gets a persistent identity record built from separate
  observations (WWN, serial, model, transport, topology); aliases are
  recorded; multipath aliases are reconciled; ambiguous identity prevents
  intrusive operations; identity verification binds to the opened handle.
* **Note:** The discovery, the identity reconciliation, the alias handling
  and the ambiguity refusal are implemented and tested. The **handle-bound**
  identity verification is **not**: the tools are executed by pathname, so
  the pre/post identity checks do not eliminate every time-of-check /
  time-of-use race. The handle-bound authority remains a mandatory
  future gate (IRK-05/IRK-07). M1 introduces no durable identity
  registry and no persistent enrollment state.
* **Next step:** Specify the identity record schema and its persistence
  format, and the handle-bound identity authority. ADR-0003 fixes the
  rules; the format is still open.

### IRK-04 — SMART backend and protocol normalization

* **Status:** in progress (the read-only scope is implemented)
* **Priority:** P0
* **Dependencies:** IRK-03
* **Acceptance criteria:** `smartctl -x -j` output is captured and
  normalised; the `smartctl` exit-status bitmask is preserved as part of
  the observation, not collapsed to a boolean; SCSI protection and
  capacity discovery are available; observations distinguish observed,
  derived and unavailable values.
* **Note:** The read-only scope is implemented: the `smartctl` adapter,
  the exit-status bitmask, the SCSI capacity and protection decoder and
  the SAS, SATA and NVMe normalisation. The **self-test** operations are
  deliberately **not** implemented in M1: they are intrusive and belong
  to a later milestone with an ownership model. The amendment
  ACT-IRONKEEPER-READONLY-INVENTORY-01-AMENDMENT-01 corrected the
  exit-status semantics to the upstream definitions, replaced the
  invented numeric companions with the real `KEY_s` and `KEY_le` ones,
  made the capacity arithmetic exact and made the missing protection
  evidence distinguishable from an observed disabled protection.
* **Next step:** Implement the self-test operations in the milestone that
  owns the device-ownership model (IRK-05/IRK-06), with the fail-closed
  admission rules.

### ACT-IRONKEEPER-READONLY-INVENTORY-01-AMENDMENT-01 — the M1 repair

* **Status:** done (the implementation and the contracts); the live
  acceptance and the public-history remediation are open
* **Owning ACT:** ACT-IRONKEEPER-READONLY-INVENTORY-01-AMENDMENT-01
* **Predecessor:** ACT-IRONKEEPER-READONLY-INVENTORY-01, independent
  review disposition `PARTIAL_INVENTORY`
* **Evidence:**
  `.factory/evidence/ACT-IRONKEEPER-READONLY-INVENTORY-01-AMENDMENT-01/`
* **Acceptance criteria:** the production binary cannot activate the test
  seams; the backend execution preserves the stream identity and the
  deadline; the device disappearance and the device replacement refuse
  the attribution; a failed acquisition cannot claim complete evidence;
  the SMART exit bits and the numeric companions follow the upstream
  definitions; the capacity arithmetic conserves every digit; a missing
  protection field never becomes Type 0; the identity confidence and the
  namespace semantics are corrected; the evidence directory is owned
  atomically; the runtime output and the manifest are validated against
  the contracts before they are published.
* **Next step:** the operator requalification on the storage host
  (procedure in the evidence directory), and the operator decision on the
  public-history remediation. The successor ACT is
  ACT-IRONKEEPER-DEVICE-OWNERSHIP-SAFETY-01.

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

* **Status:** in progress (partial)
* **Priority:** P1
* **Dependencies:** IRK-04
* **Acceptance criteria:** Expander and PHY state are observable as
  topology evidence; link errors are recorded as observations with their
  provenance.
* **Note:** The per-PHY observations are implemented: the negotiated link
  rate, the invalid DWORD count, the running disparity errors, the loss
  of DWORD synchronisation, the PHY reset problems, the SAS addresses and
  the attached PHY identifier are recorded per port and per PHY, and the
  counters are never reset or aggregated. The **expander graph** and the
  diagnosis of a shared transport bottleneck are **not** implemented.
* **Next step:** The expander topology model, in a milestone that has the
  device-ownership model.

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

* **Status:** in progress (partial)
* **Priority:** P0
* **Dependencies:** IRK-04, IRK-07, IRK-08
* **Acceptance criteria:** The lab hardware exercises the full pipeline
  against real devices; the results are reproducible; the synthetic
  fixtures used in CI are validated against the real behaviour.
* **Note:** The live SAS inventory lab (LAB-IRK-SAS-INVENTORY-01) is
  defined and its runbook is published. The lab exercises the **inventory**
  only; it is **not** the full qualification, which also needs the
  surface-read scanner (IRK-07) and the assessment engine (IRK-08).
* **Next step:** Execute LAB-IRK-SAS-INVENTORY-01 against the qualified
  executable, and define the expected results for the deliberately
  degraded scenarios.

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

### ACT-IRONKEEPER-READONLY-INVENTORY-01

* **Status:** execution-complete, verdict `INVENTORY_READY_LIVE_ACCEPTANCE_PENDING`
* **Scope:** Implement the first operational storage observation
  capabilities: the Linux discovery, the identity reconciliation, the
  bounded read-only interrogation, the lossless external JSON ingestion,
  the strict storage contracts, the CLI surface and the evidence bundle.
* **Evidence:**
  `.factory/evidence/ACT-IRONKEEPER-READONLY-INVENTORY-01/`
* **Subject:** see the exit receipt in the evidence directory.
* **Open:** the live SAS acceptance (LAB-IRK-SAS-INVENTORY-01) is
  executed by the operator against the qualified executable. The
  implementation, the contracts, the native Linux CI and the independent
  document validation are established.
* **Next:** the operator action is recorded in the exit receipt; after the
  live acceptance, ACT-IRONKEEPER-DEVICE-OWNERSHIP-SAFETY-01.

### ACT-IRONKEEPER-M0-CLOSURE-01

* **Status:** execution-complete, verdict `PARTIAL_FOUNDATION`
* **Scope:** Close M0. Correct the narrow acceptance defects that
  independent review identified — the CI toolchain bootstrap, the
  fail-closed requalification decision, the qualification accounting, the
  qualification input identity and the output truncation bounds — and
  qualify the actual subject.
* **Evidence:**
  `.factory/evidence/ACT-IRONKEEPER-M0-CLOSURE-01/`
* **Subject:** `2c8ef1e2c3108ce4f26821398256d449795b6056`
  (the executable subject; the closure documents are a later commit and
  carry their own identity).
* **Open:** the subject has no native CI run, because the sandbox cannot
  push to the remote. The operator action is
  `git push origin act/ironkeeper-foundation-01-amendment-03`.
* **Next:** ACT-IRONKEEPER-READONLY-INVENTORY-01, once the native run of
  the subject has reached a terminal conclusion with all four jobs
  successful.
* **Follow-ups (nonblocking):**
  * Inject an *actual* failing `git diff` into the selective
    requalification decision. The decision is fail-closed today, but the
    failing-diff path is currently exercised through a broken repository
    rather than through a diff that fails on its own.
  * Make the UTF-8 handling of arbitrary object keys collision-safe
    before any external telemetry ingestion. The repair of invalid bytes
    is explicit today; two distinct keys that repair to the same text
    are not yet distinguished.
  * Qualify less often. The qualification is unconditional today. The
    selective decision may only be given authority again after M1.

### ACT-IRONKEEPER-M0-CI-HANDOFF-01

* **Status:** execution-complete, verdict `PARTIAL_FOUNDATION`
* **Scope:** Correct the CI toolchain verification. `GITHUB_PATH` is a
  per-step environment-command file, so the installation directory
  cannot be reconstructed from it; the verifier now derives the
  deterministic installation path. Establish the production-path
  regression witness and prove it non-vacuous.
* **Evidence:**
  `.factory/evidence/ACT-IRONKEEPER-M0-CI-HANDOFF-01/`
* **Subject:** `3ad85446cd9561e9d9c5e16deb817aabb855dd6d`
  (the executable subject; the closure documents are a later commit and
  carry their own identity)
* **Remote evidence:** runs 45934380741 and 45934374904 executed the
  entry commit and failed at the step "Verify the pinned toolchain" in
  the amd64, arm64 and validator-qualification jobs; the secret scan
  succeeded. Run 45934831421 executed the corrected verifier: the
  production toolchain verification, the secret scan and the
  authoritative native validator qualification all passed, and only the
  regression fixture failed - which this ACT corrects.
* **Open:** the subject has no CI run; one authenticated push preflight
  was denied. The operator action is
  `git push origin act/ironkeeper-foundation-01-amendment-03`.
* **Next:** ACT-IRONKEEPER-READONLY-INVENTORY-01, once the native run of
  the subject has reached a terminal conclusion with all four jobs
  successful.

### ACT-IRONKEEPER-M0-CLOSURE-01-AMENDMENT-01

* **Status:** execution-complete, verdict `PARTIAL_FOUNDATION`
* **Scope:** Correct the three remaining closure defects: the CI
  toolchain bootstrap seam, the caller-controlled qualification
  authority and the report semantic rule for a truncated findings
  collection. Publish the observed optional-corpus results.
* **Evidence:**
  `.factory/evidence/ACT-IRONKEEPER-M0-CLOSURE-01-AMENDMENT-01/`
* **Subject:** `f1b9ca0f4f690b9ad053d928aafba82d6ab1c5c3`
* **Open:** the subject has no native CI run. One bounded authentication
  preflight was performed and denied; the operator action is
  `git push origin act/ironkeeper-foundation-01-amendment-03`.
* **Next:** ACT-IRONKEEPER-READONLY-INVENTORY-01, once the native run of
  the subject has reached a terminal conclusion with all four jobs
  successful.

### ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-03

* **Status:** execution-complete, qualification-partial
* **Note:** the predecessor could not authenticate to GitHub from its
  sandbox, so it could not observe a CI run. That observation is
  **historical**: subsequent remote CI runs `45926174624` and
  `45926147466` executed the same commit `c3c4b588` and reached terminal
  conclusions, with the native amd64 and arm64 build-and-test jobs and
  the secret-scan gate successful. The predecessor's own receipts are
  retained unchanged; the remote runs are recorded by the closure ACT.
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
* **Next:** ACT-IRONKEEPER-M0-CLOSURE-01 (mandatory gates), and then
  ACT-IRONKEEPER-READONLY-INVENTORY-01.

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
