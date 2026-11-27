## The classification and counting rules of the validator qualification.
##
## ## Why this module exists
##
## A qualification harness is only as trustworthy as its oracle. A harness
## that counts "the validator returned *something*" as a pass measures
## nothing: a validator that accepts every document and one that rejects
## every document score identically. The previous Ironkeeper harness had
## exactly that defect, and reported 1337/1337 mandatory conformance on the
## strength of it.
##
## This module is the oracle. It compares the **observed** verdict with the
## **expected** verdict and assigns each case exactly one classification.
##
## ## The classifications
##
## | Classification | Meaning | In the denominator? |
## |---|---|---|
## | `clCorrectAcceptance` | expected valid, observed valid | yes, as a pass |
## | `clCorrectRejection` | expected invalid, observed invalid | yes, as a pass |
## | `clFalseAcceptance` | expected invalid, observed valid | yes, as a failure |
## | `clFalseRejection` | expected valid, observed invalid | yes, as a failure |
## | `clExecutionError` | the validator raised instead of answering | yes, as a failure |
## | `clUnsupportedPolicy` | the case is outside the supported subset | no, excluded |
## | `clKnownLimitation` | an authorised, recorded limitation | no, excluded |
## | `clInvalidEvidence` | the test evidence itself is unusable | yes, as a failure |
##
## ## The counting invariant
##
## For every reported measurement:
##
## ```text
## denominator = passed + failed
## ```
##
## The denominator is the number of cases that count towards the
## measurement. Every one of them is either answered correctly (a pass) or
## answered incorrectly (a failure). A case that is excluded is not in
## the denominator at all: it is neither a pass nor a failure, and it is
## reported separately with its reason.
##
## A measurement with an empty denominator establishes nothing. It cannot
## be a PASS.
##
## An exclusion is only honoured when it is **authorised**. A case may be
## excluded from the denominator only when the harness itself determined
## that the case is outside the supported subset, or when the exact case
## identity appears in the repository's authorised-limitation list. The
## implementation under test can never exclude its own case: an unsupported
## answer for an in-subset case is a failure, not an exclusion.
##
## ## Determinism
##
## The module is a pure function of the case results it is given. It
## performs no I/O, reads no environment and holds no state, so the same
## results always produce the same counts and the same terminal verdict.

type
  Classification* = enum
    ## The classification of one qualification case.
    clCorrectAcceptance
    clCorrectRejection
    clFalseAcceptance
    clFalseRejection
    clExecutionError
    clUnsupportedPolicy
    clKnownLimitation
    clInvalidEvidence

  ObservedVerdict* = enum
    ## What the implementation under test actually did.
    ovAccepted
      ## The implementation answered "valid".
    ovRejected
      ## The implementation answered "invalid".
    ovError
      ## The implementation raised instead of answering.
    ovUnsupported
      ## The implementation declared the case outside its supported subset.

  CaseResult* = object
    ## The result of one qualification case.
    identity*: string
      ## The exact, stable identity of the case. It names the corpus
      ## file, the group and the test, so that a failure can be looked up.
    expectedValid*: bool
      ## The verdict the corpus expects.
    observed*: ObservedVerdict
      ## The verdict the implementation produced.
    inSupportedSubset*: bool
      ## Whether the harness determined that the case is inside the
      ## supported subset. The harness decides this from the schema
      ## document; the implementation under test never does.
    exclusionReason*: string
      ## The reason the case is excluded, when it is excluded. It is
      ## recorded verbatim so that the exclusion is auditable.
    authorisedLimitation*: bool
      ## Whether the exact case identity is listed in the repository's
      ## authorised-limitation list.
      ##
      ## The flag does not remove a case from a measurement by itself and
      ## it never turns a failure into a pass. A known upstream
      ## limitation is still a wrong answer of the library. The flag is
      ## the *authority* that lets the qualification accept such a
      ## failure, and it is only honoured when the entry itself is valid.
    invalidEvidence*: bool
      ## The evidence about this case is unusable.
      ##
      ## A stale, duplicated or malformed exclusion entry, or an entry
      ## that names no case of the corpus at all, produces such a case.
      ## It is never a measurement, so it never contributes to the
      ## denominator, and it fails the qualification.
    representationLimited*: bool
      ## Whether the case carries a number that the document model cannot
      ## represent exactly. Such a case cannot decide anything about a
      ## validator, so it is a known limitation of the test harness and is
      ## classified as such rather than as a validator failure.
    optional*: bool
      ## Whether the case belongs to the optional part of the corpus. The
      ## membership is derived from the corpus structure, not from the
      ## implementation.
    inDenominator*: bool
      ## Whether the case counts towards the qualification. A case counts
      ## when it is mandatory, lies inside the supported subset, and is
      ## neither representation-limited nor an authorised limitation.
    observedNote*: string
      ## A human-readable note about what was observed. It never
      ## influences the classification; it exists so that an excluded
      ## case still records what the implementation actually did.
    outsideSupportedSubset*: bool
      ## Whether the harness determined that the case lies outside the
      ## supported subset, from the schema document alone.
    countedAsFailure*: bool
      ## Whether a wrong answer to this case is a failure of the
      ## measurement.
      ##
      ## The flag is set by the harness from the *measurement*, not from
      ## the case. In the **raw upstream** measurement every mandatory
      ## case counts: the raw measurement is a measurement of the
      ## upstream library, and a wrong answer to a case the library
      ## claims to support is a wrong answer, whatever Ironkeeper's
      ## supported subset happens to be.
      ##
      ## In the **adapter** measurement only the cases inside the
      ## supported subset count, because the adapter is only measured
      ## over the subset it supports.

  ClassificationCounts* = object
    ## The number of cases in each classification.
    correctAcceptance*: int
    correctRejection*: int
    falseAcceptance*: int
    falseRejection*: int
    executionError*: int
    unsupportedPolicy*: int
    knownLimitation*: int
    invalidEvidence*: int

  QualificationVerdict* = enum
    ## The terminal verdict of a qualification run.
    qvPass
      ## Every in-subset case was answered correctly and every exclusion
      ## was authorised.
    qvFail
      ## At least one in-subset case was answered incorrectly, raised, or
      ## excluded without authorisation.

proc classify*(r: CaseResult): Classification =
  ## The classification of one case.
  ##
  ## The order of the rules matters. A representation-limited case is a
  ## limitation of the test harness, not of the validator, so it is
  ## classified before the verdict is even considered. An authorised
  ## limitation is a recorded, repository-owned exclusion. A case outside
  ## the supported subset is excluded with its reason. Only then is the
  ## observed verdict compared with the expected one.
  ##
  ## `inSupportedSubset` is the *harness's* determination. It is the only
  ## thing that can authorise an exclusion, and it is deliberately not
  ## derived from the observed verdict.
  ##
  ## An **authorised limitation** does not change the classification of
  ## the answer. A wrong answer stays a wrong answer: it is counted as a
  ## failure of the raw measurement, and it is never reported as a
  ## successful conformance case. The authorisation is the authority that
  ## lets the *product* qualification accept such a failure when it lies
  ## outside the required subset.
  if r.invalidEvidence:
    # The evidence about this case is unusable. It is not a measurement,
    # and it is never a pass.
    return clInvalidEvidence
  if r.representationLimited:
    # A representation-limited case is a limitation of the *harness*: the
    # document model cannot carry the number, so the case cannot decide
    # anything about a validator. It is excluded, and it is reported.
    return clKnownLimitation
  if r.observed == ovError:
    return clExecutionError
  if r.observed == ovUnsupported:
    if r.inSupportedSubset:
      # The implementation refused a case the harness considers
      # supported. That is a defect, not an exclusion.
      return clExecutionError
    # The implementation refused a case that is demonstrably outside the
    # documented supported subset. The exclusion is authorised, and its
    # reason is recorded.
    return clUnsupportedPolicy
  if r.expectedValid:
    if r.observed == ovAccepted:
      return clCorrectAcceptance
    return clFalseRejection
  if r.observed == ovRejected:
    return clCorrectRejection
  return clFalseAcceptance

proc classificationOf*(r: CaseResult): Classification =
  ## The classification of a case result.
  classify(r)

proc countsOf*(results: seq[CaseResult]): ClassificationCounts =
  ## The number of cases in each classification.
  ##
  ## Only the in-denominator cases are counted. An excluded case is
  ## reported separately, with its identity and its reason.
  var counts: ClassificationCounts
  for r in results:
    if not r.inDenominator:
      continue
    case classificationOf(r)
    of clCorrectAcceptance: inc counts.correctAcceptance
    of clCorrectRejection: inc counts.correctRejection
    of clFalseAcceptance: inc counts.falseAcceptance
    of clFalseRejection: inc counts.falseRejection
    of clExecutionError: inc counts.executionError
    of clUnsupportedPolicy: inc counts.unsupportedPolicy
    of clKnownLimitation: inc counts.knownLimitation
    of clInvalidEvidence: inc counts.invalidEvidence
  counts

proc isFailure*(c: Classification): bool =
  ## Whether a classification is a failure of the qualification.
  c in {clFalseAcceptance, clFalseRejection, clExecutionError,
        clInvalidEvidence}

proc isExclusion*(c: Classification): bool =
  ## Whether a classification removes the case from the denominator.
  c in {clUnsupportedPolicy, clKnownLimitation}

proc denominatorOf*(results: seq[CaseResult]): int =
  ## The number of cases that count towards the qualification.
  ##
  ## An excluded case does not count. Every other case does, whether it
  ## passed or failed.
  var n = 0
  for r in results:
    if r.inDenominator:
      inc n
  n

proc passesOf*(results: seq[CaseResult]): int =
  ## The number of in-denominator cases that were answered correctly.
  var n = 0
  for r in results:
    let c = classificationOf(r)
    if r.inDenominator and
       c in {clCorrectAcceptance, clCorrectRejection}:
      inc n
  n

proc failuresOf*(results: seq[CaseResult]): seq[CaseResult] =
  ## The cases that failed the measurement, in input order.
  ##
  ## Only in-denominator cases can fail. An excluded case has already been
  ## accounted for, with its reason.
  for r in results:
    if r.inDenominator and r.countedAsFailure and
       isFailure(classificationOf(r)):
      result.add r

proc invalidEvidenceOf*(results: seq[CaseResult]): seq[CaseResult] =
  ## The cases whose evidence is unusable, in input order.
  ##
  ## An unusable evidence entry is never a measurement, so it never
  ## contributes to the denominator. It nevertheless fails the
  ## qualification: a stale, duplicated or malformed exclusion entry
  ## means that the exclusion authority itself cannot be trusted.
  for r in results:
    if r.invalidEvidence:
      result.add r

proc unauthorisedExclusionsOf*(results: seq[CaseResult]): seq[CaseResult] =
  ## The cases that were excluded without authorisation.
  ##
  ## A case is excluded because the harness determined that it lies outside
  ## the supported subset, or because its exact identity is listed in the
  ## authorised-limitation list. Anything else that the implementation
  ## tried to exclude is reported here and fails the qualification.
  for r in results:
    let c = classificationOf(r)
    if c == clUnsupportedPolicy and r.inSupportedSubset and
       not r.authorisedLimitation:
      result.add r

proc verdictOf*(results: seq[CaseResult]): QualificationVerdict =
  ## The terminal verdict of a measurement.
  ##
  ## The measurement passes only when:
  ##
  ##   * every in-denominator case was answered correctly;
  ##   * no case raised instead of answering;
  ##   * no evidence was unusable;
  ##   * every exclusion was authorised; and
  ##   * the denominator is not empty.
  ##
  ## A measurement with an empty denominator establishes nothing: it
  ## measured no case at all, so it cannot establish a PASS.
  if failuresOf(results).len > 0:
    return qvFail
  if unauthorisedExclusionsOf(results).len > 0:
    return qvFail
  if invalidEvidenceOf(results).len > 0:
    return qvFail
  if denominatorOf(results) == 0:
    return qvFail
  qvPass

proc renderCounts*(c: ClassificationCounts): seq[string] =
  ## A stable, one-line-per-class rendering of the counts.
  result = @[
    "correct_acceptance=" & $c.correctAcceptance,
    "correct_rejection=" & $c.correctRejection,
    "false_acceptance=" & $c.falseAcceptance,
    "false_rejection=" & $c.falseRejection,
    "execution_error=" & $c.executionError,
    "unsupported_policy=" & $c.unsupportedPolicy,
    "known_limitation=" & $c.knownLimitation,
    "invalid_evidence=" & $c.invalidEvidence,
  ]
