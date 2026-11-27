## The qualification harness.
##
## ## The oracle
##
## The harness compares the **observed** verdict with the **expected**
## verdict from the corpus. A case passes only when the two agree. A
## provider that accepts everything and a provider that rejects everything
## therefore score identically and both fail: the harness measures
## agreement, not activity.
##
## ## The provider seam
##
## The harness does not know how a verdict is produced. It asks a
## *provider*. The production providers drive the upstream validator and the
## Ironkeeper adapter; the controlled providers exist so that the harness's
## own counting and terminal-verdict logic can be tested against verdicts
## that are wrong in a known way. A harness whose oracle cannot be shown to
## reject a wrong answer is not an oracle.
##
## ## Exclusions
##
## A case may leave the denominator only when the exclusion is authorised:
##
##   * the harness itself determined that the case lies outside the
##     supported subset, from the schema document alone; or
##   * the exact case identity is listed in the repository's authorised
##     limitation file, with a reason.
##
## The implementation under test never excludes its own case. When it
## refuses a case the harness considers supported, that refusal is a
## failure.

import std/[tables, sets]

from ironkeeper/qualification/verdict import CaseResult, ObservedVerdict,
  Classification, ClassificationCounts, classify, classificationOf, countsOf,
  denominatorOf, passesOf, failuresOf, unauthorisedExclusionsOf, verdictOf,
  QualificationVerdict, renderCounts
from ironkeeper/qualification/corpus import CorpusCase, Corpus

type
  ProviderOutcome* = object
    ## What a provider reports for one case.
    verdict*: ObservedVerdict
      ## The observed verdict.
    message*: string
      ## A diagnostic message. It never influences the classification; the
      ## classification is derived from the typed verdict alone.

  VerdictProvider* = proc (c: CorpusCase): ProviderOutcome {.closure.}
    ## The seam through which a verdict is obtained.

  Scope* = enum
    ## What a measurement covers.
    scUpstream
      ## The upstream library is measured over the whole mandatory
      ## corpus. A case that lies outside Ironkeeper's supported subset
      ## and that the library answers wrongly is recorded as an exact
      ## limitation, not as a failure of the qualification.
    scAdapter
      ## The Ironkeeper adapter is measured over the supported subset. A
      ## case outside the subset is excluded, with its reason.

  SubsetJudge* = proc (c: CorpusCase): Exclusion {.closure.}
    ## The seam through which the supported subset is decided.
    ##
    ## The judge decides from the *schema document alone* whether a case
    ## lies inside the supported subset. It never observes the
    ## implementation's answer, so the implementation cannot exclude its
    ## own case. The returned exclusion carries the reason, which is
    ## recorded verbatim.

  Exclusion* = object
    ## An authorised exclusion of one case from the denominator.
    identity*: string
    reason*: string

  QualificationReport* = object
    ## The result of one qualification run.
    results*: seq[CaseResult]
      ## Every case, in corpus order.
    counts*: ClassificationCounts
      ## The per-class counts.
    denominator*: int
      ## The number of cases that count towards the qualification.
    passed*: int
      ## The number of in-denominator cases that were answered correctly.
    verdict*: QualificationVerdict
      ## The terminal verdict.
    exclusions*: seq[Exclusion]
      ## The authorised exclusions, with their reasons.
    exclusionCounts*: Table[string, int]
      ## The number of exclusions, grouped by the reason they were
      ## excluded. The grouping is by the exact reason text, so that two
      ## different reasons are never merged.
    unsupported*: seq[string]
      ## The identities of the cases the harness placed outside the
      ## supported subset.

proc runCase(c: CorpusCase, provider: VerdictProvider,
             judge: SubsetJudge): CaseResult =
  ## Run one case through the provider.
  ##
  ## The subset decision is made first, from the schema alone. Only then
  ## is the provider asked for a verdict.
  let subset = judge(c)
  let outcome = provider(c)
  var note = $outcome.verdict
  if outcome.message.len > 0:
    note.add ": " & outcome.message
  CaseResult(
    identity: c.identity,
    expectedValid: c.expectedValid,
    observed: outcome.verdict,
    inSupportedSubset: subset.reason.len == 0,
    exclusionReason: subset.reason,
    authorisedLimitation: false,
    optional: c.optional,
    inDenominator: false,
    observedNote: note)

proc runCorpus*(corpus: Corpus, provider: VerdictProvider,
                judge: SubsetJudge, scope: Scope,
                exclusions: seq[Exclusion] = @[]): QualificationReport =
  ## Run every case of the corpus through the provider and classify the
  ## results.
  var report: QualificationReport
  ##
  ## The exclusions are the authorised ones: they are matched by the exact
  ## case identity, and each carries its reason. An exclusion that names a
  ## case the corpus does not contain is a defect in the exclusion list,
  ## and it is reported as an invalid-evidence case.
  var authorised: Table[string, string]
  for e in exclusions:
    authorised[e.identity] = e.reason

  var seen: HashSet[string]
  for c in corpus.cases:
    var caseResult = runCase(c, provider, judge)
    if authorised.hasKey(c.identity):
      caseResult.authorisedLimitation = true
      caseResult.exclusionReason = authorised[c.identity]
    if c.optional and caseResult.exclusionReason.len == 0:
      caseResult.exclusionReason =
        "the case belongs to the optional part of the corpus"
    if c.representationLimited:
      caseResult.representationLimited = true
      if caseResult.exclusionReason.len == 0:
        caseResult.exclusionReason = c.representationReason
    caseResult.outsideSupportedSubset = not caseResult.inSupportedSubset
    # A wrong answer counts as a failure when the case lies inside the
    # supported subset. Outside the subset it is an exact limitation of
    # the upstream library, which is recorded rather than failed.
    caseResult.countedAsFailure = caseResult.inSupportedSubset
    # The denominator is decided by the corpus structure and by the
    # supported subset, never by the implementation's answer.
    caseResult.inDenominator = (not c.optional) and
      (not caseResult.representationLimited) and
      (not caseResult.authorisedLimitation) and
      (scope == scUpstream or caseResult.inSupportedSubset)
    seen.incl c.identity
    report.results.add caseResult

  # An exclusion that names no case in the corpus is stale. It is not
  # silently ignored: the corpus and the limitation list must agree.
  for e in exclusions:
    if e.identity notin seen:
      report.results.add CaseResult(
        identity: e.identity,
        expectedValid: false,
        observed: ovError,
        inSupportedSubset: true,
        exclusionReason: "the authorised limitation names no case in the corpus",
        authorisedLimitation: false,
        optional: true,
        inDenominator: false,
        observedNote: "the authorised limitation is stale")

  for r in report.results:
    if not r.inSupportedSubset:
      report.unsupported.add r.identity
  report.counts = countsOf(report.results)
  report.denominator = denominatorOf(report.results)
  report.passed = passesOf(report.results)
  report.verdict = verdictOf(report.results)
  for r in report.results:
    if not r.inDenominator:
      var reason = r.exclusionReason
      if reason.len == 0:
        reason = "the case is excluded from the denominator"
      report.exclusions.add Exclusion(identity: r.identity, reason: reason)
      if report.exclusionCounts.hasKey(reason):
        report.exclusionCounts[reason] += 1
      else:
        report.exclusionCounts[reason] = 1
  report

proc mandatoryResults*(report: QualificationReport): seq[CaseResult] =
  ## The mandatory cases of the report, in corpus order.
  for r in report.results:
    if not r.optional:
      result.add r

proc optionalResults*(report: QualificationReport): seq[CaseResult] =
  ## The optional cases of the report, in corpus order.
  for r in report.results:
    if r.optional:
      result.add r

proc failures*(report: QualificationReport): seq[CaseResult] =
  ## The cases that failed the qualification.
  failuresOf(report.results)

proc upstreamLimitations*(report: QualificationReport): seq[CaseResult] =
  ## The cases that lie outside the supported subset and were answered
  ## wrongly.
  ##
  ## These are the exact limitations of the upstream library relative to
  ## Ironkeeper's supported subset. They are recorded with their identity
  ## and their expected and observed verdicts, not hidden.
  for r in report.results:
    if r.inDenominator and r.outsideSupportedSubset and
       classificationOf(r) in {clFalseAcceptance, clFalseRejection,
                               clExecutionError}:
      result.add r

proc unauthorisedExclusions*(report: QualificationReport): seq[CaseResult] =
  ## The exclusions that were not authorised.
  unauthorisedExclusionsOf(report.results)

proc renderSummary*(report: QualificationReport): seq[string] =
  ## A stable rendering of the report.
  result = @["denominator=" & $report.denominator,
             "passed=" & $report.passed,
             "failed=" & $failures(report).len,
             "unauthorised_exclusions=" & $unauthorisedExclusions(report).len]
  result.add renderCounts(report.counts)
  result.add "verdict=" & (if report.verdict == qvPass: "PASS" else: "FAIL")
