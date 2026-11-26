# ADR-0003: Persistent physical identity, aliases and multipath

* **Status:** Accepted
* **Date:** 2026-11-26
* **Milestone:** M0 — Foundations (recorded for IRK-03)
* **Deciders:** Ironkeeper maintainers

## Context

On a Linux storage host, `/dev/sdX` is an allocation in a naming
scheme, not an identity. The same physical disk can be reachable as
`/dev/sdX`, `/dev/disk/by-id/scsi-...`, `/dev/disk/by-path/...` and, in a
multipath configuration, as `/dev/mapper/mpatha` plus each underlying
path. Device names change across reboots and across hardware events.

Ironkeeper will eventually start self-tests, run full-surface reads and
make admission decisions. Performing any of those against the wrong path
means performing them against the wrong disk, which for a write-capable
operation means destroying somebody's data.

## Decision

* **`/dev/sdX` is a transient access path, never an authoritative
  physical device identifier.**
* A device's physical identity is a **persistent record** composed of
  distinct observations: **WWN**, **serial**, **model**, **transport**
  and **topology**. These are recorded separately, because they are
  separately unreliable and separately useful.
* **Aliases are recorded, not resolved away.** The set of paths that
  refer to one physical device is part of the identity record.
* **Multipath aliases are reconciled before any physical-device
  operation.** If more than one alias refers to one device, the operation
  applies to the device, through a reconciled handle.
* **Ambiguous identity prevents intrusive operations.** If the evidence
  does not uniquely identify one physical device, the operation does not
  proceed.
* **Identity verification is bound to the opened handle.** Before a
  device operation, the identity of the handle that was actually opened
  is verified against the identity record — not against the path that
  was used to open it.

## Rationale

WWN and serial are the strongest identifiers but are not universally
present, and on some devices they are known to be non-unique or
duplicated by firmware. Model and transport are weak identifiers. The
combination, with the *disagreement between them* recorded explicitly,
is what makes identity checkable: a device whose WWN changes between two
observations is a device whose identity is in question.

Recording aliases rather than resolving them away preserves the
information needed to detect a multipath configuration and to notice that
a path set changed.

Binding verification to the opened handle is the only defence against the
time-of-check-to-time-of-use gap: between resolving a path and opening
it, the path may point somewhere else. Verifying the handle closes that
gap.

## Consequences

* The identity model must distinguish *observed*, *derived* and
  *unavailable* values. An unavailable WWN is not a zero WWN.
* Two observations of the same device that disagree are a finding, not
  something to reconcile silently.
* Multipath support is a first-class concern from the start, not an
  afterthought.
* The identity subsystem is a prerequisite for any intrusive operation.
  Until it exists, only read-only observation is permitted.

## Status

Recorded and accepted. The subsystem itself belongs to IRK-03 and is not
implemented in milestone M0.
