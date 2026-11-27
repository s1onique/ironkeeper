# Architecture decisions

Two decisions constrain the work and are recorded as ADRs.

## ADR-0009 — Lossless ingestion of external telemetry

The internal strict numeric policy is **not** applied to third-party
payloads. A separate, lossless reader preserves the exact source lexeme
of every number, rejects duplicate member names before information is
lost, and never repairs an external member name, so two distinct names
can never collapse into one. This closes the foundation's open UTF-8
collision follow-up at this boundary.

The internal numeric domain is **not** widened.

See `docs/adr/0009-lossless-external-json-ingestion.md`.

## ADR-0010 — Observation identity and the external-tool execution boundary

The identity concepts stay apart, the identity carries a *confidence*,
an ambiguous identity refuses the active interrogation, M1 introduces no
durable identity registry, and every external tool runs through exactly
one bounded execution boundary with a closed set of executable paths.

The residual time-of-check/time-of-use race of a pathname-based
invocation is **documented**, not claimed to be solved.

See `docs/adr/0010-observation-identity-and-external-tool-execution.md`.

## The observation model

The five independent domains - execution outcome, observation
completeness, device-reported health, identity confidence and the
qualification verdict - are kept apart. M1 assigns **no** verdict.

The full description is in
`docs/architecture/storage-observation.md`.
