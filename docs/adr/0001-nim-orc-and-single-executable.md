# ADR-0001: Nim, ORC and a single application executable

* **Status:** Accepted
* **Date:** 2026-11-26
* **Milestone:** M0 — Foundations
* **Deciders:** Ironkeeper maintainers

## Context

Ironkeeper will run as a supervised daemon on a Linux storage host and
must also be operable from a command line on the same host. It has to
read storage evidence, keep it, and produce reproducible verdicts. It
will be deployed by operators who do not want a large runtime surface.

The two obvious shapes are a single native executable or a collection of
interpreted components with a service manager and a runtime dependency
tree. The project must also be buildable and testable on a workstation
without a storage host attached.

## Decision

* The implementation language is **Nim**.
* The application is **one executable** with multiple CLI subcommands.
* The memory manager is **ORC**, set explicitly (`--mm:orc`) rather than
  inherited from a default.
* There is no mandatory network service, no mandatory container runtime
  and no web frontend.
* The application is supervised by **systemd** when it runs as a daemon.

## Rationale

**Nim.** Nim compiles to a native binary with no runtime to install,
which keeps the deployment footprint small and the failure surface
auditable. Its static typing catches the class of error that matters most
in a storage tool: a field that is present in one observation and absent
in another being read as a zero. Its `ref object` exception model
supports the fail-closed error taxonomy directly. And its standard library
covers JSON, filesystem access and process handling without third-party
packages.

**ORC.** The default memory manager has changed between Nim releases.
Selecting ORC explicitly makes the memory behaviour a property of the
project rather than of the toolchain version, which matters for a
long-running daemon and for reproducible builds.

**A single executable.** One binary means one artefact to version, one
to package, one to audit and one to run under systemd supervision. It
also means the control socket and the CLI cannot drift apart: they are
the same process, sharing the same command vocabulary.

**Not statically linking everything.** A single executable does not mean
that every operating-system dependency must be vendored. Ironkeeper will
eventually call `smartctl`, and it may link SQLite. What matters is that
those dependencies are *declared, licensed, documented and pinned*, not
that they are hidden.

## Consequences

* Build artefacts are native binaries; CI builds on Linux amd64
  natively and compiles for arm64.
* The runtime dependency surface is small but non-zero. It must be
  documented and audited.
* Nimble is the dependency manager. A pinned dependency is pinned exactly
  (`jschema == 0.1.0`), not by range.
* The project accepts that a Nim release can change the default memory
  manager, and compensates by setting it explicitly.

## Alternatives considered

* **Rust.** A stronger memory-safety story and excellent ecosystem. The
  deciding factor was the smaller operational surface and the simpler
  path from a single binary to a supervised daemon with an embedded
  control socket. Rust remains a reasonable choice if Ironkeeper ever
  needs to link a substantial native storage library.
* **Go.** Excellent concurrency and a small deployment footprint, but a
  larger runtime footprint than a static binary and a heavier build.
* **Python.** Fast to write, but it needs a runtime, it is awkward to
  deploy as a single supervised artefact, and its dynamic typing is a
  poor fit for the evidence model, where a missing field must never be a
  zero.
* **C.** Maximum control, maximum cost. The development rate required by
  the number of subsystems is not justifiable here.
