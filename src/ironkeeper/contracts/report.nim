## Ironkeeper report model.
##
## The report is the public, machine-readable record of what Ironkeeper did
## and what it concluded. Three concerns are kept strictly apart:
##
##   * **Execution state** describes what happened to the operation.
##   * **Assessment verdict** describes what was concluded about the subject.
##   * **Device lifecycle state** describes where a device sits in its
##     lifecycle. It is *not* part of the report contract in milestone M0 and
##     is deliberately absent here, because no device subsystem exists yet.
##
## An operation may complete successfully (`SUCCEEDED`) and still carry a
## `FAIL` assessment: the operation worked, and it found a problem. An
## operation that could not obtain the evidence it needed carries
## `INCONCLUSIVE`, never `PASS`.

import std/[json, strutils, times, random]

from ironkeeper/core/version import Version, ApplicationName
from ironkeeper/core/errors import IrkErrorKind, codeFor
from ironkeeper/contracts/outputbounds import boundMessage, boundLocation,
  boundCode, boundDetail, MaxIssueCount
from ironkeeper/contracts/utf8 import sanitizeJson

type
  ExecutionState* = enum
    ## Lifecycle of an execution. These names are part of the report contract.
    esQueued = "QUEUED"
    esPreflight = "PREFLIGHT"
    esRunning = "RUNNING"
    esWaiting = "WAITING"
    esVerifying = "VERIFYING"
    esSucceeded = "SUCCEEDED"
    esFailed = "FAILED"
    esCancelled = "CANCELLED"
    esInterrupted = "INTERRUPTED"

  AssessmentVerdict* = enum
    ## Conclusion of an assessment.
    avPass = "PASS"
    avWarn = "WARN"
    avFail = "FAIL"
    avInconclusive = "INCONCLUSIVE"

  FindingSeverity* = enum
    fsInfo = "info"
    fsWarning = "warning"
    fsError = "error"

  ReportType* = enum
    ## Kinds of report this build can produce.
    rtConfigurationValidation = "configuration_validation"

  Finding* = object
    ## One structured observation about the subject of a report.
    code*: string
    severity*: FindingSeverity
    message*: string
    location*: string
    evidenceRefs*: seq[string]

  EvidenceRecord* = object
    ## A preserved observation together with its provenance.
    id*: string
    kind*: string
    collectedAt*: string
    source*: string
    tool*: string
    digest*: string
    content*: JsonNode

  Report* = object
    ## A complete report.
    schemaVersion*: int
    reportType*: ReportType
    reportId*: string
    createdAt*: string
    producerName*: string
    producerVersion*: string
    executionState*: ExecutionState
    startedAt*: string
    finishedAt*: string
    executionMessage*: string
    hasAssessment*: bool
    verdict*: AssessmentVerdict
    assessmentSummary*: string
    policyRevision*: string
    findings*: seq[Finding]
    evidence*: seq[EvidenceRecord]
    subjectKind*: string
    subjectIdentifier*: string

proc nowUtc*(): string =
  ## Current UTC time as an RFC 3339 timestamp with second precision.
  ##
  ## Used for report identities and evidence collection times.
  let t = now().utc
  t.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc newReportId*(): string =
  ## A unique identifier for a report instance.
  ##
  ## Combines the wall clock with a random suffix so that two reports created
  ## in the same second do not collide.
  randomize()
  let t = now().utc
  # The suffix is derived with explicit arithmetic rather than a cast
  # between signed and unsigned types, so that the value is well defined
  # on every architecture and the identifier always has the same shape.
  let entropy = rand(int.high) and 0x0FFFFFFF'i64
  let suffix = uint32(entropy) xor uint32(t.nanosecond and 0xFF)
  t.format("yyyyMMdd'T'HHmmss") & "-" & toHex(suffix, 8)

proc newFinding*(code: string, severity: FindingSeverity, message: string,
                 location = "", evidenceRefs: seq[string] = @[]): Finding =
  ## Construct a structured finding.
  Finding(code: code, severity: severity, message: message,
          location: location, evidenceRefs: evidenceRefs)

proc toJson*(f: Finding): JsonNode =
  ## Render a finding as a JSON object.
  ##
  ## Every bounded field is shortened here, at the production boundary,
  ## so that the rendered document always satisfies the report contract.
  var o = newJObject()
  o["code"] = newJString(boundCode(f.code))
  o["severity"] = newJString($f.severity)
  o["message"] = newJString(boundMessage(f.message))
  if f.location.len > 0:
    o["location"] = newJString(boundLocation(f.location))
  if f.evidenceRefs.len > 0:
    var arr = newJArray()
    for r in f.evidenceRefs:
      arr.add newJString(r)
    o["evidence_refs"] = arr
  o

proc toJson*(e: EvidenceRecord): JsonNode =
  var o = newJObject()
  o["id"] = newJString(e.id)
  o["kind"] = newJString(e.kind)
  o["collected_at"] = newJString(e.collectedAt)
  var prov = newJObject()
  prov["source"] = newJString(e.source)
  if e.tool.len > 0:
    prov["tool"] = newJString(e.tool)
  if e.digest.len > 0:
    prov["digest"] = newJString(e.digest)
  o["provenance"] = prov
  if not e.content.isNil:
    o["content"] = e.content
  o

proc toJson*(r: Report): JsonNode =
  ## Render a report as a JSON document that conforms to
  ## `schemas/v1/report.schema.json`.
  var root = newJObject()
  root["schema_version"] = newJInt(r.schemaVersion)
  root["report_type"] = newJString($r.reportType)

  var rid = newJObject()
  rid["id"] = newJString(r.reportId)
  rid["created_at"] = newJString(r.createdAt)
  root["report_id"] = rid

  var prod = newJObject()
  prod["name"] = newJString(r.producerName)
  prod["version"] = newJString(r.producerVersion)
  root["producer"] = prod

  var ex = newJObject()
  ex["state"] = newJString($r.executionState)
  ex["started_at"] = newJString(r.startedAt)
  ex["finished_at"] = newJString(r.finishedAt)
  if r.executionMessage.len > 0:
    ex["message"] = newJString(boundMessage(r.executionMessage))
  root["execution"] = ex

  # The findings collection is bounded. The truncation is decided *before*
  # the assessment is rendered, because a dropped finding may have been
  # an error finding: a report that dropped findings cannot claim that
  # the subject is healthy.
  #
  # When the collection is truncated, one slot is reserved for the
  # marker, so that the rendered document never exceeds the contract's
  # limit. The dropped count is derived from the number of entries that
  # are actually kept, so that the two cannot disagree: a collection of
  # 1025 findings keeps 1023 findings and drops 2, not 1.
  let truncated = r.findings.len > MaxIssueCount
  let kept = if truncated: MaxIssueCount - 1 else: r.findings.len
  let dropped = r.findings.len - kept

  if r.hasAssessment:
    var a = newJObject()
    var verdict = r.verdict
    var summary = r.assessmentSummary
    if truncated and verdict == avPass:
      # A PASS claim that rests on a truncated finding collection is not
      # supported by the evidence the document carries. The verdict is
      # therefore not PASS.
      verdict = avWarn
      summary = "the findings collection was truncated, so the assessment " &
        "cannot conclude that the subject is healthy"
    a["verdict"] = newJString($verdict)
    a["summary"] = newJString(boundMessage(summary))
    if r.policyRevision.len > 0:
      a["policy_revision"] = newJString(r.policyRevision)
    root["assessment"] = a

  var findings = newJArray()
  for i in 0 ..< kept:
    findings.add r.findings[i].toJson
  if truncated:
    var marker = newJObject()
    marker["code"] = newJString("findings.truncated")
    marker["severity"] = newJString($fsWarning)
    marker["message"] = newJString(
      "the findings collection was truncated: " & $dropped &
      " finding(s) were dropped")
    findings.add marker
  root["findings"] = findings

  if r.evidence.len > 0:
    var ev = newJArray()
    for e in r.evidence:
      ev.add e.toJson
    root["evidence"] = ev

  if r.subjectKind.len > 0:
    var s = newJObject()
    s["kind"] = newJString(r.subjectKind)
    if r.subjectIdentifier.len > 0:
      s["identifier"] = newJString(r.subjectIdentifier)
    root["subject"] = s

  sanitizeJson(root)

proc newReport*(reportType: ReportType, subjectKind = "",
                subjectIdentifier = ""): Report =
  ## Create a report with the producer identity filled in.
  let ts = nowUtc()
  Report(
    schemaVersion: 1,
    reportType: reportType,
    reportId: newReportId(),
    createdAt: ts,
    producerName: ApplicationName,
    producerVersion: Version,
    executionState: esRunning,
    startedAt: ts,
    finishedAt: ts,
    hasAssessment: false,
    subjectKind: subjectKind,
    subjectIdentifier: subjectIdentifier)

proc errorDocument*(kind: IrkErrorKind, message: string,
                    detail = ""): JsonNode =
  ## Render an error as a JSON document conforming to
  ## `schemas/v1/error.schema.json`.
  var root = newJObject()
  root["schema_version"] = newJInt(1)
  var e = newJObject()
  e["code"] = newJString(codeFor(kind))
  e["message"] = newJString(boundMessage(message))
  if detail.len > 0:
    e["detail"] = newJString(boundDetail(detail))
  root["error"] = e
  root
