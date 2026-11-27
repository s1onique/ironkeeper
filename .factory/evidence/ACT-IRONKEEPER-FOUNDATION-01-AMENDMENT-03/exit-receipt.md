# Exit receipt

```yaml
ACT_ID: ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-03
ENTRY_HEAD: fb9c5f6d5ec602b272c108a9d23a7342cbadcd35
SUBJECT_HEAD: 419eb8ca584c37a47b2e8dc4f72230367cc87143
CI_HEAD: none — no CI run could be triggered (no GitHub credential in the sandbox)
CI_RUN_ID: none
FINAL_HEAD: <the receipt commit; see `git log --oneline -1` on the branch>
BRANCH: act/ironkeeper-foundation-01-amendment-03

CONFORMANCE_ORACLE_AUTHORITY: >
  ESTABLISHED. The harness compares the observed verdict with the expected
  verdict (`classify` in src/ironkeeper/qualification/verdict.nim). The entry
  revision's `ckPass or ckFail` counting, which accepted both an acceptance
  and a rejection as a pass, is removed. Typed outcomes throughout: the
  observed verdict is an enumeration, and the adapter's failure is a typed
  `ValidationFailureKind`; no error message is ever interpreted to decide a
  classification. The previous counts (1337/1337 mandatory, 1031/1037
  optional) are marked superseded in docs/architecture/overview.md; the
  historical observation that the harness produced them is retained.

CONFORMANCE_NEGATIVE_WITNESSES: >
  ESTABLISHED. Six controlled providers drive the production counting and
  terminal-verdict logic over a minimal mixed corpus (2 valid, 2 invalid
  instances): always-accept FAIL, always-reject FAIL, inverted FAIL, error
  FAIL, correct PASS, unsupported PASS-with-explicit-classification. The
  unsupported case is classified `clUnsupportedPolicy` with its exact
  reason and is not counted as a conformance pass. The witnesses are
  `tools/validator_conformance_witnesses.nim` and run as part of every
  qualification.

CORPUS_IDENTITY: >
  ESTABLISHED. Suite revision 245a45abc90190c0bff04d97e6d2b541b4bb9f12
  (verified against the checkout), corpus digest
  81b3abac420e41bc48c5048e6f80112828972374e332c92190de9c55bc146957 computed
  over the corpus files actually read and pinned in tools/qualify_validator.sh.
  80 files, 2374 cases, 1300 mandatory and 1074 optional. A malformed corpus
  file is a problem, not a skipped file; an empty corpus is refused; the
  optional membership is derived from the corpus structure. The case
  identities are deterministic (`<file>#<group>.<test>`).

RAW_MANDATORY_RESULTS: >
  1300/1300 correct. correct_acceptance=763, correct_rejection=537,
  false_acceptance=0, false_rejection=0, execution_error=0,
  unsupported_policy=0, known_limitation=0, invalid_evidence=0.
  The upstream validator is measured directly, with the suite's remote
  schemas registered offline under their documented retrieval URIs. Without
  that registration 16 refRemote cases are answered wrongly.

RAW_OPTIONAL_RESULTS: >
  1074 optional cases, classified individually and excluded from the
  mandatory denominator, with the reason recorded for each. The upstream
  library's answers to them are reported in
  `qualification-results.md`; they do not affect the mandatory verdict.

ADAPTER_SUPPORTED_RESULTS: >
  949/949 correct over the mandatory cases of the supported subset.
  correct_acceptance=570, correct_rejection=379, false_acceptance=0,
  false_rejection=0, execution_error=0, unsupported_policy=0,
  known_limitation=0, invalid_evidence=0.

ADAPTER_POLICY_EXCLUSIONS: >
  351 mandatory cases are outside Ironkeeper's supported subset and are
  excluded with their exact identity and their exact reason, grouped by the
  exact reason text. The reasons are: a declared dialect this build does not
  implement (9 cases), an external reference that would require a network
  fetch, a nested '$id', a nested '$vocabulary', a dynamic reference, an
  unknown keyword, and the optional part of the corpus (1015 cases). The
  implementation under test can never exclude its own case: the subset is
  decided from the schema document alone, and a refusal of an in-subset case
  is a failure.

UNEXPLAINED_RESULTS: 0

SECRET_SCAN_REPORT_AUTHORITY: >
  ESTABLISHED. The report is parsed as JSON, not grepped. The gate requires
  the scanner's exit status to be zero, the report to be a complete JSON
  document, its root to be an array, and the array to be empty. Any nonempty
  array fails regardless of its member fields. Malformed, missing,
  truncated and unreadable reports fail. The diagnostic rendering happens
  after the verdict is decided and cannot change it.

PUBLIC_OUTPUT_CONTRACT_AUTHORITY: >
  ESTABLISHED. The limits are enforced at the production boundary
  (src/ironkeeper/contracts/outputbounds.nim): message 4096, location 1024,
  code 128, issue/finding count 1024, error detail 4096. A shortened value
  ends with the marker `[truncated]`; a truncated collection reserves one
  slot for a marker entry that names how many entries were dropped, so the
  document never exceeds its contract and can never be read as "no other
  issues". The compiled CLI is exercised with an oversized numeric lexeme,
  an oversized validation location, an oversized diagnostic message, more
  issues than the schema allows, an unsupported schema version, and ordinary
  valid and invalid configuration and report documents. Every JSON-mode
  result is exactly one JSON document.

INDEPENDENT_VALIDATION_COVERAGE: >
  ESTABLISHED. All six repository schemas are meta-validated, including
  `validation` and `schemaindex`, which the entry revision did not cover.
  Every machine-readable CLI command's actual output is validated against
  its authoritative contract; the classified failure output is validated
  against the error contract; the expected exit status is checked alongside
  the output schema; a missing or empty generated document fails. The
  configuration report the gate generated is fed back into
  `report validate --json`. The generated documents were additionally
  accepted by an independent Python `jsonschema` implementation.

BOUNDED_OPEN_AUTHORITY: >
  ESTABLISHED. The reader opens with O_RDONLY | O_NONBLOCK | O_CLOEXEC,
  verifies with fstat on the opened descriptor that the input is a regular
  file, reads only from that descriptor, consumes at most the limit plus
  the overflow discriminator, classifies a read error independently of EOF,
  and closes the descriptor on every exit path. The pathname is never
  trusted: a stat and an open on a path are two operations, and the file can
  be replaced between them. The substitution witness is non-vacuous — with a
  pathname pre-check the substitution slips through and the suite fails.

REFERENCE_POLICY_AUTHORITY: >
  ESTABLISHED. One schema-position walker (schemawalk.nim) serves both the
  keyword policy and the reference policy, so they cannot disagree. A `$ref`
  inside a literal `const` object, an `examples` array or a `default` value
  is data. A local JSON Pointer and a local `$anchor` are permitted; the
  bundled metaschema is permitted; an external reference, a dynamic
  reference, a nested `$id` and a nested `$vocabulary` are refused; an
  unresolvable local reference is a schema defect; a reference to a
  non-schema-bearing position is refused. 24 witnesses pin the behaviour.

WORKSPACE_OWNERSHIP: >
  ESTABLISHED. IRK_QUALIFY_WORK is a parent directory. The qualification
  creates a unique workspace inside it, records that it owns it, and removes
  only that workspace. A sentinel file and a sibling directory in the
  caller's directory survive the run. The keep option still works.

LINUX_AMD64_NATIVE: >
  NOT PERFORMED. Environment failure: the sandbox has no usable GitHub
  credential (the SSH keys cannot be read, the `gh` token is invalid, the
  keychain holds no entry, no GITHUB_TOKEN is present), so the branch could
  not be pushed and no GitHub Actions run could be triggered. No container
  runtime is available and QEMU and new infrastructure are not authorised.
  The requirement is not weakened.
LINUX_ARM64_NATIVE: >
  NOT PERFORMED. The same environment failure. No cross-architecture
  emulation was used, so no arm64 result is claimed.
CI_RUN_ID: none
CI_CONCLUSION: none

PATCH_HYGIENE: >
  CLEAN. `git diff --cached --check` passes and no tracked file contains
  trailing whitespace.
LICENSE_PRESERVED: >
  YES. shasum -a 256 LICENSE = 307c6257a17d9d9c7f0a0d5d321fc1606fa53ef1e9da305b0d3012218f63393c,
  unchanged from the entry commit.
HARDWARE_OPERATIONS: >
  NONE. No storage device was opened, no hardware discovery was performed,
  no SMART acquisition was implemented. The application opens no device and
  runs no storage tool.
PROXMOX_MODIFICATIONS: NONE
TRACKED_DIRT: >
  None at the receipt commit. The working tree is clean.
HELD_OBSERVATIONS: >
  One background command was launched and cancelled without its result being
  consumed: a recursive `find` over the filesystem that was searching for a
  local copy of the pinned validator. It was cancelled when a copy was found
  at /tmp/jschema. It produced no observation and no conclusion. No other
  background command was launched.
POST_QUALIFICATION_DIFF: >
  The evidence bundle and the epic board entry are the only changes after the
  subject commit. No executable source, no schema, no gate script and no
  workflow changed after the subject was committed. The local qualification
  was run at the subject commit; the subject was not modified afterwards.
EVIDENCE_DIRECTORY: .factory/evidence/ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-03/
EPIC_BOARD_STATUS: >
  M0 — Foundations: done (closed by this amendment). The board entry for
  ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-03 is in EPICS.md, and it records
  that the predecessor's conformance counts are superseded.

ACCEPTANCE_GATES:
  A01: MET
  A02: MET
  A03: MET
  A04: MET
  A05: MET
  A06: MET
  A07: MET
  A08: MET
  A09: MET
  A10: MET
  A11: MET
  A12: MET
  A13: UNMET — environment failure, no GitHub credential; no emulation used
  A14: MET
  A15: MET
  A16: PARTIAL — the evidence bundle and the board are updated; the CI head
        and the CI run id cannot be recorded because no CI run could be
        triggered

OPEN_FINDINGS: >
  The native Linux amd64 and arm64 qualification could not be performed
  (environment failure; the requirement is not weakened and the gate is
  reported as unmet). The supported schema policy is narrower than Draft
  2020-12 by design, and every exclusion is recorded. The strict reader
  rejects non-integral numbers — an Ironkeeper implementation restriction,
  not a JSON Schema requirement, and the documentation now says so. The
  orphaned QEMU process remains an environment-cleanup item for the
  operator; no further virtualisation troubleshooting was attempted.

FINAL_VERDICT: PARTIAL_FOUNDATION

NEXT_RECOMMENDED_ACT: ACT-IRONKEEPER-READONLY-INVENTORY-01
```

## Why the verdict is `PARTIAL_FOUNDATION`

Every repair in this amendment is made, reproduced against the production
path and witnessed. Every gate that the environment permitted is met.

The one unmet gate — the native Linux amd64 and arm64 qualification — is
unmet because the sandbox cannot authenticate to GitHub, so the branch
could not be pushed and no CI run could be triggered. That is an
**environment failure**, not a defect in the work, and it is reported as
unmet rather than worked around. The workflow that performs the native
qualification is committed with the subject, and the decision to run it is
made by the repository-owned script `tools/requalification_needed.sh`.

The subject is complete and committed at
`419eb8ca584c37a47b2e8dc4f72230367cc87143`. Before the next ACT starts,
the native qualification must be run, because it could not be run from
here.
