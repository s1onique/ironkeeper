# ADR-0011 — Compile-time test seams and the authoritative acquisition result

* **Status:** accepted
* **Date:** 2026-11-27
* **Decides:** how the test seams are isolated from the shipped binary,
  and how the completeness of a collection is decided

## Context

M1 shipped an executable that honoured `IRONKEEPER_TEST_TOOL_DIR` and
three discovery-root overrides through **environment variables**. The
shipped binary therefore had two properties that it must not have: an
environment variable could make it execute an arbitrary program, and an
environment variable could point its discovery at a synthetic tree.

M1 also derived the completeness of an evidence bundle from the
**presence of an execution record**. A record says only that a process
ran. A tool that was launched and then timed out, produced truncated
output, produced malformed JSON or omitted a mandatory field leaves an
execution record behind - and a bundle whose completeness is derived
from that record claims complete evidence that does not exist.

## Decision

1. **The test seams are a compile-time property.** The seams exist only
   in a binary that was compiled with the `ironkeeperTesting`
   definition. A production binary does not read the variables at all,
   so the decision cannot be changed at run time. The two variants are
   separate artefacts, each reports its own variant, and the CI records
   the variant of every artefact it publishes. All hardware
   qualification uses the production variant.
2. **The acquisition result is authoritative.** The coverage of a
   requested operation is a first-class value that is derived from the
   requested observation coverage - never from the presence of an
   execution record. The execution outcome, the requested coverage, the
   device-reported health, the attribution and the collection
   completeness stay five separate things.
3. **One completeness value everywhere.** The observation document, the
   evidence manifest, the human-readable output and the exit-status
   policy carry the *same* authoritative value.
4. **A failing device may accompany a complete acquisition.** The
   device-reported health of a device is an observation, not a coverage
   failure. An optional field that is unavailable does not make the
   acquisition incomplete either.
5. **Absence of evidence is never evidence of absence.** A missing
   mandatory observation, a truncated output, a timeout, a launch
   failure, a malformed response, a contradiction or a refused
   attribution all make the acquisition incomplete, and the reason names
   the cause.

## Consequences

* The repository builds two binaries. The compiled-CLI tests use the
  test-enabled one; the seam-isolation witness proves that the
  production one ignores the very same environment variables.
* A collection that did not obtain every requested observation exits
  with the documented input-unavailable status, and the document that was
  produced is still the machine-readable result.
* The evidence manifest and the observation document are validated
  against the repository contracts before they are published.

## Alternatives that were rejected

* **Ignoring the environment variables in the production build while
  keeping them in one binary.** The build could not then be identified
  as a test build from the outside, and a test-enabled binary could be
  shipped by accident.
* **Deriving the completeness from the exit status of the tool.** A
  nonzero exit status is frequently a *device-reported* condition
  (the failing-status bit), not a collection failure.
* **Keeping the completeness a string in the manifest.** A string has no
  authority: two producers can spell it differently. The value is
  computed once and carried everywhere.
