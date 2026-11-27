## Protocol-specific normalisation of `smartctl` observations.
##
## The module turns the losslessly ingested `smartctl -x -j` document into
## typed observations. It is **not** a policy module: it reports what the
## device said, and it never says whether the device is good enough.
##
## ## Rules that hold for every protocol
##
##   * A field that the device did not report becomes an observation with
##     the status `unavailable` and a reason. It never becomes a zero.
##   * A field that the protocol does not define becomes `unsupported`.
##   * A field whose exact representations disagree becomes `conflicting`.
##   * Counters are carried as exact decimal strings.
##   * The exit status of `smartctl` is a bitmask, and it is decoded
##     separately from the document (see `smartstatus.nim`).
##
## ## Protocol attribution
##
## The protocol is decided by the shape of the document, not by the
## transport of the path: `scsi_*` members mean SCSI, `ata_smart_*`
## members mean ATA, and `nvme_smart_health_information_log` means NVMe.

import std/strutils

from ironkeeper/storage/externaljson import ExtNode, member, hasMember,
  asString, ekNumber, ekString, ekBool, ekArray, ekObject
from ironkeeper/storage/smartfields import readExactField, observationFrom
from ironkeeper/storage/externaljson import exactIntegerText
from ironkeeper/storage/types import Observation, ObservationStatus, osObserved,
  osUnsupported, osUnavailable

type
  SmartProtocol* = enum
    ## The protocol family of a SMART document.
    spScsi
    spAta
    spNvme
    spUnknown

  NormalizedSmart* = object
    ## The normalised result of one SMART acquisition.
    protocol*: SmartProtocol
    observations*: seq[Observation]
    findings*: seq[string]

proc detectProtocol*(root: ExtNode): SmartProtocol =
  ## Decide the protocol family of a SMART document.
  if hasMember(root, "nvme_smart_health_information_log"):
    return spNvme
  if hasMember(root, "ata_smart_attributes") or hasMember(root, "ata_version"):
    return spAta
  if hasMember(root, "scsi_vpd_83") or hasMember(root, "scsi_error_counter_log"):
    return spScsi
  if hasMember(root, "smart_status"):
    return spScsi
  spUnknown

proc addUnavailable*(outcomes: var seq[Observation], name: string, unit: string,
                     source: string, field: string, collectedAt: string,
                     reason: string) =
  ## Append an observation that explicitly reports an unavailable field.
  outcomes.add Observation(name: name, status: osUnavailable, value: "",
                           unit: unit, source: source, sourceField: field,
                           collectedAt: collectedAt, reason: reason)

proc addHealthObservation*(outcomes: var seq[Observation], status: ExtNode,
                           source: string, collectedAt: string) =
  ## Append the device-reported health observation.
  ##
  ## The `passed` member is a boolean in the `smartctl` document. A value
  ## that is neither a boolean nor a number is reported as unavailable: it
  ## is never turned into a healthy answer.
  let passed = member(status, "passed")
  if passed.isNil:
    addUnavailable(outcomes, "device_reported_health", "state", source,
                   "smart_status.passed", collectedAt,
                   "the device did not report a SMART health status")
    return
  var healthy = false
  if passed.kind == ekBool:
    healthy = passed.boolean
  elif passed.kind == ekNumber:
    healthy = passed.str == "1"
  else:
    addUnavailable(outcomes, "device_reported_health", "state", source,
                   "smart_status.passed", collectedAt,
                   "the SMART health status could not be interpreted")
    return
  outcomes.add Observation(
    name: "device_reported_health",
    status: osObserved,
    value: (if healthy: "pass" else: "fail"),
    unit: "state", source: source, sourceField: "smart_status.passed",
    collectedAt: collectedAt)

proc addField*(outcomes: var seq[Observation], name: string, parent: ExtNode,
               key: string, unit: string, source: string,
               collectedAt: string, findings: var seq[string]) =
  ## Read one field and append its observation.
  let value = readExactField(parent, key)
  if value.status == osConflicting or value.status == osInvalid:
    findings.add value.reason
  outcomes.add observationFrom(name, value, unit, source, key, collectedAt)

proc addNumber*(outcomes: var seq[Observation], name: string, parent: ExtNode,
                key: string, unit: string, source: string,
                collectedAt: string, findings: var seq[string]) =
  ## Read one numeric field that may be a number or a numeric string.
  ##
  ## `smartctl` writes some counters as strings, for example
  ## `"gigabytes_processed": "5405.300"`. A non-integral string is kept
  ## as it is: it is not rounded and not turned into an integer.
  let node = member(parent, key)
  if node.isNil:
    return
  var text = ""
  if node.kind == ekNumber:
    text = exactIntegerText(node.str)
  elif node.kind == ekString:
    text = node.str.strip()
  else:
    return
  if text.len == 0:
    return
  outcomes.add Observation(name: name, status: osObserved, value: text,
                           unit: unit, source: source, sourceField: key,
                           collectedAt: collectedAt)

proc addScsiDirection*(outcomes: var seq[Observation], direction: string,
                       parent: ExtNode, source: string, collectedAt: string,
                       findings: var seq[string]) =
  ## Read the error counters of one direction (read, write, verify).
  let corrected = member(parent, "total_errors_corrected")
  let uncorrected = member(parent, "total_uncorrected_errors")
  let invocations = member(parent, "correction_algorithm_invocations")
  if corrected.isNil and uncorrected.isNil and invocations.isNil:
    return
  if not corrected.isNil:
    addNumber(outcomes, "scsi." & direction & "_corrected", parent,
              "total_errors_corrected", "errors", source, collectedAt,
              findings)
  if not uncorrected.isNil:
    addNumber(outcomes, "scsi." & direction & "_uncorrected", parent,
              "total_uncorrected_errors", "errors", source, collectedAt,
              findings)
  if not invocations.isNil:
    addNumber(outcomes, "scsi." & direction & "_correction_algorithm_invocations",
              parent, "correction_algorithm_invocations", "invocations",
              source, collectedAt, findings)
  let processed = member(parent, "gigabytes_processed")
  if not processed.isNil and processed.kind == ekString:
    outcomes.add Observation(name: "scsi." & direction & "_gigabytes_processed",
      status: osObserved, value: processed.str.strip(), unit: "gigabytes",
      source: source, sourceField: "gigabytes_processed",
      collectedAt: collectedAt)

proc addSasPhyObservations*(outcomes: var seq[Observation], root: ExtNode,
                            source: string, collectedAt: string,
                            findings: var seq[string]) =
  ## Read the SAS PHY observations that the tool reports.
  ##
  ## Every PHY observation stays associated with the port and the PHY it
  ## came from. The counters of unrelated PHYs are never aggregated, and
  ## the counters are never reset.
  var portIndex = 0
  while true:
    let port = member(root, "scsi_sas_port_" & $portIndex)
    if port.isNil:
      break
    var phyIndex = 0
    while true:
      let phy = member(port, "phy_" & $phyIndex)
      if phy.isNil:
        break
      let prefix = "sas.port_" & $portIndex & ".phy_" & $phyIndex
      addNumber(outcomes, prefix & ".invalid_dword_count", phy,
                "invalid_dword_count", "dwords", source, collectedAt,
                findings)
      addNumber(outcomes, prefix & ".running_disparity_error_count", phy,
                "running_disparity_error_count", "dwords", source, collectedAt,
                findings)
      addNumber(outcomes, prefix & ".loss_of_dword_synchronization_count", phy,
                "loss_of_dword_synchronization_count", "events", source,
                collectedAt, findings)
      addNumber(outcomes, prefix & ".phy_reset_problem_count", phy,
                "phy_reset_problem_count", "events", source, collectedAt,
                findings)
      let rate = member(phy, "negotiated_logical_link_rate")
      if not rate.isNil and rate.kind == ekString:
        outcomes.add Observation(
          name: prefix & ".negotiated_link_rate", status: osObserved,
          value: rate.str.strip(), unit: "gbit_per_second", source: source,
          sourceField: "negotiated_logical_link_rate",
          collectedAt: collectedAt)
      let sasAddress = member(phy, "sas_address")
      if not sasAddress.isNil and sasAddress.kind == ekString:
        outcomes.add Observation(
          name: prefix & ".sas_address", status: osObserved,
          value: sasAddress.str.strip(), unit: "address", source: source,
          sourceField: "sas_address", collectedAt: collectedAt)
      let attached = member(phy, "attached_sas_address")
      if not attached.isNil and attached.kind == ekString:
        outcomes.add Observation(
          name: prefix & ".attached_sas_address", status: osObserved,
          value: attached.str.strip(), unit: "address", source: source,
          sourceField: "attached_sas_address", collectedAt: collectedAt)
      let attachedPhy = member(phy, "attached_phy_identifier")
      if not attachedPhy.isNil:
        addNumber(outcomes, prefix & ".attached_phy_identifier", phy,
                  "attached_phy_identifier", "identifier", source, collectedAt,
                  findings)
      inc phyIndex
    inc portIndex

proc normalizeScsi*(root: ExtNode, source: string, collectedAt: string,
                    result: var NormalizedSmart) =
  ## Normalise a SCSI SMART document.
  result.protocol = spScsi
  addHealthObservation(result.observations, member(root, "smart_status"),
                       source, collectedAt)

  # ---- the identity the tool observed -------------------------------------
  let logicalUnit = member(root, "logical_unit_id")
  if not logicalUnit.isNil and logicalUnit.kind == ekString:
    result.observations.add Observation(name: "scsi.logical_unit_id",
      status: osObserved, value: logicalUnit.str.strip(), unit: "address",
      source: source, sourceField: "logical_unit_id", collectedAt: collectedAt)

  # ---- the error counters -------------------------------------------------
  let counters = member(root, "scsi_error_counter_log")
  if counters.isNil:
    result.findings.add "the SCSI error counter log was not present"
  else:
    for direction in ["read", "write", "verify"]:
      let section = member(counters, direction)
      if not section.isNil:
        addScsiDirection(result.observations, direction, section, source,
                         collectedAt, result.findings)

  # ---- the grown defect list ----------------------------------------------
  let defects = member(root, "scsi_grown_defect_list")
  if defects.isNil:
    addUnavailable(result.observations, "scsi.grown_defect_count", "defects",
                   source, "scsi_grown_defect_list", collectedAt,
                   "the grown defect list was not present")
  elif defects.kind == ekNumber:
    addNumber(result.observations, "scsi.grown_defect_count", root,
              "scsi_grown_defect_list", "defects", source, collectedAt,
              result.findings)
  else:
    addField(result.observations, "scsi.grown_defect_count", defects, "count",
             "defects", source, collectedAt, result.findings)

  # ---- the temperature ----------------------------------------------------
  let temperature = member(root, "temperature")
  if temperature.isNil:
    addUnavailable(result.observations, "scsi.temperature_current", "celsius",
                   source, "temperature.current", collectedAt,
                   "the device did not report a temperature")
  else:
    addField(result.observations, "scsi.temperature_current", temperature,
             "current", "celsius", source, collectedAt, result.findings)
    let trip = member(temperature, "drive_trip")
    if trip.isNil:
      addUnavailable(result.observations, "scsi.temperature_trip", "celsius",
                     source, "temperature.drive_trip", collectedAt,
                     "the device did not report a trip temperature")
    else:
      addNumber(result.observations, "scsi.temperature_trip", temperature,
                "drive_trip", "celsius", source, collectedAt, result.findings)

  # ---- the accumulated power-on time --------------------------------------
  let powerOn = member(root, "power_on_time")
  if powerOn.isNil:
    addUnavailable(result.observations, "scsi.power_on_hours", "hours", source,
                   "power_on_time.hours", collectedAt,
                   "the device did not report a power-on time")
  else:
    addField(result.observations, "scsi.power_on_hours", powerOn, "hours",
             "hours", source, collectedAt, result.findings)

  # ---- the rotation rate --------------------------------------------------
  let rotation = member(root, "rotation_rate")
  if rotation.isNil:
    addUnavailable(result.observations, "scsi.rotation_rate", "rpm", source,
                   "rotation_rate", collectedAt,
                   "the device did not report a rotation rate")
  else:
    addNumber(result.observations, "scsi.rotation_rate", root, "rotation_rate",
              "rpm", source, collectedAt, result.findings)

  # ---- the start-stop and load-unload counters ---------------------------
  let cycles = member(root, "scsi_start_stop_cycle_counter")
  if cycles.isNil:
    addUnavailable(result.observations, "scsi.start_stop_count", "cycles",
                   source, "scsi_start_stop_cycle_counter", collectedAt,
                   "the device did not report a start-stop counter")
    addUnavailable(result.observations, "scsi.load_unload_count", "cycles",
                   source, "scsi_start_stop_cycle_counter", collectedAt,
                   "the device did not report a load-unload counter")
  else:
    addNumber(result.observations, "scsi.start_stop_count", cycles,
              "accumulated_start_stop_cycles", "cycles", source, collectedAt,
              result.findings)
    addNumber(result.observations, "scsi.load_unload_count", cycles,
              "accumulated_load_unload_cycles", "cycles", source, collectedAt,
              result.findings)

  # ---- the non-medium error count ----------------------------------------
  # The counter is reported by some tool versions and not by others. When
  # it is absent, the observation is **unavailable**, not zero.
  let nonMedium = member(root, "non_medium_error_count")
  if nonMedium.isNil:
    addUnavailable(result.observations, "scsi.non_medium_errors", "errors",
                   source, "non_medium_error_count", collectedAt,
                   "the tool did not report a non-medium error count")
  else:
    addNumber(result.observations, "scsi.non_medium_errors", root,
              "non_medium_error_count", "errors", source, collectedAt,
              result.findings)

  # ---- the current self-test state ---------------------------------------
  # The tool reports the self-test *log*. It does not report whether a
  # self-test is running right now, so the state is unsupported rather
  # than unknown-and-assumed.
  result.observations.add Observation(
    name: "scsi.current_self_test_state", status: osUnsupported, value: "",
    unit: "state", source: source, sourceField: "self_test_log",
    collectedAt: collectedAt,
    reason: "the tool reports the self-test log, not the current self-test state")

  # ---- the background scan -----------------------------------------------
  let scan = member(root, "scsi_background_scan")
  if scan.isNil:
    addUnavailable(result.observations, "scsi.background_scans_performed",
                   "scans", source, "scsi_background_scan", collectedAt,
                   "the device did not report a background scan result")
  else:
    let status = member(scan, "status")
    if status.isNil:
      addUnavailable(result.observations, "scsi.background_scans_performed",
                     "scans", source, "scsi_background_scan.status",
                     collectedAt, "the background scan status could not be read")
    else:
      addNumber(result.observations, "scsi.background_scans_performed", status,
                "number_scans_performed", "scans", source, collectedAt,
                result.findings)

  # ---- the self-test log -------------------------------------------------
  var selfTestIndex = 0
  var selfTests = 0
  while true:
    let entry = member(root, "scsi_self_test_" & $selfTestIndex)
    if entry.isNil:
      break
    inc selfTests
    inc selfTestIndex
  result.observations.add Observation(
    name: "scsi.self_test_log_entries", status: osObserved,
    value: $selfTests, unit: "entries", source: source,
    sourceField: "scsi_self_test_N", collectedAt: collectedAt)

  # ---- the SAS PHY observations ------------------------------------------
  addSasPhyObservations(result.observations, root, source, collectedAt,
                        result.findings)

proc normalizeAta*(root: ExtNode, source: string, collectedAt: string,
                   result: var NormalizedSmart) =
  ## Normalise an ATA SMART document.
  result.protocol = spAta
  let status = member(root, "smart_status")
  if status.isNil:
    addUnavailable(result.observations, "device_reported_health", "state",
                   source, "smart_status.passed", collectedAt,
                   "the device did not report a SMART health status")
  else:
    addHealthObservation(result.observations, status, source, collectedAt)

  let temperature = member(root, "temperature")
  if temperature.isNil:
    addUnavailable(result.observations, "ata.temperature_current", "celsius",
                   source, "temperature.current", collectedAt,
                   "the device did not report a temperature")
  else:
    addField(result.observations, "ata.temperature_current", temperature,
             "current", "celsius", source, collectedAt, result.findings)

  let powerOn = member(root, "power_on_time")
  if powerOn.isNil:
    addUnavailable(result.observations, "ata.power_on_hours", "hours", source,
                   "power_on_time.hours", collectedAt,
                   "the device did not report a power-on time")
  else:
    addField(result.observations, "ata.power_on_hours", powerOn, "hours",
             "hours", source, collectedAt, result.findings)

  let cycles = member(root, "power_cycle_count")
  if cycles.isNil:
    addUnavailable(result.observations, "ata.power_cycle_count", "cycles",
                   source, "power_cycle_count", collectedAt,
                   "the device did not report a power-cycle count")
  else:
    addField(result.observations, "ata.power_cycle_count", cycles, "count",
             "cycles", source, collectedAt, result.findings)

  let attributes = member(root, "ata_smart_attributes")
  if attributes.isNil:
    addUnavailable(result.observations, "ata.attribute_table_present", "state",
                   source, "ata_smart_attributes", collectedAt,
                   "the device did not report a SMART attribute table")
  else:
    let table = member(attributes, "table")
    if table.isNil or table.kind != ekArray:
      addUnavailable(result.observations, "ata.attribute_table_present", "state",
                     source, "ata_smart_attributes.table", collectedAt,
                     "the SMART attribute table could not be interpreted")
    else:
      result.observations.add Observation(
        name: "ata.attribute_table_present", status: osObserved, value: "yes",
        unit: "state", source: source,
        sourceField: "ata_smart_attributes.table", collectedAt: collectedAt)

proc normalizeNvme*(root: ExtNode, source: string, collectedAt: string,
                    result: var NormalizedSmart) =
  ## Normalise an NVMe SMART document.
  ##
  ## The NVMe health log is **controller-wide**. Its counters are
  ## therefore attributed to the controller, never to an individual
  ## namespace: the observation names say so explicitly.
  result.protocol = spNvme
  let log = member(root, "nvme_smart_health_information_log")
  if log.isNil:
    result.findings.add "the NVMe health information log was not present"
    addUnavailable(result.observations, "nvme.critical_warning", "state",
                   source, "nvme_smart_health_information_log", collectedAt,
                   "the controller did not report a health information log")
    return

  addField(result.observations, "nvme.critical_warning", log, "critical_warning",
           "state", source, collectedAt, result.findings)
  addField(result.observations, "nvme.temperature", log, "temperature",
           "celsius", source, collectedAt, result.findings)
  addField(result.observations, "nvme.available_spare", log, "available_spare",
           "percent", source, collectedAt, result.findings)
  addField(result.observations, "nvme.available_spare_threshold", log,
           "available_spare_threshold", "percent", source, collectedAt,
           result.findings)
  addField(result.observations, "nvme.percentage_used", log, "percentage_used",
           "percent", source, collectedAt, result.findings)
  addField(result.observations, "nvme.data_units_read", log, "data_units_read",
           "units", source, collectedAt, result.findings)
  addField(result.observations, "nvme.data_units_written", log,
           "data_units_written", "units", source, collectedAt, result.findings)
  addField(result.observations, "nvme.host_read_commands", log,
           "host_read_commands", "commands", source, collectedAt,
           result.findings)
  addField(result.observations, "nvme.host_write_commands", log,
           "host_write_commands", "commands", source, collectedAt,
           result.findings)
  addField(result.observations, "nvme.power_cycles", log, "power_cycles",
           "cycles", source, collectedAt, result.findings)
  addField(result.observations, "nvme.power_on_hours", log, "power_on_hours",
           "hours", source, collectedAt, result.findings)
  addField(result.observations, "nvme.unsafe_shutdowns", log, "unsafe_shutdowns",
           "events", source, collectedAt, result.findings)
  addField(result.observations, "nvme.media_errors", log, "media_errors",
           "errors", source, collectedAt, result.findings)
  addField(result.observations, "nvme.error_log_entries", log,
           "num_err_log_entries", "entries", source, collectedAt,
           result.findings)

proc normalizeSmart*(root: ExtNode, source: string,
                     collectedAt: string): NormalizedSmart =
  ## Normalise a SMART document into observations.
  result.protocol = detectProtocol(root)
  result.observations = @[]
  result.findings = @[]
  case result.protocol
  of spScsi: normalizeScsi(root, source, collectedAt, result)
  of spAta: normalizeAta(root, source, collectedAt, result)
  of spNvme: normalizeNvme(root, source, collectedAt, result)
  of spUnknown:
    result.findings.add "the protocol of the SMART document could not be " &
      "determined; no observation was normalised"
