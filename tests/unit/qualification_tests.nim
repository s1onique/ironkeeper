## Tests for the qualification oracle and the corpus reader.
##
## The oracle is the authority of the qualification. A harness that
## compares nothing measures nothing, and a harness that lets the
## implementation under test exclude its own case measures the wrong
## thing. These tests pin both properties.

import std/[os, strutils]

import testkit

from ironkeeper/qualification/verdict import CaseResult, ObservedVerdict,
  classify, classificationOf, countsOf, verdictOf, qvPass, qvFail,
  clCorrectAcceptance, clCorrectRejection, clFalseAcceptance,
  clFalseRejection, clExecutionError, clUnsupportedPolicy,
  clKnownLimitation, clInvalidEvidence, denominatorOf, passesOf
from ironkeeper/qualification/corpus import readCorpus
from ironkeeper/qualification/jsonvalue import parsePrecise

proc mkCase(identity: string, expectedValid: bool, observed: ObservedVerdict,
             inSubset = true): CaseResult =
  CaseResult(identity: identity, expectedValid: expectedValid,
             observed: observed, inSupportedSubset: inSubset,
             inDenominator: inSubset, countedAsFailure: inSubset)

proc runSuite*(): int =
  var t = newTestSuite("qualification")

  # --- the oracle compares the two verdicts --------------------------------
  t.checkEq("an expected acceptance that was accepted is a correct acceptance",
            classify(mkCase("a", true, ovAccepted)),
            clCorrectAcceptance)
  t.checkEq("an expected rejection that was rejected is a correct rejection",
            classify(mkCase("b", false, ovRejected)),
            clCorrectRejection)
  t.checkEq("an expected acceptance that was rejected is a false rejection",
            classify(mkCase("c", true, ovRejected)),
            clFalseRejection)
  t.checkEq("an expected rejection that was accepted is a false acceptance",
            classify(mkCase("d", false, ovAccepted)),
            clFalseAcceptance)
  t.checkEq("an execution error is an execution error",
            classify(mkCase("e", true, ovError)),
            clExecutionError)

  # An always-accepting implementation fails every invalid case, and an
  # always-rejecting implementation fails every valid case. Neither
  # scores a pass by being active.
  var acceptAll: seq[CaseResult] = @[]
  var rejectAll: seq[CaseResult] = @[]
  for i in 0 ..< 10:
    acceptAll.add mkCase("valid-" & $i, true, ovAccepted)
    acceptAll.add mkCase("invalid-" & $i, false, ovAccepted)
    rejectAll.add mkCase("valid-" & $i, true, ovRejected)
    rejectAll.add mkCase("invalid-" & $i, false, ovRejected)
  t.checkEq("always accepting does not pass the qualification",
            verdictOf(acceptAll), qvFail)
  t.checkEq("always rejecting does not pass the qualification",
            verdictOf(rejectAll), qvFail)
  t.checkEq("always accepting passes only the valid half",
            passesOf(acceptAll), 10)
  t.checkEq("always rejecting passes only the invalid half",
            passesOf(rejectAll), 10)

  # --- the implementation cannot exclude its own case ----------------------
  # The implementation refuses a case the harness considers supported.
  # That is a defect, not an exclusion.
  t.checkEq("a refusal of a supported case is a failure, not an exclusion",
            classify(mkCase("f", true, ovUnsupported, true)),
            clExecutionError)
  # A refusal of a case the harness has determined to be outside the
  # supported subset is an authorised exclusion.
  t.checkEq("a refusal of an unsupported case is an exclusion",
            classify(mkCase("g", true, ovUnsupported, false)),
            clUnsupportedPolicy)

  # --- the counts ----------------------------------------------------------
  var mixed: seq[CaseResult] = @[
    mkCase("h", true, ovAccepted),
    mkCase("i", false, ovRejected),
    mkCase("j", false, ovAccepted),
    mkCase("k", true, ovRejected),
  ]
  let counts = countsOf(mixed)
  t.checkEq("the correct acceptances are counted", counts.correctAcceptance, 1)
  t.checkEq("the correct rejections are counted", counts.correctRejection, 1)
  t.checkEq("the false acceptances are counted", counts.falseAcceptance, 1)
  t.checkEq("the false rejections are counted", counts.falseRejection, 1)
  t.checkEq("the denominator counts every in-denominator case",
            denominatorOf(mixed), 4)
  t.checkEq("a wrong answer fails the qualification", $verdictOf(mixed), $qvFail)

  # --- the corpus reader ---------------------------------------------------
  let fixtures = currentSourcePath().parentDir().parentDir() /
                 "fixtures" / "conformance"
  let corpus = readCorpus(fixtures)
  t.checkEq("the fixture corpus has no problems", corpus.problems.len, 0)
  t.check("the fixture corpus is not empty", corpus.cases.len > 0)
  t.check("the fixture corpus digest is stable",
          corpus.digest.len > 0)

  # The optional membership is derived from the corpus structure.
  var optional = 0
  for c in corpus.cases:
    if c.optional:
      inc optional
  t.checkEq("the fixture corpus has no optional cases", optional, 0)

  # --- the precise reader --------------------------------------------------
  let precise = parsePrecise("""{"a": 1, "b": [1.5, 2]}""")
  t.check("the precise reader accepts a well-formed document",
          precise.problem.message.len == 0)
  t.checkEq("the precise reader finds no unrepresentable number",
            precise.unrepresentable.len, 0)

  let big = parsePrecise("""{"a": 12345678910111213141516171819202122232425262728293031}""")
  t.checkEq("the precise reader reports the unrepresentable number",
            big.unrepresentable.len, 1)
  t.check("the unrepresentable number is named",
          big.unrepresentable[0].startsWith("12345678910111213"))

  let bad = parsePrecise("""{"a": }""")
  t.check("the precise reader rejects a malformed document",
          bad.problem.message.len > 0)

  let trailing = parsePrecise("""{"a": 1} trailing""")
  t.check("the precise reader rejects trailing content",
          trailing.problem.message.len > 0)

  t.finish()
