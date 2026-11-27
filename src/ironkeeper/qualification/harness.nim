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
## ## The two measurements
##
## The harness produces two *separate* measurements, and they are never
## conflated:
##
##   * the **raw upstream** measurement drives the upstream library over
##     the whole mandatory corpus. It is a measurement of the *library*.
##     A wrong answer to a mandatory case is a failure of that
##     measurement, whether or not Ironkeeper supports the schema feature
##     the case exercises.
##   * the **adapter** measurement drives the Ironkeeper adapter over the
##     supported subset. It is a measurement of *Ironkeeper*. A case
##     outside the subset is excluded, with its reason recorded.
##
## A known upstream limitation may be *recorded and accepted* for the
## product qualification when it lies outside the required subset. It is
## never reported as a successful raw conformance case: it is counted as
## a raw failure, and it is listed as an accepted limitation.
##
## ## The counting invariant
##
## For every measurement:
##
## ```text
## denominator = passed + failed
## ```
##
## A case that is excluded is neither a pass nor a failure, and it never
## contributes to the denominator. A measurement with an empty
## denominator establishes nothing and cannot be a PASS.
##
## ## The provider seam
##
## The harness does not know how a verdict is produced. It asks a
## *provider*. The production providers drive the upstream validator and
## the Ironkeeper adapter; the controlled providers exist so that the
## harness's own counting and terminal-verdict logic can be tested against
## verdicts that are wrong in a known way. A harness whose oracle cannot
## be shown to reject a wrong answer is not an oracle.
##
## ## Exclusions
##
## An exclusion is only honoured when it is **authorised** and valid:
##
##   * the exact case identity is named by an authorised-limitation
##     entry, with a reason;
##   * the entry is not stale (it names a case of the corpus);
##   * the entry is not duplicated;
##   * the entry has a reason; and
##   * the case lies *outside* the required subset, because an exclusion
##     of a supported case would hide a defect.
##
## A stale, duplicated, malformed or unauthorised entry is unusable
## evidence: it fails the qualification rather than being ignored.

import std/[tables, sets]

from ironkeeper/qualification/verdict import CaseResult, ObservedVerdict,
  Classification, ClassificationCounts, classify, classificationOf, countsOf,
  denominatorOf, passesOf, failuresOf, unauthorisedExclusionsOf,
  invalidEvidenceOf, verdictOf, isFailure, clUnsupportedPolicy,
  clKnownLimitation, QualificationVerdict, renderCounts
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
      ## corpus. A wrong answer is a failure of that measurement, even
      ## when the case lies outside Ironkeeper's supported subset.
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
    ## The result of one measurement.
    results*: seq[CaseResult]
      ## Every case, in corpus order.
    counts*: ClassificationCounts
      ## The per-class counts.
    denominator*: int
      ## The number of cases that count towards the measurement. It is
      ## always `passed + failed`.
    passed*: int
      ## The number of in-denominator cases that were answered correctly.
    failed*: int
      ## The number of in-denominator cases that were answered wrongly.
      ## `denominator = passed + failed` holds for every measurement.
    verdict*: QualificationVerdict
      ## The terminal verdict.
    exclusions*: seq[Exclusion]
      ## The excluded cases, with their reasons.
    exclusionCounts*: Table[string, int]
      ## The number of exclusions, grouped by the reason they were
      ## excluded. The grouping is by the exact reason text, so that two
      ## different reasons are never merged.
    unsupported*: seq[string]
      ## The identities of the cases the harness placed outside the
      ## supported subset.
    acceptedLimitations*: seq[string]
      ## The identities of the raw failures that an authorised
      ## limitation entry permits the product qualification to accept.

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

proc invalidEvidenceResult(identity, reason: string): CaseResult =
  ## A case whose evidence is unusable.
  CaseResult(identity: identity, expectedValid: false, observed: ovError,
             inSupportedSubset: true, exclusionReason: reason,
             authorisedLimitation: false, optional: true,
             inDenominator: false, invalidEvidence: true,
             observedNote: reason)

proc runCorpus*(corpus: Corpus, provider: VerdictProvider,
                judge: SubsetJudge, scope: Scope,
                exclusions: seq[Exclusion] = @[]): QualificationReport =
  ## Run every case of the corpus through the provider and classify the
  ## results.
  var report: QualificationReport
  ##
  ## The exclusions are the authorised ones: they are matched by the exact
  ## case identity, and each carries a reason. An exclusion that names a
  ## case the corpus does not contain, that is duplicated, that carries no
  ## reason, or that would exclude a case inside the supported subset is
  ## a defect in the exclusion authority, and it is reported as unusable
  ## evidence: it fails the qualification.
  var authorised: Table[string, string]
  for e in exclusions:
    if e.identity.len == 0:
      report.results.add invalidEvidenceResult(
        "(no identity)",
        "the exclusion entry names no case")
      continue
    if e.reason.len == 0:
      report.results.add invalidEvidenceResult(
        e.identity, "the exclusion entry carries no reason")
      continue
    if authorised.hasKey(e.identity):
      report.results.add invalidEvidenceResult(
        e.identity, "the exclusion entry is duplicated")
      continue
    authorised[e.identity] = e.reason

  var seen: HashSet[string]
  for c in corpus.cases:
    var caseResult = runCase(c, provider, judge)
    if authorised.hasKey(c.identity) and caseResult.inSupportedSubset:
      # The exclusion names a case inside the required subset. Such an
      # exclusion would hide a defect of the supported subset, so it is
      # unauthorised and the qualification fails.
      caseResult.authorisedLimitation = false
      caseResult.exclusionReason = "the exclusion entry names a case inside " &
        "the required subset"
      report.results.add invalidEvidenceResult(
        c.identity, "the exclusion entry names a case inside the required " &
                    "subset")
      seen.incl c.identity
      continue
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
    # A wrong answer counts as a failure of the measurement. The
    # measurement decides what it covers; the answer decides whether it
    # was right.
    caseResult.countedAsFailure = true
    # The classification is derived before the denominator is decided, so
    # that an excluded classification can never sit in the denominator.
    let classification = classificationOf(caseResult)
    # The denominator is decided by the corpus structure and by the
    # measurement, never by the implementation's answer.
    var inDenominator = (not c.optional) and
      (not caseResult.representationLimited) and
      (scope == scUpstream or caseResult.inSupportedSubset)
    if classification in {clUnsupportedPolicy, clKnownLimitation}:
      inDenominator = false
    caseResult.inDenominator = inDenominator
    seen.incl c.identity
    report.results.add caseResult

  # An exclusion that names no case in the corpus is stale. It is not
  # silently ignored: the corpus and the limitation list must agree.
  for e in exclusions:
    if e.identity.len > 0 and e.identity notin seen:
      report.results.add invalidEvidenceResult(
        e.identity, "the authorised limitation names no case in the corpus")

  for r in report.results:
    if not r.inSupportedSubset:
      report.unsupported.add r.identity
  report.counts = countsOf(report.results)
  report.denominator = denominatorOf(report.results)
  report.passed = passesOf(report.results)
  report.failed = failuresOf(report.results).len
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
    # A raw failure that an authorised limitation covers is *recorded*,
    # and it is accepted for the product qualification only when it lies
    # outside the required subset.
    if r.inDenominator and r.authorisedLimitation and
       r.outsideSupportedSubset and r.countedAsFailure and
       isFailure(classificationOf(r)):
      report.acceptedLimitations.add r.identity
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

proc optionalCounts*(report: QualificationReport): tuple[total: int,
                                                      passed: int,
                                                      failed: int] =
  ## The observed results of the optional corpus.
  ##
  ## The optional cases do not count towards the denominator of the
  ## measurement, but they were *observed*: the harness ran them and
  ## compared the answer with the expected one. Their results are
  ## reported separately, so that an optional case is never described as
  ## a measured success it did not achieve, and never hidden.
  for r in report.results:
    if not r.optional:
      continue
    inc result.total
    let c = classificationOf(r)
    if c in {clCorrectAcceptance, clCorrectRejection}:
      inc result.passed
    elif c in {clFalseAcceptance, clFalseRejection, clExecutionError}:
      inc result.failed
  # The remaining optional cases were excluded from the measurement: they
  # lie outside the supported subset, or they carry a number the
  # document model cannot represent. They are neither a pass nor a
  # failure, and they are reported as excluded.

proc failures*(report: QualificationReport): seq[CaseResult] =
  ## The cases that failed the measurement.
  failuresOf(report.results)

proc invalidEvidence*(report: QualificationReport): seq[CaseResult] =
  ## The entries whose evidence is unusable.
  invalidEvidenceOf(report.results)

proc upstreamLimitations*(report: QualificationReport): seq[CaseResult] =
  ## The cases that lie outside the supported subset and were answered
  ## wrongly.
  ##
  ## These are the exact limitations of the upstream library relative to
  ## Ironkeeper's supported subset. They are recorded with their identity
  ## and their expected and observed verdicts, not hidden.
  for r in report.results:
    if r.inDenominator and r.outsideSupportedSubset and
       isFailure(classificationOf(r)):
      result.add r

proc unauthorisedExclusions*(report: QualificationReport): seq[CaseResult] =
  ## The exclusions that were not authorised.
  unauthorisedExclusionsOf(report.results)

proc productVerdict*(raw, adapter: QualificationReport): QualificationVerdict =
  ## The verdict of the *product* qualification.
  ##
  ## The product qualification is Ironkeeper, not the upstream library.
  ## It therefore passes when:
  ##
  ##   * the adapter measurement passed, and
  ##   * every raw failure lies outside the required subset and is
  ##     covered by an authorised limitation entry.
  ##
  ## A raw failure inside the required subset is a failure of the
  ## product: the library is wrong about something Ironkeeper claims to
  ## support.
  if adapter.verdict != qvPass:
    return qvFail
  if raw.denominator == 0 or adapter.denominator == 0:
    return qvFail
  for f in failures(raw):
    if not f.outsideSupportedSubset:
      return qvFail
    if not f.authorisedLimitation:
      return qvFail
  for e in invalidEvidence(raw) & invalidEvidence(adapter):
    discard e
  if invalidEvidence(raw).len > 0 or invalidEvidence(adapter).len > 0:
    return qvFail
  qvPass

proc renderSummary*(report: QualificationReport): seq[string] =
  ## A stable rendering of the report.
  result = @["denominator=" & $report.denominator,
             "passed=" & $report.passed,
             "failed=" & $report.failed,
             "invalid_evidence=" & $invalidEvidence(report).len,
             "unauthorised_exclusions=" & $unauthorisedExclusions(report).len]
  result.add renderCounts(report.counts)
  result.add "verdict=" & (if report.verdict == qvPass: "PASS" else: "FAIL")
