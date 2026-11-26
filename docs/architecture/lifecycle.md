# Lifecycle vocabularies

Ironkeeper uses three independent vocabularies. They describe three
different things, and conflating them is the most common way a storage
tool ends up lying to its operator.

This document defines them and explains why they are separate.

## Execution state

Execution state describes **what happened to the operation**. It says
nothing about the health of any device.

```
QUEUED
PREFLIGHT
RUNNING
WAITING
VERIFYING
SUCCEEDED
FAILED
CANCELLED
INTERRUPTED
```

| State | Meaning |
|---|---|
| `QUEUED` | The job is accepted and waiting for a worker |
| `PREFLIGHT` | Preconditions are being checked: ownership, identity, permissions |
| `RUNNING` | The operation is in progress |
| `WAITING` | The operation is blocked on something external, for example a self-test that runs for hours |
| `VERIFYING` | The operation finished; results are being reconciled |
| `SUCCEEDED` | The operation completed as intended |
| `FAILED` | The operation did not complete as intended |
| `CANCELLED` | The operation was cancelled before completion |
| `INTERRUPTED` | The process or host went away mid-operation |

`SUCCEEDED` means *the operation worked*. It does not mean the device is
healthy, and it does not mean the device is unhealthy.

## Assessment verdict

An assessment verdict describes **what was concluded about the subject**.

```
PASS
WARN
FAIL
INCONCLUSIVE
```

| Verdict | Meaning |
|---|---|
| `PASS` | Every mandatory check was performed and every one of them met its threshold |
| `WARN` | Every mandatory check was performed; at least one non-mandatory threshold was not met |
| `FAIL` | Every mandatory check was performed and at least one of them did not meet its threshold |
| `INCONCLUSIVE` | At least one mandatory check could not be performed, so no conclusion is available |

`PASS` is the only verdict that requires *every* mandatory check to have
actually run. `INCONCLUSIVE` is not a soft `FAIL`: it means the question
was not answered.

The difference between `FAIL` and `INCONCLUSIVE` is the difference
between "the device is bad" and "we do not know". Collapsing them is how
a storage tool ends up condemning a healthy drive, or exonerating a
failing one.

## Device lifecycle state

Device lifecycle state describes **where a device sits in its lifecycle**.

```
DISCOVERED
ENROLLED
QUALIFYING
ADMITTED
IN_SERVICE
QUARANTINED
RETIRED
```

| State | Meaning |
|---|---|
| `DISCOVERED` | The device was seen. Nothing is known about it beyond that |
| `ENROLLED` | The operator has explicitly claimed the device for management |
| `QUALIFYING` | The device is being assessed against a qualification profile |
| `ADMITTED` | The device passed qualification and may be used |
| `IN_SERVICE` | The device carries data or is otherwise in production use |
| `QUARANTINED` | The device is held back from use pending investigation |
| `RETIRED` | The device has been withdrawn from service |

Lifecycle state is a property of the *device*. Execution state is a
property of an *operation*. A device can be `IN_SERVICE` while a
qualification operation on it ends `FAILED`; a device can be `ADMITTED`
while a health check on it ends `INCONCLUSIVE`.

## Why the separation matters

Consider three outcomes of the same operation:

**A device with a failing SMART attribute.**
The operation ran, read the attribute, and compared it to the threshold.
The operation `SUCCEEDED`. The assessment is `FAIL`. The device moves
from `IN_SERVICE` to `QUARANTINED`. All three statements are true at
once, and none of them implies another.

**A device whose SMART data could not be read.**
The operation ran, tried to read the attribute, and failed to do so. The
operation `FAILED`. The assessment is `INCONCLUSIVE`. The device stays
`IN_SERVICE` — not because it is healthy, but because nothing was
concluded. Reporting `PASS` here would be a lie; reporting `FAIL` would
be a different lie.

**A successful scan that finds a transport error.**
The read completed for every sector, and some of them returned an error.
The operation `SUCCEEDED` in the sense that it read what it was asked to
read. The assessment is `FAIL`. This is the case that most clearly
shows why "the command worked" and "the device is fine" are different
claims.

## The rules

1. An execution state never appears in an assessment field, and vice
   versa.
2. A device lifecycle state never appears in an execution field or an
   assessment field.
3. `PASS` requires that every mandatory check actually ran.
4. An operation that failed to obtain mandatory evidence never produces
   `PASS`.
5. An operation that executes successfully may still produce `FAIL`.
6. A missing observation is never a zero value and never a `PASS`.
7. The assessment records the policy revision that produced it, so that
   it can be recomputed from the preserved evidence.

These rules are enforced by the report contract, which enumerates each
vocabulary separately and independently. The contract test
`tests/contract/schema_contract_tests.nim` checks that a device
lifecycle state is rejected where an execution state is expected.

## Where these appear in the M0 contracts

The report contract carries the execution state and, optionally, the
assessment verdict:

```json
{
  "execution": {
    "state": "SUCCEEDED",
    "started_at": "2026-01-01T00:00:00Z",
    "finished_at": "2026-01-01T00:00:01Z"
  },
  "assessment": {
    "verdict": "FAIL",
    "summary": "..."
  }
}
```

The device lifecycle vocabulary is **not** part of the M0 report
contract. There is no device subsystem yet, so there is nothing to
report a lifecycle state for. Adding it before the device model exists
would create a contract that describes a subsystem which does not
exist.

## Future storage report requirements

The following requirements are recorded for the storage-report milestone.
They are **not** implemented.

* A device observation must state its physical identity, not just the
  path it was reached through.
* Each observation records whether it was *observed*, *derived* or
  *unavailable*. An unavailable observation is never a zero.
* Capacity and lifetime counters that can exceed 2^53 are carried as
  decimal strings, with an explicit format marker, and compared with
  decimal-string arithmetic. See
  [overview.md](overview.md#numeric-representation).
* A verdict that depends on a tool's exit status records the full
  bitmask, not a collapsed boolean. The `smartctl` bitmask is a mandatory
  backend contract.
* A verdict records the qualification profile and policy revision that
  produced it.
* Evidence records reference each other, so that a verdict can be traced
  to the exact observations it rests on.
