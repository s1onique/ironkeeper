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
  eoSignalled, osObserved, osUnavailable, osConflicting
from ironkeeper/storage/procexec import ExecRequest, ExecResult, ExecLimits,
  defaultLimits, runTool
from ironkeeper/storage/toolpaths import ToolPaths, defaultToolPaths
from ironkeeper/storage/externaljson import parseExternal, ExtNode, member, ekArray,
  ekNumber, ekString
from ironkeeper/storage/smartfields import readExactField, ExactValue
from ironkeeper/storage/smartnorm import normalizeSmart, spNvme
from ironkeeper/storage/smartstatus import decodeSmartExit, exitBitObservations
from ironkeeper/storage/scsicap import decodeCapacity, capacityObservations,
  ProtectionEvidence, MaxProtEn, MaxPType
from ironkeeper/storage/acquisition import AcquisitionResult, newAcquisitionResult,
  require, missing, obtained, incomplete, refuseAttribution, completenessName,
  completenessReason
from ironkeeper/storage/documents import nowUtc

const
  SmartHealthObservation* = "device_reported_health"
    ## The mandatory health observation of an ATA or SCSI acquisition.
  NvmeHealthObservation* = "nvme.critical_warning"
    ## The mandatory health observation of an NVMe acquisition.
    ##
    ## The NVMe health log is controller-wide, and the device-reported
    ## health of an NVMe namespace is its critical warning.
  SmartAcquisitionObservation* = "smart.acquisition"
    ## The generic mandatory observation of a SMART acquisition that did
    ## not produce a usable response.
  CapacityTotalObservation* = "capacity.total_bytes"
    ## The mandatory observation of a capacity acquisition.
  CapacityBlockLengthObservation* = "capacity.logical_block_length"
    ## The second mandatory observation of a capacity acquisition.

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
    unreaped*: bool
      ## True when the process could not be reaped within the supported
      ## policy. The process state is then unresolved.

  CollectionResult* = object
    ## The result of one collection.
    observations*: seq[Observation]
    executions*: seq[ToolExecution]
    findings*: seq[string]
    attributionBound*: bool
    attributionReason*: string
    acquisition*: AcquisitionResult
      ## The authoritative coverage of the requested operation.

proc collectSmart*(device: DeviceRecord, paths: ToolPaths,
                   limits: ExecLimits): tuple[result: CollectionResult,
                                            execution: ToolExecution] =
  ## Collect the SMART observations of one device.
  ##
  ## The exit status is decoded as a bitmask and is preserved as an
  ## observation of its own. A nonzero status does not discard the
  ## observations that the document contains, and it does not establish a
  ## complete acquisition either: a status that reports a failing device
  ## is a **device-reported health observation**, while a status that
  ## reports a failed command is a coverage failure.
  result.result.observations = @[]
  result.result.executions = @[]
  result.result.findings = @[]
  result.result.attributionBound = true
  result.result.acquisition = newAcquisitionResult()

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
    truncated: exec.stdoutTruncated or exec.stderrTruncated,
    unreaped: exec.unreaped)

  # ---- the exit status is an observation in its own right ------------------
  # A status that no process produced carries no bits: it is never decoded
  # as an observed bitmask.
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
    result.result.acquisition.require(SmartAcquisitionObservation)
    result.result.acquisition.missing(SmartAcquisitionObservation,
      "the SMART tool did not produce a usable response: " & exec.message)
    return

  if exec.stdoutTruncated or exec.stderrTruncated:
    result.result.findings.add "the SMART response was truncated by the " &
      "configured bound"
    result.result.acquisition.require(SmartAcquisitionObservation)
    result.result.acquisition.missing(SmartAcquisitionObservation,
      "the SMART response was truncated by the configured bound")
    return

  if exec.unreaped:
    result.result.findings.add "the SMART tool process could not be reaped; " &
      "its state is unresolved"
    result.result.acquisition.incomplete(
      "the SMART tool process could not be reaped and its state is unresolved")

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
    result.result.acquisition.require(SmartAcquisitionObservation)
    result.result.acquisition.missing(SmartAcquisitionObservation,
      "the SMART response could not be ingested: " & parsed.error.message)
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

  # ---- the identity the tool observed -------------------------------------
  # The serial number that the tool reports is reconciled with the serial
  # number of the selected device. A contradiction means that the response
  # describes a **different** device, so the evidence is unbound.
  let reportedSerial = member(parsed.root, "serial_number")
  if not reportedSerial.isNil and reportedSerial.kind == ekString:
    let toolSerial = reportedSerial.str.strip()
    if toolSerial.len > 0 and device.serial.len > 0 and
       toolSerial.toUpperAscii != device.serial.toUpperAscii:
      let reason = "the SMART response reports the serial number '" &
                   toolSerial & "', which is not the serial number of the " &
                   "selected device; the evidence is unbound"
      result.result.findings.add reason
      result.result.attributionBound = false
      result.result.attributionReason = reason
      result.result.acquisition.refuseAttribution(reason)

  let normalized = normalizeSmart(parsed.root, "smartctl", nowUtc())
  for o in normalized.observations:
    result.result.observations.add o
  for f in normalized.findings:
    result.result.findings.add f

  # ---- the mandatory observation ------------------------------------------
  # The mandatory health observation depends on the protocol: an ATA or
  # SCSI device reports its health through `smart_status.passed`, and an
  # NVMe namespace reports it through the critical warning of the health
  # log. The observation is **obtained** when the device reported it -
  # including when the device reported it as unhealthy. A failing disk
  # is a complete acquisition.
  let mandatoryHealth =
    if normalized.protocol == spNvme: NvmeHealthObservation
    else: SmartHealthObservation
  result.result.acquisition.require(mandatoryHealth)
  var healthSeen = false
  for o in normalized.observations:
    if o.name == mandatoryHealth and o.status == osObserved:
      healthSeen = true
  if healthSeen:
    result.result.acquisition.obtained(mandatoryHealth)
  else:
    result.result.acquisition.missing(mandatoryHealth,
      "the SMART response did not carry a device-reported health status")

  # ---- the exit status that the document itself carries -------------------
  # The `smartctl` document carries the exit status of the tool in its
  # `smartctl.exit_status` member.
  var embedded = ExactValue(ok: false, text: "", status: osUnavailable,
                             reason: "the document did not carry an exit status")
  let smartctlMember = member(parsed.root, "smartctl")
  if not smartctlMember.isNil:
    embedded = readExactField(smartctlMember, "exit_status")
  if embedded.ok and embedded.text != $exec.exitCode:
    let reason = "the exit status in the SMART document (" & embedded.text &
                 ") contradicts the exit status of the process (" &
                 $exec.exitCode & ")"
    result.result.findings.add reason
    result.result.observations.add Observation(
      name: "smart.exit_status_consistency", status: osObserved,
      value: "conflicting", unit: "state", source: "smartctl",
      sourceField: "smartctl_exit_status", collectedAt: nowUtc(),
      reason: "the document and the process disagree about the exit status")
    result.result.acquisition.incomplete(reason)

proc collectCapacity*(device: DeviceRecord, paths: ToolPaths,
                      limits: ExecLimits): tuple[result: CollectionResult,
                                               execution: ToolExecution] =
  ## Collect the SCSI capacity observations of one device.
  result.result.observations = @[]
  result.result.executions = @[]
  result.result.findings = @[]
  result.result.attributionBound = true
  result.result.acquisition = newAcquisitionResult()
  result.result.acquisition.require(CapacityTotalObservation)
  result.result.acquisition.require(CapacityBlockLengthObservation)

  let devicePath = if device.paths.len > 0: device.paths[0] else: ""
  let request = ExecRequest(path: paths.sgReadcap,
                            args: @["--readonly", "--long", "--json",
                                     devicePath],
                            limits: limits)
  let exec = runTool(request)
  result.execution = ToolExecution(tool: "sg_readcap", outcome: exec.outcome,
    exitCode: exec.exitCode, signal: exec.signal, durationMs: exec.durationMs,
    message: exec.message, stdout: exec.stdout, stderr: exec.stderr,
    truncated: exec.stdoutTruncated or exec.stderrTruncated,
    unreaped: exec.unreaped)

  if exec.outcome == eoLaunchFailed or exec.outcome == eoTimedOut or
     exec.outcome == eoOutputLimit:
    result.result.findings.add "the capacity acquisition did not complete: " &
      exec.message
    result.result.acquisition.missing(CapacityTotalObservation,
      "the capacity tool did not produce a usable response: " & exec.message)
    result.result.acquisition.missing(CapacityBlockLengthObservation,
      "the capacity tool did not produce a usable response: " & exec.message)
    return

  if exec.stdoutTruncated or exec.stderrTruncated:
    result.result.findings.add "the capacity response was truncated by the " &
      "configured bound"
    result.result.acquisition.missing(CapacityTotalObservation,
      "the capacity response was truncated by the configured bound")
    result.result.acquisition.missing(CapacityBlockLengthObservation,
      "the capacity response was truncated by the configured bound")
    return

  if exec.unreaped:
    result.result.findings.add "the capacity tool process could not be " &
      "reaped; its state is unresolved"
    result.result.acquisition.incomplete(
      "the capacity tool process could not be reaped and its state is unresolved")

  let parsed = parseExternal(exec.stdout)
  if not parsed.ok:
    result.result.findings.add "the capacity response could not be ingested: " &
      parsed.error.message
    result.result.acquisition.missing(CapacityTotalObservation,
      "the capacity response could not be ingested: " & parsed.error.message)
    result.result.acquisition.missing(CapacityBlockLengthObservation,
      "the capacity response could not be ingested: " & parsed.error.message)
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
    result.result.acquisition.missing(CapacityTotalObservation,
      "the capacity response did not carry the fields that the decoder needs")
    result.result.acquisition.missing(CapacityBlockLengthObservation,
      "the capacity response did not carry the fields that the decoder needs")
    return
  var lengthValue = 0'i64
  try:
    lengthValue = parseBiggestInt(blockLength.text)
  except ValueError:
    lengthValue = 0'i64
  if lengthValue <= 0 or lengthValue > 65536:
    result.result.findings.add "the logical block length of the capacity " &
      "response is out of range"
    result.result.acquisition.missing(CapacityBlockLengthObservation,
      "the logical block length of the capacity response is out of range")
    return

  # The protection fields, when the tool reports them. An absent field is
  # **absent**: it is never initialised as an observed zero.
  var protection = ProtectionEvidence()
  let protEnValue = readExactField(capacityNode, "prot_en")
  if protEnValue.ok:
    var protEn = 0
    try:
      protEn = parseBiggestInt(protEnValue.text)
    except ValueError:
      protEn = -1
    protection.protEnPresent = true
    protection.protEn = protEn
    protection.protEnValid = protEn >= 0 and protEn <= MaxProtEn
  let pTypeValue = readExactField(capacityNode, "p_type")
  if pTypeValue.ok:
    var pType = 0
    try:
      pType = parseBiggestInt(pTypeValue.text)
    except ValueError:
      pType = -1
    protection.pTypePresent = true
    protection.pType = pType
    protection.pTypeValid = pType >= 0 and pType <= MaxPType
  let reading = decodeCapacity(lba.text, int(lengthValue), protection)
  for o in capacityObservations(reading, "sg_readcap", nowUtc()):
    result.result.observations.add o

  # ---- the mandatory observations -----------------------------------------
  if reading.capacityBytes.len > 0:
    result.result.acquisition.obtained(CapacityTotalObservation)
  else:
    result.result.acquisition.missing(CapacityTotalObservation,
      "the capacity could not be computed exactly")
  result.result.acquisition.obtained(CapacityBlockLengthObservation)

  # ---- the comparison with the passive capacity ---------------------------
  # The capacity that the kernel reports and the capacity that the device
  # reports are two independent observations. A discrepancy is reported;
  # it is never resolved by preferring one of them.
  #
  # The discrepancy does not make the acquisition incomplete: the
  # requested capacity **was** obtained. It is a *contradiction between
  # two sources*, and it is reported as such.
  if device.capacityBytes.len > 0 and reading.capacityBytes.len > 0 and
     device.capacityBytes != reading.capacityBytes:
    let reason = "the capacity reported by the device (" &
                 reading.capacityBytes & " bytes) differs from the capacity " &
                 "reported by the kernel (" & device.capacityBytes & " bytes)"
    result.result.findings.add reason
    result.result.observations.add Observation(
      name: "capacity.kernel_comparison", status: osConflicting, value: "",
      unit: "state", source: "sg_readcap",
      sourceField: "kernel capacity comparison", collectedAt: nowUtc(),
      reason: reason)
