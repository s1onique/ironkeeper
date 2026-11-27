# Acceptance

## The gates

| Gate | Mandatory condition | Result | Evidence |
|---|---|---|---|
| **A01** | Entry authority verified | **MET** | `entry-identity.md`: the remote is `s1onique/ironkeeper`, the entry HEAD was `aeb10ae594e695dda163a4053bdb6944b2c89ca7` as expected, the tree was clean, there were no stashes or worktrees, and `origin/main` agreed with the local `main`. |
| **A02** | CI failure masking reproduced and corrected | **MET** | `red-reproductions.md`, "F1": all six counterexamples concluded `success` at the entry commit. `repairs.md`, "F1": the gates are repository-owned, run one mandatory command at a time, and derive the verdict from the accumulated failures. `green-witnesses.md`: all 17 injected faults are detected. |
| **A03** | Secret scan fail-open reproduced and corrected | **MET** | `red-reproductions.md`, "F2": the scanner detected a finding, exited 1, and the step exited 0. `repairs.md`, "F2": the gate is fail-closed for findings, a missing scanner, a scanner that cannot execute, and a missing or malformed report. |
| **A04** | CI negative witnesses established | **MET** | `ci-qualification.md`: run **45912607978** at `2bb64bdd` concluded `failure`; the mandatory step failed, the later steps were skipped, and the successful diagnostic collection and artifact upload did **not** change the conclusion. The secret-scan finding is confirmed independently by GitHub's own push protection. |
| **A05** | Strict numeric policy enforced without silent precision loss in exact fields | **MET** | `red-reproductions.md`, "F3": four distinct defects, including an unhandled `OverflowDefect`. `repairs.md`, "F3": the exact classification. `green-witnesses.md`: every equivalent spelling agrees, and the signed minimum is rejected as a value. |
| **A06** | Supported schema policy enforced | **MET** | `red-reproductions.md`, "F4a": `additionalPropeties` and a nested unknown keyword were both **accepted**. `repairs.md`, "F4a": the supported policy, the prohibited constructs and the reference policy. `green-witnesses.md`: the keyword cases are rejected and a property whose *name* looks like a keyword is still accepted. |
| **A07** | Report semantic validation established | **MET** | `red-reproductions.md`, "F4b": every impossible timestamp and a `FAILED` execution with a `PASS` assessment were reported valid. `repairs.md`, "F4b": the calendar-time and execution/assessment consistency rules, with structural validity, semantic validity and evidence authenticity kept distinct. |
| **A08** | Public machine-readable outputs covered by strict contracts | **MET** | `red-reproductions.md`, "F4c": `schema list --json` and `report validate --json` had no schema, and an unsupported version was misclassified. `repairs.md`, "F4c": two new schemas and the documented `unsupported_schema_version` classification. |
| **A09** | Bounded file ingestion established | **MET** | `red-reproductions.md`, "F5": the 40 MiB document was read into memory before the size check. `green-witnesses.md`: the peak resident set size is 8.5 MB against the unbounded read, the result is classified `input_unavailable`, and a FIFO and a directory are refused without hanging. |
| **A10** | Validator qualification reproducible | **MET** | `repairs.md`, "F6": the harness is repository-owned with every input pinned. `green-witnesses.md`: 1337/1337 mandatory, 6 optional failures all in `optional/ecmascript-regex.json`, 312 classified policy rejections, **0 unexplained**. The command is `tools/qualify_validator.sh`. |
| **A11** | Evidence identities reconciled | **MET** | `ci-qualification.md`, "Run identity ledger": every run ID identifies exactly one observed commit. The predecessor's duplicate "final head" sections are separated, its `FINAL_HEAD` is corrected to `aeb10ae`, and its run-count claim is corrected from six to eight. |
| **A12** | Dependency authority documented and reproducible | **MET** | `docs/architecture/overview.md`, "Dependency decisions": there is **one** mechanism, the exact-commit resolution with a verified tree digest, and **no** committed `nimble.lock` is claimed. The predecessor's claim that a lock file was committed is corrected. `tools/qualify_validator.sh` performs the same resolution and refuses a different revision. |
| **A13** | Patch hygiene clean | **MET** | `git diff --check` passes, and no tracked file contains trailing whitespace. The one violation found during this ACT — a blank line at the end of `ci.yml` — was corrected. |
| **A14** | Native amd64 build and execution pass | **MET** | `ci-qualification.md`: run **45912585631**, job `build and test (amd64)`, runner `GitHub Actions 1000018961`, conclusion **success**, native execution on `ubuntu-24.04`. |
| **A15** | Native arm64 result independently classified | **MET** | `ci-qualification.md`: run **45912585631**, job `build and test (arm64)`, runner `GitHub Actions 1000018960`, conclusion **success**, native execution on `ubuntu-24.04-arm`. No cross-architecture emulation was used, so the result is a genuine arm64 execution. The predecessor's claim that the authoritative arm64 build was a cross-compilation is corrected. |
| **A16** | No physical hardware operations | **MET** | The application opens no device, runs no storage tool and opens no socket. `ironkeeper daemon` returns an explicit unsupported-operation result. The amendment touched no hardware and implemented no SMART acquisition. |
| **A17** | Original MIT licence preserved | **MET** | `shasum -a 256 LICENSE` is `307c6257a17d9d9c7f0a0d5d321fc1606fa53ef1e9da305b0d3012218f63393c`, unchanged from the entry commit. |
| **A18** | Final implementation committed | **MET** | The implementation is committed on `act/ironkeeper-foundation-01-amendment-02`. The post-qualification diff is confined to non-executable evidence and documentation; see `post-qualification-diff.md`. |
| **A19** | All outstanding terminal observations classified | **MET** | `remaining-limitations.md`: every observation is classified as **resolved**, **recorded as a known limitation**, or **an environment-cleanup item for the operator**. The orphaned QEMU process is the only environment-cleanup item, and it cannot interfere with subsequent testing. |
| **A20** | Epic board and acceptance evidence updated | **MET** | `EPICS.md` carries the amendment's board entry, the corrected M0 status, the IRK-01 and IRK-02 ownership, and the orphaned-process finding. This file is the acceptance evidence. |

**Every mandatory gate is met.**

## The identities

| Identity | Value |
|---|---|
| `ENTRY_HEAD` | `aeb10ae594e695dda163a4053bdb6944b2c89ca7` |
| `SUBJECT_HEAD` | `b6f8142e6d17910de3ac92cb8523a9338057b33b` |
| `CI_HEAD` | `b6f8142e6d17910de3ac92cb8523a9338057b33b` |
| `CI_RUN_ID` | `45912585631` |
| `FINAL_HEAD` | the commit that carries this evidence bundle |

`CI_HEAD` equals `SUBJECT_HEAD`: the qualifying run executed exactly the
qualified commit.

## The verdict

`GO_FOUNDATION`.

The review disposition of the predecessor was `PARTIAL_FOUNDATION`,
because independent review identified defects in the mandatory CI gate
authority, in strict ingestion and in contract validation. Each defect
was reproduced against the production path, repaired, and witnessed by a
regression test whose non-vacuity was demonstrated. The CI gates are now
authoritative, and a **real** GitHub Actions run at the exact subject
concluded `success` while a **real** run with a deliberately failing
mandatory test concluded `failure`.

The qualifier `PARTIAL_SCHEMA_VALIDATOR` does **not** apply: the
mandatory corpus of the official JSON Schema Test Suite passes completely
(1337/1337) under a **repository-owned** harness with every input
pinned, and the optional-corpus gaps are recorded rather than hidden.

## Outstanding findings

| Finding | Severity | Status |
|---|---|---|
| The upstream validator's optional-corpus gap: ECMA-262 regular expression semantics. | low | Recorded, not blocking. All six optional failures are in `optional/ecmascript-regex.json`, which the specification marks optional. |
| The upstream validator aborts the process on the Draft 4 boolean form of `exclusiveMaximum`. | high | Contained by the fail-closed adapter. The regression witness exercises the **real adapter**. |
| The supported schema policy is narrower than Draft 2020-12. | low | Deliberate and documented. A valid generic schema outside the subset is refused, and the qualification classifies the 312 such cases explicitly. |
| The strict reader rejects non-integral numbers. | low | Deliberate and documented. A contract that needs a fractional value must carry it as a decimal string. |
| `libpcre3` is a runtime dependency of the binary on Linux. | medium | Documented in `docs/architecture/overview.md`; installed and asserted in CI; must be carried by the packaging milestone (IRK-10). |
| The Nimble manifest version carries only the numeric part of the application version. | low | Documented; the version contract test asserts the two agree. |
| The gitleaks action is unusable for this repository because it requires a commercial licence. | low | The MIT-licensed binary is used instead, pinned by digest. |
| An orphaned QEMU process from the abandoned local virtualisation approach cannot be signalled from the sandbox. | low | An **environment-cleanup item** for the operator, not a product defect. Idle at 0.0% CPU; its guest image no longer exists; it cannot interfere with the build, the tests or the CI runs. The exact blocker and the operator action are in `linux-native.md`. |

## Deferred decisions

Recorded in `docs/architecture/overview.md` under "Proposed future
decisions":

* **Persistence.** SQLite with native linking, the embedded SQLite
  amalgamation, or minimal durable file-based persistence.
* **Control plane.** `AF_UNIX`/`SOCK_STREAM`, JSON-RPC 2.0, newline
  framing, bounded messages, `SO_PEERCRED`, filesystem permissions and
  systemd socket activation with `Accept=no`.
* **Storage backends.** `smartctl -x -j`, SCSI protection and capacity
  discovery, Linux sysfs and udev, a native aligned read-only scanner,
  NVMe health observations, SAS transport and expander topology.

None of these has been approved.

## The next recommended act

`ACT-IRONKEEPER-READONLY-INVENTORY-01`

Linux device discovery, identity normalisation, SMART JSON acquisition
through a bounded backend, synthetic hardware fixtures and read-only
inventory reports.

It depends on IRK-02 (the contract foundation, which is in place) and
feeds IRK-03, IRK-04 and IRK-07.

The recorded first real-world scenario, `LAB-IRK-SAS-ADMISSION-01`,
remains registered and unperformed. **No hardware discovery was begun by
this amendment.**
