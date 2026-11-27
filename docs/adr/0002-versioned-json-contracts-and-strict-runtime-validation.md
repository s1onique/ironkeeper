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
* Every schema must additionally satisfy Ironkeeper's **supported schema
  policy**: every keyword in a schema-bearing position is drawn from a
  documented, bounded list, and prohibited constructs are refused.
* Every JSON number is classified **exactly, from its source text**. The
  numeric range is decided before any binary64 conversion, so a value can
  never be rounded into the accepted range, a noninteger can never become
  an integer, and a nonzero number can never become zero.
* Input ingestion is **bounded**: the byte limit is enforced before an
  unbounded amount of input is consumed, and the opened input must be a
  regular file.

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

### Why the numeric decision is made from the source text

The numeric bound at 2^53 is an **Ironkeeper** restriction. JSON Schema
does not define a universal numeric model: its keywords are written over
mathematical numbers, and the specification says nothing about IEEE-754
binary64. Ironkeeper chooses binary64 as the numeric model of its own
documents, and refuses any number it cannot represent exactly. Accepting
a larger integer would mean accepting a value that cannot be represented
exactly, and a storage report that rounds a byte count is worse than one
that refuses to produce it.

The bound was originally enforced *after* converting the source text to a
binary64, which made the bound meaningless. `9007199254740993.0` was
converted to `9007199254740992.0` and then accepted; `1e-400` was
converted to `0.0`; `1.00000000000000001` was converted to `1.0`. Each
of those is a *silent* corruption: the document then claims something the
source did not say. The bound must therefore be decided from the source
text, with exact decimal arithmetic, before any lossy step.

The same code path raised an unhandled `OverflowDefect` for the signed
minimum, because `abs(int64.low)` overflows. The exact classification
compares magnitudes as `uint64` and never negates the minimum.

Ironkeeper does **not** claim that binary64 represents every decimal
fraction exactly. It never represents a fraction at all: a non-integral
decimal is refused rather than rounded. The accepted value set is a
strict subset of what binary64 can hold, and every accepted value is
exact in binary64.

### Why the supported schema policy exists

Meta-validation answers "is this a valid Draft 2020-12 schema?". It does
not answer "is this a schema whose keywords Ironkeeper understands?".
A misspelled keyword — `additionalPropeties` for `additionalProperties`,
`minimun` for `minimum` — is a *valid* Draft 2020-12 schema, so
meta-validation accepts it and the keyword's intent is silently lost.
The supported schema policy closes that gap with an explicit, bounded and
documented feature subset.

The policy distinguishes a keyword from a *name*. A property called
`minimun`, a member of a `const` object and a member of an `examples`
array are values, not keywords, and are never rejected as unknown
keywords.

### Why ingestion is bounded

Reading a document and *then* checking its size is not a limit: the
document has already been materialised in memory. The size check must
happen before the unbounded read, and the reader must refuse an input
that is not a regular file, so that a FIFO or a device node cannot block
the command.

## Consequences

* Documents are larger than a hand-written format would be.
* The project carries one third-party dependency (`jschema`) and must
  track its maintenance.
* Cross-version compatibility is handled by keeping `schemas/vN/`
  directories side by side rather than by in-place schema edits.
* A schema change that breaks a consumer requires a new version
  directory and a migration note. Compatibility is judged by producer and
  consumer behaviour; adding an optional field to a *closed* schema is
  **not** automatically compatible.
* The runtime validator and an independent CI validator must agree. CI
  cross-checks with `check-jsonschema` so that a divergence is caught.
* The supported schema policy is narrower than Draft 2020-12. A valid
  generic schema that falls outside the subset is deliberately refused.
  This is a recorded, classified outcome, not an unexplained failure.
* The strict reader rejects non-integral numbers. A contract that needs a
  fractional value must carry it as a decimal string, and a contract that
  needs a counter beyond 2^53 must carry it as a canonical decimal string
  with a documented conversion and range semantics. This applies to
  **external hardware telemetry** as well: the original observation is
  preserved exactly and is never routed through the strict reader.
