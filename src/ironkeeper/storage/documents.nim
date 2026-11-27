## Rendering of the Ironkeeper storage documents.
##
## This module turns the typed records of the storage domain into the
## strict JSON documents that the public contracts describe. It is the
## only place where a record becomes a `JsonNode`, so that the boundary
## between the typed domain and the wire format stays in one place.
##
## Every document is rendered with the properties the contract requires
## and with the properties it declares. A field that was not observed is
## **absent**; it is never rendered as an empty string or as a zero.

import std/[json, times]

from ironkeeper/storage/types import DeviceRecord, Inventory, Observation,
  ExecOutcome, statusName, confidenceName, outcomeName, identifierKindName,
  identifierNamespaceName, className, transportName

proc nowUtc*(): string =
  ## The current time as an RFC 3339 timestamp in UTC.
  utc(now()).format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc identityJson(device: DeviceRecord): JsonNode =
  ## Render the reconciled identity of a device.
  result = newJObject()
  result["confidence"] = newJString(confidenceName(device.identity.confidence))
  var identifiers = newJArray()
  for i in device.identity.identifiers:
    var entry = newJObject()
    entry["kind"] = newJString(identifierKindName(i.kind))
    entry["namespace"] = newJString(identifierNamespaceName(i.namespace))
    entry["value"] = newJString(i.value)
    entry["original"] = newJString(i.original)
    entry["source"] = newJString(i.source)
    identifiers.add entry
  result["identifiers"] = identifiers
  if device.identity.conflicts.len > 0:
    var conflicts = newJArray()
    for c in device.identity.conflicts:
      conflicts.add newJString(c)
    result["conflicts"] = conflicts
  if device.identity.duplicateSerial:
    result["duplicate_serial"] = newJBool(true)

proc deviceJson*(device: DeviceRecord, withSchemaVersion: bool): JsonNode =
  ## Render one device record.
  result = newJObject()
  if withSchemaVersion:
    result["schema_version"] = newJInt(1)
  result["kernel_name"] = newJString(device.kernelName)
  result["device_class"] = newJString(className(device.deviceClass))
  result["transport"] = newJString(transportName(device.transport))
  if device.major.len > 0:
    result["major"] = newJString(device.major)
  if device.minor.len > 0:
    result["minor"] = newJString(device.minor)
  if device.sysfsPath.len > 0:
    result["sysfs_path"] = newJString(device.sysfsPath)
  if device.vendor.len > 0:
    result["vendor"] = newJString(device.vendor)
  if device.model.len > 0:
    result["model"] = newJString(device.model)
  if device.serial.len > 0:
    result["serial"] = newJString(device.serial)
  if device.firmware.len > 0:
    result["firmware"] = newJString(device.firmware)
  if device.wwn.len > 0:
    result["wwn"] = newJString(device.wwn)
  if device.capacityBytes.len > 0:
    result["capacity_bytes"] = newJString(device.capacityBytes)
  result["logical_block_size"] = newJInt(device.logicalBlockSize)
  result["physical_block_size"] = newJInt(device.physicalBlockSize)
  if device.rotationalKnown:
    result["rotational"] = newJBool(device.rotational)
  if device.paths.len > 0:
    var paths = newJArray()
    for p in device.paths:
      paths.add newJString(p)
    result["paths"] = paths
  if device.aliases.len > 0:
    var aliases = newJArray()
    for a in device.aliases:
      aliases.add newJString(a)
    result["aliases"] = aliases
  result["identity"] = identityJson(device)
  if device.findings.len > 0:
    var findings = newJArray()
    for f in device.findings:
      findings.add newJString(f)
    result["findings"] = findings

proc inventoryDocument*(inventory: Inventory): JsonNode =
  ## Render the passive inventory document.
  result = newJObject()
  result["schema_version"] = newJInt(1)
  result["generated_at"] = newJString(nowUtc())
  result["complete"] = newJBool(inventory.complete)
  if inventory.root.len > 0:
    result["root"] = newJString(inventory.root)
  var devices = newJArray()
  for d in inventory.devices:
    devices.add deviceJson(d, withSchemaVersion = true)
  result["devices"] = devices
  if inventory.findings.len > 0:
    var findings = newJArray()
    for f in inventory.findings:
      findings.add newJString(f)
    result["findings"] = findings

proc observationJson*(observation: Observation): JsonNode =
  ## Render one observation.
  result = newJObject()
  result["name"] = newJString(observation.name)
  result["status"] = newJString(statusName(observation.status))
  if observation.value.len > 0:
    result["value"] = newJString(observation.value)
  if observation.unit.len > 0:
    result["unit"] = newJString(observation.unit)
  result["source"] = newJString(observation.source)
  if observation.sourceField.len > 0:
    result["source_field"] = newJString(observation.sourceField)
  result["collected_at"] = newJString(observation.collectedAt)
  if observation.reason.len > 0:
    result["reason"] = newJString(observation.reason)

proc executionJson*(tool: string, outcome: ExecOutcome, exitStatus: int,
                    signalNumber: int, durationMs: int,
                    message: string): JsonNode =
  ## Render the outcome of one external tool invocation.
  result = newJObject()
  result["tool"] = newJString(tool)
  result["outcome"] = newJString(outcomeName(outcome))
  result["exit_status"] = newJInt(exitStatus)
  if signalNumber != 0:
    result["signal"] = newJInt(signalNumber)
  if durationMs > 0:
    result["duration_ms"] = newJInt(durationMs)
  if message.len > 0:
    result["message"] = newJString(message)
