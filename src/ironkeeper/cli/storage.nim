## The storage commands of the Ironkeeper command line application.
##
## Two commands are implemented:
##
## ```text
## ironkeeper inventory list [--transport <name>] [--json]
## ironkeeper device inspect --wwn <wwn> | --serial <serial> | --path <path>
##                     [--smart] [--capacity] [--allow-wake]
##                     [--evidence-dir <parent>] [--json]
## ```
##
## The passive command never opens a physical device and never runs an
## observation tool. The active command requires an **explicitly selected**
## target and an explicit `--allow-wake`, because a read-only SMART
## acquisition may wake a sleeping device.
##
## The CLI never prints an admission verdict and never prints `PASS`.

import std/[json, strutils, os]

from ironkeeper/storage/types import DeviceRecord, Inventory, Observation,
  dcPhysical, osObserved, osDerived, statusName, confidenceName, transportName
from ironkeeper/storage/sysfs import discover, defaultRoots, DiscoveryRoots
from ironkeeper/core/version import TestingBuild, BuildVariant
from ironkeeper/storage/identity import reconcile, selectDevice, Selector,
  SelectorKind, skWwn, skSerial, skPath, identityFingerprint
from ironkeeper/storage/collect import collectSmart, collectCapacity,
  CollectionResult, ToolExecution
from ironkeeper/storage/acquisition import AcquisitionResult, newAcquisitionResult,
  asIncomplete, completenessName, completenessReason, isComplete,
  refuseAttribution, incomplete
import ironkeeper/storage/procexec as procexec
from ironkeeper/storage/procexec import ExecLimits
from ironkeeper/storage/toolpaths import defaultToolPaths
from ironkeeper/storage/documents import inventoryDocument, deviceJson,
  observationJson, executionJson, nowUtc
from ironkeeper/storage/evidence import EvidenceArtifact, writeBundle
from ironkeeper/contracts/validator import newValidator, validateAgainst
from ironkeeper/contracts/schemaregistry import schemaText

type
  InventoryOptions* = object
    ## The options of `ironkeeper inventory list`.
    transport*: string
    roots*: DiscoveryRoots

  InspectOptions* = object
    ## The options of `ironkeeper device inspect`.
    selector*: Selector
    smart*: bool
    capacity*: bool
    allowWake*: bool
    evidenceDir*: string
    roots*: DiscoveryRoots
    limits*: ExecLimits

  StorageResult* = object
    ## The result of a storage command.
    document*: JsonNode
    humanLines*: seq[string]
    exitCode*: int
    evidenceDirectory*: string

const
  SysfsRootEnv* = "IRONKEEPER_SYSFS_ROOT"
    ## The environment variable through which the test harness points the
    ## discovery at a synthetic sysfs tree.
  DevRootEnv* = "IRONKEEPER_DEV_ROOT"
    ## The environment variable through which the test harness points the
    ## discovery at a synthetic device tree.
  UdevRootEnv* = "IRONKEEPER_UDEV_ROOT"
    ## The environment variable through which the test harness points the
    ## discovery at synthetic udev records.

proc requireRoots*(): DiscoveryRoots =
  ## The discovery roots of this invocation.
  ##
  ## The defaults are the real roots of a Linux host. A **test-enabled**
  ## build overrides them through the documented environment variables, so
  ## that the production code path can be exercised without a storage
  ## device. A production build does not read those variables at all: the
  ## discovery roots of a shipped binary are the real roots, and an
  ## environment variable cannot redirect them.
  let defaults = defaultRoots()
  when TestingBuild:
    let sysfs = getEnv(SysfsRootEnv)
    let dev = getEnv(DevRootEnv)
    let udev = getEnv(UdevRootEnv)
    return DiscoveryRoots(
      sysfsRoot: (if sysfs.len > 0: sysfs else: defaults.sysfsRoot),
      devRoot: (if dev.len > 0: dev else: defaults.devRoot),
      udevDataDir: (if udev.len > 0: udev else: defaults.udevDataDir))
  DiscoveryRoots(sysfsRoot: defaults.sysfsRoot, devRoot: defaults.devRoot,
                 udevDataDir: defaults.udevDataDir)

proc defaultLimits*(): ExecLimits =
  ## The default execution bounds of this invocation.
  procexec.defaultLimits()

proc formatBytes(text: string): string =
  ## Render a byte count for the human-readable output.
  if text.len == 0:
    return "-"
  try:
    let value = parseBiggestInt(text)
    if value >= 1024 * 1024 * 1024:
      return $(value div (1024 * 1024 * 1024)) & " GiB"
    if value >= 1024 * 1024:
      return $(value div (1024 * 1024)) & " MiB"
    return $value & " B"
  except ValueError:
    text

proc humanInventory*(inventory: Inventory): seq[string] =
  ## Render the inventory as a compact table.
  result = @[]
  result.add "DEVICE  TRANSPORT  MODEL                     SERIAL              CAPACITY     WWN                 IDENTITY"
  for d in inventory.devices:
    if d.deviceClass != dcPhysical:
      continue
    let model = if d.model.len > 0: d.model else: "-"
    let serial = if d.serial.len > 0: d.serial else: "-"
    let wwn = if d.wwn.len > 0: d.wwn else: "-"
    result.add d.kernelName & "      " & transportName(d.transport) &
      "        " & model & "  " & serial & "  " & formatBytes(d.capacityBytes) &
      "  " & wwn & "  " & confidenceName(d.identity.confidence)
  if not inventory.complete:
    result.add "the inventory is incomplete; see the findings"

proc contractIssue(schemaName: string, document: JsonNode): string =
  ## The reason why a document does not satisfy its contract, or the
  ## empty string when it does.
  ##
  ## The documents that the application publishes are validated against
  ## the repository contracts **at the production boundary**, before they
  ## are written. A document that does not satisfy its contract is never
  ## published.
  let validator = newValidator()
  let schema = parseJson(schemaText(schemaName))
  let outcome = validateAgainst(validator, document, schema)
  if outcome.ok:
    return ""
  if outcome.error != nil:
    return outcome.error.msg
  if outcome.issues.len > 0:
    return outcome.issues[0].message
  "the document does not satisfy the " & schemaName & " contract"

proc cmdInventoryList*(options: InventoryOptions): StorageResult =
  ## `ironkeeper inventory list`
  var inventory = discover(options.roots)
  reconcile(inventory)
  if options.transport.len > 0:
    var filtered: seq[DeviceRecord] = @[]
    for d in inventory.devices:
      if transportName(d.transport) == options.transport:
        filtered.add d
    inventory.devices = filtered
  result.document = inventoryDocument(inventory)
  let issue = contractIssue("inventory", result.document)
  if issue.len > 0:
    raise newException(ValueError,
      "the inventory document does not satisfy its contract: " & issue)
  result.humanLines = humanInventory(inventory)
  result.exitCode = 0

type
  IdentityCheck* = enum
    ## The result of one identity check around a backend invocation.
    icUnchanged
      ## The device is still there and its identity is unchanged.
    icChanged
      ## The device is still there, but its identity changed.
    icMissing
      ## The device is gone.
    icIncomplete
      ## The rediscovery did not complete, so the identity could not be
      ## established as unchanged.

proc checkIdentity(roots: DiscoveryRoots, device: DeviceRecord): IdentityCheck =
  ## Check that the selected device is still the same device.
  ##
  ## The rediscovery is **not** allowed to default to the original device:
  ## a device that disappeared must be reported as missing, and a
  ## rediscovery that did not complete must be reported as incomplete.
  ## Neither may be reported as "unchanged".
  var inventory = discover(roots)
  if not inventory.complete:
    return icIncomplete
  var found = false
  var current: DeviceRecord
  for d in inventory.devices:
    if d.kernelName == device.kernelName:
      current = d
      found = true
      break
  if not found:
    return icMissing
  reconcile(inventory)
  for d in inventory.devices:
    if d.kernelName == device.kernelName:
      current = d
      break
  if identityFingerprint(current) != identityFingerprint(device):
    return icChanged
  icUnchanged

proc attributionReasonFor(check: IdentityCheck, device: DeviceRecord): string =
  ## The reason why the attribution of a collection was refused.
  case check
  of icUnchanged: ""
  of icChanged:
    "the identity of " & device.kernelName & " changed during the " &
    "collection; the observations are retained as unbound evidence"
  of icMissing:
    "the device " & device.kernelName & " disappeared during the " &
    "collection; the observations are retained as unbound evidence"
  of icIncomplete:
    "the rediscovery of " & device.kernelName & " did not complete, so the " &
    "identity could not be established as unchanged; the observations are " &
    "retained as unbound evidence"

proc mergeAcquisition(target: var AcquisitionResult, source: AcquisitionResult) =
  ## Merge the coverage of one operation into the coverage of the whole
  ## collection.
  ##
  ## The merged coverage is incomplete when **any** of the merged
  ## operations is incomplete.
  if not isComplete(source):
    target.state = asIncomplete
  for m in source.mandatory:
    var found = false
    for i in 0 ..< target.mandatory.len:
      if target.mandatory[i].name == m.name:
        found = true
        if not m.obtained:
          target.mandatory[i].obtained = false
          target.mandatory[i].reason = m.reason
        break
    if not found:
      target.mandatory.add m
  for r in source.reasons:
    if r notin target.reasons:
      target.reasons.add r

proc cmdDeviceInspect*(options: InspectOptions): StorageResult =
  ## `ironkeeper device inspect`
  ##
  ## The passive part always runs. The active part runs only when it was
  ## explicitly requested, and only against an unambiguous target.
  ##
  ## Every backend invocation is surrounded by an identity check: the
  ## identity is captured **before** the invocation and again **after**
  ## it. A device that disappeared, a device whose identity changed and a
  ## rediscovery that did not complete all **refuse** the attribution, and
  ## a detected change prevents the subsequent active commands.
  var inventory = discover(options.roots)
  reconcile(inventory)

  let selection = selectDevice(inventory, options.selector)
  if not selection.ok:
    raise newException(ValueError, selection.message)

  let device = selection.device
  var observations: seq[Observation] = @[]
  var executions: seq[ToolExecution] = @[]
  var findings: seq[string] = @[]
  var artifacts: seq[EvidenceArtifact] = @[]
  var attributionBound = true
  var attributionReason = ""
  var acquisition = newAcquisitionResult()
  var changed = false

  let paths = defaultToolPaths()

  if options.smart:
    let pre = checkIdentity(options.roots, device)
    if pre != icUnchanged:
      changed = true
      attributionBound = false
      attributionReason = attributionReasonFor(pre, device)
      findings.add attributionReason
      acquisition.refuseAttribution(attributionReason)
    else:
      let smart = collectSmart(device, paths, options.limits)
      for o in smart.result.observations:
        observations.add o
      for f in smart.result.findings:
        findings.add f
      executions.add smart.execution
      mergeAcquisition(acquisition, smart.result.acquisition)
      artifacts.add EvidenceArtifact(name: "smartctl.stdout",
        content: smart.execution.stdout, kind: "tool_stdout", tool: "smartctl",
        outcome: $smart.execution.outcome, exitStatus: smart.execution.exitCode,
        note: (if smart.execution.truncated: "the output was truncated by the " &
          "configured bound" else: ""))
      artifacts.add EvidenceArtifact(name: "smartctl.stderr",
        content: smart.execution.stderr, kind: "tool_stderr", tool: "smartctl",
        outcome: $smart.execution.outcome, exitStatus: smart.execution.exitCode)
      if not smart.result.attributionBound:
        attributionBound = false
        attributionReason = smart.result.attributionReason
      let post = checkIdentity(options.roots, device)
      if post != icUnchanged:
        changed = true
        attributionBound = false
        attributionReason = attributionReasonFor(post, device)
        findings.add attributionReason
        acquisition.refuseAttribution(attributionReason)

  if options.capacity and not changed:
    let pre = checkIdentity(options.roots, device)
    if pre != icUnchanged:
      changed = true
      attributionBound = false
      attributionReason = attributionReasonFor(pre, device)
      findings.add attributionReason
      acquisition.refuseAttribution(attributionReason)
    else:
      let capacity = collectCapacity(device, paths, options.limits)
      for o in capacity.result.observations:
        observations.add o
      for f in capacity.result.findings:
        findings.add f
      executions.add capacity.execution
      mergeAcquisition(acquisition, capacity.result.acquisition)
      artifacts.add EvidenceArtifact(name: "capacity.stdout",
        content: capacity.execution.stdout, kind: "tool_stdout",
        tool: "sg_readcap", outcome: $capacity.execution.outcome,
        exitStatus: capacity.execution.exitCode)
      artifacts.add EvidenceArtifact(name: "capacity.stderr",
        content: capacity.execution.stderr, kind: "tool_stderr",
        tool: "sg_readcap", outcome: $capacity.execution.outcome,
        exitStatus: capacity.execution.exitCode)
      if not capacity.result.attributionBound:
        attributionBound = false
        attributionReason = capacity.result.attributionReason
      let post = checkIdentity(options.roots, device)
      if post != icUnchanged:
        changed = true
        attributionBound = false
        attributionReason = attributionReasonFor(post, device)
        findings.add attributionReason
        acquisition.refuseAttribution(attributionReason)

  # ---- the document --------------------------------------------------------
  var document = newJObject()
  document["schema_version"] = newJInt(1)
  document["generated_at"] = newJString(nowUtc())
  document["device"] = deviceJson(device, withSchemaVersion = false)
  var observationArray = newJArray()
  for o in observations:
    observationArray.add observationJson(o)
  document["observations"] = observationArray
  var executionArray = newJArray()
  for e in executions:
    executionArray.add executionJson(e.tool, e.outcome, e.exitCode, e.signal,
                                      e.durationMs, e.message)
  document["executions"] = executionArray
  var attribution = newJObject()
  attribution["status"] = newJString(if attributionBound: "bound" else: "refused")
  if attributionReason.len > 0:
    attribution["reason"] = newJString(attributionReason)
  document["attribution"] = attribution
  var completeness = newJObject()
  completeness["status"] = newJString(completenessName(acquisition.state))
  let completenessText = completenessReason(acquisition)
  if completenessText.len > 0:
    completeness["reason"] = newJString(completenessText)
  document["completeness"] = completeness
  if findings.len > 0:
    var findingArray = newJArray()
    for f in findings:
      findingArray.add newJString(f)
    document["findings"] = findingArray

  result.document = document
  # The observation document is validated against its contract **before**
  # it is published, so that an invalid document never reaches the
  # operator or the evidence bundle.
  let issue = contractIssue("observation", document)
  if issue.len > 0:
    raise newException(ValueError,
      "the observation document does not satisfy its contract: " & issue)
  # The exit status follows the authoritative completeness, not the mere
  # presence of an execution record.
  result.exitCode = (if isComplete(acquisition): 0 else: 3)

  result.humanLines = @[]
  result.humanLines.add "device: " & device.kernelName
  result.humanLines.add "transport: " & transportName(device.transport)
  result.humanLines.add "model: " & (if device.model.len > 0: device.model else: "-")
  result.humanLines.add "serial: " & (if device.serial.len > 0: device.serial else: "-")
  result.humanLines.add "wwn: " & (if device.wwn.len > 0: device.wwn else: "-")
  result.humanLines.add "capacity: " & formatBytes(device.capacityBytes)
  result.humanLines.add "identity: " & confidenceName(device.identity.confidence)
  result.humanLines.add "completeness: " & completenessName(acquisition.state)
  if completenessText.len > 0:
    result.humanLines.add "completeness reason: " & completenessText
  for o in observations:
    if o.status == osObserved or o.status == osDerived:
      result.humanLines.add o.name & ": " & o.value &
        (if o.unit.len > 0: " " & o.unit else: "")
    else:
      result.humanLines.add o.name & ": " & statusName(o.status) &
        (if o.reason.len > 0: " (" & o.reason & ")" else: "")
  for f in findings:
    result.humanLines.add "finding: " & f

  # ---- the evidence bundle -------------------------------------------------
  if options.evidenceDir.len > 0:
    artifacts.add EvidenceArtifact(name: "observation.json",
      content: document.pretty(2) & "\n", kind: "normalized_document")
    let bundle = writeBundle(options.evidenceDir, nowUtc(), device, artifacts,
                              document, attributionBound, attributionReason,
                              completenessName(acquisition.state),
                              completenessText)
    result.evidenceDirectory = bundle.directory
    result.humanLines.add "evidence: " & bundle.directory
