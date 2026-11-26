# ADR-0007: Evidence authority, provenance and deterministic verdicts

* **Status:** Accepted
* **Date:** 2026-11-26
* **Milestone:** M0 — Foundations
* **Deciders:** Ironkeeper maintainers

## Context

The value of Ironkeeper is not that it looks at disks. It is that an
operator can act on what it says and be able to defend the decision
later: to a colleague, to an auditor, or to themselves six months after
the fact.

That requires three things: the observations must be preserved as they
were made, it must be clear where each observation came from, and the
verdict must be recomputable from the evidence without trusting the
verdict.

## Decision

* **Original observations are preserved.** A sanitised copy is a copy; the
  original is never modified in place.
* **Observed, derived and unavailable values are distinguishable.** An
  unavailable observation is not a zero and is not an observation.
* **Every observation carries its provenance:** collection time, source
  and, when a tool was used, the tool's identity and version.
* **A finalised evidence record cannot be silently replaced.**
* **Policy revisions are recorded with the assessment** that used them.
* **Tool identity and version are captured.** A verdict produced by a
  different version of a tool is a different verdict.
* **Incomplete observations are recorded explicitly**, as incomplete.
* **Assessment is a pure function of the preserved evidence and the
  policy revision.** The assessment layer performs no I/O.
* **Hashes are integrity checks, not proof of provenance.** A digest over
  the preserved bytes detects accidental corruption. It does not
  authenticate who produced the bytes, and Ironkeeper does not describe
  it as if it did.

## Rationale

Separating *observed* from *derived* is what makes a verdict auditable.
A derived value — a capacity computed from a sector count, a wear
percentage computed from an attribute — has a different reliability
profile from an observed one, and a reader needs to know which they are
looking at.

Recording the tool version matters because storage tools change their
output format and their exit-status semantics between releases. A verdict
without the tool version cannot be compared with a later verdict.

Making assessment pure is what makes it *reproducible*: given the same
evidence and the same policy revision, the assessment is the same, and
two operators running Ironkeeper against the same evidence reach the same
conclusion. This is why the assessment layer sits above the adapter layer
in the architecture and performs no I/O of its own.

The hash disclaimer is stated explicitly because "SHA-256 verified" is
routinely read as "authentic", and it is not. It detects corruption and
accidental modification. It proves nothing about origin.

## Consequences

* The evidence model is larger than a simple results table. That is the
  cost of auditability.
* Evidence records must be immutable once finalised, which constrains
  the persistence layer.
* A policy change invalidates the verdicts produced under the old
  policy. The policy revision makes that visible rather than silent.
* The report contract carries `provenance` with `source`, optional
  `tool` and optional `digest`, and the assessment carries an optional
  `policy_revision`.

## Status

Accepted. The report contract implements the provenance and policy
revision fields. The evidence store, its immutability guarantee and the
recomputation machinery belong to IRK-08 and later milestones.
