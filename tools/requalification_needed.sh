#!/usr/bin/env bash
# Decide whether a change requires requalification of the validator.
#
# The upstream conformance suite is large and it is not run for every
# ordinary change. It is run when a change can affect the validator, the
# supported schema policy, the reference policy, the qualification
# harness, the pinned dependency or the pinned toolchain.
#
# The decision is made by this repository-owned script, from the paths
# that changed. It is not a heuristic in a workflow file: the rule lives
# with the code it protects, and it is testable.
#
# ## Fail-closed
#
# The script never reports "not needed" because it could not establish
# what changed. Every situation in which the comparison authority is
# missing, unresolvable or unusable produces "needed", or an explicit
# failure of the gate. Absence of evidence is not evidence of absence.
#
# ## Usage
#   tools/requalification_needed.sh [<base-ref>]
#
# With no base reference, the working tree is compared with HEAD.
#
# ## Output
#   requalification=needed
#   requalification=not-needed
#
# Each decision is accompanied by a reason line:
#   requalification_reason=<text>
#
# ## Exit status
#   0  the decision was made
#   1  the comparison authority could not be established

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# An *absent* argument means "compare the working tree with HEAD". An
# argument that is present but empty is a missing comparison base, and it
# is treated as such: the two cases are not the same, and the empty one
# must not be silently replaced.
BASE="${1-HEAD}"

# The paths that can change the validator's behaviour, the supported
# subset, the harness that measures them, the fixtures it measures them
# against, the pinned dependency, the pinned toolchain or the workflow
# that runs the qualification.
#
# Every actual input of the qualification is listed here. A path that is
# not listed cannot influence the qualification, and a path that is
# listed always forces it.
PATHS='^src/ironkeeper/contracts/|^src/ironkeeper/json/|^src/ironkeeper/qualification/|^tools/validator_conformance|^tools/qualify_validator\.sh$|^tools/requalification_needed\.sh$|^tools/install_nim_toolchain\.sh$|^tools/embed_schemas\.nim$|^schemas/|^tests/fixtures/conformance/|^tests/draft2020-12/|^remotes/|^ironkeeper\.nimble$|^\.github/workflows/ci\.yml$'

# ---- the comparison authority ------------------------------------------------
# The base must exist and must resolve. A base that cannot be resolved
# means that the change evidence cannot be established, so the
# qualification is required.
if [ -z "$BASE" ]; then
  echo "requalification=needed"
  echo "requalification_reason=no comparison base was supplied"
  exit 0
fi

# The all-zero object id is what a push event carries when the branch
# did not exist before. It names no commit, so it is no comparison
# authority: the first push of a branch always requires the qualification.
case "$BASE" in
  0000000000000000000000000000000000000000)
    echo "requalification=needed"
    echo "requalification_reason=the branch has no previous commit to compare against"
    exit 0
    ;;
esac

if ! git rev-parse --verify --quiet "$BASE^{commit}" > /dev/null 2>&1; then
  echo "requalification=needed"
  echo "requalification_reason=the base reference '$BASE' could not be resolved"
  exit 0
fi

# ---- the changed paths --------------------------------------------------------
# A failed diff is not an empty diff. The failure is not suppressed: the
# qualification is required, because the change evidence is missing.
CHANGED=""
if ! CHANGED=$(git diff --name-only "$BASE" -- . 2> /dev/null); then
  echo "requalification=needed"
  echo "requalification_reason=the comparison against '$BASE' could not be established"
  exit 0
fi

if [ -z "$CHANGED" ]; then
  # Nothing changed against the base in the working tree. The staged
  # state is consulted as well, because a change that is staged but not
  # committed is still a change.
  if ! CHANGED=$(git diff --name-only --cached HEAD -- . 2> /dev/null); then
    echo "requalification=needed"
    echo "requalification_reason=the staged comparison could not be established"
    exit 0
  fi
fi

if [ -z "$CHANGED" ]; then
  # The comparison succeeded and established that nothing changed. A
  # *known* documentation-only change may be skipped.
  echo "requalification=not-needed"
  echo "requalification_reason=no path relevant to the qualification changed"
  exit 0
fi

while IFS= read -r path; do
  [ -n "$path" ] || continue
  if printf '%s\n' "$path" | grep -qE "$PATHS"; then
    echo "requalification=needed"
    echo "requalification_reason=$path"
    exit 0
  fi
done <<< "$CHANGED"

echo "requalification=not-needed"
echo "requalification_reason=no path relevant to the qualification changed"
