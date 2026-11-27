# ADR-0009 — Lossless ingestion of external telemetry

* **Status:** accepted
* **Date:** 2026-11-27
* **Decides:** how third-party JSON telemetry enters Ironkeeper

## Context

Ironkeeper's own contracts use a strict numeric policy: the strict reader
rejects an integer that does not fit in `int64`, and rejects an integral
value whose magnitude exceeds 2^53. The policy exists so that a document
cannot mean something different from what its source text says.

The telemetry of a storage device is **not** Ironkeeper's own document. A
`smartctl -x --json` response may legitimately carry a counter larger
than an unsigned 64-bit integer, and it may carry that counter in more
than one representation at once: as a decimal string, and as a
hexadecimal companion. Applying the internal policy to the complete
payload would reject a perfectly valid device response.

Routing the payload through the internal reader would also destroy
information: the internal reader rejects the value, so the field is
lost, and the operator is left with an incomplete observation for a
reason that has nothing to do with the device.

The foundation also left one open item: two distinct external member
names that repair to the same text were not distinguished, so a
text-sanitising ingestion path could collapse two names into one.

## Decision

1. **A separate reader.** External telemetry is ingested by a second,
   lossless reader (`src/ironkeeper/storage/externaljson.nim`). It is not
   the internal strict reader, and the internal numeric domain is **not**
   widened to accommodate third-party documents.
2. **Exact lexemes.** Every number keeps its exact source lexeme. No
   value passes through a binary64 conversion on the way in, and the
   exact decimal value is computed from the digits when it is consumed.
3. **No repair.** An external member name is never repaired. A document
   that is not valid UTF-8 is **rejected**, so two distinct names can
   never collapse into one. Names are compared after JSON unescaping, so
   two spellings of the same name are a duplicate and are rejected.
4. **Duplicates are detected before information is lost.** A duplicate
   member name is an ingestion failure, not a last-one-wins merge.
5. **Companions are verified where consumed.** When a value and its
   companion representation are both read, they are compared. A
   disagreement is reported as a conflicting observation and a finding;
   it is never resolved by preferring one of the two.
6. **Malformed output is evidence, not telemetry.** A response that
   cannot be ingested is preserved as raw evidence and is marked as such.
   It is never represented as successfully normalised telemetry.
7. **Normalised output is strictly valid.** The documents that Ironkeeper
   produces from ingested telemetry satisfy the Ironkeeper contracts
   exactly, including the exact-number convention: a counter beyond 2^53
   is carried as a canonical decimal **string**.

## Consequences

* The internal numeric contract stays narrow, and the third-party domain
  does not widen it.
* A device counter that exceeds 64 bits is preserved exactly, and the
  operator sees every digit.
* A malformed response is visible as a failure rather than as a missing
  field.
* The ingestion path is a second implementation of JSON parsing. It is
  deliberately small, it is exercised by the numeric witnesses in the
  test suite, and it exists because the alternative - widening the
  internal policy - would weaken the guarantee the internal policy
  exists to provide.

## Alternatives considered

* **Apply the internal reader to the external payload.** Rejected: it
  rejects valid device responses and loses the counter.
* **Widen the internal numeric domain.** Rejected: it would weaken the
  guarantee for Ironkeeper's own contracts, and it would make the
  "exactly representable" claim of the internal policy untrue.
* **Parse the external JSON with a general-purpose library.** Rejected:
  it would not preserve the exact lexeme, would not detect duplicate
  member names reliably, and would add a dependency.

## Related

* [ADR-0002](0002-versioned-json-contracts-and-strict-runtime-validation.md)
* [ADR-0007](0007-evidence-authority-provenance-and-deterministic-verdicts.md)
* [docs/architecture/storage-observation.md](../docs/architecture/storage-observation.md)
