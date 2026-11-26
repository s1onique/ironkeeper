#!/usr/bin/env bash
# The secret-scan gate.
#
# The gate runs a pinned gitleaks binary over the whole history and
# classifies the outcome. It is **fail-closed**:
#
#   * a clean scan with no findings passes;
#   * a scan that reports findings fails;
#   * a missing or non-executable scanner fails;
#   * a scanner that fails to execute fails;
#   * a missing or malformed mandatory report is **never** reported as a
#     clean scan;
#   * generating or rendering the report cannot overwrite the scan verdict.
#
# The scan verdict is decided by the scanner's own exit status and by the
# contents of the report it produced. It is never decided by a trailing
# command.
#
# Environment:
#   GITLEAKS         path to the gitleaks executable
#                    (default: gitleaks from PATH)
#   GITLEAKS_REPORT  path of the mandatory report
#                    (default: ./gitleaks-report.json)

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# shellcheck source=tools/gate.sh
. "$ROOT/tools/gate.sh"

GITLEAKS="${GITLEAKS:-gitleaks}"
GITLEAKS_REPORT="${GITLEAKS_REPORT:-$ROOT/gitleaks-report.json}"

# ---- the scanner must exist and be executable -------------------------------
if [ ! -x "$GITLEAKS" ]; then
  echo "gate: FAIL secret-scan: scanner is missing or not executable: ${GITLEAKS}" >&2
  exit 1
fi

# ---- the scan itself --------------------------------------------------------
# The report is removed first, so that a report left over from an earlier run
# can never be mistaken for the result of this one.
rm -f "$GITLEAKS_REPORT"

SCAN_LOG="$GATE_LOG_DIR/secret-scan.log"
set +e
"$GITLEAKS" git \
  --redact \
  --no-banner \
  --report-format json \
  --report-path "$GITLEAKS_REPORT" \
  --exit-code 1 > "$SCAN_LOG" 2>&1
SCAN_STATUS=$?
set -e
cat "$SCAN_LOG" || true
echo "gate: scanner exit status = ${SCAN_STATUS}"

# ---- the report must exist and be well formed ------------------------------
# A missing or malformed report is a failure. It is *not* a clean scan.
REPORT_ERROR=""
if [ ! -f "$GITLEAKS_REPORT" ]; then
  REPORT_ERROR="the mandatory scan report was not produced: ${GITLEAKS_REPORT}"
elif [ ! -s "$GITLEAKS_REPORT" ]; then
  REPORT_ERROR="the mandatory scan report is empty: ${GITLEAKS_REPORT}"
elif ! grep -q '^\s*\[' "$GITLEAKS_REPORT"; then
  REPORT_ERROR="the mandatory scan report is malformed (not a JSON array): ${GITLEAKS_REPORT}"
fi

if [ -n "$REPORT_ERROR" ]; then
  echo "gate: FAIL secret-scan: ${REPORT_ERROR}" >&2
  exit 1
fi

# ---- the verdict ------------------------------------------------------------
# The scanner signals findings with exit status 1 when --exit-code 1 is in
# effect. A non-zero status that is not 1 is an execution failure, not a
# finding, and is treated as a failure too.
FINDINGS=$(grep -c '"RuleID"' "$GITLEAKS_REPORT" || true)
if [ "$SCAN_STATUS" -eq 0 ] && [ "$FINDINGS" -eq 0 ]; then
  echo "gate: PASS secret-scan: no findings"
  exit 0
fi

if [ "$SCAN_STATUS" -eq 1 ]; then
  echo "gate: FAIL secret-scan: the scanner reported ${FINDINGS} finding(s)" >&2
  # The redacted findings are made available on failure.
  head -c 4000 "$GITLEAKS_REPORT" >&2 || true
  echo >&2
  exit 1
fi

echo "gate: FAIL secret-scan: the scanner failed to execute (exit ${SCAN_STATUS})" >&2
head -c 4000 "$SCAN_LOG" >&2 || true
echo >&2
exit 1
