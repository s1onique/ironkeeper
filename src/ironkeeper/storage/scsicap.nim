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
##
## ## What the mapping needs and what it does not get
##
## A READ CAPACITY(16) response that carries no `PROT_EN` field carries
## **no** protection information. Such a response is not evidence of
## disabled protection: it is evidence that the protection state was not
## observed. The module therefore distinguishes four states that the
## earlier implementation collapsed into one:
##
##   * `missing` - the tool did not report the field;
##   * `invalid` - the tool reported a value outside the defined range;
##   * `reserved` - the tool reported a combination the standard reserves;
##   * a normalized type - the tool reported a valid combination.
##
## Type 0 is derived **only** from an observed `PROT_EN` of zero.

import std/strutils

import ironkeeper/json/exactdecimal as dec
from ironkeeper/storage/types import Observation, ObservationStatus, osObserved,
  osDerived, osUnsupported, osInvalid, osUnavailable

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
  ProtectionMissing* = "missing"
    ## The protection state was not observed.
  ProtectionInvalid* = "invalid"
    ## The protection state was observed but outside the defined range.

  MaxProtEn* = 1
    ## The largest defined `PROT_EN` value.
  MaxPType* = 3
    ## The largest defined `P_TYPE` value.

type
  ProtectionType* = enum
    ## The normalized protection type of a logical unit.
    ptType0
    ptType1
    ptType2
    ptType3
    ptReserved
    ptMissing
      ## The tool did not report the protection fields.
    ptInvalid
      ## The tool reported protection fields outside the defined range.

  ProtectionEvidence* = object
    ## The raw protection fields as the tool reported them.
    ##
    ## The presence of a field and the validity of a field are **separate**
    ## facts: an absent field is not a zero, and an out-of-range field is
    ## not a protection type.
    protEnPresent*: bool
    protEn*: int
    protEnValid*: bool
    pTypePresent*: bool
    pType*: int
    pTypeValid*: bool

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
  of ptMissing: ProtectionMissing
  of ptInvalid: ProtectionInvalid

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

proc mapProtectionEvidence*(evidence: ProtectionEvidence): ProtectionType =
  ## Map the observed protection evidence onto the normalized protection
  ## type.
  ##
  ## Type 0 requires an **observed** `PROT_EN` of zero. An absent field
  ## yields `missing` and an out-of-range field yields `invalid`; neither
  ## is ever mapped onto Type 0.
  if not evidence.protEnPresent:
    return ptMissing
  if not evidence.protEnValid:
    return ptInvalid
  if evidence.protEn == 0:
    return ptType0
  if not evidence.pTypePresent:
    return ptMissing
  if not evidence.pTypeValid:
    return ptInvalid
  mapProtection(evidence.protEn, evidence.pType)

proc mulChecked*(a: string, b: int64): tuple[ok: bool, value: string] =
  ## Multiply an exact decimal string by a small integer, with a check.
  ##
  ## The multiplication is performed on the decimal digits, so the result
  ## is exact for every capacity that fits in `int64`. Only the **leading**
  ## zeros are trimmed: a trailing zero is a significant digit, so
  ## `1000 * 512` is `512000` and not `512`.
  let product = dec.mulSmall(a, b)
  (ok: product.ok, value: product.value)

proc addOne*(a: string): tuple[ok: bool, value: string] =
  ## Add one to an exact decimal string, with a check.
  let sum = dec.addOne(a)
  (ok: sum.ok, value: sum.value)

proc decodeCapacity*(lastLba: string, blockLength: int,
                     protection: ProtectionEvidence = ProtectionEvidence(),
                     protectionExponent = -1,
                     physicalBlockExponent = -1): CapacityReading =
  ## Decode a READ CAPACITY(16) response.
  ##
  ## The logical block count is `last_lba + 1` and the capacity is
  ## `logical_blocks * logical_block_length`. Both are computed with
  ## checked exact arithmetic; the values are carried as decimal strings
  ## so that a capacity beyond 2^53 bytes keeps every digit.
  ##
  ## The protection evidence is passed in as **evidence**, not as two
  ## integers: an absent field is absent, and it never becomes a zero.
  result.lastLogicalBlockAddress = lastLba
  result.logicalBlockLength = blockLength
  if protection.protEnPresent:
    result.protectionEnabled = protection.protEn
  if protection.pTypePresent:
    result.protectionTypeRaw = protection.pType
  result.protectionType = mapProtectionEvidence(protection)
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
    status: (if reading.protectionType == ptMissing: osUnavailable
             elif reading.protectionType == ptInvalid: osInvalid
             else: osObserved),
    value: (if reading.protectionType == ptMissing or
             reading.protectionType == ptInvalid: ""
            else: $reading.protectionEnabled),
    unit: "boolean",
    source: source, sourceField: "prot_en", collectedAt: collectedAt,
    reason: (if reading.protectionType == ptMissing:
               "the tool did not report the protection enable field"
             elif reading.protectionType == ptInvalid:
               "the tool reported a protection enable value outside the " &
               "defined range"
             else: ""))
  result.add Observation(name: "protection.raw_type",
    status: (if reading.protectionType == ptMissing: osUnavailable
             elif reading.protectionType == ptInvalid: osInvalid
             else: osObserved),
    value: (if reading.protectionType == ptMissing or
             reading.protectionType == ptInvalid: ""
            else: $reading.protectionTypeRaw),
    unit: "code",
    source: source, sourceField: "p_type", collectedAt: collectedAt,
    reason: (if reading.protectionType == ptMissing:
               "the tool did not report the protection type field"
             elif reading.protectionType == ptInvalid:
               "the tool reported a protection type value outside the " &
               "defined range"
             else: ""))
  result.add Observation(name: "protection.type",
    status: (if reading.protectionType == ptReserved: osUnsupported
             elif reading.protectionType == ptMissing: osUnavailable
             elif reading.protectionType == ptInvalid: osInvalid
             else: osDerived),
    value: protectionTypeName(reading.protectionType), unit: "type",
    source: source, sourceField: "prot_en + p_type", collectedAt: collectedAt,
    reason: (if reading.protectionType == ptReserved:
               "the protection combination is reserved and is not supported"
             elif reading.protectionType == ptMissing:
               "the protection state was not observed, so no protection " &
               "type is claimed"
             elif reading.protectionType == ptInvalid:
               "the protection fields were outside the defined range, so " &
               "no protection type is claimed"
             else: ""))
