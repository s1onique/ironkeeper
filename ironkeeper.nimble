# Package

version       = "0.1.0-dev"
author        = "Ironkeeper Contributors"
description   = "Evidence-driven storage fleet housekeeping daemon"
license       = "MIT"
srcDir        = "src"
bin           = @["ironkeeper"]
binDir        = "build"

# Dependencies
#
# jschema is the JSON Schema Draft 2020-12 validator. It is MIT licensed,
# depends only on the Nim standard library, performs no network access, and
# is qualified against the official JSON Schema Test Suite. See
# docs/architecture/overview.md, section "Validator qualification".
requires "nim >= 2.2.10"
requires "jschema == 0.1.0"

# Tasks

# All tasks delegate to tools/build.sh and the test binaries it produces,
# so that the Nimble tasks, the CI workflow and a developer workstation
# drive exactly the same compiler invocations.

task build, "Build the ironkeeper executable (release mode, ORC memory manager)":
  exec "tools/build.sh"

task check, "Type-check every module without producing a binary":
  exec "nim check --mm:orc --path:src src/ironkeeper.nim"
  exec "nim check --mm:orc --path:src --path:tests/unit tests/unit/all_unit_tests.nim"
  exec "nim check --mm:orc --path:src --path:tests/contract tests/contract/all_contract_tests.nim"
  exec "nim check --mm:orc --path:src --path:tests/integration tests/integration/all_integration_tests.nim"

task test, "Run the unit and contract test suites":
  exec "nim c -r --mm:orc --hints:off --path:src --path:tests/unit -o:build/unit_tests tests/unit/all_unit_tests.nim"
  exec "nim c -r --mm:orc --hints:off --path:src --path:tests/contract -o:build/contract_tests tests/contract/all_contract_tests.nim"

task integrationTest, "Run the integration test suite against the built binary":
  exec "nim c -r --mm:orc --hints:off --path:src --path:tests/integration -o:build/integration_tests tests/integration/all_integration_tests.nim"

task schemas, "Regenerate the embedded schema module from schemas/v1":
  exec "nim r --hints:off tools/embed_schemas.nim"

task ci, "Run the full local CI equivalent: check, test, integration, schema drift":
  exec "nimble check"
  exec "nimble test"
  exec "nimble integrationTest"
  exec "nim r --hints:off tools/embed_schemas.nim --check"
