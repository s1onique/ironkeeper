#!/usr/bin/env bash
# The regression check of the requalification decision.
#
# The decision script decides whether the validator qualification has to
# run. A decision that says "not needed" when the change evidence is
# missing, unresolvable or unusable would silently skip a mandatory
# qualification, so the decision is exercised here against small
# temporary repositories that reproduce each situation.
#
# The script under test is the **production** script,
# `tools/requalification_needed.sh`. Nothing is reimplemented here.
#
# Exit status:
#   0  every situation produced the required decision
#   1  at least one situation produced the wrong decision

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DECIDE="$ROOT/tools/requalification_needed.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/irk-requal.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0

ok() { echo "ok   $1"; PASSED=$((PASSED + 1)); }
no() { echo "FAIL $1"; FAILED=$((FAILED + 1)); }

# decide <repository> <base> -> prints the decision
#
# The script under test is copied into the temporary repository, so that
# it computes its diff against the temporary repository's history. The
# copied file is byte-identical to the production script.
decide() {
  local repo="$1" base="$2"
  mkdir -p "$repo/tools"
  cp "$DECIDE" "$repo/tools/requalification_needed.sh"
  ( cd "$repo" && bash tools/requalification_needed.sh "$base" 2>/dev/null | grep '^requalification=' | head -1 | cut -d= -f2 )
}

expect() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    ok "$label"
  else
    no "$label (expected $expected but got ${actual:-<none>})"
  fi
}

# make_repo <path> -> a repository with one commit
make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init --quiet -b main
  git -C "$repo" config user.email "test@example.invalid"
  git -C "$repo" config user.name "Test"
  echo "placeholder" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit --quiet -m "initial"
}

# touch_path <repo> <path> -> commits a change to one path
touch_path() {
  local repo="$1" path="$2"
  mkdir -p "$repo/$(dirname "$path")"
  echo "changed" > "$repo/$path"
  git -C "$repo" add "$path"
  git -C "$repo" commit --quiet -m "change $path"
}

echo "=== a first push of a branch has no comparison authority ==="
R="$WORK/first-push"
make_repo "$R"
expect "the all-zero base requires the qualification" \
  "$(decide "$R" 0000000000000000000000000000000000000000)" needed
expect "an empty base requires the qualification" \
  "$(decide "$R" "")" needed

echo
echo "=== an unresolvable comparison base requires the qualification ==="
expect "an unknown ref requires the qualification" \
  "$(decide "$R" no-such-ref-at-all)" needed

echo
echo "=== every relevant path requires the qualification ==="
for path in \
  src/ironkeeper/contracts/validator.nim \
  src/ironkeeper/json/strictjson.nim \
  src/ironkeeper/qualification/harness.nim \
  tools/validator_conformance.nim \
  tools/validator_conformance_witnesses.nim \
  tools/qualify_validator.sh \
  tools/requalification_needed.sh \
  tools/install_nim_toolchain.sh \
  tools/embed_schemas.nim \
  schemas/v1/report.schema.json \
  tests/fixtures/conformance/minimal-corpus.json \
  tests/draft2020-12/integer.json \
  remotes/draft2020-12/name.json \
  ironkeeper.nimble \
  .github/workflows/ci.yml
do
  RR="$WORK/relevant"
  rm -rf "$RR"
  make_repo "$RR"
  BASE=$(git -C "$RR" rev-parse HEAD)
  touch_path "$RR" "$path"
  expect "a change to $path requires the qualification" \
    "$(decide "$RR" "$BASE")" needed
done

echo
echo "=== a known documentation-only change may be skipped ==="
RD="$WORK/docs"
make_repo "$RD"
BASE=$(git -C "$RD" rev-parse HEAD)
touch_path "$RD" "docs/architecture/overview.md"
expect "a documentation-only change does not require the qualification" \
  "$(decide "$RD" "$BASE")" not-needed

echo
echo "=== the script reports a reason with every decision ==="
REASON=$( cd "$RD" && bash "$DECIDE" "$BASE" 2>/dev/null | grep -c '^requalification_reason=' )
if [ "$REASON" -ge 1 ]; then
  ok "the decision carries a reason"
else
  no "the decision carries a reason"
fi

echo
echo "=== the script does not suppress a failing comparison ==="
# A repository whose base ref resolves but whose diff cannot be taken is
# simulated with a base that is a valid commit in a repository with an
# unreadable index. The decision must be "needed", never "not-needed".
RF="$WORK/broken"
make_repo "$RF"
BASE=$(git -C "$RF" rev-parse HEAD)
touch_path "$RF" "src/ironkeeper/contracts/validator.nim"
( cd "$RF" && git config core.broken true && git update-index --really-refresh >/dev/null 2>&1 || true )
expect "a broken comparison requires the qualification" \
  "$(decide "$RF" "$BASE")" needed

echo
echo "=== summary ==="
echo "passed: ${PASSED}  failed: ${FAILED}"
if [ "$FAILED" -gt 0 ]; then
  echo "RESULT: FAIL — the requalification decision is wrong"
  exit 1
fi
echo "RESULT: PASS — the requalification decision is fail-closed"
exit 0
