## Integration tests: the compiled binary as a subprocess.
##
## These tests exercise the shipped artefact, not the source. They check
## the exit status, the separation of stdout and stderr, the shape of the
## machine-readable output, and that the binary does not need privileged
## access, a storage device or the network.
##
## The binary under test is located through the `IRONKEEPER_BIN`
## environment variable, or defaults to `build/ironkeeper` relative to the
## repository root.

import std/[json, os, osproc, strutils, streams]

import testkit

type
  RunResult = object
    exitCode: int
    stdoutText: string
    stderrText: string

proc binaryPath(): string =
  let fromEnv = getEnv("IRONKEEPER_BIN")
  if fromEnv.len > 0:
    return fromEnv
  let root = currentSourcePath().parentDir().parentDir().parentDir()
  return root / "build" / "ironkeeper"

proc runBinary(args: seq[string], workingDir = ""): RunResult =
  ## Execute the binary and capture its streams.
  let exe = binaryPath()
  let full = if workingDir.len > 0: exe & " " & args.join(" ") else: exe
  let process = startProcess(full, args = args, options = {})
  let outStream = process.outputStream
  let errStream = process.errorStream
  var outText = ""
  var errText = ""
  if outStream != nil:
    outText = outStream.readAll()
  if errStream != nil:
    errText = errStream.readAll()
  let code = process.waitForExit()
  process.close()
  RunResult(exitCode: code, stdoutText: outText, stderrText: errText)

proc runSuite*(): int =
  var t = newTestSuite("integration")

  let exe = binaryPath()
  t.check("the binary under test exists (" & exe & ")", fileExists(exe))
  if not fileExists(exe):
    return t.finish()

  # --- --help and --version ------------------------------------------------
  var r = runBinary(@["--help"])
  t.checkEq("--help exits successfully", r.exitCode, 0)
  t.checkContains("--help describes the command surface", r.stdoutText, "Usage:")
  t.checkContains("--help documents the exit codes", r.stdoutText, "Exit codes:")
  t.checkEq("--help writes nothing to stderr", r.stderrText, "")

  r = runBinary(@["--version"])
  t.checkEq("--version exits successfully", r.exitCode, 0)
  t.check("--version prints a version", r.stdoutText.strip().len > 0)
  t.checkEq("--version writes nothing to stderr", r.stderrText, "")

  r = runBinary(@["version"])
  t.checkEq("version exits successfully", r.exitCode, 0)
  t.check("--version and version agree", r.stdoutText == runBinary(@["--version"]).stdoutText)

  # --- Machine-readable version -------------------------------------------
  r = runBinary(@["version", "--json"])
  t.checkEq("version --json exits successfully", r.exitCode, 0)
  var versionDoc: JsonNode
  var parsedVersion = false
  try:
    versionDoc = parseJson(r.stdoutText)
    parsedVersion = true
  except JsonParsingError:
    parsedVersion = false
  t.check("version --json emits valid JSON", parsedVersion)
  if parsedVersion:
    t.checkEq("version --json names the application", versionDoc["name"].getStr, "ironkeeper")
    t.check("version --json carries a version", versionDoc["version"].getStr.len > 0)
    t.check("version --json lists the schema versions",
      versionDoc["schema_versions"].kind == JArray)

  # --- schema commands ------------------------------------------------------
  r = runBinary(@["schema", "list"])
  t.checkEq("schema list exits successfully", r.exitCode, 0)
  t.checkContains("schema list names the config schema", r.stdoutText, "config")
  t.checkContains("schema list names the report schema", r.stdoutText, "report")

  r = runBinary(@["schema", "list", "--json"])
  t.checkEq("schema list --json exits successfully", r.exitCode, 0)
  var schemaListDoc: JsonNode
  var parsedList = false
  try:
    schemaListDoc = parseJson(r.stdoutText)
    parsedList = true
  except JsonParsingError:
    parsedList = false
  t.check("schema list --json emits valid JSON", parsedList)

  r = runBinary(@["schema", "config"])
  t.checkEq("schema config exits successfully", r.exitCode, 0)
  t.checkContains("schema config prints a JSON Schema", r.stdoutText, "$schema")
  t.checkContains("schema config names the 2020-12 dialect", r.stdoutText,
    "json-schema.org/draft/2020-12/schema")

  r = runBinary(@["schema", "report"])
  t.checkEq("schema report exits successfully", r.exitCode, 0)
  t.checkContains("schema report prints a JSON Schema", r.stdoutText, "$schema")

  # --- config validate ------------------------------------------------------
  r = runBinary(@["config", "validate", "--file", "examples/ironkeeper.json"])
  t.checkEq("config validate accepts the example configuration", r.exitCode, 0)
  t.checkContains("config validate reports the assessment", r.stdoutText, "PASS")

  r = runBinary(@["config", "validate", "--file", "examples/ironkeeper.json",
                  "--json"])
  t.checkEq("config validate --json succeeds on the example", r.exitCode, 0)
  var reportDoc: JsonNode
  var parsedReport = false
  try:
    reportDoc = parseJson(r.stdoutText)
    parsedReport = true
  except JsonParsingError:
    parsedReport = false
  t.check("config validate --json emits valid JSON", parsedReport)
  if parsedReport:
    t.checkEq("the report declares its schema version",
      reportDoc["schema_version"].getInt, 1)
    t.checkEq("the report names its type", reportDoc["report_type"].getStr,
      "configuration_validation")
    t.checkEq("the report records a successful execution",
      reportDoc["execution"]["state"].getStr, "SUCCEEDED")
    t.checkEq("the report carries a PASS verdict",
      reportDoc["assessment"]["verdict"].getStr, "PASS")
    t.check("the report names its producer", reportDoc["producer"]["name"].getStr == "ironkeeper")

  # A configuration that enables destructive operations must be rejected
  # with a nonzero status and a machine-readable report.
  let tmp = getTempDir() / ("ironkeeper-integration-" & $getCurrentProcessId())
  createDir(tmp)
  defer: removeDir(tmp)
  let badPath = tmp / "destructive.json"
  writeFile(badPath, """
{
  "schema_version": 1,
  "daemon": {
    "state_directory": "/var/lib/ironkeeper",
    "socket_path": "/run/ironkeeper/control.sock"
  },
  "safety": {
    "require_explicit_enrollment": true,
    "allow_destructive_operations": true,
    "allow_tests_on_in_use_devices": false
  }
}
""")
  r = runBinary(@["config", "validate", "--file", badPath, "--json"])
  t.check("config validate rejects destructive operations", r.exitCode != 0)
  var badReport: JsonNode
  var parsedBad = false
  try:
    badReport = parseJson(r.stdoutText)
    parsedBad = true
  except JsonParsingError:
    parsedBad = false
  t.check("a rejected configuration still produces a report", parsedBad)
  if parsedBad:
    t.check("the report verdict is not PASS",
      badReport["assessment"]["verdict"].getStr != "PASS")
    t.check("the report records findings",
      badReport["findings"].kind == JArray and
      badReport["findings"].len > 0)

  # --- Failure taxonomy -----------------------------------------------------
  # A missing file is an input failure, not a crash.
  r = runBinary(@["config", "validate", "--file", "/nonexistent/ironkeeper.json"])
  t.checkEq("a missing file exits with the input-unavailable status",
    r.exitCode, 3)
  t.checkEq("a missing file writes nothing to stdout", r.stdoutText, "")
  t.checkContains("a missing file explains itself on stderr", r.stderrText, "not found")
  t.checkNotContains("a missing file does not print a stack trace",
    r.stderrText, "Traceback")

  # Malformed JSON is a syntax failure.
  let malformedPath = tmp / "malformed.json"
  writeFile(malformedPath, "{ not json")
  r = runBinary(@["config", "validate", "--file", malformedPath])
  t.checkEq("malformed JSON exits with the syntax status", r.exitCode, 4)
  t.checkNotContains("malformed JSON does not print a stack trace",
    r.stderrText, "Traceback")

  # A duplicate member name is a syntax failure.
  let duplicatePath = tmp / "duplicate.json"
  writeFile(duplicatePath, """{"schema_version": 1, "schema_version": 1}""")
  r = runBinary(@["config", "validate", "--file", duplicatePath])
  t.checkEq("a duplicate member name exits with the syntax status",
    r.exitCode, 4)

  # An unknown command is an invocation failure.
  r = runBinary(@["not-a-command"])
  t.checkEq("an unknown command exits with the invocation status", r.exitCode, 2)
  t.checkContains("an unknown command is named", r.stderrText, "not-a-command")

  # An unknown option is an invocation failure.
  r = runBinary(@["config", "validate", "--not-an-option", "x"])
  t.checkEq("an unknown option exits with the invocation status", r.exitCode, 2)
  t.checkContains("an unknown option is named", r.stderrText, "--not-an-option")

  # A missing required option is an invocation failure.
  r = runBinary(@["config", "validate"])
  t.checkEq("a missing required option exits with the invocation status",
    r.exitCode, 2)

  # The daemon is explicitly unsupported rather than silently absent.
  r = runBinary(@["daemon"])
  t.checkEq("the daemon exits with the unsupported-operation status", r.exitCode, 8)
  t.checkContains("the daemon says it is not implemented", r.stderrText,
    "not implemented")

  # --- report validate --------------------------------------------------------
  r = runBinary(@["report", "validate", "--file", "examples/ironkeeper.json"])
  t.check("report validate rejects a configuration document", r.exitCode != 0)

  # --- Report semantics -------------------------------------------------------
  # A timestamp must denote a real calendar time, not merely match a
  # regular expression. The structural layer accepts `2026-02-30`; the
  # semantic layer must not.
  let semTmp = getTempDir() / "ironkeeper-report-semantics"
  createDir(semTmp)

  proc writeReport(name, timestamp, state, verdict: string): string =
    ## Write a minimal but well-formed report document.
    let path = semTmp / name
    var text = "{\n"
    text.add "  \"schema_version\": 1,\n"
    text.add "  \"report_type\": \"configuration_validation\",\n"
    text.add "  \"report_id\": {\"id\": \"r1\", \"created_at\": \"" & timestamp & "\"},\n"
    text.add "  \"producer\": {\"name\": \"ironkeeper\", \"version\": \"0.1.0\"},\n"
    text.add "  \"execution\": {\"state\": \"" & state & "\", " &
      "\"started_at\": \"" & timestamp & "\", " &
      "\"finished_at\": \"" & timestamp & "\"},\n"
    if verdict.len > 0:
      text.add "  \"assessment\": {\"verdict\": \"" & verdict &
        "\", \"summary\": \"checked\"},\n"
    text.add "  \"findings\": []\n}\n"
    writeFile(path, text)
    path

  for (label, timestamp) in [
      ("an impossible month", "2026-13-02T03:04:05Z"),
      ("an impossible day", "2026-02-30T03:04:05Z"),
      ("an impossible hour", "2026-01-02T25:04:05Z"),
      ("an impossible minute", "2026-01-02T03:61:05Z"),
      ("an impossible second", "2026-01-02T03:04:61Z"),
      ("a non-leap February 29", "2026-02-29T00:00:00Z"),
      ("an invalid offset", "2026-01-02T03:04:05+25:00")]:
    let path = writeReport("bad-time.json", timestamp, "SUCCEEDED", "")
    r = runBinary(@["report", "validate", "--file", path, "--json"])
    t.check("report validate rejects " & label, r.exitCode != 0)
    t.check("report validate reports " & label & " as a semantic failure",
      r.exitCode == 6)

  for (label, timestamp) in [
      ("a leap day", "2024-02-29T00:00:00Z"),
      ("a UTC timestamp", "2026-01-02T03:04:05Z"),
      ("a UTC timestamp with a fraction", "2026-01-02T03:04:05.123456Z"),
      ("a positive offset", "2026-01-02T03:04:05+14:00"),
      ("a negative offset", "2026-01-02T03:04:05-12:00")]:
    let path = writeReport("good-time.json", timestamp, "SUCCEEDED", "")
    r = runBinary(@["report", "validate", "--file", path, "--json"])
    t.check("report validate accepts " & label, r.exitCode == 0)

  # A failed execution must not carry a PASS assessment.
  let failedPath = writeReport("failed-pass.json",
    "2026-01-02T03:04:05Z", "FAILED", "PASS")
  r = runBinary(@["report", "validate", "--file", failedPath, "--json"])
  t.check("report validate rejects a PASS verdict on a failed execution",
    r.exitCode != 0)
  t.check("report validate reports it as a semantic failure", r.exitCode == 6)
  t.checkContains("the reason is named", r.stdoutText, "PASS assessment")

  # An unsupported schema version has its own documented classification.
  let versionPath = semTmp / "bad-version.json"
  writeFile(versionPath, """{"schema_version": 99}""")
  r = runBinary(@["report", "validate", "--file", versionPath, "--json"])
  t.checkEq("an unsupported schema version exits with the documented status",
    r.exitCode, 7)

  # --- Bounded ingestion ------------------------------------------------------
  # An oversized document must be rejected by a bounded reader, without
  # the whole document being read into memory first.
  let bigPath = semTmp / "oversized.json"
  var handle = open(bigPath, fmWrite)
  handle.write("{\"a\":\"" )
  let chunk = "x".repeat(64 * 1024)
  for _ in 0 ..< 80:
    handle.write(chunk)
  handle.write("\"}")
  handle.close()
  r = runBinary(@["config", "validate", "--file", bigPath, "--json"])
  t.checkEq("an oversized document exits with the input-unavailable status",
    r.exitCode, 3)
  t.checkContains("the oversized document is named", r.stdoutText,
    "exceeds the maximum size")
  t.check("the oversized document produces a classified result",
    r.stdoutText.contains("input_unavailable"))

  # A directory is not a readable document.
  r = runBinary(@["config", "validate", "--file", semTmp, "--json"])
  t.checkEq("a directory exits with the input-unavailable status",
    r.exitCode, 3)

  # --- No unexpected files are created ---------------------------------------
  var before: seq[string]
  for f in walkDirRec(getCurrentDir()):
    before.add f
  discard runBinary(@["config", "validate", "--file", "examples/ironkeeper.json"])
  discard runBinary(@["version", "--json"])
  discard runBinary(@["schema", "list"])
  var newFiles = 0
  for f in walkDirRec(getCurrentDir()):
    if f notin before:
      newFiles += 1
      echo "    unexpected file: ", f
  t.checkEq("the commands create no files", newFiles, 0)

  t.finish()

