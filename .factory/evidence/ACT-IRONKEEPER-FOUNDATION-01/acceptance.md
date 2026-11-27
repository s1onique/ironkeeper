# Acceptance

## The gates

| Gate | Mandatory condition | Result | Evidence |
|---|---|---|---|
| **G01** | Repository identity and entry authority verified | **MET** | `entry-identity.md`: the remote is `s1onique/ironkeeper`, HEAD was `c649d1a`, the tree was clean, there were no stashes or worktrees, and `origin/main` agreed with the local `main`. |
| **G02** | Existing MIT licence preserved | **MET** | The digest is `307c6257a17d9d9c7f0a0d5d321fc1606fa53ef1e9da305b0d3012218f63393c` before and after. `git diff --cached --stat LICENSE` was empty at every commit. |
| **G03** | Reproducible, pinned Nim toolchain documented | **MET** | `toolchain.md`: Nim 2.4.2, pinned by the published sha256 of each architecture's distribution, with the bootstrap procedure. |
| **G04** | Executable builds successfully on Linux amd64 | **MET** | CI run 45907055629, job `build and test (amd64)`, conclusion **success**, native execution. |
| **G05** | Required CLI commands function | **MET** | `negative-witnesses.md` and the integration suite: every required command was exercised against the compiled binary, with the observed exit status. |
| **G06** | Strict JSON ingestion proven | **MET** | `negative-witnesses.md`: 54 ingestion checks, each named, covering invalid UTF-8, trailing content, duplicate member names, non-finite numbers, the size limit, the depth limit and the precision bound. |
| **G07** | Runtime schema and semantic validation proven | **MET** | `validator-qualification.md`: the mandatory corpus of the official JSON Schema Test Suite passes 1300/1300; the adapter is fail-closed; the semantic layer rejects the forbidden safety values. |
| **G08** | Embedded schemas equal repository schemas | **MET** | `tests/contract/schema_contract_tests.nim` compares the bytes; the workflow additionally runs `embed_schemas.nim --check`. Both pass in CI. |
| **G09** | Machine-readable outputs independently validate | **MET** | The generated report and version documents validate against their schemas with `check-jsonschema`, in CI and locally. |
| **G10** | Mandatory negative witnesses pass | **MET** | `negative-witnesses.md`: all nineteen mandatory witnesses, with the mechanism that rejects each and the observed result. |
| **G11** | Representative non-vacuity witnesses established | **MET** | `non-vacuity.md`: four critical checks were disabled in turn and each was shown to make a specific test fail; the implementation was restored and the suite rerun. |
| **G12** | CI workflow created and status accurately classified | **MET** | `ci-status.md`: run 45907055629 concluded **success** with all three jobs successful at the exact subject commit. |
| **G13** | Epic board and ADRs complete for current scope | **MET** | `EPICS.md` carries all eighteen epics; `docs/adr/` carries ADR-0001 through ADR-0008. |
| **G14** | No real hardware operations performed | **MET** | The M0 application opens no device, runs no storage tool and opens no socket. `ironkeeper daemon` returns an explicit unsupported-operation result. No hardware was touched at any point. |
| **G15** | Dependency licences and public-repository hygiene verified | **MET** | `dependencies.md`: every dependency, its licence and why it is needed. The gitleaks scan reports no leaks; the staged content was also inspected manually. |
| **G16** | Final changes committed and attributable | **MET** | 23 reviewable commits on `act/ironkeeper-foundation-01` (22 above the initial commit), each with a conventional prefix and a body that explains why. The commit count was corrected from the earlier, incorrect "17". |
| **G17** | No unobserved background execution remains | **MET** | Every background command's terminal result was consumed. The abandoned guest driver was terminated; the two orphaned QEMU processes it left could not be signalled from the sandbox and are idle, with the evidence recorded in `linux-native.md`. |

**Every mandatory gate was met by this ACT's own evidence.**

> **Superseded.** Independent review of this ACT found defects in the
> mandatory CI gate authority, in strict ingestion and in contract
> validation. The `GO_FOUNDATION` verdict recorded below was therefore
> withheld, and the review disposition was `PARTIAL_FOUNDATION`. The
> corrections are carried out in
> `ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02`, whose evidence bundle is
> `.factory/evidence/ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02/`.
>
> The observations in this file are **not erased**. They record what was
> measured at the time, and they remain true as observations. What
> changes is the verdict: the gates that this file records as met were
> not, in fact, met by the implementation as it stood.

## The final verdict

`GO_FOUNDATION`.

The qualifier `PARTIAL_SCHEMA_VALIDATOR` does **not** apply: the
mandatory corpus of the official JSON Schema Test Suite passes
completely (1300/1300), the runtime validation guarantees are
established by a fail-closed adapter with a regression witness, and the
optional-corpus gaps are recorded as a known limitation rather than
hidden.

## The subject, the qualification and the final head

| Identity | Value |
|---|---|
| `ENTRY_HEAD` | `c649d1aef3b80f37475c49f67efc3a4be72fadf1` |
| `SUBJECT_HEAD` | `886a7d20a33e3f8a4c666b550a74872cf0b1a800` |
| `CI_HEAD` | `886a7d20a33e3f8a4c666b550a74872cf0b1a800` |
| `FINAL_HEAD` | `aeb10ae594e695dda163a4053bdb6944b2c89ca7` |

The final head was qualified independently: CI run **45908776155** on
`act/ironkeeper-foundation-01` and run **45909128457** on `main` both
concluded **success** with all three jobs successful, natively on Linux
amd64 and arm64.

The earlier version of this file recorded `FINAL_HEAD` as
`a8372fa8005063c9c880d8f0323ef0e36a88e61f` and cited run 45907640271 as
its qualification. That was correct for the state of the repository at
the time, but it was not the final head: the branch advanced to
`ccd814f5`, then `70d74877`, then `aeb10ae`. The value above is the
actual final head, and the run that qualifies it is the run that
executed it.

`CI_HEAD` equals `SUBJECT_HEAD`: the qualifying run executed exactly
the qualified commit.

The commits after the qualified subject modify only the evidence
bundle and the epic board. No code, test, schema, dependency, build
configuration or workflow definition changes after qualification, so
the qualification remains valid.

## Outstanding findings

| Finding | Severity | Status |
|---|---|---|
| The upstream validator's optional-corpus gaps: big integers beyond binary64 precision, ECMA-262 regular expression semantics, optional overflow handling, historical draft compatibility, optional format assertion. | low | Recorded, not blocking. The mandatory corpus is complete. |
| The upstream validator aborts the process on the Draft 4 boolean form of `exclusiveMaximum`. | high | Contained by the fail-closed adapter. The regression witness is `tests/unit/validator_tests.nim`. |
| `libpcre3` is a runtime dependency of the binary on Linux. | medium | Documented in `docs/architecture/overview.md`; installed and asserted in CI; must be carried by the packaging milestone (IRK-10). |
| The Nimble manifest version carries only the numeric part of the application version, because Nimble rejects anything else. | low | Documented; the version contract test asserts the two agree. |
| The gitleaks action is unusable for this repository because it requires a commercial licence. | low | The MIT-licensed binary is used instead, pinned by digest. |

## Deferred decisions

Recorded in `docs/architecture/overview.md` under "Proposed future
decisions":

* **Persistence.** SQLite with native linking, the embedded SQLite
  amalgamation, or minimal durable file-based persistence.
* **Control plane.** `AF_UNIX`/`SOCK_STREAM`, JSON-RPC 2.0, newline
  framing, bounded messages, `SO_PEERCRED`, filesystem permissions and
  systemd socket activation with `Accept=no`.
* **Storage backends.** `smartctl -x -j`, SCSI protection and capacity
  discovery, sysfs and udev, a native aligned read-only scanner, NVMe
  health observations and SAS PHY diagnostics.

None of these has been approved. No SQLite, no JSON Schema library
beyond the one that was qualified, no libsystemd binding and no
particular concurrency implementation is claimed as decided.

## The next recommended act

`ACT-IRONKEEPER-READONLY-INVENTORY-01`

Linux device discovery, identity normalisation, SMART JSON acquisition
through a bounded backend, synthetic hardware fixtures and read-only
inventory reports.

It depends on IRK-02 (the contract foundation, which is in place) and
feeds IRK-03, IRK-04 and IRK-07.

The recorded first real-world scenario, `LAB-IRK-SAS-ADMISSION-01`,
remains registered and unperformed.
