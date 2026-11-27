#!/usr/bin/env bash
# Fault-injection harness for the Ironkeeper CI gate scripts.
#
# This harness exercises the **actual production gate scripts** with
# controlled failing executables. It proves the invariant:
#
#   > No mandatory command failure may be converted into a successful CI
#   > gate by subsequent execution, logging, report generation or artifact
#   > collection.
#
# It does not reimplement the gates. It runs the real scripts with a
# deliberately broken dependency injected through the environment, and it
# asserts that each gate terminates with a nonzero status.
#
# Usage:
#   tools/gate_fault_injection.sh
#
# Exit status:
#   0  every injected fault was detected
#   1  at least one injected fault was NOT detected (the gate is unsound)

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/irk-gate-fault.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0

# expect_failure <label> <command> [args...]
#
# Assert that the command terminates with a nonzero status. A zero status
# means the gate swallowed the injected fault.
expect_failure() {
  local label="$1"
  shift
  set +e
  "$@" > "$WORK/$label.out" 2>&1
  local status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "FAIL ${label}: the gate exited 0 although a mandatory command failed"
    sed 's/^/    | /' "$WORK/$label.out" | head -20
    FAILED=$((FAILED + 1))
    return 1
  fi
  echo "ok   ${label}: the gate exited ${status}"
  PASSED=$((PASSED + 1))
  return 0
}

# expect_success <label> <command> [args...]
expect_success() {
  local label="$1"
  shift
  set +e
  "$@" > "$WORK/$label.out" 2>&1
  local status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    echo "FAIL ${label}: the gate exited ${status} although nothing failed"
    sed 's/^/    | /' "$WORK/$label.out" | head -20
    FAILED=$((FAILED + 1))
    return 1
  fi
  echo "ok   ${label}: the gate exited 0"
  PASSED=$((PASSED + 1))
  return 0
}

echo "=== the gate scripts are present and executable ==="
for g in gate.sh gate_build_test.sh gate_schema_drift.sh gate_independent_check.sh gate_secret_scan.sh; do
  if [ ! -x "tools/$g" ]; then
    echo "FAIL tools/$g is missing or not executable"
    FAILED=$((FAILED + 1))
  else
    echo "ok   tools/$g"
    PASSED=$((PASSED + 1))
  fi
done

echo
echo "=== the gate scripts contain no failure-masking constructs ==="
# The specific constructs that produced the masked failures are forbidden
# in the gate scripts. This harness is excluded from the search: it names
# the forbidden construct in order to look for it.
MASKING_PATTERN='continue''-on-error'
if grep -nE "$MASKING_PATTERN" tools/gate.sh tools/gate_build_test.sh \
     tools/gate_schema_drift.sh tools/gate_independent_check.sh \
     tools/gate_secret_scan.sh; then
  echo "FAIL a gate script uses continue-on-error"
  FAILED=$((FAILED + 1))
else
  echo "ok   no continue-on-error in the gate scripts"
  PASSED=$((PASSED + 1))
fi

echo
echo "=== secret-scan gate: controlled scanner fixtures ==="
mkdir -p "$WORK/bin"

# (a) a scanner that reports a finding must fail the gate.
cat > "$WORK/bin/gitleaks-finding" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$prev" in --report-path) report="$a" ;; esac
  prev="$a"
done
[ -n "$report" ] && printf '[{"RuleID":"generic-api-key","File":"fixture.txt"}]\n' > "$report"
echo "leak: generic-api-key"
exit 1
EOF
chmod +x "$WORK/bin/gitleaks-finding"

# (b) a scanner that finds nothing must pass the gate.
cat > "$WORK/bin/gitleaks-clean" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$prev" in --report-path) report="$a" ;; esac
  prev="$a"
done
[ -n "$report" ] && printf '[]\n' > "$report"
echo "no leaks found"
exit 0
EOF
chmod +x "$WORK/bin/gitleaks-clean"

# (c) a scanner that cannot execute must fail the gate.
cat > "$WORK/bin/gitleaks-broken" <<'EOF'
#!/bin/sh
echo "scanner exploded" >&2
exit 7
EOF
chmod +x "$WORK/bin/gitleaks-broken"

# (d) a scanner that produces no report must not be reported as clean.
cat > "$WORK/bin/gitleaks-noreport" <<'EOF'
#!/bin/sh
echo "I wrote no report"
exit 0
EOF
chmod +x "$WORK/bin/gitleaks-noreport"

# (e) a scanner that exits zero but writes a *nonempty* array whose members
#     carry no recognisable finding fields. The report length, not the
#     member fields, is authoritative.
cat > "$WORK/bin/gitleaks-nonempty" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$prev" in --report-path) report="$a" ;; esac
  prev="$a"
done
[ -n "$report" ] && printf '[{}]\n' > "$report"
echo "no leaks found"
exit 0
EOF
chmod +x "$WORK/bin/gitleaks-nonempty"

# (f) a scanner that exits zero but writes a truncated / padded document.
cat > "$WORK/bin/gitleaks-trailing" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$prev" in --report-path) report="$a" ;; esac
  prev="$a"
done
[ -n "$report" ] && printf '[] trailing garbage\n' > "$report"
echo "no leaks found"
exit 0
EOF
chmod +x "$WORK/bin/gitleaks-trailing"

# (g) a scanner that exits zero but writes a truncated JSON document.
cat > "$WORK/bin/gitleaks-truncated" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$prev" in --report-path) report="$a" ;; esac
  prev="$a"
done
[ -n "$report" ] && printf '[\n' > "$report"
echo "no leaks found"
exit 0
EOF
chmod +x "$WORK/bin/gitleaks-truncated"

# (h) a scanner that exits zero but writes a JSON document whose root is
#     not an array.
cat > "$WORK/bin/gitleaks-notarray" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$prev" in --report-path) report="$a" ;; esac
  prev="$a"
done
[ -n "$report" ] && printf '{"findings": []}\n' > "$report"
echo "no leaks found"
exit 0
EOF
chmod +x "$WORK/bin/gitleaks-notarray"

expect_failure "secret-scan-finding"   env GITLEAKS="$WORK/bin/gitleaks-finding"   GITLEAKS_REPORT="$WORK/findings.json" GATE_LOG_DIR="$WORK/logs" tools/gate_secret_scan.sh
expect_success "secret-scan-clean"     env GITLEAKS="$WORK/bin/gitleaks-clean"     GITLEAKS_REPORT="$WORK/clean.json"    GATE_LOG_DIR="$WORK/logs" tools/gate_secret_scan.sh
expect_failure "secret-scan-broken"    env GITLEAKS="$WORK/bin/gitleaks-broken"    GITLEAKS_REPORT="$WORK/broken.json"   GATE_LOG_DIR="$WORK/logs" tools/gate_secret_scan.sh
expect_failure "secret-scan-noreport"  env GITLEAKS="$WORK/bin/gitleaks-noreport"  GITLEAKS_REPORT="$WORK/none.json"     GATE_LOG_DIR="$WORK/logs" tools/gate_secret_scan.sh
expect_failure "secret-scan-missing"   env GITLEAKS="$WORK/bin/does-not-exist"     GITLEAKS_REPORT="$WORK/missing.json"  GATE_LOG_DIR="$WORK/logs" tools/gate_secret_scan.sh

# The report-validation counterexamples. Each of these scanners exits zero
# and claims a clean scan. Each must still fail the gate.
expect_failure "secret-scan-nonempty-array"  env GITLEAKS="$WORK/bin/gitleaks-nonempty"  GITLEAKS_REPORT="$WORK/nonempty.json"  GATE_LOG_DIR="$WORK/logs" tools/gate_secret_scan.sh
expect_failure "secret-scan-trailing-garbage" env GITLEAKS="$WORK/bin/gitleaks-trailing"  GITLEAKS_REPORT="$WORK/trailing.json"  GATE_LOG_DIR="$WORK/logs" tools/gate_secret_scan.sh
expect_failure "secret-scan-truncated-report" env GITLEAKS="$WORK/bin/gitleaks-truncated" GITLEAKS_REPORT="$WORK/truncated.json" GATE_LOG_DIR="$WORK/logs" tools/gate_secret_scan.sh
expect_failure "secret-scan-report-not-array" env GITLEAKS="$WORK/bin/gitleaks-notarray" GITLEAKS_REPORT="$WORK/notarray.json"  GATE_LOG_DIR="$WORK/logs" tools/gate_secret_scan.sh

echo
echo "=== schema-drift gate: a failing drift check must fail the gate ==="
# A stand-in for the nim compiler that reports drift and exits nonzero.
cat > "$WORK/bin/nim-drift" <<'EOF'
#!/bin/sh
echo "embed_schemas: embedded schemas are out of date" >&2
exit 1
EOF
chmod +x "$WORK/bin/nim-drift"
expect_failure "schema-drift-failure" env NIM="$WORK/bin/nim-drift" GATE_LOG_DIR="$WORK/logs" tools/gate_schema_drift.sh

echo
echo "=== build-test gate: a failing mandatory step must fail the gate ==="
# The build-test gate drives `tools/build.sh` and the three test binaries.
#
# These cases run against an isolated *copy* of the repository. A stand-in
# compiler writes its output wherever the build system asks for it, so it
# must never be pointed at the working tree: a mis-parsed `-o:` argument
# would otherwise overwrite a source file.
SANDBOX="$WORK/repo"
mkdir -p "$SANDBOX"
git -C "$ROOT" archive HEAD | tar x -C "$SANDBOX"
cp "$ROOT"/tools/gate*.sh "$SANDBOX/tools/" 2>/dev/null || true
chmod +x "$SANDBOX"/tools/*.sh

# A stand-in `nim` that fails the *first* type-check must fail the gate,
# even though the later commands would succeed.
cat > "$WORK/bin/nim-fails" <<'EOF'
#!/bin/sh
echo "Error: type error in a module" >&2
exit 1
EOF
chmod +x "$WORK/bin/nim-fails"
expect_failure "build-test-typecheck-failure" env NIM="$WORK/bin/nim-fails" GATE_LOG_DIR="$WORK/logs" bash -c "cd '$SANDBOX' && tools/gate_build_test.sh"

# A stand-in `nim` that fails only the *build* step.
cat > "$WORK/bin/nim-build-fails" <<'EOF'
#!/bin/sh
case " $* " in
  *" c "*) echo "Error: build failed" >&2; exit 1 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$WORK/bin/nim-build-fails"
expect_failure "build-test-build-failure" env NIM="$WORK/bin/nim-build-fails" GATE_LOG_DIR="$WORK/logs" bash -c "cd '$SANDBOX' && tools/gate_build_test.sh"

# A stand-in build that succeeds but produces failing test binaries.
# It runs against an isolated *copy* of the repository, so that a stand-in
# compiler can never overwrite a source file in the working tree.
cat > "$WORK/bin/nim-ok-but-tests-fail" <<'EOF'
#!/bin/sh
case " $* " in
  *" c "*)
    out=""
    prev=""
    for a in "$@"; do
      case "$prev" in -o:*) out="${a#-o:}" ;; esac
      prev="$a"
    done
    printf '#!/bin/sh\necho "FAIL unit suite (1 of 1 checks failed)"\nexit 1\n' > "$out"
    chmod +x "$out"
    ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/nim-ok-but-tests-fail"
expect_failure "build-test-unit-test-failure" env NIM="$WORK/bin/nim-ok-but-tests-fail" GATE_LOG_DIR="$WORK/logs" bash -c "cd '$SANDBOX' && tools/gate_build_test.sh"

echo
echo "=== independent-check gate: a failing validation must fail the gate ==="
# A stand-in independent validator that rejects the document.
cat > "$WORK/bin/validator-fails" <<'EOF'
#!/bin/sh
case "$1" in
  --check-metaschema) exit 0 ;;
  --schemafile) echo "validation error: does not satisfy the schema" >&2; exit 1 ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/validator-fails"

# The gate needs the binary to exist. Use the real one when it is built.
if [ -x "$ROOT/build/ironkeeper" ]; then
  expect_failure "independent-check-validation-failure" \
    env IRK_VALIDATOR="$WORK/bin/validator-fails" IRK_CHECK_OUT_DIR="$WORK/out" \
    GATE_LOG_DIR="$WORK/logs" tools/gate_independent_check.sh
  # A missing independent validator must fail the gate, not be skipped.
  expect_failure "independent-check-missing-validator" \
    env IRK_VALIDATOR="$WORK/bin/does-not-exist" IRK_CHECK_OUT_DIR="$WORK/out" \
    GATE_LOG_DIR="$WORK/logs" tools/gate_independent_check.sh
else
  echo "skip independent-check cases: build/ironkeeper is not built"
fi

echo
echo "=== summary ==="
echo "passed: ${PASSED}  failed: ${FAILED}"
if [ "$FAILED" -gt 0 ]; then
  echo "RESULT: FAIL — an injected fault was not detected"
  exit 1
fi
echo "RESULT: PASS — every injected fault was detected by the production gate"
exit 0
