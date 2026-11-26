# Security policy

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Report it privately to the maintainers by opening a GitHub security
advisory on the repository, or by contacting the maintainers directly.
Please include:

* what the problem is,
* how to reproduce it,
* what an attacker gains,
* the version or commit you tested.

You will get an acknowledgement. Fixes for confirmed issues are released
as a new version, and the advisory is published once a fix is available.

Please do not test against hardware you do not own, do not access data
that is not yours, and do not use social engineering, physical access or
denial of service to demonstrate a problem.

## Security model in one paragraph

Ironkeeper will run privileged on a storage host and will eventually make
decisions about data-bearing devices. Its most important security
property is therefore **not** to act on the wrong device or to act on a
device that is in use. The full threat model is in
[docs/architecture/threat-model.md](docs/architecture/threat-model.md);
the invariants it depends on are in
[docs/architecture/invariants.md](docs/architecture/invariants.md).

## Current state

Milestone M0 is a foundation. It is worth being precise about what the
shipped binary does and does not do:

**It does:**

* parse JSON strictly, rejecting duplicate member names, invalid UTF-8,
  trailing content, non-finite numbers and out-of-range integers;
* validate documents against versioned JSON Schema Draft 2020-12
  contracts, using a bundled, offline resolver;
* enforce a safety policy whose mandatory values cannot be configured
  away;
* produce versioned, machine-readable reports.

**It does not:**

* open a block device;
* execute a SMART test or any other device command;
* open a network socket;
* run a privileged operation;
* implement a daemon, a job engine or a scheduler.

The `ironkeeper daemon` command exists only to return an explicit
unsupported-operation result.

## Supported versions

Only the latest released version is supported. Security fixes are not
backported to older releases.

## Reporting a non-security bug

Ordinary bugs belong in the issue tracker. Please include the command you
ran, its exact output, the exit status, and the version — `ironkeeper
version --json`.
