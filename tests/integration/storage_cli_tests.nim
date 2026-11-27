## Integration tests of the storage commands.
##
## The tests exercise the **compiled binary** against a synthetic sysfs
## tree and controlled backend executables. They need no root, no
## physical storage device and no access to the runner's real block
## devices.
##
## The synthetic tree is the repository-owned fixture in
## `tests/fixtures/storage/`. The controlled executables are the fixture
## scripts in `tests/fixtures/storage/tools/`.

import std/[json, os, osproc, strutils, tables, strtabs, streams]

import testkit

from ironkeeper/storage/evidence import sha256Hex

type
  RunResult = object
    exitCode: int
    stdoutText: string
    stderrText: string

proc binaryPath(): string =
  ## The **test-enabled** binary under test.
  ##
  ## The compiled-CLI integration tests need the controlled fixture
  ## seams, and those seams exist only in the test-enabled build. The
  ## production build is exercised separately, by the seam-isolation
  ## witness below, which proves that it ignores the very same
  ## environment variables.
  let fromEnv = getEnv("IRONKEEPER_BIN")
  if fromEnv.len > 0:
    return fromEnv
  let root = currentSourcePath().parentDir().parentDir().parentDir()
  return root / "build" / "ironkeeper-testing"

proc productionBinaryPath(): string =
  ## The production binary under test.
  let fromEnv = getEnv("IRONKEEPER_PRODUCTION_BIN")
  if fromEnv.len > 0:
    return fromEnv
  let root = currentSourcePath().parentDir().parentDir().parentDir()
  return root / "build" / "ironkeeper"

proc fixtureRoot(): string =
  currentSourcePath().parentDir().parentDir().parentDir() / "tests/fixtures/storage"

proc runBinary(args: seq[string], env: Table[string, string] = initTable[string, string](),
               exe = ""): RunResult =
  ## Execute the binary with a controlled environment.
  let target = if exe.len > 0: exe else: binaryPath()
  var fullEnv = newStringTable(mode = StringTableMode.modeCaseSensitive)
  fullEnv["PATH"] = getEnv("PATH")
  # The dynamic loader path is passed through, because the binary links
  # the PCRE runtime dynamically and the loader must find it.
  for loaderVar in ["LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH"]:
    let value = getEnv(loaderVar)
    if value.len > 0:
      fullEnv[loaderVar] = value
  for key, value in env:
    fullEnv[key] = value
  let process = startProcess(target, args = args, options = {}, env = fullEnv)
  var outText = ""
  var errText = ""
  if process.outputStream != nil:
    outText = process.outputStream.readAll()
  if process.errorStream != nil:
    errText = process.errorStream.readAll()
  let code = process.waitForExit()
  process.close()
  RunResult(exitCode: code, stdoutText: outText, stderrText: errText)

proc storageEnv(extra: Table[string, string] = initTable[string, string]()): Table[string, string] =
  ## The environment that points the binary at the synthetic tree.
  let root = fixtureRoot()
  result = initTable[string, string]()
  result["IRONKEEPER_SYSFS_ROOT"] = root / "sys"
  result["IRONKEEPER_DEV_ROOT"] = root / "dev"
  result["IRONKEEPER_UDEV_ROOT"] = root / "run/udev/data"
  result["IRONKEEPER_TEST_TOOL_DIR"] = root / "tools"
  for key, value in extra:
    result[key] = value

proc parseDoc(text: string): JsonNode =
  ## Parse a machine-readable document, or fail the test loudly.
  try:
    result = parseJson(text)
  except JsonParsingError:
    result = newJObject()

proc runSuite*(): int =
  var t = newTestSuite("storage-integration")

  let exe = binaryPath()
  t.check("the binary under test exists (" & exe & ")", fileExists(exe))
  if not fileExists(exe):
    return t.finish()

  # ---- the passive inventory ---------------------------------------------
  var r = runBinary(@["inventory", "list", "--json"], storageEnv())
  t.checkEq("the passive inventory exits successfully", r.exitCode, 0)
  var inventory = parseDoc(r.stdoutText)
  t.check("the inventory is a JSON document", inventory.kind == JObject)
  t.checkEq("the inventory declares its schema version",
            inventory["schema_version"].getInt, 1)
  t.check("the inventory is complete", inventory["complete"].getBool)
  var names: seq[string] = @[]
  for d in inventory["devices"]:
    names.add d["kernel_name"].getStr
  t.checkContains("the SAS disk is discovered", names.join(","), "sdb")
  t.checkContains("the NVMe namespace is discovered", names.join(","), "nvme0n1")
  t.checkContains("the partition is discovered", names.join(","), "sdb1")
  t.checkContains("the device mapper is discovered", names.join(","), "dm-0")

  # The passive inventory must not classify a partition as a physical disk.
  var partitionClass = ""
  var virtualClass = ""
  var mapperClass = ""
  for d in inventory["devices"]:
    if d["kernel_name"].getStr == "sdb1":
      partitionClass = d["device_class"].getStr
    if d["kernel_name"].getStr == "vda":
      virtualClass = d["device_class"].getStr
    if d["kernel_name"].getStr == "dm-0":
      mapperClass = d["device_class"].getStr
  t.checkEq("a partition is not a physical disk", partitionClass, "partition")
  t.checkEq("a virtual disk is not a physical disk", virtualClass, "virtual")
  t.checkEq("a device mapper is not a physical disk", mapperClass, "device_mapper")

  # A 4Kn device: the capacity is the sector count times 512.
  var capacity = ""
  for d in inventory["devices"]:
    if d["kernel_name"].getStr == "sdd":
      capacity = d["capacity_bytes"].getStr
  t.checkEq("a 4Kn device reports the correct byte capacity", capacity,
            "2000398934016")

  # ---- the passive discovery runs no observation tool ---------------------
  # The controlled `smartctl` records every execution in a marker file.
  # A passive command must never create it.
  let marker = getTempDir() / "ironkeeper-passive-marker"
  removeFile(marker)
  var markerEnv = storageEnv()
  markerEnv["IRONKEEPER_TEST_TOOL_DIR"] = fixtureRoot() / "tools-marker"
  markerEnv["IRONKEEPER_MARKER_FILE"] = marker
  r = runBinary(@["inventory", "list", "--json"], markerEnv)
  t.checkEq("the passive inventory succeeds", r.exitCode, 0)
  t.check("the passive inventory runs no observation tool", not fileExists(marker))

  r = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d4", "--json"],
                markerEnv)
  t.checkEq("the passive inspection succeeds", r.exitCode, 0)
  t.check("the passive inspection runs no observation tool",
          not fileExists(marker))

  # ---- the transport filter ----------------------------------------------
  r = runBinary(@["inventory", "list", "--transport", "nvme", "--json"],
                storageEnv())
  inventory = parseDoc(r.stdoutText)
  var onlyNvme = true
  for d in inventory["devices"]:
    if d["transport"].getStr != "nvme":
      onlyNvme = false
  t.check("the transport filter keeps only the requested transport", onlyNvme)

  # ---- the missing discovery root ----------------------------------------
  var missingEnv = storageEnv()
  missingEnv["IRONKEEPER_SYSFS_ROOT"] = fixtureRoot() / "absent"
  r = runBinary(@["inventory", "list", "--json"], missingEnv)
  inventory = parseDoc(r.stdoutText)
  t.check("a missing discovery root is not a successful inventory",
          not inventory["complete"].getBool)
  t.check("a missing discovery root reports a finding",
          inventory["findings"].len > 0)

  # ---- the active inspection requires an explicit intent ------------------
  r = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d4", "--smart"],
                storageEnv())
  t.checkEq("an active inspection without --allow-wake is refused", r.exitCode, 2)
  t.checkNotContains("the refusal does not run a tool", r.stdoutText, "observations")

  # ---- the passive inspection of an explicitly selected device ------------
  r = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d4", "--json"],
                storageEnv())
  t.checkEq("the passive inspection exits successfully", r.exitCode, 0)
  var doc = parseDoc(r.stdoutText)
  t.checkEq("the passive inspection names the device",
            doc["device"]["kernel_name"].getStr, "sdb")
  t.check("the passive inspection produces no observations",
          doc["observations"].len == 0)

  # ---- the active inspection ---------------------------------------------
  r = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d4", "--smart",
                  "--capacity", "--allow-wake", "--json"], storageEnv())
  t.checkEq("the active inspection exits successfully", r.exitCode, 0)
  doc = parseDoc(r.stdoutText)
  var names2: seq[string] = @[]
  var values: Table[string, string] = initTable[string, string]()
  for o in doc["observations"]:
    names2.add o["name"].getStr
    if o.hasKey("value"):
      values[o["name"].getStr] = o["value"].getStr
  t.checkContains("the SMART observations are present", names2.join(","),
                  "scsi.grown_defect_count")
  t.checkContains("the capacity observations are present", names2.join(","),
                  "capacity.total_bytes")
  t.checkEq("the capacity is computed exactly", values["capacity.total_bytes"],
            "900185481216")
  t.checkEq("the health status is reported as the device reported it",
            values["device_reported_health"], "pass")
  t.check("the document carries no verdict", not doc.hasKey("verdict"))
  t.check("the document carries no assessment", not doc.hasKey("assessment"))
  t.checkNotContains("the document does not claim PASS", r.stdoutText, "\"PASS\"")

  # ---- a device that reports a failing condition --------------------------
  r = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d5", "--smart",
                  "--allow-wake", "--json"], storageEnv())
  t.checkEq("a failing device is not a CLI failure", r.exitCode, 0)
  doc = parseDoc(r.stdoutText)
  var failValues: Table[string, string] = initTable[string, string]()
  for o in doc["observations"]:
    if o.hasKey("value"):
      failValues[o["name"].getStr] = o["value"].getStr
  t.checkEq("the failing status is preserved", failValues["device_reported_health"],
            "fail")
  t.checkEq("the failing exit bit is decoded",
            failValues["smartctl.exit.device_reported_failing"], "true")
  t.checkEq("the grown defect count is preserved",
            failValues["scsi.grown_defect_count"], "17")

  # ---- the NVMe counters beyond 64 bits ----------------------------------
  r = runBinary(@["device", "inspect", "--path",
                  fixtureRoot() / "dev/nvme0n1", "--smart", "--allow-wake",
                  "--json"], storageEnv())
  t.checkEq("the NVMe inspection exits successfully", r.exitCode, 0)
  doc = parseDoc(r.stdoutText)
  var nvmeValues: Table[string, string] = initTable[string, string]()
  for o in doc["observations"]:
    if o.hasKey("value"):
      nvmeValues[o["name"].getStr] = o["value"].getStr
  t.checkEq("a counter beyond 64 bits keeps every digit",
            nvmeValues["nvme.data_units_read"], "18446744073709551616")

  # ---- an ambiguous selector is refused -----------------------------------
  r = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d4", "--smart",
                  "--allow-wake", "--json"], storageEnv())
  t.checkEq("an unambiguous selector is accepted", r.exitCode, 0)

  # ---- the evidence bundle ------------------------------------------------
  let evidenceParent = getTempDir() / "ironkeeper-evidence-tests"
  removeDir(evidenceParent)
  createDir(evidenceParent)
  r = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d4", "--smart",
                  "--capacity", "--allow-wake", "--evidence-dir", evidenceParent,
                  "--json"], storageEnv())
  t.checkEq("the evidence export exits successfully", r.exitCode, 0)
  var bundles: seq[string] = @[]
  for kind, path in walkDir(evidenceParent):
    if kind == pcDir:
      bundles.add path
  t.checkEq("exactly one bundle directory is created", bundles.len, 1)
  if bundles.len == 1:
    for name in ["manifest.json", "observation.json", "smartctl.stdout",
                 "smartctl.stderr", "capacity.stdout", "capacity.stderr"]:
      t.check("the bundle contains " & name, fileExists(bundles[0] / name))
    var manifest = parseDoc(readFile(bundles[0] / "manifest.json"))
    t.checkEq("the manifest declares its schema version",
              manifest["schema_version"].getInt, 1)
    t.check("the manifest lists the artefacts", manifest["artifacts"].len > 0)
    # The manifest carries the authoritative completeness, and the
    # stored observation document agrees with it semantically.
    t.checkEq("the manifest carries the completeness",
              manifest["completeness"]["status"].getStr, "complete")
    var stored = parseDoc(readFile(bundles[0] / "observation.json"))
    t.checkEq("the stored document carries the same completeness",
              stored["completeness"]["status"].getStr,
              manifest["completeness"]["status"].getStr)
    t.checkEq("the stored document carries the same attribution",
              stored["attribution"]["status"].getStr,
              manifest["attribution"]["status"].getStr)
    var digestsOk = true
    for a in manifest["artifacts"]:
      let name = a["name"].getStr
      let expected = a["sha256"].getStr
      let actual = sha256Hex(readFile(bundles[0] / name))
      if expected != actual:
        digestsOk = false
    t.check("every manifest digest matches the preserved bytes", digestsOk)

  # A caller-owned file in the parent directory is never overwritten.
  let callerFile = evidenceParent / "caller-owned.txt"
  writeFile(callerFile, "caller data")
  r = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d4", "--smart",
                  "--allow-wake", "--evidence-dir", evidenceParent, "--json"],
                storageEnv())
  t.checkEq("the second evidence export exits successfully", r.exitCode, 0)
  t.checkEq("the caller-owned file is preserved", readFile(callerFile), "caller data")

  # ---- the attribution witnesses -----------------------------------------
  # The witnesses need a **mutable** copy of the synthetic tree: the
  # controlled tool removes or replaces the synthetic device while it
  # runs. The copy is therefore made per witness, and the repository
  # fixture is never modified.
  proc copyTree(source: string, target: string) =
    ## Copy a directory tree.
    ##
    ## The symbolic links of the tree are reproduced as symbolic links
    ## with the same target, so that the copied tree behaves like the
    ## original one.
    copyDir(source, target)

  proc mutableFixture(): string =
    ## A fresh copy of the synthetic fixture tree.
    let target = getTempDir() / "ironkeeper-mutable-fixture"
    removeDir(target)
    copyTree(fixtureRoot(), target)
    target

  proc mutableEnv(root: string): Table[string, string] =
    ## The environment that points the binary at a copied fixture tree.
    result = initTable[string, string]()
    result["IRONKEEPER_SYSFS_ROOT"] = root / "sys"
    result["IRONKEEPER_DEV_ROOT"] = root / "dev"
    result["IRONKEEPER_UDEV_ROOT"] = root / "run/udev/data"
    result["IRONKEEPER_TEST_TOOL_DIR"] = root / "tools"

  # A device that disappears while the tool runs refuses the attribution.
  var mutableRoot = mutableFixture()
  var witness = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d6",
                            "--smart", "--allow-wake", "--json"],
                           mutableEnv(mutableRoot))
  t.checkEq("a disappearing device is not a CLI success", witness.exitCode, 3)
  var witnessDoc = parseDoc(witness.stdoutText)
  t.checkEq("a disappearing device refuses the attribution",
            witnessDoc["attribution"]["status"].getStr, "refused")
  t.checkEq("a disappearing device does not claim complete evidence",
            witnessDoc["completeness"]["status"].getStr, "partial")

  # A device that is replaced while the tool runs refuses the
  # attribution, even though the kernel name, the device numbers and the
  # world-wide name stay the same.
  mutableRoot = mutableFixture()
  witness = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d7",
                         "--smart", "--allow-wake", "--json"],
                      mutableEnv(mutableRoot))
  t.checkEq("a replaced device is not a CLI success", witness.exitCode, 3)
  witnessDoc = parseDoc(witness.stdoutText)
  t.checkEq("a replaced device refuses the attribution",
            witnessDoc["attribution"]["status"].getStr, "refused")

  # A rediscovery that does not complete cannot establish an unchanged
  # identity, so the attribution is refused.
  mutableRoot = mutableFixture()
  witness = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d8",
                         "--smart", "--allow-wake", "--json"],
                      mutableEnv(mutableRoot))
  t.checkEq("a failed rediscovery is not a CLI success", witness.exitCode, 3)
  witnessDoc = parseDoc(witness.stdoutText)
  t.checkEq("a failed rediscovery refuses the attribution",
            witnessDoc["attribution"]["status"].getStr, "refused")

  # A SMART response that reports a different persistent identifier
  # produces unbound evidence.
  witness = runBinary(@["device", "inspect", "--wwn", "5000c50012345678",
                        "--smart", "--allow-wake", "--json"], storageEnv())
  t.checkEq("a contradicting tool identity is not a CLI success",
            witness.exitCode, 3)
  witnessDoc = parseDoc(witness.stdoutText)
  t.checkEq("a contradicting tool identity refuses the attribution",
            witnessDoc["attribution"]["status"].getStr, "refused")

  # A stable identity remains attributable, and the acquisition is
  # complete.
  witness = runBinary(@["device", "inspect", "--wwn", "5000c500a1b2c3d4",
                        "--smart", "--allow-wake", "--json"], storageEnv())
  t.checkEq("a stable identity is a CLI success", witness.exitCode, 0)
  witnessDoc = parseDoc(witness.stdoutText)
  t.checkEq("a stable identity stays bound",
            witnessDoc["attribution"]["status"].getStr, "bound")
  t.checkEq("a stable identity yields a complete acquisition",
            witnessDoc["completeness"]["status"].getStr, "complete")

  # ---- the production build has no test seams ----------------------------
  # The marker executable records every execution. It is supplied to the
  # **production** binary through the very environment variable that the
  # test-enabled build honours. The marker must never run.
  let production = productionBinaryPath()
  t.check("the production binary exists (" & production & ")",
          fileExists(production))
  if fileExists(production):
    let prodMarker = getTempDir() / "ironkeeper-production-marker"
    removeFile(prodMarker)
    var prodEnv = initTable[string, string]()
    prodEnv["IRONKEEPER_TEST_TOOL_DIR"] = fixtureRoot() / "tools-marker"
    prodEnv["IRONKEEPER_MARKER_FILE"] = prodMarker
    prodEnv["IRONKEEPER_SYSFS_ROOT"] = fixtureRoot() / "sys"
    prodEnv["IRONKEEPER_DEV_ROOT"] = fixtureRoot() / "dev"
    prodEnv["IRONKEEPER_UDEV_ROOT"] = fixtureRoot() / "run/udev/data"
    var prodResult = runBinary(@["device", "inspect", "--wwn",
                                "5000c500a1b2c3d4", "--smart", "--allow-wake",
                                "--json"], prodEnv, production)
    t.check("the production binary does not execute the marker",
            not fileExists(prodMarker))
    t.check("the production binary does not read the synthetic tree",
            prodResult.stdoutText.len == 0 or
            not prodResult.stdoutText.contains("\"sdb\""))

    # The two binaries identify themselves. A test-enabled binary can
    # never be mistaken for a production one.
    var prodVersion = runBinary(@["version", "--json"], prodEnv, production)
    t.checkContains("the production binary identifies its variant",
                    prodVersion.stdoutText, "\"build_variant\": \"production\"")
    var testVersion = runBinary(@["version", "--json"], storageEnv())
    t.checkContains("the test-enabled binary identifies its variant",
                    testVersion.stdoutText, "\"build_variant\": \"testing\"")

  t.finish()
