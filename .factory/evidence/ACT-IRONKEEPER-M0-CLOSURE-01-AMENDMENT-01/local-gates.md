# The repository-owned gates, executed locally on the executable subject

Subject: f1b9ca0f4f690b9ad053d928aafba82d6ab1c5c3
Host: Darwin 23.6.0 arm64

## tools/gate_build_test.sh
ok   strictjson (82 checks, 99 ms)
ok   validator-adapter (51 checks, 36 ms)
ok   unit-suites
gate: ok   test-unit
ok   contracts (56 checks, 277 ms)
ok   version-contract (6 checks, 0 ms)
ok   contract-suites
gate: ok   test-contract
ok   integration (102 checks, 433 ms)
ok   integration-suites
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
passed: 17  failed: 0
RESULT: PASS — the CI bootstrap holds

## tools/gate_requalification_decision.sh
=== summary ===
passed: 21  failed: 0
RESULT: PASS — the requalification decision is fail-closed

## tools/gate_remote_schema_integrity.sh
ok   the malformed remote schema is not counted as read

=== the qualification authority is decided by the verification ===
ok   a modified input with the repository pin is refused
ok   the refusal names the pinned digest
ok   the refused input is not classified as authoritative
ok   a caller-supplied digest accepts the modified input
ok   a caller-supplied digest yields a non-authoritative result
ok   the development-only result is classified as such
ok   a caller cannot promote a development-only result to authoritative
ok   the promotion attempt leaves the result development-only
ok   the production gate refuses a development-only result
ok   the gate names the authority requirement
ok   the qualification script reads no authority assertion

=== the qualification script binds both trees ===
ok   the qualification script digests the remote tree
ok   the qualification script digests the inputs together

=== summary ===
passed: 19  failed: 0
RESULT: PASS — the qualification input integrity holds
