## Tests for the bounds of the public output documents.
##
## The bounds are enforced at the production boundary, so the tests
## exercise the production functions: a bound that only holds in a test
## is not a bound.

import std/[json, strutils]

import testkit

from ironkeeper/contracts/outputbounds import boundText, boundMessage,
  boundLocation, boundCode, boundDetail, MaxMessageLength, MaxLocationLength,
  MaxCodeLength, MaxDetailLength, MaxIssueCount, TruncationMarker
from ironkeeper/contracts/utf8 import isValidUtf8, runeCount, sanitizeUtf8,
  sanitizeJson
from ironkeeper/contracts.report import Report, ReportType, newReport,
  newFinding, toJson, FindingSeverity, fsError, esSucceeded, avPass

proc runSuite*(): int =
  var t = newTestSuite("outputbounds")

  # --- a value that fits is returned unchanged -----------------------------
  t.checkEq("a short message is unchanged", boundMessage("hello"), "hello")
  t.checkEq("a short code is unchanged", boundCode("config.valid"), "config.valid")

  # --- a truncated value stays valid Unicode -------------------------------
  # The message is built so that a multi-byte code point straddles the
  # boundary: the cut must not split it.
  # The code point is placed so that a *byte*-oriented cut at the limit
  # would land inside it: the two bytes of the character occupy the
  # offsets 4083 and 4084, and the byte boundary falls between them.
  let filler = "a".repeat(MaxMessageLength - 13)
  let straddling = filler & "\u00e9" & "z".repeat(100)
  let truncated = boundMessage(straddling)
  t.check("the truncated message is valid UTF-8", isValidUtf8(truncated))
  t.check("the truncated message respects the limit",
          runeCount(truncated) <= MaxMessageLength)
  t.check("the truncated message carries the marker",
          truncated.endsWith(TruncationMarker))
  t.check("the truncated message is not empty", truncated.len > 0)
  t.check("the code point at the boundary survived intact",
          truncated.contains("\u00e9"))

  # A code point that would straddle the boundary must be cut *before* the
  # boundary, so the last code point before the marker is intact.
  let emoji = "b".repeat(MaxMessageLength - 2) & "\u00e9" & "c"
  let cut = boundMessage(emoji)
  t.check("the cut is valid UTF-8", isValidUtf8(cut))
  t.check("the cut respects the limit", runeCount(cut) <= MaxMessageLength)

  # --- the marker fits inside the bound -------------------------------------
  for limit in [1, 2, 5, 12, 13, 64]:
    let value = "z".repeat(200)
    let bounded = boundText(value, limit)
    t.check("the bounded value respects the limit of " & $limit,
            runeCount(bounded) <= limit)
    t.check("the bounded value is valid UTF-8 at the limit of " & $limit,
            isValidUtf8(bounded))

  # --- invalid external text receives an explicit representation ------------
  let invalid = "before\xffafter"
  let repaired = boundMessage(invalid)
  t.check("the repaired message is valid UTF-8", isValidUtf8(repaired))
  t.check("the repaired message names the defect",
          repaired.contains("[invalid utf-8]"))

  # --- stable codes are not turned into unrelated codes --------------------
  let longCode = "config." & "x".repeat(MaxCodeLength)
  let boundedCode = boundCode(longCode)
  t.check("a bounded code is valid UTF-8", isValidUtf8(boundedCode))
  t.check("a bounded code respects the limit",
          runeCount(boundedCode) <= MaxCodeLength)
  t.check("a shortened code is marked as shortened",
          boundedCode.contains("truncated"))
  t.check("a shortened code is not another code",
          boundedCode != "config." & "x".repeat(MaxCodeLength - 1))

  # --- the document is valid UTF-8 -----------------------------------------
  var node = newJObject()
  node["text"] = newJString("ok\xff")
  var arr = newJArray()
  arr.add newJString("a")
  arr.add newJInt(1)
  node["nested"] = arr
  let sanitized = sanitizeJson(node)
  t.check("the sanitised document is valid UTF-8",
          isValidUtf8($sanitized))
  t.check("the sanitised document keeps the valid text",
          sanitized["text"].getStr.contains("ok"))

  # --- the dropped-item accounting ------------------------------------------
  var report = newReport(rtConfigurationValidation, "configuration_file", "x")
  report.executionState = esSucceeded
  report.hasAssessment = true
  report.verdict = avPass
  report.assessmentSummary = "the configuration document is valid"

  # Exactly at the limit: nothing is dropped.
  for i in 0 ..< MaxIssueCount:
    report.findings.add newFinding("config.violation", fsError, "message " & $i)
  let atLimit = report.toJson
  t.checkEq("a collection of exactly 1024 findings is not truncated",
            atLimit["findings"].len, MaxIssueCount)
  var hasMarker = false
  for f in atLimit["findings"].elems:
    if f.hasKey("code") and f["code"].getStr == "findings.truncated":
      hasMarker = true
  t.check("a collection of exactly 1024 findings carries no marker", not hasMarker)

  # One over the limit: one slot is reserved for the marker, so two
  # findings are dropped, not one.
  report.findings.add newFinding("config.violation", fsError, "one too many")
  let overLimit = report.toJson
  t.checkEq("a collection of 1025 findings is truncated to the limit",
            overLimit["findings"].len, MaxIssueCount)
  var droppedText = ""
  for f in overLimit["findings"].elems:
    if f.hasKey("code") and f["code"].getStr == "findings.truncated":
      droppedText = f["message"].getStr
  t.check("the truncation marker names the dropped count",
          droppedText.contains("2 finding(s) were dropped"))
  t.check("the truncated report does not claim PASS",
          overLimit["assessment"]["verdict"].getStr != "PASS")
  t.check("the emitted report is valid UTF-8", isValidUtf8($overLimit))

  t.finish()
