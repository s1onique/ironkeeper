# Remaining limitations

These are the things M1 deliberately does **not** do. They are
limitations, not defects, and each one names the milestone that owns it.

## The identity limitations

1. **No handle-bound identity authority.** The tools are executed by
   pathname. The identity and the access paths are captured immediately
   before and after every invocation, and a detected change refuses the
   attribution of the observations, but the time-of-check /
   time-of-use race is **not** eliminated. Handle-bound authority for
   intrusive operations is a mandatory future gate (IRK-05/IRK-07).

2. **No durable identity registry.** The identifiers are observed on every
   pass and are stored only in the evidence bundle that the operator
   explicitly asked for. M1 introduces no persistent enrollment state
   and no durable identity registry.

3. **Full multipath management is not implemented.** The observed paths
   are retained and an ambiguous arrangement refuses the active
   interrogation, but the multipath device is not probed once per alias
   and a multipath map is not built.

4. **A serial-only identity is not authoritative.** A device whose only
   identifier is a serial number carries the confidence `probable`, and
   the CLI can select it by an exact serial. It never becomes a globally
   authoritative identity.

5. **The NVMe health log is controller-wide.** Its counters are
   attributed to the controller and are never presented as
   namespace-specific measurements.

## The observation limitations

6. **A read-only SMART acquisition may wake the device.** Ironkeeper
   implements no guaranteed no-wake mode: the `smartctl` low-power
   checks are unsupported for many devices and behave differently across
   protocols and controller paths. The `--allow-wake` flag makes the
   operator state the intent explicitly.

7. **The self-test operations are not implemented.** Starting, aborting
   or inspecting a running self-test is intrusive and belongs to the
   milestone that owns the device-ownership model.

8. **The surface read is not implemented.** IRK-07 owns it.

9. **The assessment engine is not implemented.** IRK-08 owns it, and
   M1 assigns **no** admission or health verdict.

10. **The ATA attribute table is not normalised into an ontology.** An
    ATA attribute name and id are vendor-specific, and no semantic
    meaning is inferred from them.

11. **No SSD endurance percentage is invented.** The percentage used is
    reported only where the device provides it with authoritative
    semantics.

12. **The NVMe byte counts are not derived.** The data units are
    reported in their original unit, because the rounding semantics of a
    conversion would be an invention.

13. **The expander graph is not built.** The per-PHY observations are
    recorded, and the upstream path is not inferred from a drive-to-
    expander negotiation.

## The process limitations

14. **The live acceptance is the inventory only.** The lab is not the
    full qualification, which also needs the surface-read scanner and
    the assessment engine.

15. **The self-test log entries are counted, not itemised.** The
    individual self-test records are preserved in the raw response; the
    normalised model reports the number of entries and the background
    scan count.

16. **The live run of the lab host needed a locally built PCRE 1.** That
    is an environment property of the host, not a product defect; the CI
    runners install the dependency the way the workflow documents.
