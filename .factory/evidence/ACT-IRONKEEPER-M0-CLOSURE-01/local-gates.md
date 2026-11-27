# The repository-owned gates, executed locally on the executable subject

Subject: 2c8ef1e2c3108ce4f26821398256d449795b6056
Host: Darwin 23.6.0 arm64
Compiler: Nim Compiler Version 2.2.4 [MacOSX: arm64]

## tools/gate_build_test.sh
gate: ok   typecheck-main
gate: ok   typecheck-unit
gate: ok   typecheck-contract
gate: ok   typecheck-integration
gate: ok   build
gate: ok   test-unit
gate: ok   test-contract
gate: ok   test-integration
gate: PASS build-test

## tools/gate_schema_drift.sh
gate: ok   schema-drift
gate: PASS schema-drift

## tools/gate_fault_injection.sh
=== summary ===
passed: 21  failed: 0
RESULT: PASS — every injected fault was detected by the production gate

## tools/gate_ci_bootstrap.sh
=== summary ===
passed: 10  failed: 0
RESULT: PASS — the CI bootstrap holds

## tools/gate_requalification_decision.sh
=== summary ===
passed: 21  failed: 0
RESULT: PASS — the requalification decision is fail-closed

## tools/gate_remote_schema_integrity.sh
=== summary ===
passed: 8  failed: 0
RESULT: PASS — the qualification input integrity holds
