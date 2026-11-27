## Aggregated integration test suite.
##
## Integration tests run the compiled binary as a subprocess. They require
## the binary to exist; the CI workflow builds it before running them.

import cli_tests
import storage_cli_tests

proc main(): int =
  var failures = cli_tests.runSuite()
  failures += storage_cli_tests.runSuite()
  if failures == 0:
    echo "ok   integration-suites"
    return 0
  echo "FAIL integration-suites (", failures, " suite(s) failed)"
  return 1

when isMainModule:
  quit(main())
