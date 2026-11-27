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
# The report is parsed as JSON, not grepped. A grep cannot tell a complete
# JSON document from a truncated one, cannot tell an empty array from an
# array with one member, and cannot tell a JSON array from an arbitrary
# line that happens to start with `[`. The gate therefore requires:
#
#   * the report exists, is readable and is not empty;
#   * it is a *complete* JSON document;
#   * its root value is an array;
#   * the array has length zero.
#
# Any nonempty array is a failure regardless of its member fields.
#
# The parse is performed by Python, which is already an available CI
# dependency. Python prints the finding count on stdout and a diagnostic on
# stderr; the diagnostic is rendered *after* the verdict is decided and can
# therefore never change it.
REPORT_ERROR=""
FINDINGS=0
if [ ! -f "$GITLEAKS_REPORT" ]; then
  REPORT_ERROR="the mandatory scan report was not produced: ${GITLEAKS_REPORT}"
elif ! REPORT_OUT=$(python3 - "$GITLEAKS_REPORT" <<'PYEOF' 2>&1
import json, sys

path = sys.argv[1]
try:
    with open(path, 'rb') as handle:
        raw = handle.read()
except OSError:
    print("the mandatory scan report could not be read: %s" % path)
    sys.exit(1)

if not raw.strip():
    print("the mandatory scan report is empty: %s" % path)
    sys.exit(1)

try:
    text = raw.decode('utf-8')
except UnicodeDecodeError:
    print("the mandatory scan report is not valid UTF-8: %s" % path)
    sys.exit(1)

try:
    # `json.loads` rejects trailing content, so a truncated or padded
    # document is not accepted.
    document = json.loads(text)
except ValueError:
    print("the mandatory scan report is not a complete JSON document: %s" % path)
    sys.exit(1)

if not isinstance(document, list):
    print("the mandatory scan report is not a JSON array: %s" % path)
    sys.exit(1)

print(len(document))
PYEOF
); then
  REPORT_ERROR="${REPORT_OUT}"
elif [ -z "$REPORT_OUT" ]; then
  REPORT_ERROR="the mandatory scan report could not be inspected: ${GITLEAKS_REPORT}"
else
  FINDINGS="$REPORT_OUT"
fi

if [ -n "$REPORT_ERROR" ]; then
  echo "gate: FAIL secret-scan: ${REPORT_ERROR}" >&2
  exit 1
fi

# ---- the verdict ------------------------------------------------------------
# The scanner signals findings with exit status 1 when --exit-code 1 is in
# effect. A non-zero status that is not 1 is an execution failure, not a
# finding, and is treated as a failure too.
#
# The verdict is derived from the scanner's own exit status and from the
# *parsed* length of the report. Nothing below this point can change it.
if [ "$SCAN_STATUS" -eq 0 ] && [ "$FINDINGS" -eq 0 ]; then
  echo "gate: PASS secret-scan: no findings"
  exit 0
fi

# The scanner exited zero but the report is not an empty array. The report
# wins: a scanner that claims a clean scan while recording findings has
# failed, and the gate must not pass it.
if [ "$SCAN_STATUS" -eq 0 ]; then
  echo "gate: FAIL secret-scan: the scanner exited 0 but the report contains ${FINDINGS} finding(s)" >&2
  head -c 4000 "$GITLEAKS_REPORT" >&2 || true
  echo >&2
  exit 1
fi

if [ "$SCAN_STATUS" -eq 1 ]; then
  echo "gate: FAIL secret-scan: the scanner reported ${FINDINGS} finding(s)" >&2
  # The redacted findings are made available on failure. This diagnostic
  # rendering cannot change the verdict: the gate already failed.
  head -c 4000 "$GITLEAKS_REPORT" >&2 || true
  echo >&2
  exit 1
fi

echo "gate: FAIL secret-scan: the scanner failed to execute (exit ${SCAN_STATUS})" >&2
head -c 4000 "$SCAN_LOG" >&2 || true
echo >&2
exit 1
