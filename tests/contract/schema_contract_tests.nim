## Contract tests for the repository JSON Schemas.
##
## These establish the properties that the published contracts depend on:
##
##   * every repository schema is a valid Draft 2020-12 schema,
##   * the schemas embedded in the binary are byte-for-byte identical to
##     the repository files,
##   * valid examples validate and invalid examples are rejected,
##   * the runtime validator and an independent validator agree on the
##     supported corpus.
##
## The independent cross-check runs in CI with a separate implementation
## (`check-jsonschema`). The runtime check here is the one that matters for
## the shipped binary.

import std/[json, os, strutils]

import testkit
import ironkeeper/contracts/schemaregistry
import ironkeeper/contracts/validator
import ironkeeper/json/strictjson

const
  SchemaDir = "schemas/v1"

  ValidConfig = """{
  "schema_version": 1,
  "daemon": {
    "state_directory": "/var/lib/ironkeeper",
    "socket_path": "/run/ironkeeper/control.sock"
  },
  "safety": {
    "require_explicit_enrollment": true,
    "allow_destructive_operations": false,
    "allow_tests_on_in_use_devices": false
  }
}"""

  ValidReport = """{
  "schema_version": 1,
  "report_type": "configuration_validation",
  "report_id": {
    "id": "20260101T000000-0000ABCD",
    "created_at": "2026-01-01T00:00:00Z"
  },
  "producer": {
    "name": "ironkeeper",
    "version": "0.1.0-dev"
  },
  "execution": {
    "state": "SUCCEEDED",
    "started_at": "2026-01-01T00:00:00Z",
    "finished_at": "2026-01-01T00:00:01Z"
  },
  "assessment": {
    "verdict": "PASS",
    "summary": "the configuration document is valid"
  },
  "findings": []
}"""

proc runSuite*(): int =
  var t = newTestSuite("contracts")
  let v = newValidator()

  # --- Every repository schema is a valid 2020-12 schema -----------------
  for name in EmbeddedSchemaNames:
    let path = SchemaDir / (name & ".schema.json")
    t.check("the repository holds " & path, fileExists(path))
    if not fileExists(path):
      continue
    let text = readFile(path)
    let doc = parseJson(text)
    t.checkEq(name & " declares the 2020-12 dialect",
      doc["$schema"].getStr, "https://json-schema.org/draft/2020-12/schema")
    t.check(name & " declares its own identity", doc.hasKey("$id"))
    # Meta-validation is the same check the runtime performs: the schema is
    # validated against the 2020-12 metaschema, not against itself.
    let metaschema = parseJson("""{"$ref":"https://json-schema.org/draft/2020-12/schema"}""")
    let metaOutcome = v.validateAgainst(doc, metaschema)
    t.check(name & " is a valid 2020-12 schema", metaOutcome.ok)
    if not metaOutcome.ok:
      for issue in metaOutcome.issues:
        echo "    ", issue.keywordLocation, ": ", issue.message

  # --- Embedded schemas equal repository schemas --------------------------
  for name in EmbeddedSchemaNames:
    let path = SchemaDir / (name & ".schema.json")
    if not fileExists(path):
      continue
    t.checkEq("the embedded " & name & " schema matches the repository file",
      schemaText(name), readFile(path))

  # --- Valid examples pass ------------------------------------------------
  let configSchema = parseJson(schemaText("config"))
  t.check("the example configuration validates",
    v.validateAgainst(parseJson(ValidConfig), configSchema).ok)

  let reportSchema = parseJson(schemaText("report"))
  t.check("the example report validates",
    v.validateAgainst(parseJson(ValidReport), reportSchema).ok)

  # --- Invalid examples fail ----------------------------------------------
  # Unknown schema version.
  let unknownVersion = ValidConfig.replace("\"schema_version\": 1",
                                           "\"schema_version\": 99")
  t.check("rejects an unknown schema version",
    not v.validateAgainst(parseJson(unknownVersion), configSchema).ok)

  # Unknown nested property.
  let unknownProperty = ValidConfig.replace(
    "\"socket_path\"", "\"unknown_member\": 1, \"socket_path\"")
  t.check("rejects an unknown nested property",
    not v.validateAgainst(parseJson(unknownProperty), configSchema).ok)

  # Unknown top-level property.
  let unknownTop = ValidConfig.replace("\"schema_version\": 1",
                                        "\"schema_version\": 1, \"extra\": 1")
  t.check("rejects an unknown top-level property",
    not v.validateAgainst(parseJson(unknownTop), configSchema).ok)

  # Missing mandatory property.
  # A missing mandatory property is removed from the parsed document
  # rather than by textual surgery, so the test cannot accidentally leave
  # a malformed document behind.
  let missingNode = parseJson(ValidConfig)
  missingNode["safety"].delete("allow_tests_on_in_use_devices")
  t.check("rejects a missing mandatory property",
    not v.validateAgainst(missingNode, configSchema).ok)

  let missingTop = parseJson(ValidConfig)
  missingTop.delete("daemon")
  t.check("rejects a missing mandatory top-level property",
    not v.validateAgainst(missingTop, configSchema).ok)

  # Wrong primitive type.
  let wrongType = ValidConfig.replace("\"schema_version\": 1",
                                       "\"schema_version\": \"1\"")
  t.check("rejects a wrong primitive type",
    not v.validateAgainst(parseJson(wrongType), configSchema).ok)

  # A string supplied in place of a boolean.
  let stringForBool = ValidConfig.replace(
    "\"allow_destructive_operations\": false",
    "\"allow_destructive_operations\": \"false\"")
  t.check("rejects a string in place of a boolean",
    not v.validateAgainst(parseJson(stringForBool), configSchema).ok)

  # The forbidden destructive-operation policy is rejected by the schema
  # itself, not only by the semantic layer.
  let destructive = ValidConfig.replace(
    "\"allow_destructive_operations\": false",
    "\"allow_destructive_operations\": true")
  t.check("the schema itself rejects destructive operations",
    not v.validateAgainst(parseJson(destructive), configSchema).ok)

  # A report with an unknown execution state.
  let badState = ValidReport.replace("\"SUCCEEDED\"", "\"SOMETHING_ELSE\"")
  t.check("rejects an unknown execution state",
    not v.validateAgainst(parseJson(badState), reportSchema).ok)

  # A report with an unknown assessment verdict.
  let badVerdict = ValidReport.replace("\"PASS\"", "\"MAYBE\"")
  t.check("rejects an unknown assessment verdict",
    not v.validateAgainst(parseJson(badVerdict), reportSchema).ok)

  # A report that mixes an execution state with a lifecycle state.
  let lifecycleLeak = ValidReport.replace("\"SUCCEEDED\"", "\"IN_SERVICE\"")
  t.check("rejects a device lifecycle state used as an execution state",
    not v.validateAgainst(parseJson(lifecycleLeak), reportSchema).ok)

  # --- The example configuration in the repository is valid ----------------
  if fileExists("examples/ironkeeper.json"):
    let example = parseStrict(readFile("examples/ironkeeper.json"))
    t.check("the repository example parses under the strict reader", example.ok)
    if example.ok:
      t.check("the repository example satisfies the configuration schema",
        v.validateAgainst(example.node, configSchema).ok)

  # --- Every machine-readable output has an authoritative schema -----------
  # Each public output document must be covered by a schema that this
  # build implements. The list below names the command and the contract
  # that governs its output.
  const OutputContracts = [
    ("version --json", "version"),
    ("schema list --json", "schemaindex"),
    ("report validate --json", "validation"),
    ("config validate --json", "report"),
    ("a classified failure", "error"),
  ]
  for (label, contract) in OutputContracts:
    t.check("the output of " & label & " has a schema (" & contract & ")",
      contract in EmbeddedSchemaNames)

  # The validation result document must accept the shape the CLI emits.
  let validationSchema = parseJson(schemaText("validation"))
  let validResult = """{"schema_version":1,"valid":true,"structural_valid":true,"semantic_valid":true,"issues":[]}"""
  t.check("the validation result document satisfies its contract",
    v.validateAgainst(parseJson(validResult), validationSchema).ok)
  let invalidResult = """{"schema_version":1,"valid":false,"structural_valid":true,"semantic_valid":false,"issues":[{"location":"/a","keyword_location":"","message":"m"}]}"""
  t.check("an invalid validation result satisfies its contract",
    v.validateAgainst(parseJson(invalidResult), validationSchema).ok)

  # The schema index document must accept the shape the CLI emits.
  let indexSchema = parseJson(schemaText("schemaindex"))
  let indexDoc = """{"schema_version":1,"schemas":[{"name":"config","version":1,"dialect":"https://json-schema.org/draft/2020-12/schema"}]}"""
  t.check("the schema index document satisfies its contract",
    v.validateAgainst(parseJson(indexDoc), indexSchema).ok)

  # The error document must accept the shape the CLI emits.
  let errorSchema = parseJson(schemaText("error"))
  let errorDoc = """{"schema_version":1,"error":{"code":"invalid_invocation","message":"m"}}"""
  t.check("the error document satisfies its contract",
    v.validateAgainst(parseJson(errorDoc), errorSchema).ok)

  # An oversized diagnostic must not make the document violate its own
  # contract: the message field is bounded, and a message longer than the
  # bound must be rejected rather than silently emitted.
  let oversizedError = """{"schema_version":1,"error":{"code":"invalid_invocation","message":"""" &
    "x".repeat(5000) & """"}}"""
  t.check("an oversized error message does not satisfy the error contract",
    not v.validateAgainst(parseJson(oversizedError), errorSchema).ok)

  # The same holds for the validation result: a large finding set must
  # not produce a document that violates the output contract.
  var manyIssues = """{"schema_version":1,"valid":false,"issues":["""
  for i in 0 ..< 2000:
    if i > 0:
      manyIssues.add ","
    manyIssues.add """{"message":"m"}"""
  manyIssues.add "]}"
  t.check("a large finding set does not satisfy the validation contract",
    not v.validateAgainst(parseJson(manyIssues), validationSchema).ok)

  t.finish()

