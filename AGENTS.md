# AGENTS.md

These are the engineering rules for Ironkeeper. They apply to every change,
whether it is written by a person or by an agent. They are deliberately
short: a rule that cannot be followed is a rule that will be ignored.

The rules below are *binding*. Where a rule conflicts with convenience,
the rule wins and the conflict is raised as an issue.

## Module shape

* **Prefer small, cohesive modules.** A module should have one reason to
  change.
* **Target roughly 250 lines per production source file.** A file that
  exceeds 400 lines requires justification in the pull request, and the
  justification must name the cohesion that made the split impossible.
* **Avoid god objects, catch-all utility modules and circular imports.**
  A module that everything imports is a module nobody owns.
* **Prefer typed contracts over unstructured string dictionaries.** A
  `JsonNode` crossing a module boundary must be converted to a Nim type
  at that boundary.

## Boundaries

* **Keep hardware adapters separate from policy decisions.** An adapter
  observes; it does not judge. A policy module judges; it does not observe.
* **Keep I/O separate from deterministic assessment logic.** Assessment
  must be a pure function of preserved evidence and policy, so that it can
  be recomputed and compared.
* **Every external side effect must have an explicit owner.** A module that
  opens a device, writes a file or runs a command is named in the module
  that owns that effect. No module opens a device "just to look".

## Correctness

* **Never conflate missing information with a zero value.** Absence of
  evidence is not evidence of absence. Use an explicit optional or a
  distinct state; never a sentinel.
* **Never report PASS without sufficient evidence.** An operation that
  could not obtain the evidence it needed reports `INCONCLUSIVE`.
* **An unsuccessful execution is not a confirmed unhealthy disk.** Keep
  execution state, assessment verdict and device lifecycle state separate.
* **Fail closed.** When a check cannot be performed, the operation fails.
  It does not assume the permissive answer.
* **Do not accept input you have not validated.** All JSON enters through
  the strict reader. All schemas are meta-validated before use.

## Tests

* **Tests must exercise production paths**, not independently
  reimplemented approximations. A test that reimplements the logic it is
  testing proves only that the reimplementation agrees with itself.
* **Every regression fix must have a meaningful regression witness**: a
  test that fails without the fix and passes with it. A test that passes
  either way is not a witness.
* **Avoid duplicating tests that establish the same invariant.** Two
  tests that prove the same thing cost maintenance and prove nothing more.
* **Do not use test count as a proxy for quality.** Ten table-driven cases
  that pin down a real invariant are worth more than a hundred tests that
  each restate the previous one.
* **Demonstrate non-vacuity for critical safety and contract tests.** For
  a change to a validation or safety check, temporarily disable or reverse
  the check, show that the relevant test fails, then restore the
  implementation and rerun the suite. Do not commit a deliberately broken
  implementation.

## Dependencies

* **Document and minimise dependencies.** Every dependency is listed in
  `docs/architecture/overview.md` with its licence, its maintenance
  activity and why it is needed.
* **Prefer a proven, maintainable, permissively licensed dependency** over
  a reimplementation — but only after the candidate has been *qualified*,
  not merely chosen.
* **Never add a dependency for something the standard library already
  does adequately.**

## Contracts

* **Keep public contracts backward-compatible within their declared
  version.** A change that breaks a consumer requires a new version
  directory and a migration note.
* **Every public document has an explicit schema version.**
* **Structural validation and semantic validation are distinct.** Do not
  try to express a policy rule in a schema when it belongs in the
  semantic layer.

## Process

* **Every ACT must update the epic board** and leave reviewable evidence
  under `.factory/evidence/`.
* **Never invent completed work, command results, CI results or hardware
  observations.** If a command was not run, do not report its output. If a
  background command was launched but its result was not consumed, it is
  not evidence.
* **Do not weaken a mandatory acceptance gate to obtain a passing
  verdict.** Report the gate as unmet and explain why.
* **Record decisions as ADRs.** A decision that constrains future work
  gets a record in `docs/adr/` and a link from the architecture
  documentation.

## Execution environments

* **Use existing execution infrastructure before provisioning new
  infrastructure.** A standard CI runner or an already-authorised Linux
  host is preferred over anything built for the occasion.
* **Prefer native CI runners over workstation emulation.** Cross-
  architecture emulation is not evidence of native execution. If arm64
  matters, run on an arm64 runner.
* **Do not build disposable infrastructure merely to satisfy a test gate
  when suitable infrastructure already exists.** A local virtual machine
  built to run a Linux test suite is an unjustified diversion from the
  product.
* **Separate environment failures from product failures.** When an
  execution environment fails, record it as an environment failure, not as
  a defect in the implementation, and do not weaken the requirement it was
  meant to satisfy.
* **Bound infrastructure troubleshooting.** At most ten minutes of active
  troubleshooting and at most two substantially different remediation
  attempts for the same environment failure, before the approach is
  reassessed. These limits apply to provisioning, not to product work.
* **Avoid redundant polling and uncontrolled background execution.** One
  authoritative observation per outstanding execution is sufficient.
  Repeated sleep-and-poll loops are not evidence collection.
* **Require terminal evidence for asynchronous execution.** A workflow
  that was submitted is not a workflow that succeeded. Wait for and record
  the terminal conclusion.
* **Record the exact source identity for every qualification result.**
  A verdict belongs to a commit. A run at a different commit is not
  evidence for the current subject, and a result obtained after the
  subject changed must be re-qualified.
* **Preserve completed implementation when the verification strategy
  changes.** A new way of verifying the work does not invalidate the work
  already done.

## Repository hygiene

* **Never commit real homelab identifiers, production SMART captures,
  credentials, device serials, WWNs, private IP addresses or sensitive
  topology** without explicit approval. Use synthetic fixtures or
  consistently anonymised copies.
* **Never modify or sanitise original evidence in place.** Anonymisation
  produces a copy; the original stays untouched.
* **Hashes are integrity checks, not proof of provenance.** Do not
  describe a digest as if it authenticated the origin of a document.
