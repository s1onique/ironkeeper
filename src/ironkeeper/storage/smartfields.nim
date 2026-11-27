## Field extraction helpers for external SMART JSON.
##
## The `smartctl -x -j` document has three different numeric shapes:
##
##   * a plain JSON number, for example `"hours": 42015`;
##   * a **decimal string**, used by `smartctl` for values that do not fit
##     into a JSON number, for example `"value": "18446744073709551616"`;
##   * the **`KEY_s` and `KEY_le` companions**, which `smartctl` emits
##     beside a value that may exceed the JSON safe integer range.
##
## ## The companions that actually exist
##
## With the verbose JSON option (`--json=ov`, smartmontools 7.4 and
## later) `smartctl` emits, for a value that may exceed 53 bits, the
## number itself under `KEY`, the exact decimal value as a string under
## `KEY_s`, and - for a value that exceeds 64 bits - the raw bytes as a
## little-endian byte array under `KEY_le` (`smartmontools/json.cpp`).
##
## These are the companions the module reads. A companion that the tool
## did not emit is simply absent; a field with a different name is an
## **unrelated** field and never participates in the comparison.
##
## This module reads a value together with its companion and reports what
## it found, so that the normalisation layer can consume a value only when
## the representations agree. A disagreement is an **explicit finding**,
## never a silently preferred value.

import std/strutils

from ironkeeper/storage/externaljson import ExtNode, member, asString,
  exactIntegerText, ekNumber, ekString, ekArray
from ironkeeper/json/exactdecimal import leBytesToDecimal
from ironkeeper/storage/types import Observation, ObservationStatus, osObserved,
  osUnavailable, osInvalid, osConflicting

type
  ExactValue* = object
    ## The outcome of reading one numeric field.
    ok*: bool
    text*: string
      ## The exact decimal value.
    status*: ObservationStatus
    reason*: string

proc readExactField*(parent: ExtNode, key: string): ExactValue =
  ## Read one numeric field, with its companion representations.
  ##
  ## The field may be a JSON number or a decimal string. The companion
  ## `KEY_s` (the exact decimal value as a string) and the companion
  ## `KEY_le` (the raw bytes as a little-endian byte array) are compared
  ## with the value when they are present. A disagreement is reported as
  ## `osConflicting`; a companion that cannot be interpreted is reported
  ## as `osInvalid`.
  result.status = osUnavailable
  let node = member(parent, key)
  if node.isNil:
    result.reason = "the tool did not report " & key
    return

  var text = ""
  if node.kind == ekNumber:
    text = exactIntegerText(node.str)
    if text.len == 0:
      result.status = osInvalid
      result.reason = key & " is not an exact integer"
      return
  elif node.kind == ekString:
    text = exactIntegerText(node.str)
    if text.len == 0:
      result.status = osInvalid
      result.reason = key & " is not an exact decimal integer"
      return
  else:
    result.status = osInvalid
    result.reason = key & " is not a number"
    return

  # ---- the `KEY_s` companion ------------------------------------------------
  # The exact decimal value as a string. It must agree with the value.
  let stringCompanion = member(parent, key & "_s")
  if not stringCompanion.isNil:
    if stringCompanion.kind != ekString:
      result.status = osInvalid
      result.reason = key & "_s is not a string"
      return
    let companionText = exactIntegerText(stringCompanion.str)
    if companionText.len == 0:
      result.status = osInvalid
      result.reason = key & "_s is not an exact decimal integer"
      return
    if companionText != text:
      result.status = osConflicting
      result.reason = key & " and its companion " & key & "_s disagree"
      return

  # ---- the `KEY_le` companion ------------------------------------------------
  # The raw bytes as a little-endian byte array. It must agree with the
  # value as well.
  let byteCompanion = member(parent, key & "_le")
  if not byteCompanion.isNil:
    if byteCompanion.kind != ekArray:
      result.status = osInvalid
      result.reason = key & "_le is not an array of bytes"
      return
    var bytes: seq[int] = @[]
    for item in byteCompanion.items:
      if item.kind != ekNumber:
        result.status = osInvalid
        result.reason = key & "_le contains a non-numeric byte"
        return
      var byteValue = 0
      try:
        byteValue = parseInt(item.str)
      except ValueError:
        result.status = osInvalid
        result.reason = key & "_le contains a byte that is not an integer"
        return
      bytes.add byteValue
    let decimal = leBytesToDecimal(bytes)
    if not decimal.ok:
      result.status = osInvalid
      result.reason = key & "_le is malformed: " & decimal.reason
      return
    if decimal.value != text:
      result.status = osConflicting
      result.reason = key & " and its companion " & key & "_le disagree"
      return

  result.ok = true
  result.text = text
  result.status = osObserved
  result.reason = ""

proc observationFrom*(name: string, value: ExactValue, unit: string,
                      source: string, field: string,
                      collectedAt: string): Observation =
  ## Turn an exact field into an observation.
  ##
  ## A field that is not available becomes an observation with the status
  ## `unavailable` and the reason. It never becomes a zero.
  if value.ok:
    Observation(name: name, status: osObserved, value: value.text, unit: unit,
                source: source, sourceField: field, collectedAt: collectedAt)
  else:
    Observation(name: name, status: value.status, value: "", unit: unit,
                source: source, sourceField: field, collectedAt: collectedAt,
                reason: value.reason)
