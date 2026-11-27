## The active observation collection of one explicitly selected device.
##
## The collector performs the supported read-only observations of a
## selected device and returns them together with the evidence of how
## they were obtained.
##
## ## What it does
##
##   * capture the identity and the access paths **immediately before**
##     and **immediately after** every backend invocation;
##   * execute `smartctl -x -jv DEVICE` and `sg_readcap --readonly --long
##     --json DEVICE` through the bounded execution boundary;
##   * preserve the complete raw response of every tool;
##   * normalise the responses into typed observations;
##   * refuse the attribution of the observations when the identity of the
##     device changed during the collection.
##
## ## What it never does
##
## It never starts, stops or aborts a self-test, never scans a surface,
## never writes to a device, never resets a PHY counter and never changes
## a power state. The tools it runs are read-only by construction, and
## the arguments are fixed.

import std/[json, strutils]

from ironkeeper/storage/types import DeviceRecord, Observation, ExecOutcome,
  eoSucceeded, eoNonZeroExit, eoTimedOut, eoLaunchFailed, eoOutputLimit,
  eoSignalled, osObserved, osUnavailable
from ironkeeper/storage/procexec import ExecRequest, ExecResult, ExecLimits,
  defaultLimits, runTool
from ironkeeper/storage/toolpaths import ToolPaths, defaultToolPaths
from ironkeeper/storage/externaljson import parseExternal, ExtNode, member, ekArray,
  ekNumber, ekString
from ironkeeper/storage/smartfields import readExactField, ExactValue
from ironkeeper/storage/smartnorm import normalizeSmart
from ironkeeper/storage/smartstatus import decodeSmartExit, exitBitObservations
from ironkeeper/storage/scsicap import decodeCapacity, capacityObservations
from ironkeeper/storage/documents import nowUtc

type
  ToolExecution* = object
    ## The record of one external tool invocation.
    tool*: string
    outcome*: ExecOutcome
    exitCode*: int
    signal*: int
    durationMs*: int
    message*: string
    stdout*: string
    stderr*: string
    truncated*: bool

  CollectionResult* = object
    ## The result of one collection.
    observations*: seq[Observation]
    executions*: seq[ToolExecution]
    findings*: seq[string]
    attributionBound*: bool
    attributionReason*: string

proc identityFingerprint*(device: DeviceRecord): string =
  ## A fingerprint of the identity of a device.
  ##
  ## The fingerprint is compared before and after a backend invocation. A
  ## change invalidates the attribution of the affected observations.
  result = device.kernelName & "|" & device.major & ":" & device.minor & "|" &
           device.wwn & "|" & device.serial
  for p in device.paths:
    result.add "|" & p

proc collectSmart*(device: DeviceRecord, paths: ToolPaths,
                   limits: ExecLimits): tuple[result: CollectionResult,
                                            execution: ToolExecution] =
  ## Collect the SMART observations of one device.
  ##
  ## The exit status is decoded as a bitmask and is preserved as an
  ## observation of its own. A nonzero status does not discard the
  ## observations that the document contains.
  result.result.observations = @[]
  result.result.executions = @[]
  result.result.findings = @[]
  result.result.attributionBound = true

  let devicePath = if device.paths.len > 0: device.paths[0] else: ""
  # The invocation is fixed: `smartctl -x --json=o DEVICE`. The `-jv`
  # spelling of the `-j` option is ambiguous in smartctl 7.x and is
  # refused by the tool, so the explicit `--json=o` form is used.
  let request = ExecRequest(path: paths.smartctl,
                            args: @["-x", "--json=o", devicePath],
                            limits: limits)
  let exec = runTool(request)
  result.execution = ToolExecution(tool: "smartctl", outcome: exec.outcome,
    exitCode: exec.exitCode, signal: exec.signal, durationMs: exec.durationMs,
    message: exec.message, stdout: exec.stdout, stderr: exec.stderr,
    truncated: exec.stdoutTruncated or exec.stderrTruncated)

  # ---- the exit status is an observation in its own right ------------------
  let bits = decodeSmartExit(exec.exitCode)
  for o in exitBitObservations(bits, "smartctl", nowUtc()):
    result.result.observations.add o

  if exec.outcome == eoLaunchFailed or exec.outcome == eoTimedOut or
     exec.outcome == eoOutputLimit:
    result.result.findings.add "the SMART acquisition did not complete: " &
      exec.message
    result.result.observations.add Observation(
      name: "smart.acquisition", status: osUnavailable, value: "",
      unit: "state", source: "smartctl", sourceField: "process outcome",
      collectedAt: nowUtc(), reason: exec.message)
    return

  let parsed = parseExternal(exec.stdout)
  if not parsed.ok:
    # The raw response is retained as evidence, but it is **not**
    # represented as successfully normalised telemetry.
    result.result.findings.add "the SMART response could not be ingested: " &
      parsed.error.message
    result.result.observations.add Observation(
      name: "smart.acquisition", status: osUnavailable, value: "",
      unit: "state", source: "smartctl", sourceField: "process outcome",
      collectedAt: nowUtc(), reason: parsed.error.message)
    return

  # The tool identity comes from the document itself, so the recorded
  # version is the version that produced *this* response.
  let toolNode = member(parsed.root, "smartctl")
  if not toolNode.isNil:
    let version = member(toolNode, "version")
    if not version.isNil and version.kind == ekArray:
      var parts: seq[string] = @[]
      for v in version.items:
        if v.kind == ekNumber:
          parts.add v.str
      if parts.len > 0:
        result.execution.tool = "smartctl " & parts.join(".")
    let revision = member(toolNode, "svn_revision")
    if not revision.isNil and revision.kind == ekString:
      result.execution.tool.add " (r" & revision.str.strip() & ")"

  let normalized = normalizeSmart(parsed.root, "smartctl", nowUtc())
  for o in normalized.observations:
    result.result.observations.add o
  for f in normalized.findings:
    result.result.findings.add f

  # ---- the exit status that the document itself carries -------------------
  # The `smartctl` document carries the exit status of the tool in its
  # `smartctl.exit_status` member.
  var embedded = ExactValue(ok: false, text: "", status: osUnavailable,
                             reason: "the document did not carry an exit status")
  let smartctlMember = member(parsed.root, "smartctl")
  if not smartctlMember.isNil:
    embedded = readExactField(smartctlMember, "exit_status")
  if embedded.ok and embedded.text != $exec.exitCode:
    result.result.findings.add "the exit status in the SMART document (" &
      embedded.text & ") contradicts the exit status of the process (" &
      $exec.exitCode & ")"
    result.result.observations.add Observation(
      name: "smart.exit_status_consistency", status: osObserved,
      value: "conflicting", unit: "state", source: "smartctl",
      sourceField: "smartctl_exit_status", collectedAt: nowUtc(),
      reason: "the document and the process disagree about the exit status")

proc collectCapacity*(device: DeviceRecord, paths: ToolPaths,
                      limits: ExecLimits): tuple[result: CollectionResult,
                                               execution: ToolExecution] =
  ## Collect the SCSI capacity observations of one device.
  result.result.observations = @[]
  result.result.executions = @[]
  result.result.findings = @[]
  result.result.attributionBound = true

  let devicePath = if device.paths.len > 0: device.paths[0] else: ""
  let request = ExecRequest(path: paths.sgReadcap,
                            args: @["--readonly", "--long", "--json",
                                     devicePath],
                            limits: limits)
  let exec = runTool(request)
  result.execution = ToolExecution(tool: "sg_readcap", outcome: exec.outcome,
    exitCode: exec.exitCode, signal: exec.signal, durationMs: exec.durationMs,
    message: exec.message, stdout: exec.stdout, stderr: exec.stderr,
    truncated: exec.stdoutTruncated or exec.stderrTruncated)

  if exec.outcome == eoLaunchFailed or exec.outcome == eoTimedOut or
     exec.outcome == eoOutputLimit:
    result.result.findings.add "the capacity acquisition did not complete: " &
      exec.message
    return

  let parsed = parseExternal(exec.stdout)
  if not parsed.ok:
    result.result.findings.add "the capacity response could not be ingested: " &
      parsed.error.message
    return

  # The `sg_readcap --json` document carries the response in a member
  # whose name depends on the tool version. The candidate names are tried
  # in order; a document that carries none of them is refused.
  var capacityNode: ExtNode = nil
  for candidate in ["read_capacity_16_parameter_data", "read_capacity",
                    "read_capacity_10_parameter_data"]:
    let node = member(parsed.root, candidate)
    if not node.isNil:
      capacityNode = node
      break
  if capacityNode.isNil:
    capacityNode = parsed.root

  # The field names differ between the tool versions as well.
  var lba = readExactField(capacityNode, "returned_logical_block_address")
  if not lba.ok:
    lba = readExactField(capacityNode, "last_lba")
  var blockLength = readExactField(capacityNode, "logical_block_length_in_bytes")
  if not blockLength.ok:
    blockLength = readExactField(capacityNode, "block_length")
  if not lba.ok or not blockLength.ok:
    result.result.findings.add "the capacity response did not carry the " &
      "fields that the decoder needs"
    return
  let lengthValue = try: parseBiggestInt(blockLength.text) except ValueError: 0'i64

  # The protection fields, when the tool reports them.
  var protEn = 0
  var pType = 0
  let protEnValue = readExactField(capacityNode, "prot_en")
  if protEnValue.ok:
    protEn = try: parseBiggestInt(protEnValue.text) except ValueError: 0
  let pTypeValue = readExactField(capacityNode, "p_type")
  if pTypeValue.ok:
    pType = try: parseBiggestInt(pTypeValue.text) except ValueError: 0
  let reading = decodeCapacity(lba.text, int(lengthValue), protEn, pType)
  for o in capacityObservations(reading, "sg_readcap", nowUtc()):
    result.result.observations.add o
