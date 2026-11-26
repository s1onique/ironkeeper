# Build and test results

## Authoritative result

The authoritative build and test result is the CI run at the exact
qualified subject commit. See `ci-status.md`.

| Layer | Where | Result |
|---|---|---|
| Build (release, ORC) | CI, native linux amd64 and arm64 | **pass** |
| Unit tests | CI, native linux amd64 and arm64 | **pass** |
| Contract tests | CI, native linux amd64 and arm64 | **pass** |
| Integration tests | CI, native linux amd64 and arm64 | **pass** |
| Independent schema validation | CI, native linux amd64 and arm64 | **pass** |
| Secret scan | CI | **pass** |

## Local result

The local result on the macOS development workstation, at the same
source state:

```
$ tools/build.sh
==> building src/ironkeeper.nim -> build/ironkeeper
==> building tests/unit/all_unit_tests.nim -> build/unit_tests
==> building tests/contract/all_contract_tests.nim -> build/contract_tests
==> building tests/integration/all_integration_tests.nim -> build/integration_tests
==> build complete

$ ./build/unit_tests
ok   cli-args (15 checks, 0 ms)
ok   config-semantics (16 checks, 0 ms)
ok   strictjson (54 checks, 24 ms)
ok   validator-adapter (37 checks, 4 ms)
ok   unit-suites

$ ./build/contract_tests
ok   contracts (35 checks, 41 ms)
ok   version-contract (6 checks, 0 ms)
ok   contract-suites

$ ./build/integration_tests
ok   integration (54 checks, 208 ms)
ok   integration-suites

$ nim r --hints:off tools/embed_schemas.nim --check
embed_schemas: OK (4 schemas, no drift)
```

**Total: 217 checks across the three suites, all passing.**

The macOS result is a portable-build result. It is **not** evidence of
Linux-native compatibility; the CI run is.

## Compiler invocations

Every artefact is produced by `tools/build.sh`, which is what both the
Nimble tasks and the CI workflow drive:

```sh
nim c --mm:orc --hints:off \
  --path:src --path:tests/unit --path:tests/contract --path:tests/integration \
  --path:<dependency> \
  -o:<output> <source>
```

The application is built with `-d:release --opt:speed`; the test
binaries are built in the default mode so that assertions and stack
traces remain available when a test fails.

The memory manager is **ORC**, set explicitly rather than inherited
from the toolchain default.

## Type checking

Every module is type-checked, not only the ones that the test binaries
pull in:

```sh
nim check --mm:orc --path:src --path:<dependency> src/ironkeeper.nim
nim check --mm:orc --path:src --path:tests/unit --path:<dependency> \
  tests/unit/all_unit_tests.nim
nim check --mm:orc --path:src --path:tests/unit --path:tests/contract \
  --path:<dependency> tests/contract/all_contract_tests.nim
nim check --mm:orc --path:src --path:tests/unit --path:tests/integration \
  --path:<dependency> tests/integration/all_integration_tests.nim
```

## CLI smoke

```
$ ./build/ironkeeper --version
0.1.0-dev

$ ./build/ironkeeper config validate --file examples/ironkeeper.json
report 20261126T223359-752360EE
execution: SUCCEEDED
assessment: PASS - the configuration document is valid

$ ./build/ironkeeper schema list
config
error
report
version
```

## Independent cross-validation

The machine-readable output the binary produces was validated with a
second, independent implementation:

```
$ check-jsonschema --check-metaschema schemas/v1/config.schema.json
ok -- validation done
$ check-jsonschema --check-metaschema schemas/v1/report.schema.json
ok -- validation done
$ check-jsonschema --check-metaschema schemas/v1/error.schema.json
ok -- validation done
$ check-jsonschema --check-metaschema schemas/v1/version.schema.json
ok -- validation done
$ check-jsonschema --schemafile schemas/v1/config.schema.json examples/ironkeeper.json
ok -- validation done
$ check-jsonschema --schemafile schemas/v1/report.schema.json out/report.json
ok -- validation done
$ check-jsonschema --schemafile schemas/v1/version.schema.json out/version.json
ok -- validation done
```

The runtime validator and the independent validator therefore agree on
the supported contract corpus.
