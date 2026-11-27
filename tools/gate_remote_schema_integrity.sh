#!/usr/bin/env bash
# The regression check of the qualification input integrity.
#
# The qualification consumes two trees of the pinned suite: the
# Draft 2020-12 corpus and the remote schemas the corpus references. A
# digest over the corpus alone does not identify the input, because a
# modified remote schema changes the answer without changing the corpus.
#
# This check proves, with a **single synthetic remote-schema mutation**,
# that a changed remote input is detected:
#
#   1. the digest of the two trees is computed;
#   2. one remote schema is mutated;
#   3. the digest is computed again and must differ; and
#   4. a malformed remote schema is refused by the reader rather than
#      being skipped.
#
# The check needs no network and no hardware.
#
# Exit status:
#   0  every property holds
#   1  at least one property does not hold

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/irk-remote.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0
ok() { echo "ok   $1"; PASSED=$((PASSED + 1)); }
no() { echo "FAIL $1"; FAILED=$((FAILED + 1)); }

# A synthetic suite: a corpus directory and a remote schema.
SUITE="$WORK/suite"
mkdir -p "$SUITE/tests/draft2020-12" "$SUITE/remotes/draft2020-12"
cat > "$SUITE/tests/draft2020-12/integer.json" <<'EOF'
[{"description":"an integer schema","schema":{"type":"integer"},"tests":[{"description":"an integer is valid","data":1,"valid":true}]}]
EOF
cat > "$SUITE/remotes/draft2020-12/name.json" <<'EOF'
{"type":"string"}
EOF

# The digest computation is the one the qualification uses.
inputs_digest() {
  find "$SUITE/tests/draft2020-12" "$SUITE/remotes" -type f -name '*.json' | \
    LC_ALL=C sort | \
    while read -r f; do printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" \
      "${f#"$SUITE"/}"; done | sha256sum | cut -d' ' -f1
}

echo "=== a changed remote input is detected ==="
BEFORE=$(inputs_digest)
# The mutation is synthetic and local: one byte of one remote schema.
python3 - "$SUITE/remotes/draft2020-12/name.json" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
open(path, "w").write(text.replace('"string"', '"integer"'))
PY
AFTER=$(inputs_digest)
if [ "$BEFORE" != "$AFTER" ]; then
  ok "a mutated remote schema changes the inputs digest"
else
  no "a mutated remote schema changes the inputs digest"
fi

echo
echo "=== the remote digest of the reader covers the remote tree ==="
cat > "$WORK/remote_probe.nim" <<'EOF'
import std/[os, strutils]
from ironkeeper/qualification/remotes import readRemoteSchemas

let dir = paramStr(1)
let registration = readRemoteSchemas(dir, "http://localhost:1234")
echo "files=", registration.fileCount
echo "digest=", registration.digest
echo "problems=", registration.problems.len
for p in registration.problems:
  echo "problem: ", p.file, ": ", p.message
EOF
XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/nimcache}" nim r --nimcache:"${XDG_CACHE_HOME:-/tmp/nimcache}" \
  --hints:off --path:"$ROOT/src" "$WORK/remote_probe.nim" "$SUITE/remotes" \
  > "$WORK/probe.out" 2>&1
if grep -q "^files=1$" "$WORK/probe.out"; then
  ok "the reader reads the remote tree"
else
  no "the reader reads the remote tree"
  cat "$WORK/probe.out"
fi
if grep -q "^problems=0$" "$WORK/probe.out"; then
  ok "a well-formed remote tree produces no problem"
else
  no "a well-formed remote tree produces no problem"
fi

echo
echo "=== a malformed remote schema is refused, not skipped ==="
printf '{ this is not json' > "$SUITE/remotes/draft2020-12/broken.json"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/nimcache}" nim r --nimcache:"${XDG_CACHE_HOME:-/tmp/nimcache}" \
  --hints:off --path:"$ROOT/src" "$WORK/remote_probe.nim" "$SUITE/remotes" \
  > "$WORK/probe2.out" 2>&1
if grep -q "^problems=1$" "$WORK/probe2.out"; then
  ok "a malformed remote schema produces a problem"
else
  no "a malformed remote schema produces a problem"
  cat "$WORK/probe2.out"
fi
if grep -q "not well-formed JSON" "$WORK/probe2.out"; then
  ok "the problem names the malformed document"
else
  no "the problem names the malformed document"
fi
# The document must not have been registered: a malformed schema that was
# silently skipped would be a schema that was measured against nothing.
if grep -q "^files=1$" "$WORK/probe2.out"; then
  ok "the malformed remote schema is not counted as read"
else
  no "the malformed remote schema is not counted as read"
fi
rm -f "$SUITE/remotes/draft2020-12/broken.json"

echo
echo "=== the qualification authority is decided by the verification ==="
# The production qualification script decides the authority of its own
# result. The decision is exercised here through the production script
# itself, in its inputs-only mode: the decision is the production
# decision, and the mode only avoids the measurement.
QUALIFY="$ROOT/tools/qualify_validator.sh"

# The digest of the synthetic suite, computed exactly as the production
# script computes it.
synthetic_digest() {
  find "$SUITE/tests/draft2020-12" "$SUITE/remotes" -type f -name '*.json' | \
    LC_ALL=C sort | \
    while read -r f; do printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" \
      "${f#"$SUITE"/}"; done | sha256sum | cut -d' ' -f1
}

# (a) A modified input with the repository pin is refused.
set +e
bash "$QUALIFY" --check-inputs-only --suite "$SUITE" > "$WORK/refused.out" 2>&1
REFUSED_STATUS=$?
set -e
if [ "$REFUSED_STATUS" -ne 0 ]; then
  ok "a modified input with the repository pin is refused"
else
  no "a modified input with the repository pin is refused"
  cat "$WORK/refused.out"
fi
if grep -q "does not match the pinned digest" "$WORK/refused.out"; then
  ok "the refusal names the pinned digest"
else
  no "the refusal names the pinned digest"
fi
if grep -q "^qualification_authoritative=true$" "$WORK/refused.out"; then
  no "the refused input was classified as authoritative"
else
  ok "the refused input is not classified as authoritative"
fi

# (b) A modified input with a caller-supplied matching digest is a
#     development-only result.
DIGEST=$(synthetic_digest)
set +e
env IRK_QUALIFY_EXPECTED_INPUTS_DIGEST="$DIGEST" \
  bash "$QUALIFY" --check-inputs-only --suite "$SUITE" > "$WORK/override.out" 2>&1
OVERRIDE_STATUS=$?
set -e
if [ "$OVERRIDE_STATUS" -eq 0 ]; then
  ok "a caller-supplied digest accepts the modified input"
else
  no "a caller-supplied digest accepts the modified input"
  cat "$WORK/override.out"
fi
if grep -q "^qualification_authoritative=false$" "$WORK/override.out"; then
  ok "a caller-supplied digest yields a non-authoritative result"
else
  no "a caller-supplied digest yields a non-authoritative result"
  cat "$WORK/override.out"
fi
if grep -q "^qualification_classification=development-override$" "$WORK/override.out"; then
  ok "the development-only result is classified as such"
else
  no "the development-only result is classified as such"
fi

# (c) A caller cannot promote that result to authoritative.
set +e
env IRK_QUALIFY_EXPECTED_INPUTS_DIGEST="$DIGEST" IRK_QUALIFY_AUTHORITATIVE=1 \
  bash "$QUALIFY" --check-inputs-only --suite "$SUITE" > "$WORK/promote.out" 2>&1
PROMOTE_STATUS=$?
set -e
if grep -q "^qualification_authoritative=true$" "$WORK/promote.out"; then
  no "a caller promoted a development-only result to authoritative"
else
  ok "a caller cannot promote a development-only result to authoritative"
fi
if grep -q "^qualification_classification=development-override$" "$WORK/promote.out"; then
  ok "the promotion attempt leaves the result development-only"
else
  no "the promotion attempt leaves the result development-only"
fi

# (d) The production gate refuses a development-only result.
set +e
env IRK_QUALIFY_EXPECTED_INPUTS_DIGEST="$DIGEST" IRK_QUALIFY_AUTHORITATIVE=1 \
  IRK_QUALIFY_REQUIRE_AUTHORITATIVE=1 \
  bash "$QUALIFY" --check-inputs-only --suite "$SUITE" > "$WORK/gate.out" 2>&1
GATE_STATUS=$?
set -e
if [ "$GATE_STATUS" -ne 0 ]; then
  ok "the production gate refuses a development-only result"
else
  no "the production gate refuses a development-only result"
  cat "$WORK/gate.out"
fi
if grep -q "requires an authoritative qualification" "$WORK/gate.out"; then
  ok "the gate names the authority requirement"
else
  no "the gate names the authority requirement"
fi

# The authority mechanism itself must be gone: no environment variable
# may grant authority.
if grep -q 'IRK_QUALIFY_AUTHORITATIVE' "$QUALIFY"; then
  no "the qualification script still reads an authority assertion"
else
  ok "the qualification script reads no authority assertion"
fi

echo
echo "=== the qualification script binds both trees ==="
if grep -q 'REMOTES_DIR' tools/qualify_validator.sh; then
  ok "the qualification script digests the remote tree"
else
  no "the qualification script digests the remote tree"
fi
if grep -q 'INPUTS_DIGEST=' tools/qualify_validator.sh; then
  ok "the qualification script digests the inputs together"
else
  no "the qualification script digests the inputs together"
fi

echo
echo "=== summary ==="
echo "passed: ${PASSED}  failed: ${FAILED}"
if [ "$FAILED" -gt 0 ]; then
  echo "RESULT: FAIL — the qualification input integrity does not hold"
  exit 1
fi
echo "RESULT: PASS — the qualification input integrity holds"
exit 0
