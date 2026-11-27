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

from ironkeeper/storage.types import DeviceRecord, Inventory, Observation,
  dcPhysical, osObserved, osDerived, statusName, confidenceName, transportName
from ironkeeper/storage.sysfs import discover, defaultRoots, DiscoveryRoots
from ironkeeper.storage.identity import reconcile, selectDevice, Selector,
  SelectorKind, skWwn, skSerial, skPath
from ironkeeper/storage.collect import collectSmart, collectCapacity,
  CollectionResult, ToolExecution, identityFingerprint
import ironkeeper/storage.procexec as procexec
from ironkeeper/storage.procexec import ExecLimits
from ironkeeper/storage.toolpaths import defaultToolPaths
from ironkeeper.storage.documents import inventoryDocument, deviceJson,
  observationJson, executionJson, nowUtc
from ironkeeper/storage.evidence import EvidenceArtifact, writeBundle

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
  ## The defaults are the real roots of a Linux host. The test harness
  ## overrides them through the documented environment variables, so that
  ## the production code path can be exercised without a storage device.
  let defaults = defaultRoots()
  let sysfs = getEnv(SysfsRootEnv)
  let dev = getEnv(DevRootEnv)
  let udev = getEnv(UdevRootEnv)
  DiscoveryRoots(
    sysfsRoot: (if sysfs.len > 0: sysfs else: defaults.sysfsRoot),
    devRoot: (if dev.len > 0: dev else: defaults.devRoot),
    udevDataDir: (if udev.len > 0: udev else: defaults.udevDataDir))

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
  result.humanLines = humanInventory(inventory)
  result.exitCode = 0

proc cmdDeviceInspect*(options: InspectOptions): StorageResult =
  ## `ironkeeper device inspect`
  ##
  ## The passive part always runs. The active part runs only when it was
  ## explicitly requested, and only against an unambiguous target.
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

  let before = identityFingerprint(device)
  let paths = defaultToolPaths()

  if options.smart:
    let smart = collectSmart(device, paths, options.limits)
    for o in smart.result.observations:
      observations.add o
    for f in smart.result.findings:
      findings.add f
    executions.add smart.execution
    artifacts.add EvidenceArtifact(name: "smartctl.stdout",
      content: smart.execution.stdout, kind: "tool_stdout", tool: "smartctl",
      outcome: $smart.execution.outcome, exitStatus: smart.execution.exitCode,
      note: (if smart.execution.truncated: "the output was truncated by the " &
        "configured bound" else: ""))
    artifacts.add EvidenceArtifact(name: "smartctl.stderr",
      content: smart.execution.stderr, kind: "tool_stderr", tool: "smartctl",
      outcome: $smart.execution.outcome, exitStatus: smart.execution.exitCode)

  if options.capacity:
    let capacity = collectCapacity(device, paths, options.limits)
    for o in capacity.result.observations:
      observations.add o
    for f in capacity.result.findings:
      findings.add f
    executions.add capacity.execution
    artifacts.add EvidenceArtifact(name: "capacity.stdout",
      content: capacity.execution.stdout, kind: "tool_stdout",
      tool: "sg_readcap", outcome: $capacity.execution.outcome,
      exitStatus: capacity.execution.exitCode)
    artifacts.add EvidenceArtifact(name: "capacity.stderr",
      content: capacity.execution.stderr, kind: "tool_stderr",
      tool: "sg_readcap", outcome: $capacity.execution.outcome,
      exitStatus: capacity.execution.exitCode)

  # ---- the identity is checked again after the collection -----------------
  var afterInventory = discover(options.roots)
  reconcile(afterInventory)
  var after = device
  for d in afterInventory.devices:
    if d.kernelName == device.kernelName:
      after = d
      break
  let afterFingerprint = identityFingerprint(after)
  if before != afterFingerprint:
    attributionBound = false
    attributionReason = "the identity or the access path of " &
      device.kernelName & " changed during the collection; the observations " &
      "are retained as unbound evidence"
    findings.add attributionReason

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
  if findings.len > 0:
    var findingArray = newJArray()
    for f in findings:
      findingArray.add newJString(f)
    document["findings"] = findingArray

  result.document = document
  result.exitCode = 0

  result.humanLines = @[]
  result.humanLines.add "device: " & device.kernelName
  result.humanLines.add "transport: " & transportName(device.transport)
  result.humanLines.add "model: " & (if device.model.len > 0: device.model else: "-")
  result.humanLines.add "serial: " & (if device.serial.len > 0: device.serial else: "-")
  result.humanLines.add "wwn: " & (if device.wwn.len > 0: device.wwn else: "-")
  result.humanLines.add "capacity: " & formatBytes(device.capacityBytes)
  result.humanLines.add "identity: " & confidenceName(device.identity.confidence)
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
                              (if executions.len > 0: "complete" else: "partial"))
    result.evidenceDirectory = bundle.directory
    result.humanLines.add "evidence: " & bundle.directory
