# ADR-0002: Versioned JSON contracts and strict runtime validation

* **Status:** Accepted
* **Date:** 2026-11-26
* **Milestone:** M0 — Foundations
* **Deciders:** Ironkeeper maintainers

## Context

Ironkeeper's outputs are consumed by operators, by scripts and, later, by
other hosts in a fleet. Its inputs are configuration files that an
operator edits by hand. Both sides need a contract that is precise,
versioned and enforced at runtime rather than merely documented.

The specific failure modes that motivated this decision:

* Two JSON parsers disagree about a document with duplicate member names.
* A configuration that says `"true"` where a boolean is required is
  accepted by one tool and rejected by another.
* A document with trailing content is silently truncated by one reader
  and rejected by another.
* A schema that references an external URI causes a validation run to
  fetch from the network, in a tool that is supposed to work offline.

## Decision

* All public documents are **JSON Schema Draft 2020-12** and live under
  `schemas/v1/`.
* Every public document carries an explicit **`schema_version`**.
* Every object boundary sets **`additionalProperties: false`**.
* Validation is performed **at runtime by the shipped binary**, using a
  qualified Draft 2020-12 validator.
* Input is ingested by a **strict reader** that rejects invalid UTF-8,
  trailing content, duplicate member names, non-finite numbers and
  out-of-range integers.
* **No implicit type coercion** anywhere.
* **Schema resolution never reaches the network.** Only local JSON
  Pointers and the bundled metaschema resolve.
* Structural validation and semantic validation are **distinct passes**
  with distinct failure classes.
* Every schema is **meta-validated** against the Draft 2020-12 metaschema
  before it is used to validate data.

## Rationale

JSON Schema was chosen over a hand-written validator because the
vocabulary is standard, reviewable and testable against an independent
implementation. A hand-written validator for Ironkeeper's own schemas
would be less code, but it would have no independent conformance story
and no way to cross-check against another implementation.

The strict reader exists because `std/json` is permissive in ways that
matter for evidence. A document whose meaning depends on parser
implementation details is not auditable. The reader is a separate module
rather than a wrapper, so that there is no permissive fallback
underneath it.

The numeric bound at 2^53 exists because JSON Schema's numeric semantics
are defined over IEEE-754 binary64. Accepting a larger integer would
mean accepting a value that cannot be represented exactly, and a storage
report that rounds a byte count is worse than one that refuses to produce
it.

Meta-validating every schema before use is what makes "an unsupported
keyword must not silently become a no-op" enforceable. It also contains
a known defect in the upstream validator, as
[ADR-0002](../architecture/overview.md#validator-qualification) records.

## Consequences

* Documents are larger than a hand-written format would be.
* The project carries one third-party dependency (`jschema`) and must
  track its maintenance.
* Cross-version compatibility is handled by keeping `schemas/vN/`
  directories side by side rather than by in-place schema edits.
* A schema change that breaks a consumer requires a new version
  directory and a migration note.
* The runtime validator and an independent CI validator must agree. CI
  cross-checks with `check-jsonschema` so that a divergence is caught.
