# Invariants

These are the properties Ironkeeper must preserve. They are stated as
rules about behaviour, not about implementation, and they are the things
that a future ACT must not break.

Each invariant names the mechanism that enforces it today, or says plainly
that nothing enforces it yet.

## Documents and parsing

**I-1. A document is either fully understood or rejected.**
There is no partial parse, no "best effort" recovery and no permissive
fallback. *Enforced by:* the strict reader in
`src/ironkeeper/json/strictjson.nim`, which never delegates to
`std/json`.

**I-2. A document's meaning does not depend on the parser.**
Duplicate member names, trailing content, invalid UTF-8, non-finite
numbers and out-of-range integers are rejected, so two conforming
implementations agree on what a document means. *Enforced by:* the strict
reader; witnessed by `tests/unit/strictjson_tests.nim`.

**I-3. A member name is identified by its value, not its spelling.**
`"a"` and `"a"` are the same member name. *Enforced by:* the
strict reader compares names after unescaping.

**I-4. Numbers are represented exactly or not at all.**
No value whose magnitude exceeds 2^53 is accepted, because such a value
cannot be represented exactly as a binary64 and would silently round.
*Enforced by:* the strict reader; documented in
[overview.md](overview.md#numeric-representation).

**I-5. Every document is bounded.**
Size and nesting depth are limited, and the limits are part of the public
contract. *Enforced by:* the strict reader.

## Contracts and validation

**I-6. Every public document declares its schema version.**
*Enforced by:* the `schema_version` property in every schema.

**I-7. Every object boundary rejects unknown properties.**
An unknown property is a schema violation, not something to ignore. *Enforced
by:* `additionalProperties: false` in every object of every schema.

**I-8. Structural and semantic validation are distinct.**
A schema establishes shape; a semantic pass establishes the rules a
schema cannot express. The two have separate failure classes
(`schema_validation_failed` and `semantic_validation_failed`). *Enforced
by:* `src/ironkeeper/config/semantics.nim` running after
`src/ironkeeper/contracts/validator.nim`.

**I-9. A schema is validated before it is used.**
A schema document is meta-validated against the Draft 2020-12 metaschema
before it validates anything. An unsupported keyword is refused, not
silently ignored. *Enforced by:* the adapter in
`src/ironkeeper/contracts/validator.nim`.

**I-10. Schema resolution never touches the network.**
Only local JSON Pointers and the bundled metaschema URI resolve.
Everything else is rejected. *Enforced by:* the adapter; there is no
fetching code path.

**I-11. The embedded schemas are the repository schemas.**
The bytes compiled into the binary are byte-for-byte identical to the
files under `schemas/v1/`. *Enforced by:*
`tests/contract/schema_contract_tests.nim`.

**I-12. There is no implicit type coercion.**
`"true"` is not a boolean. `1` is not `true`. A string is never accepted
where a number is required. *Enforced by:* the strict reader's typed
parsing and by the schemas; witnessed by
`tests/unit/validator_tests.nim`.

## Safety

**I-13. The mandatory safety policy cannot be configured away.**
`allow_destructive_operations` must be false,
`require_explicit_enrollment` must be true and
`allow_tests_on_in_use_devices` must be false. The schema accepts only
`false` for the two that must be false, and the semantic layer rejects
any attempt to change them. *Enforced by:* the configuration schema and
`src/ironkeeper/config/semantics.nim`; witnessed by
`tests/unit/config_semantics_tests.nim`.

**I-14. Absence of evidence of usage is not evidence that a device is
unused.**
*Not yet enforceable:* the ownership subsystem does not exist. The rule is
recorded here so that it is implemented correctly when it is.

**I-15. Ambiguous identity prevents intrusive operations.**
*Not yet enforceable:* the identity subsystem does not exist.

**I-16. A device operation binds identity verification to the opened
handle.**
The path used to reach a device is never the identity of the device.
*Not yet enforceable:* the identity subsystem does not exist.

## Execution, assessment and lifecycle

**I-17. An unsuccessful execution is not a confirmed unhealthy disk.**
Execution state and assessment verdict are separate fields with separate
vocabularies. *Enforced by:* the report contract; the two vocabularies
cannot be mixed because the report schema enumerates them independently.

**I-18. An operation that executed successfully may still report FAIL.**
The operation worked; it found a problem. *Enforced by:* the report
contract, which allows `execution.state = SUCCEEDED` together with
`assessment.verdict = FAIL`.

**I-19. An operation that could not obtain the evidence it needed never
reports PASS.**
Such an operation reports `INCONCLUSIVE`, or omits the assessment
entirely. *Enforced by:* the assessment rules; the report contract
requires that an assessment, when present, carries a verdict.

**I-20. Device lifecycle state is never reported as an execution state
or an assessment verdict.**
`IN_SERVICE` is not an execution state. `FAIL` is not a lifecycle state.
*Enforced by:* the report contract enumerates each vocabulary separately;
witnessed by `tests/contract/schema_contract_tests.nim`.

**I-21. Missing information is never represented as a zero value.**
*Partially enforceable:* the strict reader has no way to invent a zero,
and the contract schemas use `required` lists rather than defaults. The
general rule applies to the observation model, which does not yet exist.

## Evidence

**I-22. Original observations are preserved.**
A sanitised copy is a copy; the original is never modified in place.

**I-23. Observed, derived and unavailable values are distinguishable.**
*Not yet enforceable:* the observation model does not exist.

**I-24. Evidence carries its provenance.**
Collection time, source and tool identity are recorded with the
observation. *Enforced by:* the `evidence` block of the report contract.

**I-25. A finalised evidence record cannot be silently replaced.**
*Not yet enforceable:* the evidence store does not exist.

**I-26. An assessment can be recomputed from the evidence and the policy
that produced it.**
The report carries a `policy_revision`. *Partially enforceable:* the
field exists and is carried; the recomputation machinery does not exist
yet.

**I-27. A hash is an integrity check, not proof of provenance.**
The report contract describes the digest field as an integrity check over
the preserved bytes. Nothing in Ironkeeper claims that a digest
authenticates the origin of a document.

## Interfaces

**I-28. Unknown commands and unsupported arguments fail explicitly.**
No argument is silently ignored. *Enforced by:* the argument parser;
witnessed by `tests/unit/cli_args_tests.nim` and the integration tests.

**I-29. An ordinary input error never produces an exception trace.**
*Enforced by:* the CLI catches classified failures and renders them.

**I-30. stdout carries the result; stderr carries diagnostics.**
In machine-readable mode stdout carries exactly one JSON document.
*Enforced by:* the CLI's output discipline; witnessed by the integration
tests.

**I-31. Exit codes are stable.**
The eight documented exit codes do not change within schema version 1.
*Enforced by:* `src/ironkeeper/core/errors.nim` and the documented table
in [overview.md](overview.md#error-taxonomy-and-exit-codes).

**I-32. There is no implicit network access and no implicit device
access.**
The M0 application opens no device and opens no socket. *Enforced by:*
absence of the code; the integration tests assert that the commands
create no files and need no privileges.

**I-33. The daemon is not a placeholder.**
`ironkeeper daemon` returns an explicit unsupported-operation result.
It does not start, daemonise or pretend. *Enforced by:* the command
dispatcher.

## Repository

**I-34. Real identifiers do not enter the repository.**
Device serials, WWNs, production SMART captures, credentials and private
topology stay out. Synthetic fixtures or consistently anonymised copies
are used instead. *Enforced by:* review, and by the secret scanning CI
job.

**I-35. The version has exactly one authoritative source.**
`src/ironkeeper/core/version.nim`. The Nimble manifest mirrors it and a
contract test asserts that they agree. *Enforced by:*
`tests/contract/version_contract_tests.nim`.
