# Threat model

This document describes what Ironkeeper defends against, what it does not,
and what it will not attempt to defend against.

It is written for the real deployment: a Linux storage host with
privileged access to raw devices, running a daemon that a human operator
trusts to make decisions about data-bearing hardware.

## Assets

| Asset | Why it matters |
|---|---|
| Data on attached storage | A mistaken write or a wrong destructive action destroys data that has no backup |
| Device identity | If identity is wrong, an operation lands on the wrong device |
| Evidence and reports | A verdict that cannot be reproduced or audited is worthless |
| The host itself | A storage daemon runs with elevated privileges and touches kernel interfaces |
| Operator trust | The operator acts on the verdicts. A false PASS is worse than no verdict |

## Trust boundaries

```
   operator / CI
        |
        |  command line, AF_UNIX control socket (future)
        v
  +-----------------------------------+
  |  CLI / control plane              |  unprivileged input surface
  +-----------------------------------+
        |
        |  typed in-process calls
        v
  +-----------------------------------+
  |  policy and assessment            |  deterministic, no I/O
  +-----------------------------------+
        |
        |  observation requests
        v
  +-----------------------------------+
  |  adapters (smartctl, sysfs, ...)  |  the only place that touches hardware
  +-----------------------------------+
        |
        v
  raw devices, filesystems, ZFS pools
```

The important property is that the assessment layer sits *above* the
adapter layer and performs no I/O. An assessment is a pure function of
preserved evidence, so it can be replayed, compared and audited without
touching a device.

## Threats addressed

### T-1. Malformed or hostile input

**Threat.** A configuration or report document with duplicate member
names, invalid UTF-8, trailing content, non-finite numbers, enormous
nesting depth or an unknown schema version. A schema document that
references an external URI. A schema that uses an unsupported keyword.

**Response.** Strict ingestion rejects all of these before any semantic
interpretation. The schema is meta-validated before use. External
references are refused. Documented resource limits bound size and depth.

**Residual risk.** The upstream validator is a third-party
implementation; a bug in it is a bug in Ironkeeper. The adapter
contains the known defect, and the mandatory-corpus conformance is
measured rather than assumed.

### T-2. Type confusion and coercion

**Threat.** A document that says `"true"` where a boolean is required, or
`"1"` where an integer is required, exploiting an implementation that
coerces.

**Response.** No coercion anywhere. The strict reader produces typed
values; the schemas require exact types; `const` is used for values that
must be exactly one thing.

### T-3. Safety policy weakened through configuration

**Threat.** An operator, a deployment template or a stray edit sets
`allow_destructive_operations: true`, or a future schema change makes
the flag optional and its default permissive.

**Response.** The schema accepts only `false` for the destructive flag
and only `true` for explicit enrollment. The semantic layer rejects any
attempt to change the mandatory values, with a distinct issue code. A
configuration that asks for destructive operations is refused, not
silently downgraded.

### T-4. Acting on the wrong device

**Threat.** `/dev/sdX` is reassigned between discovery and operation, or
two paths refer to the same multipath device, or a path is a symlink to
something else.

**Response.** The rule is recorded as invariants I-15 and I-16:
`/dev/sdX` is never an authoritative physical identifier; multipath
aliases are reconciled first; ambiguous identity prevents intrusive
operations; identity verification binds to the opened handle.

**Status.** Not yet implemented. The invariant is recorded so that it is
built correctly rather than retrofitted.

### T-5. Acting on a device that is in use

**Threat.** A device that carries a mounted filesystem, a swap area, an
LVM physical volume, an MD RAID member, a ZFS vdev or a multipath map is
subjected to a self-test or a write.

**Response.** The ownership subsystem must account for all of those, and
must treat *unavailable or incomplete* ownership evidence as "not proven
unused". The report contract distinguishes a failed execution from a
confirmed failure, so a tool that could not determine ownership cannot
produce a FAIL verdict that looks like a device fault.

**Status.** Not yet implemented.

### T-6. Reporting a verdict that was never earned

**Threat.** A missing observation is treated as a zero, so a device that
was never read looks healthy; or an operation that could not complete is
reported as a clean run.

**Response.** `INCONCLUSIVE` exists precisely for this. A missing
observation is never a zero value. The assessment layer performs no I/O,
so it cannot accidentally "read" something. An assessment carries the
policy revision that produced it, so it can be recomputed.

### T-7. Evidence tampering or silent replacement

**Threat.** A finalised evidence record is overwritten, or an original
capture is sanitised in place, so the audit trail no longer reflects what
was observed.

**Response.** Originals are never modified; sanitisation produces a copy.
Finalised evidence must not be silently replaced. A digest over the
preserved bytes provides an integrity check. The report contract records
provenance with every evidence record.

**Status.** The provenance fields are implemented; the immutability
guarantee belongs to the evidence store, which does not yet exist.

### T-8. Information disclosure through the public repository

**Threat.** A real homelab inventory, a production SMART capture,
device serials, WWNs, credentials or private topology is committed to a
public repository.

**Response.** Synthetic fixtures only, or consistently anonymised copies.
CI runs secret scanning. Originals are never sanitised in place.

### T-9. Privilege escalation through the control interface

**Threat.** A local process connects to the control socket and asks for a
privileged operation.

**Response.** The proposed control plane binds to a filesystem path with
restricted permissions, uses `SO_PEERCRED` to identify the peer, and
systemd socket activation with `Accept=no` keeps the listening socket
owned by systemd. Every request is authorised against an explicit policy.

**Status.** Not yet implemented. The control socket does not exist; the
design is recorded so that it is not built casually.

### T-10. Resource exhaustion

**Threat.** A document with a million nested levels, or a hundred
megabytes of JSON, exhausts memory or stack.

**Response.** Documented size and depth limits, enforced during parsing
rather than after it. The parser's recursion is bounded by the depth
limit.

### T-11. Denial of service through the validator

**Threat.** A schema with a self-referential `$ref` causes infinite
recursion.

**Response.** The upstream validator detects infinite reference chains
and raises rather than overflowing the stack. The adapter catches it and
reports an internal failure.

## Explicitly out of scope

Ironkeeper does **not** attempt to defend against:

* **A hostile root.** The daemon runs privileged. A root attacker on the
  host is not in the threat model.
* **Kernel or firmware compromise.** Out of scope.
* **Firmware lying about a device.** No software can detect a device
  that misreports its own SMART data. The evidence records what the
  device said; it does not certify that the device is truthful.
* **Physical attacks on the storage medium.** Out of scope.
* **Denial of service by the operator.** A privileged operator can stop
  the daemon.

## Security properties that must hold

1. The application never opens a block device in milestone M0.
2. The application never opens a network socket.
3. The application never runs a privileged command.
4. Destructive operations are refused, and the refusal cannot be
   configured away.
5. Every failure is classified and reported without a stack trace.
6. Every document that enters the application is strictly parsed and
   validated.
7. Every report that leaves the application is reproducible from its
   evidence and its policy revision.
