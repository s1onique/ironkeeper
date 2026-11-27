#!/usr/bin/env bash
# Decide whether a change requires requalification of the validator.
#
# The upstream conformance suite is large and it is not run for every
# ordinary change. It is run when a change can affect the validator, the
# supported schema policy, the reference policy, the qualification
# harness or the pinned dependency.
#
# The decision is made by this repository-owned script, from the paths
# that changed. It is not a heuristic in a workflow file: the rule lives
# with the code it protects, and it is testable.
#
# Usage:
#   tools/requalification_needed.sh [<base-ref>]
#
# With no base reference, the working tree is compared with HEAD.
#
# Output:
#   requalification=needed
#   requalification=not-needed
#
# Exit status:
#   0  the decision was made
#   1  the base reference could not be resolved

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

BASE="${1:-HEAD}"

# The paths that can change the validator's behaviour, the supported
# subset, the harness that measures them, or the pinned dependency.
PATHS='^src/ironkeeper/contracts/|^src/ironkeeper/json/|^src/ironkeeper/qualification/|^tools/validator_conformance|^tools/qualify_validator\.sh$|^tools/embed_schemas\.nim$|^schemas/|^ironkeeper\.nimble$'

if ! git rev-parse --verify --quiet "$BASE" > /dev/null; then
  echo "requalification_needed: the base reference '$BASE' could not be resolved" >&2
  exit 1
fi

CHANGED=$(git diff --name-only "$BASE" -- . || true)
if [ -z "$CHANGED" ]; then
  # Nothing changed against the base: the committed state is the subject.
  CHANGED=$(git diff --name-only --cached HEAD -- . || true)
fi

for path in $CHANGED; do
  if echo "$path" | grep -qE "$PATHS"; then
    echo "requalification=needed"
    echo "requalification_reason=$path"
    exit 0
  fi
done

echo "requalification=not-needed"
