## Aggregated unit test suite.
##
## Each module exposes a `runSuite()` procedure that prints its own summary
## and returns a process exit code. The aggregator runs them all and fails
## if any of them fails.

import boundedread_tests
import cli_args_tests
import config_semantics_tests
import outputbounds_tests
import qualification_tests
import schemapolicy_tests
import storage_tests
import storage_witness_tests
import strictjson_tests
import validator_tests

proc main(): int =
  var failures = 0
  failures += boundedread_tests.runSuite()
  failures += cli_args_tests.runSuite()
  failures += config_semantics_tests.runSuite()
  failures += outputbounds_tests.runSuite()
  failures += qualification_tests.runSuite()
  failures += schemapolicy_tests.runSuite()
  failures += storage_tests.runSuite()
  failures += storage_witness_tests.runSuite()
  failures += strictjson_tests.runSuite()
  failures += validator_tests.runSuite()
  if failures == 0:
    echo "ok   unit-suites"
    return 0
  echo "FAIL unit-suites (", failures, " suite(s) failed)"
  return 1

when isMainModule:
  quit(main())
