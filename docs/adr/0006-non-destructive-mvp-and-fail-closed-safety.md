# ADR-0006: Non-destructive MVP and fail-closed safety

* **Status:** Accepted
* **Date:** 2026-11-26
* **Milestone:** M0 — Foundations
* **Deciders:** Ironkeeper maintainers

## Context

Ironkeeper will eventually manage production storage. The most dangerous
thing it can do is write to or destroy the wrong device. The cost of that
mistake is not a failed maintenance job; it is somebody's data.

There is also a subtler danger: a tool that is *configured* to be safe
but that fails open under an unexpected condition. A safety check that
cannot determine whether a device is in use and then proceeds anyway is
worse than no safety check at all, because it creates false confidence.

## Decision

* **Non-destructive by default.** Milestone M0 performs no write to any
  device. The first milestone that performs any device operation will be
  read-only.
* **Destructive operations are not implemented in M0**, and the safety
  policy that forbids them **cannot be configured away**:
  `allow_destructive_operations` accepts only `false`, and the semantic
  layer rejects any attempt to change the mandatory safety values.
* **Fail closed.** When a required check cannot be performed, the
  operation fails. It does not assume the permissive answer.
* **Absence of evidence of usage is not evidence that a device is
  unused.** Incomplete ownership evidence means "not proven unused", and
  an intrusive operation does not proceed.
* **Ambiguous identity prevents intrusive operations.**
* **A verdict requires evidence.** An operation that could not obtain
  the evidence it needed reports `INCONCLUSIVE`, never `PASS`.
* **Every external side effect has an explicit owner.** The module that
  opens a device, writes a file or runs a command is named.
* **Originals are never modified in place.**

## Rationale

The MVP is deliberately non-destructive because the value of Ironkeeper
is in *observing and deciding*, not in acting. A read-only tool that
produces trustworthy verdicts is useful immediately and cannot destroy
anything. Adding the ability to act later, on top of a tool whose
observation and verdict machinery is already trusted, is a much smaller
step than adding both at once.

Making the safety values non-configurable is unusual for configuration
systems, and that is the point. A flag that turns off a safety property
is a flag that will be turned off once, for a reason that seemed
reasonable, and never turned back on. In M0 the schema itself accepts
only the safe value, so the dangerous configuration is not expressible.

Fail-closed is the only safe default for a check whose failure mode is
"the system cannot tell whether this disk is in use". The alternative —
proceeding when the answer is unknown — converts an absence of
information into a destructive action.

## Consequences

* The M0 configuration contract is deliberately tiny. It carries the
  safety block so that the *shape* of the policy is established, and
  nothing else.
* Future configuration options for schedules, hardware backends and
  execution behaviour are **not** accepted until the subsystem that
  would honour them exists. An accepted-but-ignored option is a lie.
* The destructive-operations milestone (IRK-16) requires explicit
  authorisation, ownership verification and handle-bound identity
  verification, and it is a P2 epic.
* Every safety check needs a test that proves it actually rejects.

## Status

Accepted and implemented for the parts that exist in M0: the mandatory
safety policy values, the strict ingestion fail-closed behaviour, and the
`INCONCLUSIVE` verdict path. The ownership and identity subsystems are
recorded but not implemented.
