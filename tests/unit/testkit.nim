## Minimal test harness for Ironkeeper.
##
## Ironkeeper does not depend on a test framework. The suite is small, has
## no external dependency, and produces deterministic output that a CI job
## can parse. Failures are reported with the file and line of the
## assertion.
##
## Usage:
##
##   var t = newTestSuite("strictjson")
##   t.check("parses an object", parseStrict("{}").ok)
##   t.checkEq("reports the right count", parseStrict("{}").node.len, 0)
##   t.finish()

import std/[strutils, times]

type
  TestSuite = ref object
    name: string
    total: int
    failures: seq[string]
    startedAt: DateTime

proc newTestSuite*(name: string): TestSuite =
  TestSuite(name: name, total: 0, failures: @[], startedAt: now())

proc fail(suite: TestSuite, msg: string) =
  let loc = getStackTrace()[0 ..< 1].split("\n")[0].strip()
  suite.failures.add loc & ": " & msg

proc check*(suite: TestSuite, what: string, condition: bool) =
  ## Assert that `condition` holds.
  inc suite.total
  if not condition:
    suite.fail("expected " & what)

proc checkEq*(suite: TestSuite, what: string, actual, expected: string) =
  ## Assert that two strings are equal.
  inc suite.total
  if actual != expected:
    suite.fail(what & ": expected " & expected & " but got " & actual)

proc checkEq*(suite: TestSuite, what: string, actual, expected: int) =
  inc suite.total
  if actual != expected:
    suite.fail(what & ": expected " & $expected & " but got " & $actual)

proc checkNe*(suite: TestSuite, what: string, actual, unexpected: string) =
  inc suite.total
  if actual == unexpected:
    suite.fail(what & ": expected a value other than " & unexpected)

proc checkContains*(suite: TestSuite, what: string, haystack: string,
                    needle: string) =
  inc suite.total
  if not haystack.contains(needle):
    suite.fail(what & ": expected to find " & needle & " in " & haystack)

proc checkNotContains*(suite: TestSuite, what: string, haystack: string,
                       needle: string) =
  inc suite.total
  if haystack.contains(needle):
    suite.fail(what & ": expected not to find " & needle & " in " & haystack)

proc finish*(suite: TestSuite): int =
  ## Print the summary and return the process exit code.
  let elapsed = now() - suite.startedAt
  if suite.failures.len == 0:
    echo "ok   ", suite.name, " (", suite.total, " checks, ",
         $(elapsed.inMilliseconds), " ms)"
    return 0
  echo "FAIL ", suite.name, " (", suite.failures.len, " of ", suite.total,
       " checks failed)"
  for f in suite.failures:
    echo "  - ", f
  return 1
