# ADR-0005: Durable job lifecycle and restart reconciliation

* **Status:** Accepted
* **Date:** 2026-11-26
* **Milestone:** M0 — Foundations (recorded for IRK-06)
* **Deciders:** Ironkeeper maintainers

## Context

Ironkeeper will run long operations against storage devices: a
full-surface read of a multi-terabyte disk takes hours, a SMART
self-test takes longer. The host will reboot, the daemon will be
restarted by systemd, and an operator will restart it deliberately.

A job that is in flight when the process dies must not be lost, and it
must not be assumed to have succeeded. A job that was started must not be
silently abandoned. And the operator must be able to ask, months later,
what actually happened.

## Decision

* The job lifecycle is **durable**. The job record survives the process
  that created it.
* The lifecycle is the execution vocabulary defined in
  [lifecycle.md](../architecture/lifecycle.md): `QUEUED`, `PREFLIGHT`,
  `RUNNING`, `WAITING`, `VERIFYING`, `SUCCEEDED`, `FAILED`, `CANCELLED`,
  `INTERRUPTED`.
* On startup, the daemon performs **restart reconciliation**: it reads the
  persisted job records, compares them with the work it can actually see,
  and resolves each one into a definite state.
* A job that was `RUNNING` when the process died is **not** resumed
  blindly. It is moved to `INTERRUPTED` unless the operation is
  explicitly resumable and the resumption is safe. For an intrusive
  operation, resuming is not safe by default.
* **Scheduled and on-demand execution are the same kind of job.** There
  is one engine and one lifecycle, so that a scheduled run and an
  operator-triggered run are audited identically.
* Job state transitions are **recorded, not merely held**. The sequence
  of transitions is part of the audit trail.

## Rationale

The tempting alternative is to keep job state in memory and treat a
restart as "everything was cancelled". That is simple, and it is wrong
for a storage tool: a cancelled full-surface read leaves the operator
unable to distinguish "I stopped it" from "the machine lost power
half-way through" from "it finished and nobody looked at the result".

`INTERRUPTED` exists specifically so that the third case is not
collapsed into the first two.

Not resuming intrusive operations by default follows from the
non-destructive principle: an operation that was interrupted at an
unknown point may have left a device in an unknown state, and repeating
it without knowing where it stopped is a risk.

Making scheduled and on-demand execution the same kind of job means the
audit trail does not need two vocabularies, and that a schedule cannot
quietly do something the operator would not approve if they had typed it.

## Consequences

* Job state needs durable storage. The persistence technology is an open
  decision; see
  [overview.md](../architecture/overview.md#proposed-future-decisions).
* Restart reconciliation is a distinct, well-defined piece of work that
  must be tested against crash scenarios, not just against a clean
  start.
* Idempotency matters: replaying a job record must not perform the
  operation twice.
* The scheduler (IRK-11) is a producer of jobs, not a separate execution
  path.

## Status

Recorded and accepted. The job engine is **not** implemented in
milestone M0.
