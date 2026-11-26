#!/usr/bin/env bash
# The embedded-schema drift gate.
#
# Verifies that the schema bytes embedded in the binary are byte-for-byte
# identical to the repository files in `schemas/v1/`. A drift is a failure:
# the binary would otherwise validate against contracts that are not the
# published ones.
#
# The check tool is run through `gate_run`, so its own exit status decides
# the verdict. Nothing runs after it that could turn a failure into a
# success.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# shellcheck source=tools/gate.sh
. "$ROOT/tools/gate.sh"

NIM="${NIM:-nim}"

if ! gate_run schema-drift "$NIM" r --hints:off tools/embed_schemas.nim --check; then
  gate_summarise "schema-drift" "schema-drift" || exit 1
  exit 1
fi

gate_summarise "schema-drift"
