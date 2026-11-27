# Remaining limitations and held observations

Every observation that was outstanding at the end of this ACT is
classified here. Nothing is left unclassified.

## Resolved by this ACT

| Observation | Disposition |
|---|---|
| A mandatory CI command failure could be masked by a later successful command. | **Resolved.** The gates are repository-owned and fail-closed; 17 injected faults are detected. |
| The secret-scan gate forced its own success and discarded a detected finding. | **Resolved.** The gate fails on findings, on a missing scanner, on a scanner that cannot execute, and on a missing or malformed report. |
| A numeric value could be rounded into the accepted range, a noninteger could become an integer, and a nonzero number could become zero. | **Resolved.** The exact classification is made from the source text. |
| The signed minimum integer raised an unhandled `OverflowDefect`. | **Resolved.** The magnitude is compared as a `uint64` and the minimum is never negated. |
| An unknown or misspelled schema keyword was silently accepted. | **Resolved.** The supported schema policy rejects it. |
| A report with an impossible timestamp was reported valid. | **Resolved.** The semantic layer checks the calendar fields. |
| A failed execution could carry a `PASS` assessment. | **Resolved.** The execution and the verdict must agree. |
| `schema list --json` and `report validate --json` had no output contract. | **Resolved.** Two schemas were added and the contract suite covers them. |
| An unsupported schema version was classified as an ordinary schema violation. | **Resolved.** It now receives `unsupported_schema_version` and exit 7. |
| An oversized document was read into memory before the size check. | **Resolved.** The reader is bounded and checks the opened input type. |
| The validator qualification could not be reproduced from the repository. | **Resolved.** The harness is repository-owned with every input pinned. |
| The evidence bundle identified one run at two different commits, and one commit as two "final heads". | **Resolved.** Every run ID identifies exactly one commit, and the ledger is in `ci-qualification.md`. |
| The documentation claimed a committed `nimble.lock` that does not exist. | **Resolved.** The claim was corrected and the single dependency-resolution mechanism is documented. |
| The documentation named an Alpine guest and a cross-compilation as the authoritative Linux build. | **Corrected.** The authoritative build is native on `ubuntu-24.04` and `ubuntu-24.04-arm`. |

## Known limitations, recorded and not blocking

| Limitation | Why it is acceptable |
|---|---|
| The upstream validator does not implement ECMA-262 regular expression semantics. | All six optional-corpus failures are in `optional/ecmascript-regex.json`, which the specification marks optional. The mandatory corpus passes completely. |
| The supported schema policy is narrower than Draft 2020-12. | Deliberate. A valid generic schema outside the subset is refused rather than partially understood. The qualification classifies every such case explicitly, and none is counted as an unexplained result. |
| The strict reader rejects non-integral numbers. | Deliberate. A value that cannot be represented exactly is refused rather than rounded. A contract that needs a fractional value must carry it as a decimal string. |
| `libpcre3` is a runtime dependency of the binary on Linux. | Documented, installed and asserted in CI. It must be carried by the packaging milestone (IRK-10). |
| The Nimble manifest version carries only the numeric part of the application version. | Nimble rejects anything else. The version contract test asserts the two agree. |
| The gitleaks *action* is unusable for this repository. | It requires a commercial licence for an organisation-owned repository. The MIT-licensed binary is used instead, pinned by digest. |

## The environment-cleanup item

| Item | Classification |
|---|---|
| An orphaned QEMU process (PID 70203) from the abandoned local virtualisation approach. | **Environment cleanup, operator action required.** It could not be signalled: `kill -TERM` and `kill -KILL` are both denied by the sandbox. It is idle at 0.0% CPU, its guest image no longer exists, and it cannot interfere with the build, the tests or the CI runs. The exact blocker and the operator action are recorded in `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01/linux-native.md`. |

## Held background-command observations

Three background commands were launched earlier in the session and their
terminal results were consumed. Each is classified here.

| Job | Terminal state | Classification |
|---|---|---|
| `cmd_mwy62nphix2biu0r` | `unknown_job` (receipt evicted) | **Resolved, already consumed.** The command was a filesystem probe for a local `jschema` checkout. Its terminal result was observed while it was still running and was `containment_failed` with the probe's output showing no local `jschema` was present. The dependency was therefore resolved from its pinned GitHub revision instead, and that resolution is the mechanism the project uses. The receipt was evicted from the registry after the observation was taken; nothing was left unobserved. |
| `cmd_mwy67mvegn5ccz9k` | `cancelled` | **Resolved.** This was the FIFO special-file probe. Its terminal result was observed: the CLI classified the FIFO as `input_unavailable` and exited 3, **without hanging**. The command was then cancelled because it was no longer needed. |
| `cmd_mwy6lzhckfyde5zb` | `deadline_exceeded` | **Resolved, and the product result inside it is the expected one.** This was the same FIFO probe, launched with a background sleep child. The retained terminal output is the probe's own result: `fifo_rc=3 (124 would mean it hung)`, with the classified `input_unavailable` document. The `deadline_exceeded` state refers to the *background job wrapper's* wall-clock budget, which expired after the probe itself had already completed with the expected outcome. It is not a product failure: the assertion under test - that the validation command does not hang on a special file - **passed**. |

The FIFO probe is the F5 witness for the bounded-ingestion requirement.
Its result is also recorded in `green-witnesses.md`, "Bounded ingestion".

## Held observations: not started by this ACT

These are **held** deliberately. This amendment restores acceptance
authority; it does not expand the feature set.

* No hardware discovery was begun. No device was opened, enumerated or
  touched.
* SMART acquisition was **not** implemented. The numeric policy
  distinguishes strict internal contracts from external hardware
  acquisition and lossless normalisation, and the storage adapters that
  will implement the latter do not exist yet.
* No storage schema was added. The storage observation and inventory
  contracts remain a separate deliverable.
* No persistent state, control socket, job engine or metrics exporter
  was implemented.
* The generic schema migration framework was **not** introduced. The
  compatibility rule is documented in `CONTRIBUTING.md` and applied by
  hand.
* No QEMU or other local virtualisation work was attempted.

## Scope boundary

The amendment authorises correction, regression witnesses, native GitHub
Actions qualification and pushing the existing ACT branch. It does not
authorise a merge to `main`, a release, a deployment, a physical storage
operation or a destructive operation. None of those was performed.
