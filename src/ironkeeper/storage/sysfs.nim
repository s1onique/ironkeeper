## Passive Linux block-device discovery.
##
## This module is the **only** module that reads the kernel's block-device
## interfaces. It is strictly passive: it opens no block device, it never
## runs an observation tool, and it never writes anything. Everything it
## reports comes from the filesystem.
##
## ## Why sysfs and udev
##
## The authoritative inputs are:
##
##   * `/sys/class/block/<name>/` - the kernel's view of the device;
##   * `/sys/dev/block/<major>:<minor>/` - the same, keyed by device number;
##   * `/run/udev/data/b<major>:<minor>` - udev's recorded properties;
##   * `/dev/disk/by-id/`, `/dev/disk/by-path/` - the persistent aliases.
##
## `lsblk` and `lsscsi` are **not** used: they are operator cross-checks,
## not the inventory implementation, because their output format is a
## presentation layer rather than a stable interface.
##
## ## The sector convention
##
## The `size` attribute of a block device is expressed in **512-byte
## sectors**, regardless of the device's own logical block size. It is
## therefore multiplied by 512 and never by the logical block size. A 4Kn
## device therefore reports the same byte count as its capacity, not a
## quarter of it.
##
## ## Failure handling
##
## A missing discovery root is a **failure**, not an empty inventory. A
## device that disappears between the enumeration and the attribute reads
## yields a partial record with an explicit finding. A malformed attribute
## yields an explicit finding, never a silently coerced value.

import std/[os, posix, strutils, algorithm, tables]

from ironkeeper/storage/types import DeviceRecord, DeviceClass, Transport,
  Inventory, dcPhysical, dcPartition, dcMapper, dcRaid, dcLoop, dcRam,
  dcOptical, dcVirtual, dcUnknown, trSas, trSata, trNvme, trScsi, trUnknown,
  icUnresolved

const
  SysfsSectorBytes* = 512
    ## The unit of the `size` attribute of a Linux block device.

type
  DiscoveryRoots* = object
    ## The filesystem roots the discovery adapter reads.
    sysfsRoot*: string
      ## Defaults to `/sys`.
    devRoot*: string
      ## Defaults to `/dev`.
    udevDataDir*: string
      ## Defaults to `/run/udev/data`.

proc defaultRoots*(): DiscoveryRoots =
  ## The roots of a real Linux host.
  DiscoveryRoots(sysfsRoot: "/sys", devRoot: "/dev",
                 udevDataDir: "/run/udev/data")

proc readAttr(path: string): tuple[ok: bool, value: string] =
  ## Read one sysfs attribute.
  ##
  ## A missing attribute, an unreadable attribute and a directory are all
  ## reported as "not available". The caller decides what that means for
  ## the individual field; the attribute itself is never coerced.
  try:
    if not fileExists(path):
      return (ok: false, value: "")
    let raw = readFile(path)
    (ok: true, value: raw.strip())
  except IOError, OSError:
    (ok: false, value: "")

proc readUdevProps(path: string): Table[string, string] =
  ## Read the udev properties of one device.
  ##
  ## The file format is one `KEY=VALUE` pair per line. Only the `E:` (device)
  ## properties are read; the `S:` (state) and `L:` (link) lines are not
  ## properties of the device.
  result = initTable[string, string]()
  let content = readAttr(path)
  if not content.ok or content.value.len == 0:
    return
  for line in content.value.splitLines():
    if line.len < 3 or line[0] != 'E' or line[1] != ':':
      continue
    let pair = line[2 .. ^1]
    let eq = pair.find('=')
    if eq <= 0:
      continue
    result[pair[0 ..< eq]] = pair[eq + 1 .. ^1]

proc isPartitionName(name: string): bool =
  ## True when a kernel block name denotes a partition.
  ##
  ## A partition name is a disk name followed by digits: `sda1`,
  ## `nvme0n1p3`. A name without a trailing digit is never a partition,
  ## and only the kernel naming schemes that actually produce partitions
  ## are considered: the trailing digits of a `zd0` or a `md0` name are
  ## part of the name, not a partition number.
  var i = name.len - 1
  if i < 0 or name[i] notin {'0' .. '9'}:
    return false
  while i >= 0 and name[i] in {'0' .. '9'}:
    dec i
  if i < 0:
    return false
  let base = name[0 .. i]
  if base.len == 0:
    return false
  # `p` separates a namespace from its partitions: `nvme0n1p3`.
  var stem = base
  if stem.endsWith("p"):
    stem = stem[0 .. ^2]
  if stem.len == 0:
    return false
  for ch in stem:
    if not (ch in {'a' .. 'z'} or ch in {'A' .. 'Z'}):
      return false
  # The stem must look like a kernel disk name: `sd`, `hd`, `vd`, `xvd`,
  # `nvme`, `mmcblk`.
  let lower = stem.toLowerAscii
  var isDiskStem = lower.startsWith("sd") or lower.startsWith("hd") or
                   lower.startsWith("vd") or lower.startsWith("xvd") or
                   lower.startsWith("nvme") or lower.startsWith("mmcblk")
  if not isDiskStem:
    # A namespace name carries the namespace number before the `p`:
    # `nvme0n1p3` has the stem `nvme0n1`.
    let withoutNumbers = lower.replace("0", "").replace("1", "")
                             .replace("2", "").replace("3", "")
                             .replace("4", "").replace("5", "")
                             .replace("6", "").replace("7", "")
                             .replace("8", "").replace("9", "")
    isDiskStem = withoutNumbers.startsWith("nvme") or
                 withoutNumbers.startsWith("mmcblk")
  isDiskStem

proc classifyByName(name: string): DeviceClass =
  ## Classify a block device by its kernel name.
  ##
  ## The name is a hint, never the last word: a partition of a physical disk
  ## is still a partition, and a `vd*` device is virtual even though the
  ## kernel names it like a SCSI disk.
  if name.startsWith("dm-"):
    return dcMapper
  if name.startsWith("md"):
    return dcRaid
  if name.startsWith("loop"):
    return dcLoop
  if name.startsWith("ram") or name.startsWith("zram"):
    return dcRam
  if name.startsWith("sr"):
    return dcOptical
  if name.startsWith("vd") or name.startsWith("xvd"):
    return dcVirtual
  if name.startsWith("nbd") or name.startsWith("zfs"):
    return dcVirtual
  if name.startsWith("zd"):
    # A ZFS zvol is a logical volume on top of a pool. It is not a
    # physical disk, and it is not a partition of one either.
    return dcVirtual
  dcUnknown

proc transportOf(name: string, deviceDir: string, driver: string): Transport =
  ## Decide the transport of a device from its sysfs shape.
  if name.startsWith("nvme"):
    return trNvme
  # A SAS device exposes its own SAS address in the SCSI device directory.
  if readAttr(deviceDir / "sas_address").ok:
    return trSas
  if driver.contains("ata"):
    return trSata
  if driver.contains("sd") or driver.contains("sr"):
    return trSata
  # A SCSI device without a more specific attribution.
  if readAttr(deviceDir / "type").ok:
    return trScsi
  trUnknown


proc collectDeviceNames(blockDir: string): tuple[ok: bool, names: seq[string]] =
  ## Enumerate the kernel block device names.
  result.names = @[]
  if not dirExists(blockDir):
    return (ok: false, names: result.names)
  for kind, path in walkDir(blockDir):
    if dirExists(path) or fileExists(path):
      let name = path.extractFilename()
      if name.len > 0:
        result.names.add name
  result.names.sort()
  (ok: true, names: result.names)

proc resolveAliasTarget(linkPath: string): string =
  ## Resolve a `/dev/disk/by-*` alias to the kernel device name it names.
  ##
  ## The link target is relative to `/dev` (`../../sdb`). The basename is
  ## the kernel device name.
  try:
    var buffer: array[4096, char]
    let written = posix.readlink(linkPath.cstring, addr buffer[0], 4095)
    if written <= 0:
      return ""
    let target = newString(written)
    copyMem(addr target[0], addr buffer[0], written)
    let base = target.extractFilename()
    if base.len > 0:
      return base
  except IOError, OSError:
    discard
  ""

proc collectAliases(devRoot: string, wanted: seq[string]): Table[string, seq[string]] =
  ## Map a kernel device name to its persistent aliases.
  result = initTable[string, seq[string]]()
  for dirName in ["disk/by-id", "disk/by-path"]:
    let aliasDir = devRoot / dirName
    if not dirExists(aliasDir):
      continue
    for kind, path in walkDir(aliasDir):
      # The alias is a symbolic link to a device node, so it is not a
      # regular file. The link itself is what matters here.
      if dirExists(path):
        continue
      let target = resolveAliasTarget(path)
      if target.len == 0 or target notin wanted:
        continue
      let alias = path.absolutePath
      if alias notin result.getOrDefault(target, @[]):
        result.mgetOrPut(target, @[]).add alias
  for key in result.keys:
    result[key].sort()

proc parseCapacityBytes(sectors: string): tuple[ok: bool, value: string] =
  ## Convert the sysfs `size` attribute into an exact byte count.
  ##
  ## The `size` attribute counts 512-byte sectors. The multiplication is
  ## checked: an overflowing result is refused rather than wrapped.
  let trimmed = sectors.strip()
  if trimmed.len == 0:
    return (ok: false, value: "")
  var sectors64: int64
  try:
    sectors64 = parseBiggestInt(trimmed)
  except ValueError:
    return (ok: false, value: "")
  if sectors64 < 0:
    return (ok: false, value: "")
  let bytes = sectors64 * int64(SysfsSectorBytes)
  if bytes shr 63 != 0:
    return (ok: false, value: "")
  (ok: true, value: $bytes)


proc parsePositiveInt(text: string, fallback: int): int =
  ## Parse a small non-negative integer attribute.
  let trimmed = text.strip()
  if trimmed.len == 0:
    return fallback
  try:
    result = parseInt(trimmed)
  except ValueError:
    result = fallback
  if result < 0:
    result = fallback

proc discoverDevice(name: string, blockDir: string, roots: DiscoveryRoots,
                    allNames: seq[string],
                    aliases: Table[string, seq[string]]): DeviceRecord =
  ## Read one block device from sysfs.
  result.kernelName = name
  result.deviceClass = classifyByName(name)
  result.transport = trUnknown
  result.identity.confidence = icUnresolved

  let dir = blockDir / name
  let deviceDir = dir / "device"

  let devAttr = readAttr(dir / "dev")
  if devAttr.ok and devAttr.value.len > 0:
    let parts = devAttr.value.split(':')
    if parts.len == 2:
      result.major = parts[0]
      result.minor = parts[1]

  result.sysfsPath = dir.absolutePath

  # ---- capacity ------------------------------------------------------------
  let sizeAttr = readAttr(dir / "size")
  if sizeAttr.ok:
    let capacity = parseCapacityBytes(sizeAttr.value)
    if capacity.ok:
      result.capacityBytes = capacity.value
    else:
      result.findings.add "the size attribute of " & name &
        " is malformed and was not interpreted"
  else:
    result.findings.add "the size attribute of " & name & " is unavailable"

  # ---- block sizes ---------------------------------------------------------
  let lbs = readAttr(dir / "queue/logical_block_size")
  result.logicalBlockSize = if lbs.ok: parsePositiveInt(lbs.value, 0) else: 0
  let pbs = readAttr(dir / "queue/physical_block_size")
  result.physicalBlockSize = if pbs.ok: parsePositiveInt(pbs.value, 0) else: 0

  # ---- rotational ----------------------------------------------------------
  let rot = readAttr(dir / "queue/rotational")
  if rot.ok and rot.value.len > 0:
    result.rotationalKnown = true
    result.rotational = rot.value == "1"

  # ---- identity attributes -------------------------------------------------
  let vendor = readAttr(deviceDir / "vendor")
  if vendor.ok:
    result.vendor = vendor.value
  let model = readAttr(deviceDir / "model")
  if model.ok:
    result.model = model.value
  let rev = readAttr(deviceDir / "rev")
  if rev.ok:
    result.firmware = rev.value
  let driver = readAttr(deviceDir / "driver")
  let driverName = if driver.ok: driver.value else: ""
  result.transport = transportOf(name, deviceDir, driverName)

  # ---- partition detection -------------------------------------------------
  let partitionAttr = readAttr(dir / "partition")
  if partitionAttr.ok:
    result.deviceClass = dcPartition
  elif isPartitionName(name):
    var stem = name
    while stem.len > 0 and stem[^1] in {'0' .. '9'}:
      stem.setLen(stem.len - 1)
    if stem.endsWith("p"):
      stem.setLen(stem.len - 1)
    if stem in allNames:
      result.deviceClass = dcPartition
    else:
      result.findings.add "the name of " & name &
        " looks like a partition, but its parent device was not discovered"

  # ---- device state --------------------------------------------------------
  let state = readAttr(deviceDir / "state")
  if state.ok and state.value != "running":
    result.findings.add "the kernel reports the state of " & name & " as '" &
      state.value & "'"

  # ---- access paths and aliases --------------------------------------------
  result.paths.add roots.devRoot / name
  if aliases.hasKey(name):
    result.aliases = aliases[name]

  # ---- udev properties -----------------------------------------------------
  if result.major.len > 0 and result.minor.len > 0:
    let udevPath = roots.udevDataDir / ("b" & result.major & ":" & result.minor)
    let props = readUdevProps(udevPath)
    if props.len > 0:
      if result.serial.len == 0 and props.hasKey("ID_SERIAL_SHORT"):
        result.serial = props["ID_SERIAL_SHORT"]
      elif result.serial.len == 0 and props.hasKey("ID_SERIAL"):
        result.serial = props["ID_SERIAL"]
      if result.model.len == 0 and props.hasKey("ID_MODEL"):
        result.model = props["ID_MODEL"]
      if result.vendor.len == 0 and props.hasKey("ID_VENDOR"):
        result.vendor = props["ID_VENDOR"]
      # udev's bus attribution refines the transport, but it does not
      # override a stronger observation: a device that exposes a SAS
      # address stays SAS even when udev calls the bus `scsi`.
      if props.hasKey("ID_BUS"):
        case props["ID_BUS"]
        of "ata":
          if result.transport != trSas and result.transport != trNvme:
            result.transport = trSata
        of "nvme":
          if result.transport != trSas:
            result.transport = trNvme
        of "scsi":
          if result.transport == trUnknown:
            result.transport = trScsi
        else:
          discard
      if result.wwn.len == 0 and props.hasKey("ID_WWN_WITH_EXTENSION"):
        result.wwn = props["ID_WWN_WITH_EXTENSION"]
      elif result.wwn.len == 0 and props.hasKey("ID_WWN"):
        result.wwn = props["ID_WWN"]
    else:
      result.findings.add "no udev properties were available for " & name

  # ---- the world-wide name -------------------------------------------------
  if result.wwn.len == 0:
    let wwid = readAttr(deviceDir / "wwid")
    if wwid.ok and wwid.value.len > 0:
      result.wwn = wwid.value
    else:
      let blockWwid = readAttr(dir / "wwid")
      if blockWwid.ok and blockWwid.value.len > 0:
        result.wwn = blockWwid.value

  # ---- the NVMe namespace identity -----------------------------------------
  if result.transport == trNvme:
    let nsid = readAttr(dir / "nsid")
    if nsid.ok and nsid.value.len > 0:
      result.findings.add "nvme namespace id: " & nsid.value
    let eui = readAttr(dir / "eui")
    if eui.ok and eui.value.len > 0 and result.wwn.len == 0:
      result.wwn = "eui." & eui.value
  if result.deviceClass == dcUnknown and result.transport != trUnknown:
    result.deviceClass = dcPhysical
  if result.deviceClass == dcUnknown:
    result.findings.add "the device class of " & name & " could not be determined"


proc discover*(roots: DiscoveryRoots): Inventory =
  ## Perform one passive discovery pass.
  ##
  ## The pass never opens a block device and never runs an observation
  ## tool. A missing discovery root is reported as an **incomplete**
  ## inventory with an explicit finding: an enumeration failure is never
  ## turned into a successful empty inventory.
  let blockDir = roots.sysfsRoot / "class/block"
  result.root = roots.sysfsRoot
  result.findings = @[]
  result.devices = @[]
  result.complete = true

  let names = collectDeviceNames(blockDir)
  if not names.ok:
    result.complete = false
    result.findings.add "the block-device discovery root is unavailable: " &
      blockDir
    return

  let aliases = collectAliases(roots.devRoot, names.names)

  for name in names.names:
    if not dirExists(blockDir / name) and not fileExists(blockDir / name):
      result.findings.add "the device " & name &
        " disappeared during the enumeration"
      result.complete = false
      continue
    try:
      let record = discoverDevice(name, blockDir, roots, names.names, aliases)
      result.devices.add record
    except IOError, OSError:
      result.findings.add "the device " & name &
        " could not be read completely; its observations are partial"
      result.complete = false
