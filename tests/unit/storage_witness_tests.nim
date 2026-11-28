## Regression witnesses of the M1 amendment.
##
## The witnesses exercise the **production** modules: the bounded
## execution boundary, the acquisition model, the SMART exit-status
## semantics, the exact-decimal arithmetic and the identity
## reconciliation. They never reimplement the logic they test.

import std/[os, strutils, json, posix]

import testkit

from ironkeeper/storage/types import DeviceRecord, Observation,
  ObservationStatus, osObserved, osUnavailable, osConflicting, osInvalid,
  ExecOutcome, eoSucceeded, eoNonZeroExit, eoTimedOut,
  eoOutputLimit, eoLaunchFailed, eoSignalled, dcPhysical, dcPartition,
  IdentityConfidence, icAuthoritative, icAmbiguous, icProbable,
  icUnresolved, statusName
from ironkeeper/storage/procexec import runTool, ExecRequest, ExecLimits
from ironkeeper/storage/acquisition import newAcquisitionResult, require,
  obtained, missing, incomplete, refuseAttribution, completenessName, isComplete,
  completenessReason, asComplete, asIncomplete
from ironkeeper/storage/smartstatus import decodeSmartExit, exitBitObservations,
  SmartBitCommandLine, SmartBitDeviceOpen, SmartBitCommandFailed,
  SmartBitFailingStatus, SmartBitPrefailThreshold, SmartBitHistoricalThreshold,
  SmartBitErrorLog, SmartBitSelfTestLog
from ironkeeper/storage/smartfields import readExactField
from ironkeeper/storage/externaljson import parseExternal
from ironkeeper/storage/scsicap import decodeCapacity, mapProtectionEvidence,
  ProtectionEvidence, mulChecked, addOne, protectionTypeName, ptType0,
  ptType1, ptType2, ptType3, ptReserved, ptMissing, ptInvalid
from ironkeeper/storage/identity import reconcile, selectDevice, Selector,
  SelectorKind, skWwn, isUsableWwn
from ironkeeper/storage/sysfs import discover, DiscoveryRoots

proc writeFixture(path: string, content: string) =
  createDir(path.parentDir())
  system.writeFile(path, content)

proc observationValue(observations: seq[Observation], name: string): string =
  ## The value of one observation, or the empty string.
  for o in observations:
    if o.name == name:
      return o.value
  ""

proc observationStatus(observations: seq[Observation],
                       name: string): ObservationStatus =
  ## The status of one observation.
  for o in observations:
    if o.name == name:
      return o.status
  osUnavailable

proc runSuite*(): int =
  var t = newTestSuite("storage-witness")

  # ======================================================================
  # W2 - the bounded execution boundary
  # ======================================================================
  let sh = "/bin/sh"

  # ---- the stream identity ------------------------------------------------
  # The standard output closes before the standard error, and the standard
  # error keeps producing data. The captured streams must stay separate.
  #
  # The **delay** before the standard error produces its data is part of
  # the witness, not a convenience. The defect that the witness pins down
  # is only observable while the standard error is the *only* stream left
  # in the poll descriptor array: the executor rebuilds that array after
  # every end of file, so the standard error takes the place of the
  # standard output. The data must therefore arrive strictly *after* the
  # standard output reached end of file. Without the delay the witness is
  # a race between the child and the parent, and it detects the defect
  # only by luck.
  let outFirst = runTool(ExecRequest(path: sh,
    args: @["-c", "exec 1>&-; sleep 0.5; printf 'late-stderr-data' >&2; sleep 0.5"],
    limits: ExecLimits(deadlineMs: 5000, maxStdoutBytes: 4096,
                        maxStderrBytes: 4096)))
  t.checkEq("the closed standard output is captured as empty",
            outFirst.stdout.strip(), "")
  t.checkContains("the standard error keeps its own data", outFirst.stderr,
                  "late-stderr-data")

  # The standard error closes first, and the standard output keeps
  # producing data. The delay plays the same role here: the standard
  # output must produce its data while it is the only stream left in the
  # descriptor array.
  let errFirst = runTool(ExecRequest(path: sh,
    args: @["-c", "exec 2>&-; sleep 0.5; printf 'late-stdout-data'; sleep 0.5"],
    limits: ExecLimits(deadlineMs: 5000, maxStdoutBytes: 4096,
                        maxStderrBytes: 4096)))
  t.checkContains("the standard output keeps its own data", errFirst.stdout,
                  "late-stdout-data")
  t.checkEq("the closed standard error is captured as empty",
            errFirst.stderr.strip(), "")

  # Both streams saturate their pipes.
  let both = runTool(ExecRequest(path: sh,
    args: @["-c", "yes aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >&1; " &
            "yes bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb >&2"],
    limits: ExecLimits(deadlineMs: 10000, maxStdoutBytes: 4096,
                        maxStderrBytes: 4096)))
  t.checkEq("both saturated streams are classified as an output limit",
            both.outcome, eoOutputLimit)

  # One stream exceeds its own bound while the other stays small.
  let oneBound = runTool(ExecRequest(path: sh,
    args: @["-c", "printf 'small' >&2; yes aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
    limits: ExecLimits(deadlineMs: 10000, maxStdoutBytes: 4096,
                        maxStderrBytes: 4096)))
  t.checkEq("a single oversized stream is classified as an output limit",
            oneBound.outcome, eoOutputLimit)
  t.check("the bounded stream is still captured",
          oneBound.stderr.contains("small"))

  # The child closes both streams and keeps running: the deadline stays
  # authoritative after the pipes reach end of file.
  let closesBoth = runTool(ExecRequest(path: sh,
    args: @["-c", "exec 1>&- 2>&-; sleep 30"],
    limits: ExecLimits(deadlineMs: 700, maxStdoutBytes: 4096,
                        maxStderrBytes: 4096)))
  t.checkEq("a child that closes both streams is still bound by the deadline",
            closesBoth.outcome, eoTimedOut)

  # An invalid executable is a launch failure, not an ordinary exit.
  let invalid = runTool(ExecRequest(path: "/nonexistent/tool", args: @[]))
  t.checkEq("an invalid executable is a launch failure", invalid.outcome,
            eoLaunchFailed)

  # A program that runs and exits with status 127 is **not** a launch
  # failure. This is the distinction that the launch-status pipe makes.
  let exit127 = runTool(ExecRequest(path: sh, args: @["-c", "exit 127"]))
  t.checkEq("a program that exits with 127 is not a launch failure",
            exit127.outcome, eoNonZeroExit)
  t.checkEq("the exit status 127 is preserved", exit127.exitCode, 127)

  # The child is terminated by a signal.
  let signalled = runTool(ExecRequest(path: sh,
    args: @["-c", "kill -TERM $$"],
    limits: ExecLimits(deadlineMs: 5000, maxStdoutBytes: 4096,
                        maxStderrBytes: 4096)))
  t.checkEq("a signalled child is classified as a signal", signalled.outcome,
            eoSignalled)
  t.check("the terminating signal is recorded", signalled.signal == SIGTERM)

  # ======================================================================
  # W4 - the acquisition model
  # ======================================================================
  var acquisition = newAcquisitionResult()
  acquisition.require("device_reported_health")
  t.check("a fresh acquisition is complete", acquisition.isComplete)
  acquisition.missing("device_reported_health", "the tool did not run")
  t.check("a missing mandatory observation makes the acquisition incomplete",
          not acquisition.isComplete)
  t.checkEq("the incomplete state is named", completenessName(acquisition.state),
            "partial")
  t.checkContains("the reason of an incomplete acquisition is reported",
                  completenessReason(acquisition), "did not run")

  var obtainedResult = newAcquisitionResult()
  obtainedResult.require("device_reported_health")
  obtainedResult.obtained("device_reported_health")
  t.check("an obtained mandatory observation keeps the acquisition complete",
          obtainedResult.isComplete)

  var refused = newAcquisitionResult()
  refused.require("device_reported_health")
  refused.obtained("device_reported_health")
  refused.refuseAttribution("the device disappeared")
  t.check("a refused attribution makes the acquisition incomplete",
          not refused.isComplete)

  # ======================================================================
  # W5 - the SMART exit-status semantics
  # ======================================================================
  # Every bit is decoded independently.
  for bit in [SmartBitCommandLine, SmartBitDeviceOpen, SmartBitCommandFailed,
              SmartBitFailingStatus, SmartBitPrefailThreshold,
              SmartBitHistoricalThreshold, SmartBitErrorLog,
              SmartBitSelfTestLog]:
    let bits = decodeSmartExit(bit)
    var set = 0
    if bits.commandLine: set = set or 1
    if bits.deviceOpen: set = set or 2
    if bits.commandFailed: set = set or 4
    if bits.failingStatus: set = set or 8
    if bits.prefailThreshold: set = set or 16
    if bits.historicalThreshold: set = set or 32
    if bits.errorLog: set = set or 64
    if bits.selfTestLog: set = set or 128
    t.checkEq("the bit " & $bit & " is decoded independently", set, bit)

  # Several combinations.
  let combined = decodeSmartExit(SmartBitFailingStatus or
                                 SmartBitPrefailThreshold or
                                 SmartBitErrorLog)
  t.check("the combination decodes the failing-status bit",
          combined.failingStatus)
  t.check("the combination decodes the prefail-threshold bit",
          combined.prefailThreshold)
  t.check("the combination decodes the error-log bit", combined.errorLog)
  t.check("the combination does not decode the self-test-log bit",
          not combined.selfTestLog)
  t.check("the combination does not decode the command-line bit",
          not combined.commandLine)

  # A status that no process produced carries no bits.
  let synthetic = decodeSmartExit(-1)
  t.check("a synthetic status is not decoded", not synthetic.observed)
  let syntheticObs = exitBitObservations(synthetic, "smartctl",
                                         "2026-01-01T00:00:00Z")
  var bitCount = 0
  for o in syntheticObs:
    if o.name.startsWith("smartctl.exit.") and o.name != "smartctl.exit.status":
      inc bitCount
  t.checkEq("a synthetic status yields no bit observations", bitCount, 0)
  t.check("a synthetic status yields an unavailable observation",
          syntheticObs.len > 0 and syntheticObs[0].status == osUnavailable)

  # ---- the numeric companions --------------------------------------------
  # The number and the decimal companion agree.
  let agree = parseExternal("""{"a": 100, "a_s": "100"}""")
  t.check("a document with an agreeing companion is ingested", agree.ok)
  let agreeValue = readExactField(agree.root, "a")
  t.check("an agreeing decimal companion is accepted", agreeValue.ok)
  t.checkEq("the exact value is preserved", agreeValue.text, "100")

  # The number and the decimal companion disagree.
  let disagree = parseExternal("""{"a": 100, "a_s": "200"}""")
  let disagreeValue = readExactField(disagree.root, "a")
  t.check("a disagreeing decimal companion is refused", not disagreeValue.ok)
  t.checkEq("a disagreeing decimal companion is a conflict",
            disagreeValue.status, osConflicting)

  # A valid little-endian companion: the byte at index `i` carries the
  # weight `256^i`.
  let le = parseExternal("""{"a": 258, "a_le": [2, 1]}""")
  let leValue = readExactField(le.root, "a")
  t.check("a valid little-endian companion is accepted", leValue.ok)
  t.checkEq("the little-endian companion agrees", leValue.text, "258")

  # A contradictory little-endian companion.
  let leBad = parseExternal("""{"a": 258, "a_le": [3, 1]}""")
  let leBadValue = readExactField(leBad.root, "a")
  t.check("a contradictory little-endian companion is refused",
          not leBadValue.ok)
  t.checkEq("a contradictory little-endian companion is a conflict",
            leBadValue.status, osConflicting)

  # A malformed companion.
  let leMalformed = parseExternal("""{"a": 100, "a_le": [300]}""")
  let leMalformedValue = readExactField(leMalformed.root, "a")
  t.check("a malformed little-endian companion is refused",
          not leMalformedValue.ok)
  t.checkEq("a malformed little-endian companion is invalid",
            leMalformedValue.status, osInvalid)

  # A 128-bit counter with every representation.
  let big = parseExternal("""{"a": 18446744073709551616,
    "a_s": "18446744073709551616", "a_le": [0, 0, 0, 0, 0, 0, 0, 0, 1]}""")
  let bigValue = readExactField(big.root, "a")
  t.check("a 128-bit counter with every companion is accepted", bigValue.ok)
  t.checkEq("a 128-bit counter keeps every digit", bigValue.text,
            "18446744073709551616")

  # An unknown, unrelated vendor field changes nothing.
  let unrelated = parseExternal("""{"a": 100, "vendor_specific_thing": 7,
    "another_vendor_field": {"x": 1}}""")
  let unrelatedValue = readExactField(unrelated.root, "a")
  t.check("an unrelated vendor field does not affect the value",
          unrelatedValue.ok)
  t.checkEq("the value is unaffected by the unrelated field",
            unrelatedValue.text, "100")

  # ======================================================================
  # W6 - the exact capacity arithmetic and the protection evidence
  # ======================================================================
  # The witness of the amendment: the last LBA 999 with a block length of
  # 512 is 512000 bytes. The trailing zeros are significant digits.
  let witness = decodeCapacity("999", 512)
  t.checkEq("the capacity conserves every digit", witness.capacityBytes,
            "512000")
  t.checkEq("the logical block count is the last LBA plus one",
            witness.logicalBlockCount, "1000")

  # A capacity that ends in several zeros.
  let zeros = decodeCapacity("9999", 512)
  t.checkEq("a capacity that ends in zeros conserves them",
            zeros.capacityBytes, "5120000")

  # The zero boundary and the carry boundary.
  let zeroBoundary = decodeCapacity("0", 512)
  t.checkEq("a capacity of one block is exact", zeroBoundary.capacityBytes,
            "512")
  let carry = decodeCapacity("999999999999999999", 512)
  t.checkEq("the carry boundary is exact", carry.logicalBlockCount,
            "1000000000000000000")

  # A large exact capacity.
  let large = decodeCapacity("9223372036854775807", 4096)
  t.checkEq("a large capacity is exact", large.capacityBytes,
            "37778931862957161709568")

  # An invalid negative value.
  let negative = decodeCapacity("-1", 512)
  t.checkEq("a negative last LBA produces no capacity",
            negative.capacityBytes, "")
  t.checkEq("a negative last LBA produces no block count",
            negative.logicalBlockCount, "")

  # An out-of-range block length.
  let badLength = decodeCapacity("999", 0)
  t.checkEq("an out-of-range block length produces no capacity",
            badLength.capacityBytes, "")

  # The overflow boundary of the multiplication: the result is exact even
  # beyond the 64-bit range.
  let overflow = decodeCapacity("9223372036854775807", 65536)
  t.checkEq("the multiplication is exact beyond the 64-bit range",
            overflow.capacityBytes, "604462909807314587353088")

  # The multiplication primitive itself.
  let multiplied = mulChecked("1000", 512)
  t.check("the multiplication succeeds", multiplied.ok)
  t.checkEq("the multiplication conserves the trailing zeros",
            multiplied.value, "512000")
  let incremented = addOne("999")
  t.check("the increment succeeds", incremented.ok)
  t.checkEq("the increment conserves the trailing zeros", incremented.value,
            "1000")

  # ---- the protection evidence --------------------------------------------
  # A missing `PROT_EN` is **missing**, never an observed zero.
  let missingProtection = decodeCapacity("999", 512)
  t.checkEq("a missing protection field is missing",
            missingProtection.protectionType, ptMissing)
  t.checkEq("a missing protection field is never Type 0",
            protectionTypeName(missingProtection.protectionType), "missing")

  # An invalid `PROT_EN` is invalid.
  let invalidProtection = decodeCapacity("999", 512, ProtectionEvidence(
    protEnPresent: true, protEn: 7, protEnValid: false,
    pTypePresent: true, pType: 0, pTypeValid: true))
  t.checkEq("an out-of-range protection field is invalid",
            invalidProtection.protectionType, ptInvalid)

  # Type 0 is derived only from an observed disabled protection.
  let disabled = decodeCapacity("999", 512, ProtectionEvidence(
    protEnPresent: true, protEn: 0, protEnValid: true,
    pTypePresent: true, pType: 0, pTypeValid: true))
  t.checkEq("an observed disabled protection is Type 0",
            disabled.protectionType, ptType0)

  # Types 1 to 3 are derived from valid observed combinations.
  for (protEn, pType, expected) in [(1'i32, 0'i32, ptType1),
                                    (1'i32, 1'i32, ptType2),
                                    (1'i32, 2'i32, ptType3)]:
    let reading = decodeCapacity("999", 512, ProtectionEvidence(
      protEnPresent: true, protEn: protEn, protEnValid: true,
      pTypePresent: true, pType: pType, pTypeValid: true))
    t.checkEq("the valid combination " & $protEn & "/" & $pType &
              " maps to the expected type", reading.protectionType, expected)

  # A reserved combination is reserved.
  let reserved = decodeCapacity("999", 512, ProtectionEvidence(
    protEnPresent: true, protEn: 1, protEnValid: true,
    pTypePresent: true, pType: 3, pTypeValid: true))
  t.checkEq("a reserved combination is reserved", reserved.protectionType,
            ptReserved)

  # ======================================================================
  # W7 - the identity reconciliation
  # ======================================================================
  t.check("a usable world-wide name is usable",
          isUsableWwn("naa.5000c50001234567"))
  t.check("an all-zero identifier is not usable", not isUsableWwn("0x0"))
  t.check("a short identifier is not usable", not isUsableWwn("0x1234"))
  t.check("a non-hexadecimal identifier is not usable",
          not isUsableWwn("not-a-wwwn-at-all"))

  # Two NVMe namespaces behind one controller: the shared controller
  # serial is not a contradiction, and the namespace identities are kept
  # apart.
  let base = getTempDir() / "ironkeeper-witness-identity"
  removeDir(base)
  let sysfs = base / "sys"
  let dev = base / "dev"
  writeFixture(sysfs / "class/block/nvme0n1/dev", "259:0\n")
  writeFixture(sysfs / "class/block/nvme0n1/size", "1000\n")
  writeFixture(sysfs / "class/block/nvme0n1/queue/logical_block_size", "512\n")
  writeFixture(sysfs / "class/block/nvme0n1/eui", "0011223344556677\n")
  writeFixture(sysfs / "class/block/nvme0n2/dev", "259:1\n")
  writeFixture(sysfs / "class/block/nvme0n2/size", "1000\n")
  writeFixture(sysfs / "class/block/nvme0n2/queue/logical_block_size", "512\n")
  writeFixture(sysfs / "class/block/nvme0n2/eui", "0011223344556688\n")
  writeFixture(sysfs / "class/block/nvme0n1/device/serial", "SYNTHETIC-CTRL-1\n")
  writeFixture(sysfs / "class/block/nvme0n2/device/serial", "SYNTHETIC-CTRL-1\n")
  writeFixture(base / "run/udev/data/b259:0",
    "E:ID_BUS=nvme\nE:ID_SERIAL_SHORT=SYNTHETIC-CTRL-1\n")
  writeFixture(base / "run/udev/data/b259:1",
    "E:ID_BUS=nvme\nE:ID_SERIAL_SHORT=SYNTHETIC-CTRL-1\n")
  var nvmeInventory = discover(DiscoveryRoots(sysfsRoot: sysfs, devRoot: dev,
                                             udevDataDir: base / "run/udev/data"))
  reconcile(nvmeInventory)
  var ns1: DeviceRecord
  var ns2: DeviceRecord
  for d in nvmeInventory.devices:
    if d.kernelName == "nvme0n1": ns1 = d
    if d.kernelName == "nvme0n2": ns2 = d
  t.checkEq("a namespace with an EUI-64 is authoritative",
            ns1.identity.confidence, icAuthoritative)
  t.checkEq("the second namespace is authoritative too",
            ns2.identity.confidence, icAuthoritative)
  t.check("a shared controller serial is not a contradiction",
          ns1.identity.conflicts.len == 0 and ns2.identity.conflicts.len == 0)
  t.check("the namespace identities differ",
          ns1.namespaceIds.len > 0 and ns2.namespaceIds.len > 0 and
          ns1.namespaceIds[0] != ns2.namespaceIds[0])

  # Conflicting udev and sysfs world-wide names are a contradiction.
  let conflictBase = getTempDir() / "ironkeeper-witness-conflict"
  removeDir(conflictBase)
  let conflictSysfs = conflictBase / "sys"
  writeFixture(conflictSysfs / "class/block/sda/dev", "8:0\n")
  writeFixture(conflictSysfs / "class/block/sda/size", "1000\n")
  writeFixture(conflictSysfs / "class/block/sda/queue/logical_block_size", "512\n")
  writeFixture(conflictSysfs / "class/block/sda/device/wwid",
               "naa.5000c50001234567\n")
  writeFixture(conflictBase / "run/udev/data/b8:0",
    "E:ID_BUS=scsi\nE:ID_WWN_WITH_EXTENSION=0x5000c50099999999\n")
  var conflictInventory = discover(DiscoveryRoots(
    sysfsRoot: conflictSysfs, devRoot: conflictBase / "dev",
    udevDataDir: conflictBase / "run/udev/data"))
  reconcile(conflictInventory)
  t.check("a conflicting world-wide name is ambiguous",
          conflictInventory.devices[0].identity.confidence == icAmbiguous)

  t.finish()
