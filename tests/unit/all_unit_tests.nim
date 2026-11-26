## Aggregated unit test suite.
##
## Each module exposes a `runSuite()` procedure that prints its own summary
## and returns a process exit code. The aggregator runs them all and fails
## if any of them fails.

import std/os

import cli_args_tests
import config_semantics_tests
import strictjson_tests
import validator_tests

proc main(): int =
  var failures = 0
  failures += cli_args_tests.runSuite()
  failures += config_semantics_tests.runSuite()
  failures += strictjson_tests.runSuite()
  failures += validator_tests.runSuite()
  if failures == 0:
    echo "ok   unit-suites"
    return 0
  echo "FAIL unit-suites (", failures, " suite(s) failed)"
  return 1

when isMainModule:
  quit(main())
