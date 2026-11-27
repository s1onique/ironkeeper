# Acceptance

## The gates

| Gate | Mandatory condition | Result | Evidence |
|---|---|---|---|
| **A01** | Entry authority established | **MET** | `entry-identity.md`: the remote is `s1onique/ironkeeper`, the entry HEAD was `fb9c5f6d5ec602b272c108a9d23a7342cbadcd35` as expected, the tree was clean, there were no stashes or worktrees, and the state of `main` is recorded as observed without speculation. |
| **A02** | Conformance harness compares actual and expected validity | **MET** | `repairs.md`, "F1": `classify` in `src/ironkeeper/qualification/verdict.nim` compares the observed verdict with the expected one. The entry revision's `ckPass or ckFail` counting is removed. `qualification-results.md`: 1300/1300 raw and 949/949 adapter, each with the per-class counts. |
| **A03** | Always-accept, always-reject and inverted-verdict witnesses fail | **MET** | `green-witnesses.md`: the six controlled providers are driven against the production counting and terminal-verdict logic. The first four FAIL, the correct provider PASSes. The unit suite pins the same property independently. |
| **A04** | Adapter execution errors and unexplained results fail qualification | **MET** | `repairs.md`, "F1": `ovError` is `clExecutionError`; a refusal of an in-subset case is `clExecutionError`, not an exclusion; `verdictOf` fails on any failure or unauthorised exclusion; the harness exits nonzero. `qualification-results.md`: `execution_error=0`, `unauthorised_exclusions=0`. |
| **A05** | Corpus identity and exclusions are authoritative | **MET** | `qualification-results.md`: the suite revision, the corpus digest (`81b3abac…`), the file count, the case counts and every exclusion with its exact reason. `repairs.md`, "F1": a malformed corpus file is a problem, not a skipped file; an empty corpus is refused; the optional membership comes from the corpus structure. |
| **A06** | Real supported-subset conformance established | **MET** | `qualification-results.md`: the raw upstream validator answers 1300/1300 mandatory cases correctly, and the Ironkeeper adapter answers 949/949 mandatory cases of the supported subset correctly. The two measurements are separate and separately reported. No unrestricted Draft 2020-12 conformance is claimed from a restricted implementation. |
| **A07** | Malformed and nonempty scanner reports fail | **MET** | `red-reproductions.md`, "F2": `[{}]`, `[] trailing garbage` and `[` all **passed** the entry revision's gate. `green-witnesses.md`: all four now fail, and the gate's own witnesses are 21 of 21. |
| **A08** | Actual public CLI output conforms to its contracts | **MET** | `green-witnesses.md`: the compiled CLI is exercised with an oversized numeric lexeme, an oversized validation location, an oversized diagnostic message, more issues than the schema allows, an unsupported schema version and ordinary valid and invalid documents. Every JSON-mode result is exactly one JSON document; the independent Python validator accepts all five generated documents. |
| **A09** | Independent validation covers every public output contract | **MET** | `green-witnesses.md`: all six repository schemas are meta-validated, including `validation` and `schemaindex`; every machine-readable CLI command's actual output is validated; the classified failure output is validated; the expected exit status is checked alongside the output schema; a missing or empty generated document fails. |
| **A10** | Bounded ingestion handles open-time substitution safely | **MET** | `repairs.md`, "F4": the reader opens non-blocking with close-on-exec and verifies the opened descriptor with `fstat`. `green-witnesses.md`: the substitution witness is non-vacuous — with a pathname pre-check the substitution slips through and the suite fails; restored, it passes. |
| **A11** | Reference policy is schema-position-aware | **MET** | `repairs.md`, "F5": one schema-position walker serves both policies. `green-witnesses.md`: 24 checks pin every required witness. The `collectExternalRefs` traversal that disagreed with the policy is removed. |
| **A12** | Qualification cleanup preserves caller-owned directories | **MET** | `green-witnesses.md`: with an isolated temporary parent containing a sentinel file and a sibling directory, both survive the run. The workspace is created inside the caller's directory and only it is removed. |
| **A13** | Native Linux amd64 and arm64 qualification passes | **UNMET** | **Environment failure.** The sandbox has no usable GitHub credential: the SSH keys cannot be read, the `gh` token is invalid, the keychain holds no entry, and no `GITHUB_TOKEN` is present. The branch could not be pushed, so no GitHub Actions run could be triggered. `entry-identity.md`, "The environment failure". No local virtualisation was attempted: there is no container runtime, and QEMU and new infrastructure are not authorised. The requirement is **not** weakened; the gate is reported as unmet. |
| **A14** | Patch hygiene clean and MIT license preserved | **MET** | `git diff --cached --check` passes and no tracked file contains trailing whitespace. `shasum -a 256 LICENSE` is `307c6257a17d9d9c7f0a0d5d321fc1606fa53ef1e9da305b0d3012218f63393c`, unchanged from the entry commit. |
| **A15** | No hardware operations or infrastructure modifications | **MET** | The application opens no device, runs no storage tool and opens no socket. `ironkeeper daemon` returns an explicit unsupported-operation result. The amendment opened no storage device, performed no hardware discovery, and created no infrastructure. The only temporary artefacts are directories under `/tmp` and the repository's own `build/` output. |
| **A16** | Exact-head evidence, epic board and final receipt updated | **PARTIAL** | The evidence bundle and `EPICS.md` carry the amendment's board entry and the corrected M0 status. The receipt cannot record a CI head or a CI run id, because no CI run could be triggered (A13). |

**One gate is unmet and one is partial. Both are caused by the same
environment failure, and neither is worked around.**

## The identities

| Identity | Value |
|---|---|
| `ENTRY_HEAD` | `fb9c5f6d5ec602b272c108a9d23a7342cbadcd35` |
| `SUBJECT_HEAD` | `419eb8ca584c37a47b2e8dc4f72230367cc87143` |
| `CI_HEAD` | **none** — no CI run could be triggered |
| `CI_RUN_ID` | **none** |
| `CI_CONCLUSION` | **none** |
| `FINAL_HEAD` | the receipt commit, recorded in `exit-receipt.md` |
| `BRANCH` | `act/ironkeeper-foundation-01-amendment-03` |

## The verdict

`PARTIAL_FOUNDATION`.

Every repair in this amendment is made, reproduced and witnessed on the
production path, and every gate that the environment permitted is met.
The one gate that is unmet — the native Linux amd64 and arm64
qualification — is unmet because the sandbox cannot authenticate to
GitHub, not because the work is incomplete. The subject is complete and
committed; it is qualified locally on macOS, and the workflow that
performs the native qualification is committed with it.

The predecessor's `PARTIAL_FOUNDATION` disposition was based on a
conformance harness that compared nothing. That defect is repaired, and
the repaired harness produces **genuine** counts: 1300/1300 mandatory
cases for the upstream validator and 949/949 for the Ironkeeper adapter
over its supported subset, with every exclusion recorded by identity and
reason.

The qualifier `PARTIAL_SCHEMA_VALIDATOR` does **not** apply: the
mandatory corpus of the official JSON Schema Test Suite is answered
correctly by the upstream validator, and the Ironkeeper adapter answers
correctly every mandatory case inside its supported subset. The
supported subset is narrower than Draft 2020-12 by design, and every
exclusion is recorded.

## Outstanding findings

| Finding | Severity | Status |
|---|---|---|
| The native Linux amd64 and arm64 qualification could not be performed. | high | **Environment failure.** No GitHub credential is available in the sandbox. The requirement is not weakened; the gate is reported as unmet. The workflow that performs it is committed. |
| The supported schema policy is narrower than Draft 2020-12. | low | Deliberate and documented. Every exclusion carries its exact identity and reason. |
| The strict reader rejects non-integral numbers. | low | Deliberate and documented. **This is an Ironkeeper implementation restriction, not a JSON Schema requirement**; the documentation is corrected. |
| `libpcre3` is a runtime dependency of the binary on Linux. | medium | Documented in `docs/architecture/overview.md`; installed and asserted in CI; must be carried by the packaging milestone (IRK-10). |
| The Nimble manifest version carries only the numeric part of the application version. | low | Documented; the version contract test asserts the two agree. |
| The gitleaks action is unusable for this repository because it requires a commercial licence. | low | The MIT-licensed binary is used instead, pinned by digest. |
| An orphaned QEMU process from the abandoned local virtualisation approach cannot be signalled from the sandbox. | low | An **environment-cleanup item** for the operator, not a product defect. It was not touched by this amendment and no further virtualisation troubleshooting was attempted. |

## The next recommended act

`ACT-IRONKEEPER-READONLY-INVENTORY-01`

Linux device discovery, identity normalisation, SMART JSON acquisition
through a bounded backend, synthetic hardware fixtures and read-only
inventory reports.

It depends on IRK-02 (the contract foundation, which is in place) and
feeds IRK-03, IRK-04 and IRK-07.

**Before it starts**, the native Linux amd64 and arm64 qualification must
be run, because it could not be run from the sandbox. The command is
`tools/qualify_validator.sh`, and the CI workflow
`validator-qualification` performs it.

The recorded first real-world scenario, `LAB-IRK-SAS-ADMISSION-01`,
remains registered and unperformed. **No hardware discovery was begun by
this amendment.**
