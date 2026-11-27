#!/usr/bin/env bash
# The Ironkeeper validator qualification.
#
# This is the *deterministic* command that reproduces the validator
# qualification. It pins every input, so that a result always identifies
# the exact artefacts it was measured against.
#
# Pinned inputs:
#
#   | Input        | Pin                                                    |
#   |--------------|--------------------------------------------------------|
#   | Validator    | jschema at $JSCHEMA_COMMIT, tree digest verified      |
#   | Test suite   | JSON-Schema-Test-Suite at $SUITE_REVISION              |
#   | Draft        | Draft 2020-12                                          |
#   | Corpus       | every file under tests/draft2020-12 (mandatory) and     |
#   |              | tests/draft2020-12/optional (optional, classified)     |
#
# The suite is *not* required for routine developer iteration: the test
# suite of the project itself does not need it. It is required to
# requalify, which is necessary whenever the dependency revision, the
# adapter, the numeric policy or the supported keyword set changes.
#
# Usage:
#   tools/qualify_validator.sh [--suite <path>]
#
# With no --suite, the suite is cloned into a temporary directory at the
# pinned revision.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

JSCHEMA_COMMIT="a936862556f24fde475059c560c1a13f00291457"
JSCHEMA_TREE_SHA256="323f47f85dba93a0f96bd3ffd6ec964abe2663e260c988596d7a49a0d68573a8"
JSCHEMA_REPO="https://github.com/Niminem/jschema.git"
SUITE_REVISION="245a45abc90190c0bff04d97e6d2b541b4bb9f12"
SUITE_REPO="https://github.com/json-schema-org/JSON-Schema-Test-Suite.git"

NIM="${NIM:-nim}"
KEEP="${IRK_QUALIFY_KEEP:-0}"

# ---- the invocation-owned workspace ----------------------------------------
# The caller may supply a location through IRK_QUALIFY_WORK. That
# location is a **parent** directory: the qualification creates a unique
# workspace *inside* it and removes only that workspace. The caller's own
# files and directories are never removed.
#
# The previous behaviour removed IRK_QUALIFY_WORK itself, recursively. A
# caller who pointed it at a directory with other content lost that
# content.
WORK_PARENT="${IRK_QUALIFY_WORK:-${TMPDIR:-/tmp}}"
mkdir -p "$WORK_PARENT"
WORK=$(mktemp -d "$WORK_PARENT/irk-qualify.XXXXXX")
# The workspace is owned by this invocation. Only it is removed.
WORK_OWNED=1

cleanup() {
  if [ "$KEEP" = "1" ]; then
    echo "qualification work directory kept: $WORK"
    return
  fi
  if [ "$WORK_OWNED" = "1" ] && [ -n "$WORK" ] && [ -d "$WORK" ]; then
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

SUITE_DIR=""
if [ "${1:-}" = "--suite" ]; then
  SUITE_DIR="$2"
fi

# ---- the validator --------------------------------------------------------
# The dependency is resolved at the exact commit and its tree digest is
# verified. The digest pins the whole tree, so a rewritten tag or a
# changed file is detected.
DEPS="$WORK/jschema"
git clone --quiet "$JSCHEMA_REPO" "$DEPS"
git -C "$DEPS" checkout --quiet "$JSCHEMA_COMMIT"
ACTUAL_TREE=$(git -C "$DEPS" archive HEAD | sha256sum | cut -d' ' -f1)
if [ "$ACTUAL_TREE" != "$JSCHEMA_TREE_SHA256" ]; then
  echo "qualify_validator: the validator tree digest does not match" >&2
  echo "  expected: $JSCHEMA_TREE_SHA256" >&2
  echo "  actual:   $ACTUAL_TREE" >&2
  exit 1
fi
echo "validator_commit=$JSCHEMA_COMMIT"
echo "validator_tree_sha256=$ACTUAL_TREE"

# ---- the test suite -------------------------------------------------------
if [ -z "$SUITE_DIR" ]; then
  SUITE_DIR="$WORK/suite"
  git clone --quiet --branch legacy "$SUITE_REPO" "$SUITE_DIR"
fi
ACTUAL_SUITE=$(git -C "$SUITE_DIR" rev-parse HEAD)
if [ "$ACTUAL_SUITE" != "$SUITE_REVISION" ]; then
  echo "qualify_validator: the test suite is not at the pinned revision" >&2
  echo "  expected: $SUITE_REVISION" >&2
  echo "  actual:   $ACTUAL_SUITE" >&2
  exit 1
fi
echo "suite_revision=$ACTUAL_SUITE"

# ---- the input identity ------------------------------------------------------
# The tested input is identified by its own digest, not only by the
# revision of the checkout. A checkout can be modified without its
# revision changing, so the digest is what identifies the corpus.
#
# The digest covers **both** trees that the qualification consumes: the
# Draft 2020-12 corpus *and* the remote schemas the corpus references. A
# digest over the corpus alone would not identify the input, because a
# modified remote schema changes the answer without changing the corpus.
CORPUS_DIR="$SUITE_DIR/tests/draft2020-12"
REMOTES_DIR="$SUITE_DIR/remotes"
INPUTS_DIGEST=$(find "$CORPUS_DIR" "$REMOTES_DIR" -type f -name '*.json' | \
  LC_ALL=C sort | \
  while read -r f; do printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" \
    "${f#"$SUITE_DIR"/}"; done | sha256sum | cut -d' ' -f1)
echo "corpus_dir=$CORPUS_DIR"
echo "remotes_dir=$REMOTES_DIR"
echo "inputs_digest_sha256=$INPUTS_DIGEST"

# The pinned digest of both trees at the pinned revision.
SUITE_INPUTS_DIGEST="45bf30e6bc639547d4b7a75fe152fce5451e523fa976ff82f0576e9c6fcd1322"
EXPECTED_INPUTS_DIGEST="$SUITE_INPUTS_DIGEST"

# A caller-supplied digest override is a **development** convenience. It
# is accepted only when the caller states that the result is not
# authoritative, and the result is classified accordingly: an
# unqualified override never produces an authoritative verdict.
AUTHORITATIVE=1
if [ -n "${IRK_QUALIFY_EXPECTED_INPUTS_DIGEST:-}" ]; then
  EXPECTED_INPUTS_DIGEST="$IRK_QUALIFY_EXPECTED_INPUTS_DIGEST"
  if [ "${IRK_QUALIFY_AUTHORITATIVE:-0}" != "1" ]; then
    echo "qualification_authoritative=false"
    echo "qualification_classification=development-override"
    echo "qualify_validator: the expected digest was supplied by the caller;" >&2
    echo "  the result is therefore NOT authoritative" >&2
  else
    echo "qualification_authoritative=true"
  fi
else
  echo "qualification_authoritative=true"
fi

if [ "$EXPECTED_INPUTS_DIGEST" != "$INPUTS_DIGEST" ]; then
  echo "qualify_validator: the tested input does not match the expected digest" >&2
  echo "  expected: $EXPECTED_INPUTS_DIGEST" >&2
  echo "  actual:   $INPUTS_DIGEST" >&2
  exit 1
fi
echo "inputs_digest_verified=true"

# ---- the remote schema tree --------------------------------------------------
# The remote schemas are mandatory inputs. A missing or malformed remote
# schema is refused: the harness would otherwise measure a corpus whose
# references it could not resolve.
if [ ! -d "$REMOTES_DIR" ]; then
  echo "qualify_validator: the remote schema tree is missing: $REMOTES_DIR" >&2
  exit 1
fi
REMOTE_COUNT=$(find "$REMOTES_DIR" -type f -name '*.json' | wc -l | tr -d ' ')
echo "remote_schema_files=$REMOTE_COUNT"
if [ "$REMOTE_COUNT" -eq 0 ]; then
  echo "qualify_validator: the remote schema tree is empty" >&2
  exit 1
fi

# ---- the non-vacuity witnesses ---------------------------------------------
# The harness's own oracle is witnessed first. A harness that cannot be
# shown to reject a wrong answer is not an oracle, so the qualification
# refuses to run without this step.
echo "=== the harness oracle is witnessed against controlled providers ==="
"$NIM" r --hints:off --path:"$ROOT/src" --path:"$DEPS/src" \
  tools/validator_conformance_witnesses.nim \
  --corpus "$ROOT/tests/fixtures/conformance"

# ---- run the harness ------------------------------------------------------
"$NIM" r --hints:off --path:"$ROOT/src" --path:"$DEPS/src" \
  tools/validator_conformance.nim --suite "$SUITE_DIR"
