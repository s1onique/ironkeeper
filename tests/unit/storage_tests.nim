## Unit tests of the storage observation domain.
##
## The tests exercise the **production** modules: discovery, identity
## reconciliation, the bounded execution boundary, the lossless external
## ingestion, the SMART normalisation and the SCSI protection mapping.
## They never reimplement the logic they test.

import std/[os, strutils, json]

import testkit

from ironkeeper/storage/types import DeviceRecord, DeviceClass, Transport,
  statusName, dcPhysical,
  dcPartition, dcVirtual, trSas, trSata, trNvme, ObservationStatus, osObserved,
  osUnavailable, osDerived, osConflicting, IdentityConfidence, icAuthoritative,
  icAmbiguous, icProbable, ExecOutcome, eoSucceeded, eoNonZeroExit, eoTimedOut,
  eoOutputLimit, eoLaunchFailed
from ironkeeper/storage/sysfs import discover, DiscoveryRoots, defaultRoots,
  SysfsSectorBytes
from ironkeeper/storage/identity import reconcile, selectDevice, Selector,
  SelectorKind, skWwn, skSerial, skPath
from ironkeeper/storage/procexec import runTool, ExecRequest, ExecLimits
from ironkeeper/storage/externaljson import parseExternal, member, asString,
  exactIntegerText, hexToDecimal, ExtNode
from ironkeeper/storage/scsicap import mapProtection, decodeCapacity,
  protectionTypeName, ptType0, ptType1, ptType2, ptType3, ptReserved
from ironkeeper/storage/smartstatus import decodeSmartExit, SmartBitFailingStatus
from ironkeeper/storage/smartnorm import normalizeSmart, detectProtocol, spScsi,
  spAta, spNvme
from ironkeeper/storage/smartfields import readExactField
from ironkeeper/storage/documents import inventoryDocument, observationJson
from ironkeeper/storage/evidence import sha256Hex
from ironkeeper/util/sha256 import sha256

proc writeFixture(path: string, content: string) =
  ## Write a fixture file.
  createDir(path.parentDir())
  system.writeFile(path, content)

proc buildSysfs(root: string) =
  ## Build a synthetic sysfs tree.
  ##
  ## The tree contains one SAS disk with a 4Kn logical block size, one
  ## partition, one virtual disk and one loop device.
  let blockDir = root / "class/block"
  createDir(blockDir)

  # A SAS disk with a 4096-byte logical block size. The `size` attribute is
  # in 512-byte sectors, so the byte count is the sector count times 512.
  writeFixture(blockDir / "sdb/dev", "8:16\n")
  writeFixture(blockDir / "sdb/size", "1000\n")
  writeFixture(blockDir / "sdb/diskseq", "42\n")
  writeFixture(blockDir / "sdb/queue/logical_block_size", "4096\n")
  writeFixture(blockDir / "sdb/queue/physical_block_size", "4096\n")
  writeFixture(blockDir / "sdb/queue/rotational", "1\n")
  writeFixture(blockDir / "sdb/device/vendor", "SEAGATE \n")
  writeFixture(blockDir / "sdb/device/model", "ST900MM0006 \n")
  writeFixture(blockDir / "sdb/device/rev", "0004\n")
  writeFixture(blockDir / "sdb/device/wwid", "naa.5000c500a1b2c3d4\n")
  writeFixture(blockDir / "sdb/device/sas_address", "0x5000c500a1b2c3d4\n")
  writeFixture(blockDir / "sdb/device/state", "running\n")
  writeFixture(blockDir / "sdb/device/driver", "sd\n")

  # A partition of the disk.
  writeFixture(blockDir / "sdb1/dev", "8:17\n")
  writeFixture(blockDir / "sdb1/size", "500\n")
  writeFixture(blockDir / "sdb1/partition", "1\n")
  writeFixture(blockDir / "sdb1/queue/logical_block_size", "4096\n")
  writeFixture(blockDir / "sdb1/queue/physical_block_size", "4096\n")

  # A virtual disk and a loop device.
  writeFixture(blockDir / "vda/dev", "254:0\n")
  writeFixture(blockDir / "vda/size", "2048\n")
  writeFixture(blockDir / "vda/queue/logical_block_size", "512\n")
  writeFixture(blockDir / "vda/queue/physical_block_size", "512\n")
  writeFixture(blockDir / "vda/device/driver", "vd\n")

  writeFixture(blockDir / "zd0/dev", "250:0\n")
  writeFixture(blockDir / "zd0/size", "1048576\n")
  writeFixture(blockDir / "zd0/queue/logical_block_size", "512\n")

  writeFixture(blockDir / "loop0/dev", "7:0\n")
  writeFixture(blockDir / "loop0/size", "0\n")
  writeFixture(blockDir / "loop0/queue/logical_block_size", "512\n")

proc buildUdev(root: string, devRoot: string) =
  ## Build the synthetic udev records and the aliases.
  createDir(root)
  writeFixture(root / "b8:16",
    "E:ID_BUS=scsi\nE:ID_SERIAL=WD-0WX12\nE:ID_MODEL=WDC\n")
  createDir(devRoot / "disk/by-id")
  let aliasPath = devRoot / "disk/by-id/scsi-0x5000c500a1b2c3d4"
  if not fileExists(aliasPath):
    createSymlink("../../sdb", aliasPath)

proc runSuite*(): int =
  var t = newTestSuite("storage")

  # ---- the discovery of a synthetic tree ---------------------------------
  let base = getTempDir() / "ironkeeper-storage-tests"
  removeDir(base)
  let sysfs = base / "sys"
  let dev = base / "dev"
  buildSysfs(sysfs)
  buildUdev(base / "run/udev/data", dev)
  let roots = DiscoveryRoots(sysfsRoot: sysfs, devRoot: dev,
                             udevDataDir: base / "run/udev/data")

  let inventory = discover(roots)
  t.check("the discovery of a readable tree is complete", inventory.complete)
  t.checkEq("the tree contains five block devices", inventory.devices.len, 5)

  var disk: DeviceRecord
  for d in inventory.devices:
    if d.kernelName == "sdb":
      disk = d
  t.check("the disk was discovered", disk.kernelName == "sdb")
  t.checkEq("a 4Kn disk is a physical disk candidate", disk.deviceClass, dcPhysical)
  t.checkEq("the SAS address attributes the transport", disk.transport, trSas)
  t.checkEq("the capacity is the sector count times 512", disk.capacityBytes, "512000")
  t.checkEq("the logical block size is read", disk.logicalBlockSize, 4096)
  t.check("the world-wide name was observed", disk.wwn.len > 0)

  var partition: DeviceRecord
  for d in inventory.devices:
    if d.kernelName == "sdb1":
      partition = d
  t.checkEq("a partition is not a physical disk", partition.deviceClass, dcPartition)

  var virt: DeviceRecord
  for d in inventory.devices:
    if d.kernelName == "vda":
      virt = d
  t.checkEq("a virtual disk is not a physical disk", virt.deviceClass, dcVirtual)

  var loopDev: DeviceRecord
  for d in inventory.devices:
    if d.kernelName == "loop0":
      loopDev = d
  t.checkEq("a loop device is not a physical disk", loopDev.deviceClass, dcLoop)

  # ---- a missing discovery root is a failure ------------------------------
  let absent = discover(DiscoveryRoots(sysfsRoot: base / "absent",
                                        devRoot: dev, udevDataDir: base / "run"))
  t.check("a missing discovery root is not a successful inventory",
          not absent.complete)
  t.check("a missing discovery root produces a finding", absent.findings.len > 0)

  # ---- identity reconciliation -------------------------------------------
  var reconciled = discover(roots)
  reconcile(reconciled)
  var reconciledDisk: DeviceRecord
  for d in reconciled.devices:
    if d.kernelName == "sdb":
      reconciledDisk = d
  t.checkEq("a world-wide name is authoritative",
            reconciledDisk.identity.confidence, icAuthoritative)

  # The world-wide name selects exactly one device.
  let byWwn = selectDevice(reconciled, Selector(kind: skWwn,
    value: "0x5000c500a1b2c3d4"))
  t.check("the world-wide name resolves to the disk", byWwn.ok)
  t.checkEq("the world-wide name resolves to the right disk",
            byWwn.device.kernelName, "sdb")

  # A serial that two devices carry is ambiguous and refuses.
  var duplicated = discover(roots)
  for i in 0 ..< duplicated.devices.len:
    if duplicated.devices[i].kernelName == "sdb1":
      duplicated.devices[i].serial = "WD-0WX12"
  reconcile(duplicated)
  let bySerial = selectDevice(duplicated, Selector(kind: skSerial,
    value: "WD-0WX12"))
  t.check("a duplicated serial does not resolve", not bySerial.ok)
  t.check("a duplicated serial is reported as ambiguous", bySerial.ambiguous)

  # A conflicting world-wide name is ambiguous. The conflict is between two
  # *physical* devices: a partition inherits the identity of its disk and
  # is not a conflicting device.
  var conflicting = discover(roots)
  for i in 0 ..< conflicting.devices.len:
    if conflicting.devices[i].kernelName == "vda":
      conflicting.devices[i].wwn = "naa.5000c500a1b2c3d4"
      conflicting.devices[i].deviceClass = dcPhysical
  reconcile(conflicting)
  var conflictDisk: DeviceRecord
  for d in conflicting.devices:
    if d.kernelName == "sdb":
      conflictDisk = d
  t.checkEq("a duplicated world-wide name is ambiguous",
            conflictDisk.identity.confidence, icAmbiguous)

  # ---- the lossless external ingestion -----------------------------------
  let big = parseExternal("""{"a": 18446744073709551616, "b": 0}""")
  t.check("a large external number is ingested", big.ok)
  t.checkEq("the exact lexeme of a large number is preserved",
            member(big.root, "a").str, "18446744073709551616")

  let duplicate = parseExternal("""{"a": 1, "a": 2}""")
  t.check("a duplicate external key is rejected", not duplicate.ok)
  t.checkContains("the duplicate key is named", duplicate.error.message,
                   "duplicate object member name")

  let escaped = parseExternal("""{"a": 1, "\u0061": 2}""")
  t.check("a key that collides after unescaping is rejected", not escaped.ok)

  let invalidUtf8 = parseExternal("{\"a\": \"" & "\xFF\xFE" & "\"}")
  t.check("invalid UTF-8 is rejected", not invalidUtf8.ok)

  t.checkEq("an exact integer is canonicalised",
            exactIntegerText("9007199254740993"), "9007199254740993")
  t.checkEq("a hexadecimal companion is converted exactly",
            hexToDecimal("10000000000000000"), "18446744073709551616")
  # A trailing zero is a significant digit: a counter of 10000 must not
  # become 1, and a counter of 30 must not become 3.
  t.checkEq("a counter with trailing zeros keeps every digit",
            exactIntegerText("10000"), "10000")
  t.checkEq("a counter that ends in zero keeps its zero",
            exactIntegerText("30"), "30")
  t.checkEq("a counter with several trailing zeros keeps every digit",
            exactIntegerText("1000000"), "1000000")
  t.checkEq("a hexadecimal companion with trailing zeros is exact",
            hexToDecimal("100000"), "1048576")
  t.checkEq("a non-integral number is refused",
            exactIntegerText("1.5"), "")

  # ---- the SMART exit status ---------------------------------------------
  let bits = decodeSmartExit(8)
  t.check("the failing-status bit is decoded", bits.failingStatus)
  t.check("the command-line bit is not set", not bits.commandLine)
  t.checkEq("the original numeric status is preserved", bits.status, 8)

  # ---- the SCSI protection mapping ---------------------------------------
  t.checkEq("PROT_EN 0 is Type 0", mapProtection(0, 7), ptType0)
  t.checkEq("PROT_EN 1 and P_TYPE 0 is Type 1", mapProtection(1, 0), ptType1)
  t.checkEq("PROT_EN 1 and P_TYPE 1 is Type 2", mapProtection(1, 1), ptType2)
  t.checkEq("PROT_EN 1 and P_TYPE 2 is Type 3", mapProtection(1, 2), ptType3)
  t.checkEq("PROT_EN 1 and P_TYPE 3 is reserved", mapProtection(1, 3), ptReserved)
  t.checkEq("PROT_EN 1 and P_TYPE 7 is reserved", mapProtection(1, 7), ptReserved)
  t.checkEq("the reserved type is never mapped onto Type 0",
            protectionTypeName(ptReserved), "reserved_unsupported")

  let reading = decodeCapacity("1758174767", 512)
  t.checkEq("the logical block count is the last LBA plus one",
            reading.logicalBlockCount, "1758174768")
  t.checkEq("the capacity is the block count times the block length",
            reading.capacityBytes, "900185481216")

  # ---- the SMART normalisation -------------------------------------------
  # The fixture uses the shape that `smartctl -x --json=o` produces for a
  # SCSI device.
  let scsiDoc = parseExternal("""{"smart_status": {"passed": true},
    "logical_unit_id": "0x5000c500a1b2c3d4",
    "scsi_error_counter_log": {
      "read": {"total_errors_corrected": 12, "total_uncorrected_errors": 3,
        "correction_algorithm_invocations": 118,
        "gigabytes_processed": "5405.300"},
      "write": {"total_errors_corrected": 0, "total_uncorrected_errors": 0},
      "verify": {"total_errors_corrected": 0, "total_uncorrected_errors": 0}},
    "scsi_grown_defect_list": 4,
    "temperature": {"current": 34, "drive_trip": 65},
    "power_on_time": {"hours": 42015},
    "rotation_rate": 10020,
    "scsi_start_stop_cycle_counter": {"accumulated_start_stop_cycles": 812,
      "accumulated_load_unload_cycles": 120034},
    "scsi_background_scan": {"status": {"number_scans_performed": 15}},
    "scsi_self_test_0": {"code": {"value": 2, "string": "Background long"}},
    "scsi_sas_port_0": {"phy_0": {"negotiated_logical_link_rate":
      "phy enabled; 12 Gbps", "invalid_dword_count": 0,
      "running_disparity_error_count": 0,
      "loss_of_dword_synchronization_count": 0,
      "phy_reset_problem_count": 0, "sas_address": "0x5000c500a1b2c3d5",
      "attached_sas_address": "0x50000d1700e5fdbf",
      "attached_phy_identifier": 5}}}""")
  t.check("the SCSI fixture is ingested", scsiDoc.ok)
  t.checkEq("the protocol is SCSI", detectProtocol(scsiDoc.root), spScsi)
  let normalized = normalizeSmart(scsiDoc.root, "smartctl", "2026-01-01T00:00:00Z")
  var found: seq[string] = @[]
  for o in normalized.observations:
    found.add o.name & "=" & statusName(o.status)
  t.checkContains("the corrected error count is observed",
                  found.join(","), "scsi.read_corrected=observed")
  t.checkContains("the uncorrected error count is observed",
                  found.join(","), "scsi.read_uncorrected=observed")
  t.checkContains("the correction algorithm invocations are kept distinct",
                  found.join(","),
                  "scsi.read_correction_algorithm_invocations=observed")
  t.checkContains("the start-stop counter is observed",
                  found.join(","), "scsi.start_stop_count=observed")
  t.checkContains("the load-unload counter is observed",
                  found.join(","), "scsi.load_unload_count=observed")
  t.checkContains("the background scan count is observed",
                  found.join(","), "scsi.background_scans_performed=observed")
  t.checkContains("the SAS PHY counters are observed",
                  found.join(","),
                  "sas.port_0.phy_0.invalid_dword_count=observed")
  t.checkContains("the logical unit identifier is observed",
                  found.join(","), "scsi.logical_unit_id=observed")
  t.checkContains("the grown defect count is observed",
                  found.join(","), "scsi.grown_defect_count=observed")
  t.checkContains("the temperature is observed",
                  found.join(","), "scsi.temperature_current=observed")
  t.checkContains("the power-on time is observed",
                  found.join(","), "scsi.power_on_hours=observed")
  t.checkContains("the health status is observed",
                  found.join(","), "device_reported_health=observed")

  let ataDoc = parseExternal("""{"ata_smart_attributes": {"table": []},
    "smart_status": {"passed": false}, "temperature": {"current": 30}}""")
  t.checkEq("the ATA protocol is detected", detectProtocol(ataDoc.root), spAta)

  # The real `smartctl` companions are `KEY_s` (the exact decimal value
  # as a string) and `KEY_le` (the raw bytes as a little-endian byte
  # array). The number itself keeps its exact source lexeme.
  let nvmeDoc = parseExternal("""{"nvme_smart_health_information_log": {
    "critical_warning": 0, "temperature": 305, "percentage_used": 3,
    "data_units_read": 18446744073709551616,
    "data_units_read_s": "18446744073709551616",
    "data_units_read_le": [0, 0, 0, 0, 0, 0, 0, 0, 1]}}""")
  t.checkEq("the NVMe protocol is detected", detectProtocol(nvmeDoc.root), spNvme)
  let nvmeNormalized = normalizeSmart(nvmeDoc.root, "smartctl", "2026-01-01T00:00:00Z")
  var units = ""
  for o in nvmeNormalized.observations:
    if o.name == "nvme.data_units_read":
      units = o.value
  t.checkEq("a counter beyond 64 bits keeps every digit", units,
            "18446744073709551616")

  # A companion that disagrees is a finding, not a silently preferred value.
  let disagreeing = parseExternal("""{"nvme_smart_health_information_log": {
    "data_units_read": 100, "data_units_read_s": "200"}}""")
  let disagreeingNormalized = normalizeSmart(disagreeing.root, "smartctl",
                                             "2026-01-01T00:00:00Z")
  t.check("a disagreeing companion is reported", disagreeingNormalized.findings.len > 0)

  # ---- the missing field is unavailable, never a zero ---------------------
  let sparse = parseExternal("""{"scsi_vpd_83": {"x": 1}}""")
  let sparseNormalized = normalizeSmart(sparse.root, "smartctl", "2026-01-01T00:00:00Z")
  var zeroSeen = false
  var unavailableSeen = false
  for o in sparseNormalized.observations:
    if o.status == osUnavailable:
      unavailableSeen = true
    if o.value == "0" and o.status == osObserved and
       o.name in ["scsi.read_corrected", "scsi.read_uncorrected",
                  "scsi.grown_defect_count", "scsi.temperature_current",
                  "scsi.power_on_hours", "scsi.rotation_rate",
                  "scsi.start_stop_count", "scsi.load_unload_count"]:
      zeroSeen = true
  t.check("a missing field is unavailable", unavailableSeen)
  t.check("a missing field is not fabricated as zero", not zeroSeen)

  # ---- the bounded execution boundary ------------------------------------
  let echoTool = "/bin/echo"
  let ok = runTool(ExecRequest(path: echoTool, args: @["hello"],
                                limits: ExecLimits(deadlineMs: 5000,
                                  maxStdoutBytes: 1024, maxStderrBytes: 1024)))
  t.checkEq("a successful invocation reports success", ok.outcome, eoSucceeded)
  t.checkEq("the standard output is captured", ok.stdout.strip(), "hello")

  let relative = runTool(ExecRequest(path: "echo", args: @["hello"]))
  t.checkEq("a relative tool path is refused", relative.outcome, eoLaunchFailed)

  let missingTool = runTool(ExecRequest(path: "/nonexistent/tool", args: @[]))
  t.checkEq("a missing tool is a launch failure", missingTool.outcome,
            eoLaunchFailed)

  let sh = "/bin/sh"
  let timeout = runTool(ExecRequest(path: sh, args: @["-c", "sleep 5"],
    limits: ExecLimits(deadlineMs: 500, maxStdoutBytes: 1024,
                        maxStderrBytes: 1024)))
  t.checkEq("a timeout is classified as a timeout", timeout.outcome, eoTimedOut)

  let saturation = runTool(ExecRequest(path: sh,
    args: @["-c", "yes aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
    limits: ExecLimits(deadlineMs: 10000, maxStdoutBytes: 4096,
                        maxStderrBytes: 4096)))
  t.checkEq("an oversized output is classified as an output-limit violation",
            saturation.outcome, eoOutputLimit)

  let nonzero = runTool(ExecRequest(path: "/bin/sh", args: @["-c", "exit 3"]))
  t.checkEq("a nonzero exit is classified", nonzero.outcome, eoNonZeroExit)
  t.checkEq("the exit status is preserved", nonzero.exitCode, 3)

  # ---- the digest ----------------------------------------------------------
  t.checkEq("the SHA-256 of the empty string is correct", sha256Hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  t.checkEq("the SHA-256 of 'abc' is correct", sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

  t.finish()
