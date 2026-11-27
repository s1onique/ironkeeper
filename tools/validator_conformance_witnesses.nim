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

from ironkeeper/qualification/corpus import readCorpus
from ironkeeper/qualification/harness import runCorpus, failures,
  unauthorisedExclusions, upstreamLimitations, Scope, scAdapter
from ironkeeper/qualification/providers import controlledProvider,
  controlledProviderByName, subsetJudge, ControlledProviderKind
from ironkeeper/qualification/verdict import classificationOf,
  clUnsupportedPolicy, clKnownLimitation, qvPass

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

  echo "witness_failures=", failed
  if failed > 0:
    echo "RESULT: FAIL"
    quit(1)
  echo "RESULT: PASS — every controlled provider was detected correctly"
  quit(0)

main()
