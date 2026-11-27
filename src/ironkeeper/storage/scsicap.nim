## SCSI READ CAPACITY(16) observations and protection-format mapping.
##
## This module is **pure**: it decodes a capacity response into typed
## values and maps the protection fields into a normalized protection
## type. It performs no I/O; the acquisition of the response belongs to
## the backend that calls it.
##
## ## The protection mapping
##
## The raw `PROT_EN` and `P_TYPE` fields are **not** the protection type.
## The mapping is:
##
## | PROT_EN | P_TYPE | normalized protection |
## |---|---|---|
## | 0 | any | Type 0 |
## | 1 | 0 | Type 1 |
## | 1 | 1 | Type 2 |
## | 1 | 2 | Type 3 |
## | 1 | 3-7 | reserved / unsupported |
##
## Both raw fields are always retained next to the derived value, and a
## reserved combination is reported as **unsupported**: it is never
## silently mapped onto Type 0.

import std/strutils

from ironkeeper/storage/types import Observation, ObservationStatus, osObserved,
  osDerived, osUnsupported, osInvalid

const
  ProtectionType0* = "type_0"
    ## No protection information.
  ProtectionType1* = "type_1"
    ## Protection information in the guard field.
  ProtectionType2* = "type_2"
    ## Protection information in the logical block application tag.
  ProtectionType3* = "type_3"
    ## Protection information in both the guard and the application tag.
  ProtectionReserved* = "reserved_unsupported"
    ## A reserved protection combination. Never mapped onto Type 0.

type
  ProtectionType* = enum
    ## The normalized protection type of a logical unit.
    ptType0
    ptType1
    ptType2
    ptType3
    ptReserved

  CapacityReading* = object
    ## A decoded READ CAPACITY(16) response.
    lastLogicalBlockAddress*: string
      ## The last logical block address, as an exact decimal string.
    logicalBlockCount*: string
      ## The number of logical blocks, as an exact decimal string.
    logicalBlockLength*: int
      ## The logical block length in bytes.
    capacityBytes*: string
      ## The total capacity in bytes, as an exact decimal string.
    protectionEnabled*: int
      ## The raw `PROT_EN` value.
    protectionTypeRaw*: int
      ## The raw `P_TYPE` value.
    protectionType*: ProtectionType
    protectionExponent*: int
      ## The protection information exponent, when the tool reports it.
    physicalBlockExponent*: int
      ## The logical blocks per physical block exponent, when reported.

proc protectionTypeName*(t: ProtectionType): string =
  ## The stable wire name of a normalized protection type.
  case t
  of ptType0: ProtectionType0
  of ptType1: ProtectionType1
  of ptType2: ProtectionType2
  of ptType3: ProtectionType3
  of ptReserved: ProtectionReserved

proc mapProtection*(protEn: int, pType: int): ProtectionType =
  ## Map the raw protection fields onto the normalized protection type.
  ##
  ## The mapping is total: every combination of `PROT_EN` and `P_TYPE`
  ## has an answer, and the reserved combinations are answered as
  ## *reserved*, not as Type 0.
  if protEn == 0:
    return ptType0
  case pType
  of 0: ptType1
  of 1: ptType2
  of 2: ptType3
  else: ptReserved

proc mulChecked*(a: string, b: int64): tuple[ok: bool, value: string] =
  ## Multiply an exact decimal string by a small integer, with a check.
  ##
  ## The multiplication is performed on the decimal digits, so the result
  ## is exact for every capacity that fits in `int64`.
  if a.len == 0 or b < 0:
    return (ok: false, value: "")
  var carry = 0'i64
  var digits = ""
  for i in countdown(a.len - 1, 0):
    let d = (a[i].ord - '0'.ord).int64 * b + carry
    carry = d div 10
    digits.add $(d mod 10)
  while carry > 0:
    digits.add $(carry mod 10)
    carry = carry div 10
  var result = ""
  for i in countdown(digits.len - 1, 0):
    result.add digits[i]
  let trimmed = result.strip(chars = {'0'})
  if trimmed.len == 0:
    return (ok: true, value: "0")
  (ok: true, value: trimmed)

proc addOne*(a: string): tuple[ok: bool, value: string] =
  ## Add one to an exact decimal string, with a check.
  if a.len == 0:
    return (ok: false, value: "")
  var carry = 1
  var digits = ""
  for i in countdown(a.len - 1, 0):
    let d = (a[i].ord - '0'.ord) + carry
    carry = d div 10
    digits.add $(d mod 10)
  while carry > 0:
    digits.add $(carry mod 10)
    carry = carry div 10
  var result = ""
  for i in countdown(digits.len - 1, 0):
    result.add digits[i]
  let trimmed = result.strip(chars = {'0'})
  if trimmed.len == 0:
    return (ok: true, value: "0")
  (ok: true, value: trimmed)

proc decodeCapacity*(lastLba: string, blockLength: int,
                     protEn = 0, pType = 0,
                     protectionExponent = -1,
                     physicalBlockExponent = -1): CapacityReading =
  ## Decode a READ CAPACITY(16) response.
  ##
  ## The logical block count is `last_lba + 1` and the capacity is
  ## `logical_blocks * logical_block_length`. Both are computed with
  ## checked exact arithmetic; the values are carried as decimal strings
  ## so that a capacity beyond 2^53 bytes keeps every digit.
  result.lastLogicalBlockAddress = lastLba
  result.logicalBlockLength = blockLength
  result.protectionEnabled = protEn
  result.protectionTypeRaw = pType
  result.protectionType = mapProtection(protEn, pType)
  result.protectionExponent = protectionExponent
  result.physicalBlockExponent = physicalBlockExponent

  let count = addOne(lastLba)
  if not count.ok:
    return
  result.logicalBlockCount = count.value
  if blockLength <= 0:
    return
  let capacity = mulChecked(count.value, int64(blockLength))
  if capacity.ok:
    result.capacityBytes = capacity.value

proc capacityObservations*(reading: CapacityReading, source: string,
                           collectedAt: string): seq[Observation] =
  ## Turn a decoded capacity response into observations.
  ##
  ## Every field that the response did not provide becomes an
  ## observation with the status `unavailable`, never a zero.
  result = @[]
  result.add Observation(name: "capacity.last_logical_block_address",
    status: (if reading.lastLogicalBlockAddress.len > 0: osObserved
             else: osUnsupported),
    value: reading.lastLogicalBlockAddress, unit: "blocks",
    source: source, sourceField: "last_logical_block_address",
    collectedAt: collectedAt,
    reason: (if reading.lastLogicalBlockAddress.len > 0: ""
             else: "the tool did not report the last logical block address"))
  result.add Observation(name: "capacity.logical_block_count",
    status: (if reading.logicalBlockCount.len > 0: osDerived
             else: osUnsupported),
    value: reading.logicalBlockCount, unit: "blocks",
    source: source, sourceField: "last_logical_block_address + 1",
    collectedAt: collectedAt,
    reason: (if reading.logicalBlockCount.len > 0: ""
             else: "the last logical block address was not available"))
  result.add Observation(name: "capacity.logical_block_length",
    status: (if reading.logicalBlockLength > 0: osObserved
             else: osUnsupported),
    value: (if reading.logicalBlockLength > 0: $reading.logicalBlockLength
             else: ""),
    unit: "bytes", source: source, sourceField: "logical_block_length",
    collectedAt: collectedAt,
    reason: (if reading.logicalBlockLength > 0: ""
             else: "the tool did not report the logical block length"))
  result.add Observation(name: "capacity.total_bytes",
    status: (if reading.capacityBytes.len > 0: osDerived
             else: osUnsupported),
    value: reading.capacityBytes, unit: "bytes",
    source: source, sourceField: "logical_block_count * logical_block_length",
    collectedAt: collectedAt,
    reason: (if reading.capacityBytes.len > 0: ""
             else: "the capacity could not be computed exactly"))
  result.add Observation(name: "protection.enabled",
    status: osObserved, value: $reading.protectionEnabled, unit: "boolean",
    source: source, sourceField: "prot_en", collectedAt: collectedAt)
  result.add Observation(name: "protection.raw_type",
    status: osObserved, value: $reading.protectionTypeRaw, unit: "code",
    source: source, sourceField: "p_type", collectedAt: collectedAt)
  result.add Observation(name: "protection.type",
    status: (if reading.protectionType == ptReserved: osUnsupported
             else: osDerived),
    value: protectionTypeName(reading.protectionType), unit: "type",
    source: source, sourceField: "prot_en + p_type", collectedAt: collectedAt,
    reason: (if reading.protectionType == ptReserved:
               "the protection combination is reserved and is not supported"
             else: ""))
