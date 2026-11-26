#!/usr/bin/env bash
# Shared fail-closed gate helper for the Ironkeeper CI gates.
#
# Every repository-owned gate script sources this file. It exists so that
# the gate logic is written once, in one place, and so that a mandatory
# command failure can never be converted into a successful gate.
#
# The invariant this file enforces:
#
#   > No mandatory command failure may be converted into a successful CI
#   > gate by subsequent execution, logging, report generation or artifact
#   > collection.
#
# Design rules:
#
#   * `gate_run` executes exactly one mandatory command and returns *its*
#     exit status. It never runs a second command whose status could
#     overwrite the first.
#   * Diagnostics are collected by a *separate* call to `gate_diagnose`,
#     which is explicitly non-mandatory and is never allowed to change the
#     gate result.
#   * `gate_require_file` asserts that a mandatory artefact exists and is
#     non-empty. A missing or malformed artefact is a failure, never an
#     implicit "clean".
#
# Environment:
#   GATE_LOG_DIR   directory that receives the diagnostic logs
#                  (default: ./gate-logs)

set -euo pipefail

GATE_LOG_DIR="${GATE_LOG_DIR:-./gate-logs}"
mkdir -p "$GATE_LOG_DIR"

# gate_run <label> <command> [args...]
#
# Run one mandatory command. Its stdout and stderr are captured into
# "$GATE_LOG_DIR/<label>.log" and echoed to the terminal. The function
# returns the command's own exit status.
gate_run() {
  local label="$1"
  shift
  local log="$GATE_LOG_DIR/${label}.log"
  local status=0
  # `set -e` is deliberately suspended *only* around the command itself so
  # that its status can be observed. Nothing else runs inside this block,
  # so there is no later command whose success could mask the failure.
  set +e
  "$@" > "$log" 2>&1
  status=$?
  set -e
  cat "$log" || true
  if [ "$status" -ne 0 ]; then
    echo "gate: FAIL ${label} (exit ${status}); log: ${log}" >&2
  else
    echo "gate: ok   ${label}"
  fi
  return "$status"
}

# gate_diagnose <label> <command> [args...]
#
# Run a *non-mandatory* diagnostic command. Its output is captured and
# echoed. Its exit status is deliberately discarded: diagnostics never
# influence the gate verdict. This is the only sanctioned way to render a
# log or to collect an artefact after a mandatory command has failed.
gate_diagnose() {
  local label="$1"
  shift
  local log="$GATE_LOG_DIR/${label}.log"
  set +e
  "$@" > "$log" 2>&1
  local status=$?
  set -e
  cat "$log" || true
  echo "gate: diagnostic ${label} (exit ${status}, not authoritative)"
  return 0
}

# gate_require_file <label> <path>
#
# Assert that a mandatory artefact exists and is not empty. A missing or
# empty artefact is a gate failure: it is never reported as a clean run.
gate_require_file() {
  local label="$1"
  local path="$2"
  if [ ! -f "$path" ]; then
    echo "gate: FAIL ${label}: mandatory report is missing: ${path}" >&2
    return 1
  fi
  if [ ! -s "$path" ]; then
    echo "gate: FAIL ${label}: mandatory report is empty: ${path}" >&2
    return 1
  fi
  echo "gate: ok   ${label} (${path} present)"
  return 0
}

# gate_summarise <name> <failed-label>...
#
# Print the final verdict of a gate. The verdict is derived from the
# accumulated failure list, never from the status of a trailing command.
gate_summarise() {
  local name="$1"
  shift
  if [ "$#" -gt 0 ]; then
    echo "gate: FAIL ${name}: failed mandatory step(s): $*" >&2
    return 1
  fi
  echo "gate: PASS ${name}"
  return 0
}
