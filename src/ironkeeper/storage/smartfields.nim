## Field extraction helpers for external SMART JSON.
##
## The `smartctl -x -j` document has three different numeric shapes:
##
##   * a plain JSON number, for example `"hours": 42015`;
##   * a **decimal string**, used by `smartctl` for values that do not fit
##     into a JSON number, for example `"value": "18446744073709551616"`;
##   * a **raw companion**, for example `"value_raw": "0x10000000000000000"`,
##     which `smartctl` emits beside a value that is too large for a
##     64-bit integer.
##
## This module reads a value together with its companion and reports what
## it found, so that the normalisation layer can consume a value only when
## the representations agree. A disagreement is an **explicit finding**,
## never a silently preferred value.

import std/strutils

from ironkeeper/storage/externaljson import ExtNode, member, asString,
  exactIntegerText, hexToDecimal, ekNumber, ekString
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
  ## The field may be a JSON number or a decimal string. When a companion
  ## `key_raw` (a hexadecimal string) or `key_hex` is present, it is
  ## compared with the value. A disagreement is reported as
  ## `osConflicting`; a companion that cannot be interpreted is reported as
  ## `osInvalid`.
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

  # ---- the companions ------------------------------------------------------
  for companion in ["_raw", "_hex"]:
    let other = member(parent, key & companion)
    if other.isNil:
      continue
    let otherText = asString(other)
    if otherText.len == 0:
      result.status = osInvalid
      result.reason = key & companion & " is empty"
      return
    var otherDecimal = ""
    if otherText.startsWith("0x") or otherText.startsWith("0X"):
      otherDecimal = hexToDecimal(otherText[2 .. ^1])
      if otherDecimal.len == 0:
        result.status = osInvalid
        result.reason = key & companion & " is not a hexadecimal number"
        return
    else:
      otherDecimal = exactIntegerText(otherText)
      if otherDecimal.len == 0:
        result.status = osInvalid
        result.reason = key & companion & " is not an exact decimal integer"
        return
    if otherDecimal != text:
      result.status = osConflicting
      result.reason = key & " and its companion " & key & companion &
        " disagree"
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
