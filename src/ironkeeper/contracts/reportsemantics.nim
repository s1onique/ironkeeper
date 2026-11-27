## Semantic validation of Ironkeeper report documents.
##
## Structural validation (JSON Schema) and semantic validation are
## distinct concerns. The schema establishes the *shape* of a report: the
## members that exist, their types and their lengths. It cannot establish
## that a timestamp denotes a real moment in time, because the schema
## only has a regular expression to work with.
##
## This module establishes the rules the schema cannot express:
##
##   * a timestamp must denote a valid calendar time in a supported UTC
##     representation;
##   * the execution state and the assessment verdict must be consistent:
##     an operation that failed or did not complete cannot carry a `PASS`
##     assessment.
##
## ## What this module does not do
##
## It does not verify that the *evidence* a report cites is authentic. A
## structurally and semantically valid report is a well-formed claim; it
## is not proof. `ironkeeper report validate` therefore reports on the
## document, never on the truth of what it asserts.

import std/[json, strutils]

type
  ReportSemanticIssue* = object
    ## One reason a report failed semantic validation.
    code*: string
      ## Stable machine-readable issue code.
    message*: string
    location*: string
      ## JSON Pointer to the offending position in the document.

  ReportSemanticResult* = object
    ok*: bool
    issues*: seq[ReportSemanticIssue]

proc issue(code, msg, loc: string): ReportSemanticIssue =
  ReportSemanticIssue(code: code, message: msg, location: loc)

const
  TruncatedFindingsCode* = "findings.truncated"
    ## The code of the finding that marks a truncated findings
    ## collection. A report that carries it does not know which findings
    ## it dropped, so it cannot claim that the subject is healthy.

  MaxDaysInMonth* = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    ## The number of days in each month, with February at its leap-year
    ## maximum. The leap-year rule is applied separately.

proc isLeapYear(y: int): bool =
  ## The Gregorian leap-year rule.
  (y mod 4 == 0 and y mod 100 != 0) or y mod 400 == 0

proc daysInMonth(year, month: int): int =
  ## The number of days in `month` of `year`.
  if month == 2 and not isLeapYear(year):
    return 28
  MaxDaysInMonth[month - 1]

proc isValidTimestamp(ts: string): bool =
  ## True when `ts` is a supported RFC 3339 timestamp that denotes a real
  ## calendar time.
  ##
  ## The supported representations are:
  ##
  ##   * `YYYY-MM-DDTHH:MM:SSZ` — UTC;
  ##   * `YYYY-MM-DDTHH:MM:SS[.fraction]Z` — UTC with a fraction;
  ##   * `YYYY-MM-DDTHH:MM:SS[.fraction](+|-)HH:MM` — a numeric offset.
  ##
  ## The calendar fields are checked: the month must be 1..12, the day
  ## must exist in that month (so 29 February exists only in a leap
  ## year), the hour must be 0..23, the minute and the second 0..59, and
  ## the offset hour 0..23 with the offset minute 0..59.
  if ts.len < 20:
    return false
  # The date part.
  if ts[4] != '-' or ts[7] != '-':
    return false
  if ts[10] != 'T':
    return false
  for pos in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]:
    if ts[pos] notin {'0' .. '9'}:
      return false
  var year = parseInt(ts[0 .. 3])
  var month = parseInt(ts[5 .. 6])
  var day = parseInt(ts[8 .. 9])
  var hour = parseInt(ts[11 .. 12])
  var minute = parseInt(ts[14 .. 15])
  var second = parseInt(ts[17 .. 18])
  if month < 1 or month > 12:
    return false
  if day < 1 or day > daysInMonth(year, month):
    return false
  if hour > 23 or minute > 59 or second > 59:
    return false

  # The optional fraction.
  var idx = 19
  if idx < ts.len and ts[idx] == '.':
    inc idx
    let fracStart = idx
    while idx < ts.len and ts[idx] in {'0' .. '9'}:
      inc idx
    if idx == fracStart:
      return false

  # The offset.
  if idx >= ts.len:
    return false
  if ts[idx] == 'Z':
    return idx == ts.len - 1
  if ts[idx] == '+' or ts[idx] == '-':
    inc idx
    # The offset is `HH:MM`.
    if idx + 5 != ts.len:
      return false
    if ts[idx + 2] != ':':
      return false
    for pos in [idx, idx + 1, idx + 3, idx + 4]:
      if ts[pos] notin {'0' .. '9'}:
        return false
    let offsetHour = parseInt(ts[idx .. idx + 1])
    let offsetMinute = parseInt(ts[idx + 3 .. idx + 4])
    if offsetHour > 23 or offsetMinute > 59:
      return false
    return true
  false

proc checkTimestamp(node: JsonNode, path: string,
                    issues: var seq[ReportSemanticIssue]) =
  ## Check that `node` is a string holding a valid timestamp.
  if node.isNil or node.kind != JString:
    return
  if not isValidTimestamp(node.getStr):
    issues.add issue("report.invalid_timestamp",
      "the timestamp does not denote a valid calendar time: " & node.getStr,
      path)

proc validateReportSemantics*(doc: JsonNode): ReportSemanticResult =
  ## Validate the semantics of a report document.
  ##
  ## The document is assumed to have passed structural validation. The
  ## checks are applied defensively anyway: a member that is not present,
  ## or that has an unexpected type, is skipped rather than reported, so
  ## that a *structural* defect is reported by the schema layer and not
  ## duplicated here.
  var issues: seq[ReportSemanticIssue]

  if doc.kind != JObject:
    return ReportSemanticResult(ok: true, issues: issues)

  # ---- the timestamps ----------------------------------------------------
  if doc.hasKey("report_id") and doc["report_id"].kind == JObject:
    let rid = doc["report_id"]
    if rid.hasKey("created_at"):
      checkTimestamp(rid["created_at"], "/report_id/created_at", issues)
  if doc.hasKey("execution") and doc["execution"].kind == JObject:
    let ex = doc["execution"]
    if ex.hasKey("started_at"):
      checkTimestamp(ex["started_at"], "/execution/started_at", issues)
    if ex.hasKey("finished_at"):
      checkTimestamp(ex["finished_at"], "/execution/finished_at", issues)
  if doc.hasKey("evidence") and doc["evidence"].kind == JArray:
    for i, ev in doc["evidence"].elems:
      if ev.kind == JObject and ev.hasKey("collected_at"):
        checkTimestamp(ev["collected_at"], "/evidence/" & $i & "/collected_at",
          issues)

  # ---- the execution and the assessment must agree -----------------------
  # An operation that failed, or that did not complete, cannot have
  # concluded that the subject is healthy. Such a report must carry
  # `INCONCLUSIVE`, never `PASS`.
  let executionState = if doc.hasKey("execution") and
                         doc["execution"].kind == JObject and
                         doc["execution"].hasKey("state") and
                         doc["execution"]["state"].kind == JString:
                        doc["execution"]["state"].getStr
                      else: ""
  let verdict = if doc.hasKey("assessment") and
                  doc["assessment"].kind == JObject and
                  doc["assessment"].hasKey("verdict") and
                  doc["assessment"]["verdict"].kind == JString:
                   doc["assessment"]["verdict"].getStr
                 else: ""
  if verdict == "PASS":
    case executionState
    of "FAILED", "CANCELLED", "INTERRUPTED":
      issues.add issue("report.pass_on_failed_execution",
        "a " & executionState & " execution must not carry a PASS assessment",
        "/assessment/verdict")
    of "QUEUED", "PREFLIGHT", "RUNNING", "WAITING", "VERIFYING":
      issues.add issue("report.pass_on_incomplete_execution",
        "an incomplete execution (" & executionState &
        ") must not carry a PASS assessment",
        "/assessment/verdict")
    else:
      discard

  # ---- a truncated finding collection cannot claim PASS -------------------
  # A report that dropped findings does not know what it dropped. A PASS
  # claim that rests on a truncated collection is therefore unsupported:
  # the dropped findings may have been errors. The producer already
  # refuses to emit such a claim; the semantic layer rejects one that
  # arrives from elsewhere.
  if verdict == "PASS" and doc.hasKey("findings") and
     doc["findings"].kind == JArray:
    for finding in doc["findings"].elems:
      if finding.kind == JObject and finding.hasKey("code") and
         finding["code"].kind == JString and
         finding["code"].getStr == TruncatedFindingsCode:
        issues.add issue("report.pass_with_truncated_findings",
          "a report whose findings were truncated must not carry a PASS " &
          "assessment",
          "/assessment/verdict")
        break

  ReportSemanticResult(ok: issues.len == 0, issues: issues)
