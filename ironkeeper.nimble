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

task build, "Build the ironkeeper executable (release mode, ORC memory manager)":
  exec "nim c -d:release --mm:orc --opt:speed -o:" & quote(joinPaths(getEnv("NIMBLE_OUTPUT_DIR", "build"), "ironkeeper")) & " src/ironkeeper.nim"

task check, "Type-check every module without producing a binary":
  exec "nim check --mm:orc src/ironkeeper.nim"
  exec "nim check --mm:orc --path:tests tests/unit/all_unit_tests.nim"
  exec "nim check --mm:orc --path:tests tests/contract/all_contract_tests.nim"

task test, "Run the unit and contract test suites":
  exec "nim c -r --mm:orc --hints:off -o:build/unit_tests tests/unit/all_unit_tests.nim"
  exec "nim c -r --mm:orc --hints:off -o:build/contract_tests tests/contract/all_contract_tests.nim"

task integrationTest, "Run the integration test suite against the built binary":
  exec "nim c -r --mm:orc --hints:off -o:build/integration_tests tests/integration/all_integration_tests.nim"

task schemas, "Regenerate the embedded schema module from schemas/v1":
  exec "nim r --hints:off tools/embed_schemas.nim"

task ci, "Run the full local CI equivalent: check, test, integration, schema lint":
  exec "nimble check"
  exec "nimble test"
  exec "nimble integrationTest"
  exec "nimble schemas --check"
