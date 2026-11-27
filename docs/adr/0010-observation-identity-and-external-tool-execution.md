# ADR-0010 — Observation identity and the external-tool execution boundary

* **Status:** accepted
* **Date:** 2026-11-27
* **Decides:** how M1 observes a device and how it runs the tools that
  observe it

## Context

M1 introduces the first operations that touch a storage device. Two
questions have to be answered before any code is written: *which* device
is being observed, and *how* is the observation tool executed?

The identity question is subtle because several distinct concepts are
involved: the storage identity of a disk, the namespace or logical-unit
identity, the controller identity, the access path, and the transport
endpoint. A SAS port address is not a logical-unit identifier. A
controller serial is not an NVMe namespace identifier: two namespaces
behind one controller are two storage namespaces, and the NVMe health log
is controller-wide.

The execution question is equally subtle. `smartctl` is invoked by
pathname, so between the moment the operator names a device and the
moment the tool opens it, the device behind the path can change. A
pre/post identity comparison narrows that window; it does not close it.

## Decision

1. **The concepts stay apart.** The identity model keeps the storage
   identity, the namespace identity, the controller identity, the access
   path and the transport endpoint separate. They are never collapsed
   into one "device id".
2. **Confidence, not certainty.** A reconciled identity carries a
   confidence: `authoritative` (a persistent identifier that survives
   ordinary path changes), `probable` (a weaker observation, for example
   a serial number), `ambiguous` (contradictory or duplicated
   observations) and `unresolved` (nothing usable was observed). A
   serial-only identity never becomes globally authoritative.
3. **Ambiguity refuses.** An ambiguous identity refuses the active
   interrogation. A selector that matches more than one device is never
   resolved arbitrarily.
4. **No durable identity registry.** M1 observes the identifiers on every
   pass and stores them only in the evidence bundle that the operator
   explicitly asked for. Persistent enrollment state is a later
   milestone.
5. **One execution boundary.** Every external tool runs through
   `src/ironkeeper/storage/procexec.nim` and through nothing else: an
   absolute path, an argument vector, a controlled environment, separate
   and independently bounded output streams, a monotonic deadline, the
   termination of the whole process group, and the reaping of the child.
   The outcome is classified, so a timeout and a nonzero exit are
   different things.
6. **The tool set is closed.** The executable paths are fixed. The test
   harness injects a controlled executable through an explicit seam; no
   CLI option or configuration file can make an ordinary invocation run
   an arbitrary program.
7. **The residual race is documented, not hidden.** The pre/post identity
   comparison is implemented and it invalidates the attribution when it
   detects a change. It is explicitly **not** a handle-bound guarantee,
   and handle-bound authority for intrusive operations remains a
   mandatory future gate (IRK-05/IRK-07).

## Consequences

* The operator always knows which device was selected, and the document
  says so.
* A target whose identity is contradictory is never interrogated.
* A device that is replaced during a collection yields **unbound**
  evidence rather than a misattributed observation.
* The tool boundary is small enough to be reviewed as a whole, and every
  failure mode of an external process has a distinct classification.
* The TOCTOU window remains open for the passive and the read-only
  paths. It is a known, recorded limitation, not a solved problem.

## Alternatives considered

* **Merge devices by model or serial.** Rejected: two identical drives
  are two drives.
* **Trust `/dev/sdX`.** Rejected: the path is not a physical identity.
* **Run the tools through a shell.** Rejected: it introduces an
  interpolation surface and a second failure mode.
* **Open the device and interrogate it through the handle.** Deferred:
  it needs the ownership model of IRK-05 and it belongs to the
  intrusive-operation milestone.

## Related

* [ADR-0003](0003-persistent-physical-identity-aliases-and-multipath.md)
* [ADR-0006](0006-non-destructive-mvp-and-fail-closed-safety.md)
* [ADR-0008](0008-external-tooling-and-native-implementation-boundaries.md)
* [docs/architecture/storage-observation.md](../docs/architecture/storage-observation.md)
