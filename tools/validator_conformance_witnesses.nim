## The non-vacuity witnesses of the validator conformance harness.
##
## ## Why this program exists
##
## A qualification harness is only as trustworthy as its oracle. A harness
## that counts "the validator returned *something*" as a pass measures
## nothing: a validator that accepts every document and one that rejects
## every document score identically. The previous Ironkeeper harness had
## exactly that defect, and it reported 1337/1337 mandatory conformance on
## the strength of it.
##
## This program therefore drives the **production** counting and
## terminal-verdict logic of the harness with controlled verdict
## providers whose behaviour is known:
##
## | Provider | Expected qualification verdict |
## |---|---|
## | always accepts | FAIL |
## | always rejects | FAIL |
## | inverted verdict | FAIL |
## | raises an execution error | FAIL |
## | correct verdict | PASS |
## | verdict for an explicitly unsupported case | PASS, with the unsupported |
## | | case explicitly classified |
##
## The witnesses exercise the production code path: the same
## `runCorpus`, the same classification, the same counts and the same
## terminal verdict that the real qualification uses.
##
## ## Usage
##
## ```sh
##   nim r tools/validator_conformance_witnesses.nim --corpus <dir>
## ```
##
## The corpus must contain both valid and invalid instances, so that an
## always-accepting provider and an always-rejecting provider are both
## wrong.

import std/[os]

from ironkeeper/qualification/corpus import readCorpus, Corpus, CorpusCase
from ironkeeper/qualification/harness import runCorpus, failures,
  unauthorisedExclusions, invalidEvidence, upstreamLimitations, productVerdict,
  Exclusion, Scope, scUpstream, scAdapter
from ironkeeper/qualification/providers import controlledProvider,
  controlledProviderByName, subsetJudge, ControlledProviderKind
from ironkeeper/qualification/verdict import classificationOf,
  clUnsupportedPolicy, clKnownLimitation, clInvalidEvidence,
  clFalseAcceptance, clFalseRejection, qvPass, qvFail

const
  ExpectedFailing* = ["always-accept", "always-reject", "inverted", "error"]
    ## The providers whose wrong answers must fail the qualification.

  ExpectedPassing* = ["correct", "unsupported"]
    ## The providers whose answers must pass the qualification.

proc optionValue(name: string, default = ""): string =
  let params = commandLineParams()
  var i = 0
  while i < params.len:
    if params[i] == name and i + 1 < params.len:
      return params[i + 1]
    inc i
  default


proc firstOutsideSubset(corpus: Corpus): string =
  ## The identity of the first case that lies outside the supported
  ## subset.
  ##
  ## The decision is made by the production judge, from the schema
  ## document alone.
  let judge = subsetJudge()
  for c in corpus.cases:
    if judge(c).reason.len > 0:
      return c.identity
  ""

proc main() =
  let corpusDir = optionValue("--corpus")
  if corpusDir.len == 0:
    stderr.writeLine("usage: nim r tools/validator_conformance_witnesses.nim --corpus <dir>")
    quit(2)

  let corpus = readCorpus(corpusDir)
  if corpus.problems.len > 0:
    for p in corpus.problems:
      echo "corpus_problem: ", p.file, ": ", p.message
    quit(1)
  if corpus.cases.len == 0:
    echo "the witness corpus is empty"
    quit(1)

  # The corpus must contain both valid and invalid instances, or the
  # witnesses would not discriminate.
  var valid = 0
  var invalid = 0
  for c in corpus.cases:
    if c.expectedValid: inc valid else: inc invalid
  echo "witness_corpus_cases=", corpus.cases.len
  echo "witness_corpus_valid=", valid
  echo "witness_corpus_invalid=", invalid
  if valid == 0 or invalid == 0:
    echo "the witness corpus must contain both valid and invalid instances"
    quit(1)

  var failed = 0

  proc check(label: string, kind: ControlledProviderKind, mustPass: bool) =
    let report = runCorpus(corpus, controlledProvider(kind), subsetJudge(),
                           scAdapter)
    let passed = report.verdict == qvPass
    echo "provider=", label,
         " verdict=", (if passed: "PASS" else: "FAIL"),
         " denominator=", report.denominator,
         " passed=", report.passed,
         " failed=", failures(report).len,
         " unauthorised_exclusions=", unauthorisedExclusions(report).len
    if passed != mustPass:
      echo "FAIL: the provider '", label, "' was expected to ",
           (if mustPass: "pass" else: "fail"), " the qualification"
      failed += 1
      return
    if not mustPass:
      # A failing provider must be detected by a *failure*, not merely by
      # a nonzero exit status.
      if failures(report).len == 0:
        echo "FAIL: the provider '", label,
             "' failed the qualification without a recorded failure"
        failed += 1
        return
    echo "ok: the provider '", label, "' ",
         (if mustPass: "passed" else: "failed"), " as required"

  for name in ExpectedFailing:
    check(name, controlledProviderByName(name), false)
  for name in ExpectedPassing:
    check(name, controlledProviderByName(name), true)

  # The unsupported case must receive an explicit classification, not a
  # conformance pass and not a silent exclusion.
  let report = runCorpus(corpus, controlledProvider(cpUnsupported),
                         subsetJudge(), scAdapter)
  var unsupportedCount = 0
  var limitationCount = 0
  for r in report.results:
    let c = classificationOf(r)
    if c == clUnsupportedPolicy:
      inc unsupportedCount
      echo "unsupported_case: ", r.identity, " reason=", r.exclusionReason
    elif c == clKnownLimitation:
      inc limitationCount
  echo "unsupported_classified=", unsupportedCount
  echo "known_limitation_classified=", limitationCount
  if unsupportedCount == 0:
    echo "FAIL: the unsupported case was not given an explicit classification"
    failed += 1
  else:
    echo "ok: the unsupported case received an explicit classification"

  # --- the required witnesses of the accounting ------------------------------
  #
  # The witnesses above show that a wrong answer is detected. The
  # witnesses below show that the *accounting* is coherent: that a raw
  # failure outside the adapter subset is not conflated with an adapter
  # result, that an empty denominator establishes nothing, and that an
  # invalid exclusion entry fails the qualification.
  echo ""
  echo "=== the accounting witnesses ==="

  # (1) A wrong raw answer outside the adapter subset.
  #
  # The raw measurement covers the whole mandatory corpus, so a wrong
  # answer there is a raw failure, even when the case lies outside the
  # adapter's supported subset. It is not a success.
  let wrongRaw = controlledProvider(cpWrongOutsideSubset)
  let rawWrong = runCorpus(corpus, wrongRaw, subsetJudge(), scUpstream)
  let rawWrongFailures = failures(rawWrong)
  echo "raw_wrong_outside_subset_failures=", rawWrongFailures.len
  if rawWrongFailures.len == 0:
    echo "FAIL: a wrong raw answer outside the adapter subset was not counted"
    failed += 1
  elif rawWrong.denominator != rawWrong.passed + rawWrong.failed:
    echo "FAIL: the raw denominator is not passed + failed"
    failed += 1
  else:
    echo "ok: a wrong raw answer outside the adapter subset is a raw failure"

  # (2) The adapter refuses a case inside the supported subset.
  #
  # A refusal of a supported case is a defect, not an exclusion.
  let adapterWrong = runCorpus(corpus, controlledProvider(cpRefuseSupported),
                                subsetJudge(), scAdapter)
  echo "adapter_refuses_supported_failures=", failures(adapterWrong).len
  if failures(adapterWrong).len == 0:
    echo "FAIL: the adapter's refusal of a supported case was not counted"
    failed += 1
  else:
    echo "ok: the adapter's refusal of a supported case is a failure"

  # (3) A stale exclusion naming a case the corpus does not contain.
  #
  # The exclusion authority must agree with the corpus. A stale entry is
  # unusable evidence, and it fails the qualification.
  let stale = runCorpus(corpus, controlledProvider(cpCorrect), subsetJudge(),
                        scAdapter, @[Exclusion(identity: "no-such-case#0.0",
                                               reason: "a stale entry")])
  echo "stale_exclusion_invalid_evidence=", invalidEvidence(stale).len
  if invalidEvidence(stale).len == 0:
    echo "FAIL: a stale exclusion did not produce invalid evidence"
    failed += 1
  elif stale.verdict == qvPass:
    echo "FAIL: a stale exclusion did not fail the qualification"
    failed += 1
  else:
    echo "ok: a stale exclusion fails the qualification"

  # (4) An empty effective qualification denominator.
  #
  # A measurement that measured no case establishes nothing. It cannot
  # establish a PASS.
  # The optional corpus carries only optional cases, and an optional case
  # never counts towards the denominator. The effective denominator of a
  # measurement over it is therefore empty.
  let optionalCorpus = readCorpus(corpusDir & "/../optional-corpus")
  let judge = subsetJudge()
  let empty = runCorpus(optionalCorpus, controlledProvider(cpCorrect),
                        subsetJudge(), scAdapter)
  echo "empty_denominator=", empty.denominator,
       " optional_cases=", optionalCorpus.cases.len,
       " optional_flags=", (block:
  var n = 0
  for c in optionalCorpus.cases:
    if c.optional: inc n
  n)
  if empty.denominator != 0:
    echo "FAIL: the effective denominator was not empty"
    failed += 1
  elif empty.verdict == qvPass:
    echo "FAIL: an empty denominator established a PASS"
    failed += 1
  else:
    echo "ok: an empty denominator cannot establish a PASS"

  # (5) A correct mixed answer set.
  #
  # The counts of a correct measurement add up: the denominator is the
  # number of cases that count, and the passes and the failures partition
  # it.
  let mixed = runCorpus(corpus, controlledProvider(cpCorrect), subsetJudge(),
                        scAdapter)
  echo "mixed_denominator=", mixed.denominator,
       " passed=", mixed.passed, " failed=", mixed.failed
  if mixed.denominator != mixed.passed + mixed.failed:
    echo "FAIL: the denominator is not passed + failed"
    failed += 1
  elif mixed.failed != 0:
    echo "FAIL: a correct provider produced a failure"
    failed += 1
  else:
    echo "ok: a correct measurement satisfies denominator = passed + failed"

  # (6) An explicitly authorised policy exclusion.
  #
  # An exclusion that names a real case outside the required subset, with
  # a reason, is honoured: the case leaves the denominator, and it is
  # reported with its reason rather than silently dropped.
  let outside = firstOutsideSubset(corpus)
  if outside.len == 0:
    echo "FAIL: the witness corpus has no case outside the supported subset"
    failed += 1
  else:
    let authorised = runCorpus(corpus, controlledProvider(cpCorrect),
                               subsetJudge(), scAdapter,
                               @[Exclusion(identity: outside,
                                           reason: "the case exercises a " &
                                                   "feature outside the " &
                                                   "supported subset")])
    echo "authorised_exclusion_exclusions=", authorised.exclusions.len
    var named = false
    for e in authorised.exclusions:
      if e.identity == outside and e.reason.len > 0:
        named = true
    if not named:
      echo "FAIL: the authorised exclusion was not reported with its reason"
      failed += 1
    elif unauthorisedExclusions(authorised).len != 0:
      echo "FAIL: an authorised exclusion was reported as unauthorised"
      failed += 1
    else:
      echo "ok: an authorised policy exclusion is honoured and reported"

  # The product qualification accepts a raw failure outside the required
  # subset only when an authorised limitation covers it.
  if outside.len > 0:
    var limitationEntries: seq[Exclusion] = @[]
    for c in corpus.cases:
      if judge(c).reason.len > 0:
        limitationEntries.add Exclusion(
          identity: c.identity,
          reason: "a known upstream limitation outside the required subset")
    let rawWithLimitation = runCorpus(corpus, wrongRaw, subsetJudge(),
                                      scUpstream, limitationEntries)
    let accepted = productVerdict(rawWithLimitation, mixed)
    echo "product_verdict_with_limitation=",
         (if accepted == qvPass: "PASS" else: "FAIL")
    if accepted != qvPass:
      echo "FAIL: an authorised upstream limitation was not accepted"
      failed += 1
    else:
      echo "ok: an authorised upstream limitation is accepted for the product"
    let rawWithoutLimitation = runCorpus(corpus, wrongRaw, subsetJudge(),
                                         scUpstream)
    let rejected = productVerdict(rawWithoutLimitation, mixed)
    echo "product_verdict_without_limitation=",
         (if rejected == qvPass: "PASS" else: "FAIL")
    if rejected == qvPass:
      echo "FAIL: an unauthorised raw failure was accepted for the product"
      failed += 1
    else:
      echo "ok: an unauthorised raw failure is not accepted for the product"

  echo "witness_failures=", failed
  if failed > 0:
    echo "RESULT: FAIL"
    quit(1)
  echo "RESULT: PASS — every controlled provider was detected correctly"
  quit(0)

main()
