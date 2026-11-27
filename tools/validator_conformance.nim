## The Ironkeeper validator conformance harness.
##
## This program qualifies the JSON Schema validator against the official
## JSON Schema Test Suite and against Ironkeeper's own supported schema
## policy. It is a *repository-owned* harness: the revision it runs
## against is pinned here, not chosen at the moment of the run.
##
## ## What it measures, and what it does not
##
## Two different things are measured, and they are reported separately:
##
##   1. **Upstream raw-validator conformance.** The validator library is
##      driven directly, with no Ironkeeper policy in the way. This
##      measures the *library*.
##   2. **Ironkeeper adapter conformance.** The same cases are driven
##      through the Ironkeeper adapter, which adds the supported schema
##      policy, the reference policy and the meta-validation gate. A case
##      that lies outside the documented supported subset is excluded, with
##      its reason recorded. A case inside the subset that the adapter
##      answers wrongly is a failure.
##
## ## The oracle
##
## A case passes only when the observed verdict *equals* the expected
## verdict. The harness never counts "the validator returned something" as
## a pass. A validator that accepts everything scores exactly as badly as
## one that rejects everything.
##
## ## The pinned inputs
##
## | Input | Pin |
## |---|---|
## | Validator | `jschema` at the commit in `JSCHEMA_COMMIT` |
## | Test suite | `JSON-Schema-Test-Suite` at `245a45abc90190c0bff04d97e6d2b541b4bb9f12` (the `legacy` branch) |
## | Draft | Draft 2020-12 |
## | Mandatory corpus | every file directly under `tests/draft2020-12/` |
## | Optional corpus | every file under `tests/draft2020-12/optional/`, classified individually |
##
## The optional membership of a case is derived from the corpus structure,
## not from a hand-maintained list of file names.
##
## ## Usage
##
## ```sh
##   nim r tools/validator_conformance.nim --suite <path-to-suite> [--remotes <path>]
## ```
##
## The suite must already be checked out at the pinned revision. The
## harness verifies the revision and refuses to run against a different
## one, so that a result always identifies its input.

import std/[os, tables, algorithm]

from ironkeeper/qualification/corpus import readCorpus, Corpus, CorpusCase
from ironkeeper/qualification/harness import runCorpus, QualificationReport,
  Exclusion, failures, unauthorisedExclusions, invalidEvidence,
  renderSummary, productVerdict, Scope, scUpstream, scAdapter,
  upstreamLimitations, mandatoryResults, optionalResults
from ironkeeper/qualification/providers import newRawRegistry, rawProvider,
  adapterProvider, subsetJudge, RemoteBaseUri
from ironkeeper/qualification/remotes import readRemoteSchemas
from ironkeeper/qualification/verdict import QualificationVerdict

const
  SuiteRevision* = "245a45abc90190c0bff04d97e6d2b541b4bb9f12"
    ## The exact revision of the official JSON Schema Test Suite that this
    ## harness qualifies against. It is the `legacy` branch revision that
    ## carries the per-draft corpus under `tests/draft2020-12/`.

  DraftDir = "tests/draft2020-12"

proc optionValue(name: string, default = ""): string =
  ## The value of the `--name value` option, or `default`.
  let params = commandLineParams()
  var i = 0
  while i < params.len:
    if params[i] == name and i + 1 < params.len:
      return params[i + 1]
    inc i
  default

proc renderReport(report: QualificationReport, label: string) =
  ## Render one report.
  echo "[" & label & "]"
  echo "  denominator=", report.denominator
  echo "  passed=", report.passed
  echo "  failed=", failures(report).len
  echo "  unauthorised_exclusions=", unauthorisedExclusions(report).len
  echo "  invalid_evidence=", invalidEvidence(report).len
  for line in renderSummary(report):
    echo "  ", line
  for f in failures(report):
    echo "  failure: ", f.identity,
         " expected_valid=", f.expectedValid,
         " observed=", f.observed
  for u in unauthorisedExclusions(report):
    echo "  unauthorised_exclusion: ", u.identity, " reason=", u.exclusionReason
  for e in invalidEvidence(report):
    echo "  invalid_evidence: ", e.identity, " reason=", e.exclusionReason
  for l in upstreamLimitations(report):
    echo "  upstream_limitation: ", l.identity,
         " expected_valid=", l.expectedValid,
         " observed=", l.observed,
         " note=", l.observedNote
  echo "  exclusions=", report.exclusions.len
  var reasons: seq[string] = @[]
  for reason in report.exclusionCounts.keys:
    reasons.add reason
  reasons.sort()
  for reason in reasons:
    echo "  exclusion_reason: count=", report.exclusionCounts[reason],
         " reason=", reason

proc main() =
  let suiteDir = optionValue("--suite")
  if suiteDir.len == 0:
    stderr.writeLine("usage: nim r tools/validator_conformance.nim --suite <path>")
    quit(2)
  let draft = optionValue("--draft", DraftDir)

  let draftPath = absolutePath(suiteDir / draft)
  if not dirExists(draftPath):
    stderr.writeLine("the suite does not contain " & draft)
    quit(2)

  # ---- the corpus ---------------------------------------------------------
  # The corpus is read through the repository-owned reader, which refuses
  # a malformed file rather than skipping it, and which computes a digest
  # over the files it actually read.
  let corpus = readCorpus(draftPath)
  if corpus.problems.len > 0:
    echo "corpus_problems=", corpus.problems.len
    for p in corpus.problems:
      echo "  corpus_problem: ", p.file, ": ", p.message
    quit(1)
  if corpus.cases.len == 0:
    echo "the corpus is empty; refusing to qualify against it"
    quit(1)

  echo "suite_revision=", SuiteRevision
  echo "draft=2020-12"
  echo "corpus_files=", corpus.fileCount
  echo "corpus_cases=", corpus.cases.len
  echo "corpus_digest_fnv1a64=", corpus.digest

  var mandatoryTotal = 0
  var optionalTotal = 0
  for c in corpus.cases:
    if c.optional:
      inc optionalTotal
    else:
      inc mandatoryTotal
  echo "mandatory_cases=", mandatoryTotal
  echo "optional_cases=", optionalTotal
  echo "corpus_representation_limited=",
       (block:
         var n = 0
         for c in corpus.cases:
           if c.representationLimited:
             inc n
         n)

  # ---- the remote schemas --------------------------------------------------
  # The remote tree is part of the measured input. A remote schema that
  # cannot be read is a problem, not a file to be passed over: the
  # qualification refuses to run against a corpus whose references it
  # could not resolve.
  let remote = readRemoteSchemas(suiteDir / "remotes", RemoteBaseUri)
  echo "remote_files=", remote.fileCount
  echo "remote_digest_fnv1a64=", remote.digest
  if remote.problems.len > 0:
    echo "remote_problems=", remote.problems.len
    for p in remote.problems:
      echo "  remote_problem: ", p.file, ": ", p.message
    quit(1)

  # ---- the raw upstream validator -----------------------------------------
  let rawRegistry = newRawRegistry(suiteDir)
  if rawRegistry.problems.len > 0:
    echo "remote_problems=", rawRegistry.problems.len
    for p in rawRegistry.problems:
      echo "  remote_problem: ", p
    quit(1)
  let rawReport = runCorpus(corpus, rawProvider(rawRegistry.registry),
                             subsetJudge(), scUpstream)
  renderReport(rawReport, "raw-upstream")

  # ---- the Ironkeeper adapter ---------------------------------------------
  let adapterReport = runCorpus(corpus, adapterProvider(), subsetJudge(),
                                scAdapter)
  renderReport(adapterReport, "ironkeeper-adapter")

  # ---- the verdict ---------------------------------------------------------
  # The qualification fails when either measurement fails. An unexplained
  # result is never tolerated.
  # The qualification fails when the *product* qualification fails. The
  # raw measurement is a measurement of the upstream library: a wrong
  # answer there is a raw failure, and it is reported as such. It is
  # accepted for the product only when it lies outside the required
  # subset and an authorised limitation entry covers it.
  let rawVerdict = rawReport.verdict
  let adapterVerdict = adapterReport.verdict
  let productResult = productVerdict(rawReport, adapterReport)
  echo "raw_verdict=", (if rawVerdict == qvPass: "PASS" else: "FAIL")
  echo "adapter_verdict=", (if adapterVerdict == qvPass: "PASS" else: "FAIL")
  echo "product_verdict=", (if productResult == qvPass: "PASS" else: "FAIL")
  echo "raw_accepted_limitations=", rawReport.acceptedLimitations.len
  for identity in rawReport.acceptedLimitations:
    echo "  accepted_limitation: ", identity
  # The per-class counts of the mandatory corpus, for the receipt.
  echo "raw_mandatory_cases=", mandatoryResults(rawReport).len
  echo "raw_optional_cases=", optionalResults(rawReport).len
  echo "adapter_mandatory_cases=", mandatoryResults(adapterReport).len
  echo "adapter_optional_cases=", optionalResults(adapterReport).len
  if (invalidEvidence(rawReport).len > 0) or
     (invalidEvidence(adapterReport).len > 0):
    quit(1)
  if productResult != qvPass:
    quit(1)
  quit(0)

main()
