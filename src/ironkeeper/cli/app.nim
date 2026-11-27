## Ironkeeper command line application.
##
## This module owns the command surface, the output conventions and the
## mapping from failures to exit codes. It performs no I/O against storage
## devices, opens no network connections and has no background modes.
##
## Output conventions:
##
##   * Human-readable output goes to stdout.
##   * Machine-readable output (`--json`) goes to stdout, and nothing else
##     does. Diagnostics for a failed machine-readable run go to stderr.
##   * A failure always produces a nonzero exit status and, in JSON mode, a
##     document conforming to `schemas/v1/error.schema.json`.

import std/[json, strutils, os, tables]

from ironkeeper/core/errors import IrkErrorImpl, IrkErrorKind, newIrkError, exitCodeFor, codeFor, ExitOk
from ironkeeper/core/version import Version, ApplicationName
from ironkeeper/contracts/report import Report, ReportType, newReport, toJson, errorDocument, newFinding,
  ExecutionState, AssessmentVerdict, FindingSeverity, esFailed, esSucceeded,
  avPass, avWarn, avFail, avInconclusive, fsError, fsInfo, fsWarning, nowUtc
from ironkeeper/contracts/schemaregistry import EmbeddedSchemaNames, schemaText
from ironkeeper/contracts/validator import newValidator, validateAgainst, SchemaIssue
from ironkeeper/contracts/reportsemantics import validateReportSemantics
from ironkeeper/contracts/outputbounds import boundMessage, boundLocation,
  MaxIssueCount
from ironkeeper/contracts/utf8 import sanitizeJson
from ironkeeper/json/strictjson import parseStrict, StrictJsonResult, MaxDocumentBytes
from ironkeeper/json/boundedread import openDocument, closeDocument, readDocument,
  ofNotRegularFile, rfTooLarge
from ironkeeper/config/semantics import validateConfigSemantics
import ironkeeper/cli/args as argmod
import ironkeeper/cli/storage as storagemod
import ironkeeper/storage/identity as identitymod

const
  SupportedSchemaVersion* = 1
    ## The contract schema version this build implements.
    ##
    ## A document that declares a different `schema_version` is reported
    ## with the documented `unsupported_schema_version` classification,
    ## not as an ordinary schema violation.

  UsageText = """
ironkeeper - evidence-driven storage fleet housekeeping daemon

Usage:
  ironkeeper --help
  ironkeeper --version
  ironkeeper version [--json]
  ironkeeper config validate --file <path> [--json]
  ironkeeper schema list [--json]
  ironkeeper schema config [--json]
  ironkeeper schema report [--json]
  ironkeeper schema inventory [--json]
  ironkeeper schema device [--json]
  ironkeeper schema observation [--json]
  ironkeeper schema evidence [--json]
  ironkeeper report validate --file <path> [--json]
  ironkeeper inventory list [--transport <name>] [--json]
  ironkeeper device inspect (--wwn <wwn> | --serial <serial> | --path <path>)
                     [--smart] [--capacity] [--allow-wake]
                     [--evidence-dir <parent>] [--json]

Exit codes:
  0   success
  2   invalid command line invocation
  3   input unavailable
  4   invalid JSON syntax
  5   schema validation failure
  6   semantic validation failure
  7   unsupported schema version
  8   unsupported operation
  70  internal application failure
"""

  ConfigUsage = """
Usage: ironkeeper config validate --file <path> [--json]

Validates a configuration document against schemas/v1/config.schema.json and
then against the semantic rules of milestone M0. The mandatory safety values
cannot be configured away: a document that enables destructive operations is
rejected.
"""

  SchemaUsage = """
Usage:
  ironkeeper schema list [--json]
  ironkeeper schema config [--json]
  ironkeeper schema report [--json]

Prints the schemas that this build implements. `schema list` names them;
`schema config` and `schema report` print the schema documents themselves.
"""

  ReportUsage = """
Usage: ironkeeper report validate --file <path> [--json]

Validates a report document against schemas/v1/report.schema.json.
"""

  InventoryUsage = """
Usage: ironkeeper inventory list [--transport <name>] [--json]

Lists the block devices that the kernel reports. The command is passive:
it opens no physical device and runs no observation tool.
"""

  InspectUsage = """
Usage: ironkeeper device inspect (--wwn <wwn> | --serial <serial> | --path <path>)
                     [--smart] [--capacity] [--allow-wake]
                     [--evidence-dir <parent>] [--json]

Inspects one explicitly selected device. Without `--smart` and
`--capacity` the command is passive. With them it performs read-only
interrogations, and `--allow-wake` is required, because a read-only SMART
acquisition may wake a sleeping device.
"""

type
  CliContext = object
    stdoutBuf: string
    stderrBuf: string
    json: bool
    producedResult: bool
      ## True once a machine-readable *result* document has been written.
      ## When set, a subsequent failure does not append an error document,
      ## so that stdout carries exactly one JSON document.

proc writeOut(ctx: var CliContext, text: string) =
  ## Append human-readable or machine-readable output to the stdout buffer.
  ctx.stdoutBuf.add text
  if not ctx.stdoutBuf.endsWith("\n"):
    ctx.stdoutBuf.add "\n"

proc emitJson(ctx: var CliContext, node: JsonNode) =
  ## Write a machine-readable document to stdout.
  ##
  ## The document is sanitised before it is written: every string in it is
  ## repaired to valid UTF-8, so that the emitted document is always
  ## readable by a conforming JSON consumer, whatever the input carried.
  ctx.stdoutBuf.add sanitizeJson(node).pretty(2)
  ctx.stdoutBuf.add "\n"
  ctx.producedResult = true

proc failInvocation(msg: string) {.noreturn.} =
  raise newIrkError(EInvalidInvocation, msg)

proc cmdVersion(ctx: var CliContext, args: argmod.ParsedArgs) =
  ## `ironkeeper version`
  ctx.json = args.json
  if args.json:
    var v = newJObject()
    v["name"] = newJString(ApplicationName)
    v["version"] = newJString(Version)
    var sv = newJArray()
    sv.add newJInt(1)
    v["schema_versions"] = sv
    v["contract"] = newJString("https://json-schema.org/draft/2020-12/schema")
    ctx.emitJson(v)
  else:
    ctx.writeOut(Version)

proc cmdSchema(ctx: var CliContext, args: argmod.ParsedArgs) =
  ## `ironkeeper schema list|config|report`
  if args.command.len < 1:
    failInvocation("schema requires a subcommand: list, config or report")
  let which = args.command[0]
  ctx.json = args.json
  case which
  of "list":
    if ctx.json:
      var arr = newJArray()
      for n in EmbeddedSchemaNames:
        var e = newJObject()
        e["name"] = newJString(n)
        e["version"] = newJInt(1)
        e["dialect"] = newJString("https://json-schema.org/draft/2020-12/schema")
        arr.add e
      var root = newJObject()
      root["schema_version"] = newJInt(1)
      root["schemas"] = arr
      ctx.emitJson(root)
    else:
      for n in EmbeddedSchemaNames:
        ctx.writeOut(n)
  of "config", "report", "inventory", "device", "observation", "evidence":
    let text = schemaText(which)
    if ctx.json:
      # The schema itself is JSON; emit it as a JSON document.
      ctx.emitJson(parseJson(text))
    else:
      ctx.writeOut(text.strip())
  else:
    failInvocation("unknown schema subcommand: " & which)

proc readDocument(path: string): tuple[node: JsonNode, text: string] =
  ## Read and strictly ingest a JSON document from `path`.
  ##
  ## The input is read through a **bounded**, **descriptor-based** reader:
  ##
  ##   * the byte limit is enforced *before* an unbounded amount of input
  ##     is consumed, so a large or endless source cannot exhaust memory;
  ##   * the file is opened with `O_RDONLY | O_NONBLOCK | O_CLOEXEC`, so
  ##     the open itself cannot block on a FIFO and the descriptor cannot
  ##     leak into a child process;
  ##   * the regularity of the input is decided by `fstat` on the
  ##     **opened descriptor**, not by a `stat` on the path. A pathname
  ##     pre-check would not be sufficient: the file can be replaced
  ##     between the check and the open.
  ##
  ## The descriptor is closed on every exit path.
  if path.len == 0:
    raise newIrkError(EInputUnavailable, "no file path was given")
  if not fileExists(path):
    raise newIrkError(EInputUnavailable, "file not found: " & path)
  if dirExists(path):
    raise newIrkError(EInputUnavailable, "not a regular file: " & path)

  let opened = openDocument(path)
  if not opened.ok:
    if opened.failure == ofNotRegularFile:
      raise newIrkError(EInputUnavailable,
        "not a regular file: " & path)
    raise newIrkError(EInputUnavailable,
      "cannot open " & path & ": " & opened.message)

  # The descriptor is owned by this scope from here on, and it is closed
  # on every exit path.
  var read = readDocument(opened.descriptor, MaxDocumentBytes)
  closeDocument(opened.descriptor)

  if not read.ok:
    if read.failure == rfTooLarge:
      raise newIrkError(EInputUnavailable,
        "the document exceeds the maximum size of " & $MaxDocumentBytes &
        " bytes: " & path)
    # A read failure is classified independently of end-of-file.
    raise newIrkError(EInputUnavailable,
      "cannot read " & path & ": " & read.message)

  let text = read.text
  let res = parseStrict(text)
  if not res.ok:
    raise newIrkError(EInvalidJsonSyntax, res.error.message,
                      "at byte offset " & $res.error.offset)
  (node: res.node, text: text)

proc declaredSchemaVersion(doc: JsonNode): int =
  ## The `schema_version` a document declares, or 0 when it declares none.
  if doc.kind == JObject and doc.hasKey("schema_version"):
    let v = doc["schema_version"]
    if v.kind == JInt:
      return v.getInt
  0

proc cmdConfigValidate(ctx: var CliContext, args: argmod.ParsedArgs) =
  ## `ironkeeper config validate --file <path>`
  ctx.json = args.json
  let path = args.requireOption("file")
  let doc = readDocument(path)

  let validator = newValidator()
  let configSchema = parseJson(schemaText("config"))
  let outcome = validateAgainst(validator, doc.node, configSchema)

  var report = newReport(rtConfigurationValidation, "configuration_file", path)

  if not outcome.ok:
    if outcome.error != nil:
      report.executionState = esFailed
      report.executionMessage = outcome.error.msg
      report.hasAssessment = true
      report.verdict = avInconclusive
      report.assessmentSummary = "validation could not be completed"
      report.findings.add newFinding("config.validation_error", fsError,
        outcome.error.msg)
    else:
      report.executionState = esSucceeded
      report.hasAssessment = true
      report.verdict = avFail
      report.assessmentSummary =
        "the configuration document does not satisfy the configuration contract"
      for issue in outcome.issues:
        report.findings.add newFinding("config.schema_violation", fsError,
          issue.message, issue.location)
  else:
    let sem = validateConfigSemantics(doc.node)
    if sem.ok:
      report.executionState = esSucceeded
      report.hasAssessment = true
      report.verdict = avPass
      report.assessmentSummary = "the configuration document is valid"
    else:
      report.executionState = esSucceeded
      report.hasAssessment = true
      report.verdict = avFail
      report.assessmentSummary =
        "the configuration document violates a mandatory rule"
      for issue in sem.issues:
        report.findings.add newFinding(issue.code, fsError, issue.message,
          issue.location)

  report.finishedAt = nowUtc()

  if ctx.json:
    ctx.emitJson(report.toJson)
  else:
    ctx.writeOut("report " & report.reportId)
    ctx.writeOut("execution: " & $report.executionState)
    if report.hasAssessment:
      ctx.writeOut("assessment: " & $report.verdict & " - " & report.assessmentSummary)
    for f in report.findings:
      var line = $f.severity & ": " & f.code & ": " & f.message
      if f.location.len > 0:
        line.add " (at " & f.location & ")"
      ctx.writeOut(line)

  # The exit status follows the assessment, not merely the execution state.
  #
  # When a report has already been produced, that report *is* the
  # machine-readable result: no second document is emitted, so that stdout
  # always carries exactly one JSON document in machine-readable mode.
  if report.hasAssessment and report.verdict != avPass:
    if outcome.error != nil:
      raise newIrkError(EInternalFailure, report.assessmentSummary)
    # An unsupported schema version has its own documented classification,
    # distinct from an ordinary schema violation.
    let declared = declaredSchemaVersion(doc.node)
    if declared > 0 and declared != SupportedSchemaVersion:
      raise newIrkError(EUnsupportedSchemaVersion,
        "unsupported schema_version: " & $declared &
        "; this build implements version " & $SupportedSchemaVersion)
    if outcome.issues.len > 0:
      raise newIrkError(ESchemaValidation, outcome.issues[0].message,
        outcome.issues[0].location)
    raise newIrkError(ESemanticValidation, report.assessmentSummary)

proc cmdReportValidate(ctx: var CliContext, args: argmod.ParsedArgs) =
  ## `ironkeeper report validate --file <path>`
  ##
  ## The command reports on the *document*: whether it satisfies the
  ## structural contract and whether it satisfies the semantic contract.
  ## It says nothing about the authenticity of the evidence the document
  ## cites. That is a separate question, and the command does not answer
  ## it.
  ctx.json = args.json
  let path = args.requireOption("file")
  let doc = readDocument(path)
  let validator = newValidator()
  let reportSchema = parseJson(schemaText("report"))
  let outcome = validateAgainst(validator, doc.node, reportSchema)

  # The semantic layer runs only when the structural layer passed: a
  # document that does not satisfy the shape is not semantically
  # interpretable.
  var semantic = validateReportSemantics(doc.node)
  var semanticApplicable = outcome.ok
  if not outcome.ok and outcome.error != nil:
    # An internal failure is not an ordinary invalidity. The semantic
    # layer cannot be trusted to have run against a usable schema.
    semanticApplicable = false

  var issues = outcome.issues
  if semanticApplicable:
    for si in semantic.issues:
      issues.add SchemaIssue(location: si.location, keywordLocation: "",
                             message: si.message)

  let valid = outcome.ok and semantic.ok

  if ctx.json:
    var root = newJObject()
    root["schema_version"] = newJInt(1)
    root["valid"] = newJBool(valid)
    root["structural_valid"] = newJBool(outcome.ok)
    if semanticApplicable:
      root["semantic_valid"] = newJBool(semantic.ok)
    # The issue collection is bounded at the production boundary. When
    # entries are dropped, a marker issue names how many, so that the
    # document cannot be read as "there were no other issues" and the
    # verdict cannot become a success.
    var issueArray = newJArray()
    # When the collection is truncated, one slot is reserved for the
    # marker, so that the rendered document never exceeds the contract's
    # limit. The dropped count is derived from the number of entries that
    # are actually kept, so that the two cannot disagree: 1025 issues
    # keep 1023 issues and drop 2, not 1.
    let truncated = issues.len > MaxIssueCount
    let kept = if truncated: MaxIssueCount - 1 else: issues.len
    let dropped = issues.len - kept
    for i in 0 ..< kept:
      var entry = newJObject()
      entry["location"] = newJString(boundLocation(issues[i].location))
      entry["keyword_location"] =
        newJString(boundLocation(issues[i].keywordLocation))
      entry["message"] = newJString(boundMessage(issues[i].message))
      issueArray.add entry
    if truncated:
      var marker = newJObject()
      marker["code"] = newJString("issues.truncated")
      marker["message"] = newJString(
        "the issue collection was truncated: " & $dropped &
        " issue(s) were dropped")
      issueArray.add marker
    root["issues"] = issueArray
    ctx.emitJson(root)
  else:
    if valid:
      ctx.writeOut("valid")
    else:
      ctx.writeOut("invalid")
      for issue in issues:
        var line = issue.location & ": " & issue.message
        if issue.keywordLocation.len > 0:
          line.add " (schema " & issue.keywordLocation & ")"
        ctx.writeOut(line)

  if not valid:
    if outcome.error != nil:
      raise newIrkError(EInternalFailure, outcome.error.msg)
    # An unsupported schema version has its own documented classification,
    # distinct from an ordinary schema violation.
    let declared = declaredSchemaVersion(doc.node)
    if declared > 0 and declared != SupportedSchemaVersion:
      raise newIrkError(EUnsupportedSchemaVersion,
        "unsupported schema_version: " & $declared &
        "; this build implements version " & $SupportedSchemaVersion)
    if not outcome.ok:
      raise newIrkError(ESchemaValidation,
        "the report document does not satisfy the report contract")
    raise newIrkError(ESemanticValidation,
      "the report document does not satisfy the report semantics")

proc cmdInventoryList(ctx: var CliContext, args: argmod.ParsedArgs) =
  ## `ironkeeper inventory list`
  ctx.json = args.json
  let transport = args.optionalOption("transport")
  if transport.len > 0 and transport notin ["sas", "sata", "nvme", "scsi", "unknown"]:
    failInvocation("unknown transport: " & transport)
  let result = storagemod.cmdInventoryList(
    storagemod.InventoryOptions(transport: transport,
                                roots: storagemod.requireRoots()))
  if ctx.json:
    ctx.emitJson(result.document)
  else:
    for line in result.humanLines:
      ctx.writeOut(line)

proc cmdDeviceInspect(ctx: var CliContext, args: argmod.ParsedArgs) =
  ## `ironkeeper device inspect`
  ctx.json = args.json
  let hasWwn = args.options.hasKey("wwn")
  let hasSerial = args.options.hasKey("serial")
  let hasPath = args.options.hasKey("path")
  let selected = (if hasWwn: 1 else: 0) + (if hasSerial: 1 else: 0) +
                 (if hasPath: 1 else: 0)
  if selected == 0:
    failInvocation("device inspect requires exactly one of --wwn, --serial or --path")
  if selected > 1:
    failInvocation("device inspect accepts exactly one of --wwn, --serial or --path")
  let wantsSmart = args.hasFlag("smart")
  let wantsCapacity = args.hasFlag("capacity")
  let allowWake = args.hasFlag("allow-wake")
  if (wantsSmart or wantsCapacity) and not allowWake:
    failInvocation("an active interrogation requires --allow-wake: a read-only " &
      "SMART acquisition may wake a sleeping device")
  var selector: identitymod.Selector
  if hasWwn:
    selector = identitymod.Selector(kind: identitymod.skWwn,
                                   value: args.requireOption("wwn"))
  elif hasSerial:
    selector = identitymod.Selector(kind: identitymod.skSerial,
                                   value: args.requireOption("serial"))
  else:
    selector = identitymod.Selector(kind: identitymod.skPath,
                                   value: args.requireOption("path"))
  var options = storagemod.InspectOptions(selector: selector, smart: wantsSmart,
    capacity: wantsCapacity, allowWake: allowWake,
    evidenceDir: args.optionalOption("evidence-dir"),
    roots: storagemod.requireRoots(), limits: storagemod.defaultLimits())
  let result =
    try:
      storagemod.cmdDeviceInspect(options)
    except ValueError as e:
      raise newIrkError(EInputUnavailable, e.msg)
  if ctx.json:
    ctx.emitJson(result.document)
  else:
    for line in result.humanLines:
      ctx.writeOut(line)

proc dispatch(ctx: var CliContext, argv: seq[string]) =
  ## Route a command line to its implementation.
  ##
  ## The command path is determined first, without interpreting options, so
  ## that each subcommand can declare which options it accepts. Option
  ## parsing happens exactly once, in the subcommand.
  #
  # The `--json` flag is honoured globally, including for failures that
  # happen before a command is dispatched.
  for a in argv:
    if a == "--json":
      ctx.json = true
      break
  let command = argmod.commandPath(argv)
  if command.len == 0:
    # No command: only --help and --version are meaningful.
    let probe = argmod.parseArgs(argv, @[], @[])
    if probe.help:
      ctx.writeOut(UsageText.strip())
      return
    if probe.hasFlag("version"):
      cmdVersion(ctx, probe)
      return
    failInvocation("no command given; run 'ironkeeper --help'")

  let cmd = command[0]
  case cmd
  of "version":
    if command.len > 1:
      failInvocation("version takes no subcommand")
    let sub = argmod.parseArgs(argv, @[], @[])
    cmdVersion(ctx, sub)
  of "config":
    if command.len < 2:
      failInvocation("config requires a subcommand: validate")
    if command[1] != "validate":
      failInvocation("unknown config subcommand: " & command[1])
    let sub = argmod.parseArgs(argv[2 .. ^1], @["file"], @[])
    if sub.help:
      ctx.writeOut(ConfigUsage.strip())
      return
    cmdConfigValidate(ctx, sub)
  of "schema":
    let sub = argmod.parseArgs(argv[1 .. ^1], @[], @[])
    if sub.help:
      ctx.writeOut(SchemaUsage.strip())
      return
    cmdSchema(ctx, sub)
  of "report":
    if command.len < 2:
      failInvocation("report requires a subcommand: validate")
    if command[1] != "validate":
      failInvocation("unknown report subcommand: " & command[1])
    let sub = argmod.parseArgs(argv[2 .. ^1], @["file"], @[])
    if sub.help:
      ctx.writeOut(ReportUsage.strip())
      return
    cmdReportValidate(ctx, sub)
  of "inventory":
    if command.len < 2:
      failInvocation("inventory requires a subcommand: list")
    if command[1] != "list":
      failInvocation("unknown inventory subcommand: " & command[1])
    let sub = argmod.parseArgs(argv[2 .. ^1], @["transport"], @[])
    if sub.help:
      ctx.writeOut(InventoryUsage.strip())
      return
    cmdInventoryList(ctx, sub)
  of "device":
    if command.len < 2:
      failInvocation("device requires a subcommand: inspect")
    if command[1] != "inspect":
      failInvocation("unknown device subcommand: " & command[1])
    let sub = argmod.parseArgs(argv[2 .. ^1],
      @["wwn", "serial", "path", "evidence-dir"],
      @["smart", "capacity", "allow-wake"])
    if sub.help:
      ctx.writeOut(InspectUsage.strip())
      return
    cmdDeviceInspect(ctx, sub)
  of "daemon":
    # The daemon is not implemented. It is named explicitly so that the
    # failure is honest rather than "unknown command".
    raise newIrkError(EUnsupportedOperation,
      "the daemon is not implemented in this build; no background mode exists")
  of "help":
    ctx.writeOut(UsageText.strip())
  else:
    failInvocation("unknown command: " & cmd &
      "; run 'ironkeeper --help' for the list of commands")

proc run*(argv: seq[string]): int =
  ## Run the application and return the process exit code.
  ##
  ## `argv` holds the arguments *without* the program name, exactly as
  ## `commandLineParams()` returns them.
  var ctx = CliContext(stdoutBuf: "", stderrBuf: "", json: false, producedResult: false)
  var code = ExitOk
  try:
    dispatch(ctx, argv)
  except IrkErrorImpl as e:
    # A classified failure: render it and return its exit code.
    #
    # If a machine-readable result document was already produced, it *is*
    # the answer and stdout must carry exactly one JSON document. The
    # failure is then summarised on stderr only.
    if ctx.json and not ctx.producedResult:
      ctx.stdoutBuf.add sanitizeJson(
        errorDocument(e.data.kind, e.data.message, e.data.detail)).pretty(2)
      ctx.stdoutBuf.add "\n"
      ctx.producedResult = true
    else:
      ctx.stderrBuf.add "error: " & e.data.message
      if e.data.detail.len > 0:
        ctx.stderrBuf.add " (" & e.data.detail & ")"
      ctx.stderrBuf.add "\n"
      ctx.stderrBuf.add "error code: " & codeFor(e.data.kind) & "\n"
    code = e.data.exitCode
  except CatchableError as e:
    # An unexpected but catchable condition. Report it as an internal
    # failure without a stack trace.
    ctx.stderrBuf.add "internal error: " & e.msg & "\n"
    code = exitCodeFor(EInternalFailure)

  # stdout carries the result; stderr carries diagnostics. They are never
  # mixed, so that a caller can pipe stdout into a JSON parser.
  if ctx.stdoutBuf.len > 0:
    stdout.write(ctx.stdoutBuf)
  if ctx.stderrBuf.len > 0:
    stderr.write(ctx.stderrBuf)
  flushFile(stdout)
  flushFile(stderr)
  code
