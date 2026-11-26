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
WORK="${IRK_QUALIFY_WORK:-$(mktemp -d "${TMPDIR:-/tmp}/irk-qualify.XXXXXX")}"
KEEP="${IRK_QUALIFY_KEEP:-0}"

cleanup() {
  if [ "$KEEP" != "1" ]; then
    rm -rf "$WORK"
  else
    echo "qualification work directory kept: $WORK"
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

# ---- run the harness ------------------------------------------------------
"$NIM" r --hints:off --path:"$ROOT/src" --path:"$DEPS/src" \
  tools/validator_conformance.nim --suite "$SUITE_DIR"
