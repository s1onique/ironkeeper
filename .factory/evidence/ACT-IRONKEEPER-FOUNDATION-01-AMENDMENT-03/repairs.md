# Repairs

Each repair is on the production path that the finding was reproduced
against. No repair introduces a second implementation of the thing it
repairs.

## F1 — The conformance oracle

**Production path.** `src/ironkeeper/qualification/verdict.nim`,
`src/ironkeeper/qualification/harness.nim`,
`src/ironkeeper/qualification/corpus.nim`,
`src/ironkeeper/qualification/providers.nim`,
`src/ironkeeper/qualification/jsonvalue.nim`,
`tools/validator_conformance.nim`,
`tools/validator_conformance_witnesses.nim`.

**The oracle.** `classify` compares the **observed** verdict with the
**expected** verdict and assigns exactly one classification:

| Classification | Meaning | In the denominator |
|---|---|---|
| `clCorrectAcceptance` | expected valid, observed valid | yes, as a pass |
| `clCorrectRejection` | expected invalid, observed invalid | yes, as a pass |
| `clFalseAcceptance` | expected invalid, observed valid | yes, as a failure |
| `clFalseRejection` | expected valid, observed invalid | yes, as a failure |
| `clExecutionError` | the validator raised instead of answering | yes, as a failure |
| `clUnsupportedPolicy` | the case is outside the supported subset | no, excluded |
| `clKnownLimitation` | an authorised, recorded limitation | no, excluded |
| `clInvalidEvidence` | the test evidence itself is unusable | yes, as a failure |

**Typed outcomes.** The observed verdict is a typed enumeration
(`ObservedVerdict`), and the adapter's failure is a typed enumeration
(`ValidationFailureKind` in `src/ironkeeper/contracts/validator.nim`:
`vfkNone`, `vfkUnsupportedDialect`, `vfkSchemaPolicy`,
`vfkReferencePolicy`, `vfkInternal`). No error *message* is ever
interpreted to decide a classification.

**An execution defect is not an invalid instance.** A raised exception is
`clExecutionError`, never `clCorrectRejection`.

**The implementation cannot exclude its own case.** The supported subset
is decided by `subsetJudge`, which reads the **schema document alone** —
the keyword policy, the reference policy and the declared dialect. It
never observes the implementation's answer. A refusal of a case the
harness considers supported is `clExecutionError`: a defect, not an
exclusion.

**Exclusions are recorded.** Every excluded case carries its identity and
its reason. The reasons are grouped by their exact text, so two different
reasons are never merged, and the grouping is printed by the harness.

**Corpus integrity.**

* The suite revision is pinned, and the **tested corpus** is identified by
  a digest computed over the corpus files that were actually read
  (`corpus_digest_sha256` in `tools/qualify_validator.sh`, and
  `corpus_digest_fnv1a64` in the harness).
* A malformed corpus file is a **problem**, not a skipped file: the
  reader refuses it and the qualification exits nonzero.
* An empty corpus is refused.
* The optional membership of a case is derived from the corpus structure
  — the official suite's `optional` directory — not from a hand-maintained
  list of file names.
* The case identities are deterministic: `<file>#<group>.<test>`.

**Remote schemas.** The suite's `remotes/` directory is registered under
the retrieval URI the suite documents (`http://localhost:1234` plus the
path relative to `remotes`). The registration reads the checkout; the
registry never fetches, so the validation stays offline. Without the
registration, 16 `refRemote.json` cases are answered wrongly; with it,
they are answered correctly.

**Numeric precision.** The corpus is read by
`src/ironkeeper/qualification/jsonvalue.nim`, which parses the source text
and keeps every number's exact lexeme. A number the document model cannot
hold — an integer outside the 64-bit signed range, a magnitude that
overflows — is reported with its exact lexeme and its exact position, and
the case that carries it is classified as a **known limitation of the
test harness**, not as a validator failure. The classification does not
claim that the validator lacks the precision.

**Two measurements, separately.** `runCorpus` takes a `Scope`:

* `scUpstream` measures the library over the whole mandatory corpus. A
  case outside Ironkeeper's supported subset that the library answers
  wrongly is recorded as an exact `upstream_limitation`.
* `scAdapter` measures Ironkeeper over the supported subset.

**The process exits nonzero on any unexplained result.** The harness
exits 1 when either measurement fails or when any exclusion is
unauthorised.

## F2 — The secret-scan report authority

**Production path.** `tools/gate_secret_scan.sh`.

The report is now **parsed**, not grepped, with Python — an existing CI
dependency. The gate requires all of:

* the scanner's exit status is zero;
* the report exists, is readable and is not empty;
* it is a **complete** JSON document (`json.loads` rejects trailing
  content and truncated documents);
* its root value is an **array**;
* the array's length is **zero**.

Any nonempty array fails, regardless of its member fields. A scanner that
exits zero while recording findings fails: the report wins over the
scanner's own claim.

The diagnostic rendering (`head -c 4000` of the report) happens **after**
the verdict is decided, so it cannot change it.

## F3 — The public output contracts

**Production path.** `src/ironkeeper/contracts/outputbounds.nim`,
`src/ironkeeper/contracts/report.nim`, `src/ironkeeper/cli/app.nim`.

The limits are enforced at the production boundary, not only stated in
the schema:

| Bound | Limit |
|---|---|
| message | 4096 |
| location | 1024 |
| code | 128 |
| issue / finding count | 1024 |
| error detail | 4096 |

**Truncation is explicit.** A shortened value ends with the marker
`[truncated]`, so a consumer can tell that it was shortened. A truncated
**collection** reserves one slot for a marker entry that names how many
entries were dropped (`issues.truncated`, `findings.truncated`), so the
document never exceeds the contract's limit and can never be read as
"there were no other issues". The marker is itself an issue, so a
truncated result can never become valid or PASS.

**The evidence is not silently removed.** The dropped entries are all
*additional* violations: the document was already invalid, so the verdict
does not change, and the marker records exactly how much evidence was
left out.

## F4 — Bounded ingestion

**Production path.** `src/ironkeeper/json/boundedread.nim`,
`readDocument` in `src/ironkeeper/cli/app.nim`.

The reader now:

* opens the path with `O_RDONLY | O_NONBLOCK | O_CLOEXEC`, so the open
  cannot block on a FIFO and the descriptor cannot leak into a child
  process;
* verifies with `fstat` on the **opened descriptor** that the input is a
  regular file;
* reads only from that descriptor;
* consumes at most the limit **plus the overflow discriminator**;
* classifies a read error independently of end-of-file;
* closes the descriptor on every exit path.

The reader **never trusts the pathname**. A `stat` on the path and an
`open` on the path are two separate operations, and the file can be
replaced between them; only the descriptor can be trusted.

## F5 — The supported reference policy

**Production path.** `src/ironkeeper/contracts/schemawalk.nim`,
`src/ironkeeper/contracts/schemarefs.nim`,
`src/ironkeeper/contracts/schemapolicy.nim`,
`src/ironkeeper/contracts/validator.nim`.

The two policies now share **one** interpretation of the document: the
schema-position walker. It reports every member of every schema-bearing
position, and it never descends into a plain value.

The reference policy:

* treats a `$ref` inside a literal `const` object, an `examples` array or
  a `default` value as **data**;
* permits a local JSON Pointer that resolves to a schema-bearing position;
* permits a local `$anchor` that names an anchor of the same document;
* permits the bundled metaschema URI;
* refuses an **external** reference, with the reason that it would
  require a network fetch;
* refuses a **dynamic** reference (`$dynamicRef`, `$dynamicAnchor`);
* refuses a reference to a **non-schema-bearing** position;
* treats an **unresolvable** local reference as a schema defect;
* refuses a **nested `$id`**, because a new base URI would change the
  meaning of every reference beneath it and the supported resolution
  model is document-local;
* refuses a nested `$vocabulary` for the same reason.

A root `$id` and a root `$vocabulary` are accepted: they describe the
document itself.

The collection of external references that lived in `validator.nim` is
**removed**. It walked every member of every object, which is what made
the two policies disagree.

## F6 — The qualification workspace

**Production path.** `tools/qualify_validator.sh`.

The caller's `IRK_QUALIFY_WORK` is now treated as a **parent** directory.
The qualification creates a unique workspace *inside* it with `mktemp -d`,
records that it owns it, and removes **only** that workspace. The
caller's own files and directories are preserved, and the existing
`IRK_QUALIFY_KEEP` option still keeps the workspace.
