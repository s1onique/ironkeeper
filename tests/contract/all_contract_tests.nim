## Aggregated contract test suite.
##
## Contract tests exercise the published contracts rather than internal
## behaviour: they check that the schemas are valid, that the embedded
## copies match the repository, and that valid and invalid examples are
## classified as they should be.

import schema_contract_tests
import version_contract_tests

proc main(): int =
  var failures = 0
  failures += schema_contract_tests.runSuite()
  failures += version_contract_tests.runSuite()
  if failures == 0:
    echo "ok   contract-suites"
    return 0
  echo "FAIL contract-suites (", failures, " suite(s) failed)"
  return 1

when isMainModule:
  quit(main())
