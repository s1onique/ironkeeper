# Contract validation

The four new public documents are version 1, use JSON Schema Draft
2020-12, reject unknown properties at every authoritative object
boundary, and are embedded byte-for-byte into the binary.

| Schema | Purpose |
|---|---|
| `schemas/v1/inventory.schema.json` | the passive inventory document |
| `schemas/v1/device.schema.json` | one discovered block device |
| `schemas/v1/observation.schema.json` | the normalised observations of one device |
| `schemas/v1/evidence.schema.json` | the manifest of an evidence bundle |

## The checks that cover them

* **Meta-validation.** Every repository schema is validated against the
  bundled Draft 2020-12 metaschema, by the contract suite and by the
  independent validator.
* **The supported schema policy.** Every keyword in a schema-bearing
  position must be one Ironkeeper supports, and no prohibited construct
  may appear.
* **The reference policy.** Every reference must be a local JSON
  Pointer, a local `$anchor`, or the bundled metaschema URI.
* **Embedding.** The embedded bytes are byte-for-byte identical to the
  repository files; `tools/gate_schema_drift.sh` verifies it.
* **Unknown properties.** A document with an unknown member at an
  authoritative boundary is rejected. The contract suite pins this for
  the inventory document.
* **The generated documents.** The contract suite validates the documents
  that the production renderer produces from the synthetic tree, against
  the new contracts.
* **The independent cross-check.** `tools/gate_independent_check.sh`
  generates the inventory and the observation document from the binary
  against the repository fixture tree and validates them with
  `check-jsonschema`, an implementation that is independent of the
  runtime validator.

## The observed result

```text
gate: ok   generate-inventory (out/inventory.json, exit 0)
gate: ok   crosscheck-inventory
gate: ok   generate-observation (out/observation.json, exit 0)
gate: ok   crosscheck-observation
...
gate: PASS independent-check
```

## The numeric convention

The storage contracts carry the byte counts and the large counters as
**canonical decimal strings**, because a value beyond 2^53 does not fit
the internal exact-number domain. The internal domain itself was **not**
widened.
