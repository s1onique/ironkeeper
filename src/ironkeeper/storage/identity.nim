## Identity and path reconciliation for Ironkeeper.
##
## This module turns the raw observations of the discovery adapter into a
## *reconciled identity* per device, and answers the question "which device
## does this selector name?".
##
## ## The concepts that are kept apart
##
## The module never collapses these into one another:
##
##   * **physical or logical storage identity** - the thing that is the
##     disk: a SCSI logical unit, an ATA device, an NVMe namespace;
##   * **namespace / logical unit identity** - the addressed unit inside a
##     controller;
##   * **controller identity** - the adapter or controller;
##   * **access path** - `/dev/sdX`, an alias, a multipath path;
##   * **transport endpoint** - the SAS port address, the SCSI target.
##
## A SAS port address is **not** the disk's logical-unit identifier, and a
## controller serial is **not** an NVMe namespace identifier: two namespaces
## behind one controller are two storage namespaces.
##
## ## Confidence
##
## A reconciled identity carries a confidence:
##
##   * `authoritative` - a persistent identifier was observed that survives
##     ordinary path changes (a SCSI logical-unit WWN, an ATA WWN, an NVMe
##     namespace NGUID/EUI-64/UUID);
##   * `probable` - only weaker observations exist, for example a serial
##     number. A serial-only identity never becomes globally authoritative;
##   * `ambiguous` - the observations contradict each other, or another
##     device carries the same identifier;
##   * `unresolved` - nothing usable was observed.
##
## An ambiguous identity **refuses** active interrogation.

import std/[strutils, tables, sets]

from ironkeeper/storage/types import DeviceRecord, Inventory, Identity,
  IdentityConfidence, Identifier, IdentifierKind, IdentifierNamespace,
  icAuthoritative, icProbable, icAmbiguous, icUnresolved, ikScsiWwn,
  ikAtaWwn, ikNguid, ikEui64, ikNvmeUuid, ikSerial, ikDiskSeq, inLogicalUnit,
  inNamespace, inController, dcPhysical

type
  SelectorKind* = enum
    ## The way an operator names a device.
    skWwn
      ## A persistent world-wide name.
    skSerial
      ## An exact device serial number.
    skPath
      ## A device path that must resolve through the inventory.

  Selector* = object
    ## An explicit target selection.
    kind*: SelectorKind
    value*: string

  SelectionResult* = object
    ## The outcome of resolving a selector.
    ok*: bool
    device*: DeviceRecord
    found*: bool
      ## True when at least one device matched.
    ambiguous*: bool
      ## True when more than one device matched.
    message*: string
      ## Why the selection failed.

proc stripHexPrefix(s: string): string =
  ## Remove a `0x` or `0X` prefix.
  if s.len > 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X'):
    return s[2 .. ^1]
  s

proc canonicalizeWwn(raw: string): string =
  ## Canonicalise a world-wide name.
  ##
  ## The Linux kernel reports a SCSI WWN as `naa.5000cca0570377c4`, udev as
  ## `0x5000cca0570377c4`, and some tools as the bare hex digits. All
  ## three denote the same identifier, so all three canonicalise to the
  ## lowercase hex digits. A value that is not hexadecimal is returned
  ## unchanged, so that a malformed value is visible rather than hidden.
  var text = raw.strip()
  if text.len == 0:
    return ""
  let dot = text.find('.')
  if dot >= 0:
    text = text[dot + 1 .. ^1]
  text = stripHexPrefix(text)
  if text.len > 0:
    var hex = true
    for ch in text:
      if not (ch in {'0' .. '9'} or ch in {'a' .. 'f'} or ch in {'A' .. 'F'}):
        hex = false
        break
    if hex:
      return text.toLowerAscii
  text

proc canonicalizeSerial(raw: string): string =
  ## Canonicalise a serial number for comparison.
  ##
  ## The comparison form is the trimmed, whitespace-collapsed, upper-cased
  ## text. The *original* value is always preserved alongside it.
  raw.strip().replace(" ", "").toUpperAscii


proc identifierOfWwn(raw: string): Identifier =
  ## Build the identifier record of an observed world-wide name.
  let canonical = canonicalizeWwn(raw)
  if canonical.len == 0:
    return Identifier(kind: ikScsiWwn, namespace: inLogicalUnit, value: "",
                      original: raw, source: "sysfs:wwid")
  Identifier(kind: ikScsiWwn, namespace: inLogicalUnit, value: canonical,
             original: raw, source: "sysfs:wwid")

proc reconcile*(inv: var Inventory) =
  ## Reconcile the identities of every discovered device.
  ##
  ## The reconciliation detects, without ever merging devices:
  ##
  ##   * two devices that carry the same serial number;
  ##   * two devices that carry the same world-wide name;
  ##   * a device whose own observations disagree.
  ##
  ## A device is never merged into another device on the strength of a
  ## model, a serial or a path alone.
  var serialCounts = initTable[string, int]()
  var wwnCounts = initTable[string, int]()
  # Only **physical disk candidates** take part in the duplicate
  # detection. A partition inherits the serial number of its disk, so
  # counting partitions would make every disk with a partition look
  # ambiguous.
  for d in inv.devices:
    if d.deviceClass != dcPhysical:
      continue
    if d.serial.len > 0:
      let key = canonicalizeSerial(d.serial)
      if key.len > 0:
        serialCounts[key] = serialCounts.getOrDefault(key) + 1
    if d.wwn.len > 0:
      let key = canonicalizeWwn(d.wwn)
      if key.len > 0:
        wwnCounts[key] = wwnCounts.getOrDefault(key) + 1

  for i in 0 ..< inv.devices.len:
    var identity = Identity(confidence: icUnresolved, identifiers: @[],
                            conflicts: @[], duplicateSerial: false)
    let d = inv.devices[i]

    if d.wwn.len > 0:
      let identifier = identifierOfWwn(d.wwn)
      identity.identifiers.add identifier
      if d.deviceClass == dcPhysical and
         wwnCounts.getOrDefault(identifier.value) > 1:
        identity.conflicts.add "the world-wide name " & identifier.value &
          " is carried by more than one device"
    if d.serial.len > 0:
      let key = canonicalizeSerial(d.serial)
      identity.identifiers.add Identifier(
        kind: ikSerial, namespace: inLogicalUnit, value: key,
        original: d.serial, source: "sysfs:udev")
      if d.deviceClass == dcPhysical and serialCounts.getOrDefault(key) > 1:
        identity.duplicateSerial = true
        identity.conflicts.add "the serial number " & d.serial &
          " is carried by more than one device"

    # A world-wide name is authoritative for a logical unit. For an NVMe
    # namespace, the kernel's `wwid` names the *namespace*; a controller
    # serial does not, so it never becomes an authoritative namespace
    # identity.
    if identity.identifiers.len > 0 and identity.identifiers[0].kind == ikScsiWwn:
      identity.confidence = icAuthoritative
    elif d.serial.len > 0:
      identity.confidence = icProbable
    else:
      identity.confidence = icUnresolved

    if identity.conflicts.len > 0:
      identity.confidence = icAmbiguous

    inv.devices[i].identity = identity


proc selectDevice*(inv: Inventory, selector: Selector): SelectionResult =
  ## Resolve an explicit selector against the discovered inventory.
  ##
  ## An ambiguous selector never resolves arbitrarily: it returns
  ## `ambiguous = true` and no device, and the caller refuses the active
  ## interrogation.
  result.ok = false
  result.found = false
  result.ambiguous = false

  var matches: seq[DeviceRecord] = @[]
  case selector.kind
  of skWwn:
    let wanted = canonicalizeWwn(selector.value)
    if wanted.len == 0:
      result.message = "the requested world-wide name is empty"
      return
    for d in inv.devices:
      if d.wwn.len > 0 and canonicalizeWwn(d.wwn) == wanted:
        matches.add d
  of skSerial:
    let wanted = canonicalizeSerial(selector.value)
    if wanted.len == 0:
      result.message = "the requested serial number is empty"
      return
    for d in inv.devices:
      if d.serial.len > 0 and canonicalizeSerial(d.serial) == wanted:
        matches.add d
  of skPath:
    let wanted = selector.value.strip()
    for d in inv.devices:
      var hit = false
      for p in d.paths:
        if p == wanted:
          hit = true
      for a in d.aliases:
        if a == wanted:
          hit = true
      if hit:
        matches.add d

  if matches.len == 0:
    result.message = "no device matches the selector '" & selector.value & "'"
    return
  if matches.len > 1:
    result.found = true
    result.ambiguous = true
    var names: seq[string] = @[]
    for m in matches:
      names.add m.kernelName
    result.message = "the selector '" & selector.value &
      "' matches more than one device: " & names.join(", ")
    return

  let device = matches[0]
  result.found = true
  if device.identity.confidence == icAmbiguous:
    result.message = "the identity of " & device.kernelName &
      " is ambiguous: " & device.identity.conflicts.join("; ")
    return
  if device.deviceClass != dcPhysical:
    result.message = device.kernelName & " is not a physical disk candidate (" &
      $device.deviceClass & ") and is not an active-interrogation target"
    return
  result.device = device
  result.ok = true
  result.message = ""
