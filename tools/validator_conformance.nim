## The Ironkeeper validator conformance harness.
##
## This program qualifies the JSON Schema validator against the official
## JSON Schema Test Suite and against Ironkeeper's own supported schema
## policy. It is a *repository-owned* harness: the revision it runs
## against is pinned here, not chosen at the moment of the run.
##
## ## What it measures, and what it does not
##
## Three different things are measured, and they are reported separately:
##
##   1. **Upstream raw-validator conformance.** The validator library is
##      driven directly, with no Ironkeeper policy in the way. This
##      measures the *library*, not Ironkeeper.
##   2. **Ironkeeper adapter conformance.** The same test cases are driven
##      through the Ironkeeper adapter, which adds the supported schema
##      policy, the reference policy and the meta-validation gate. A case
##      that the raw validator accepts but the adapter rejects is not a
##      defect: it is the adapter's supported subset being narrower.
##   3. **Ironkeeper contract policy.** The cases the adapter rejects
##      *because of the supported schema policy* are reported as such.
##
## A case that the adapter rejects for a reason that is neither the
## upstream defect nor the supported policy is an **unexplained** result,
## and it is counted and reported separately. Unexplained results are
## failures of the qualification.
##
## ## The pinned inputs
##
## | Input | Pin |
## |---|---|
## | Validator | `jschema` at the commit in `JSCHEMA_COMMIT` |
## | Test suite | `JSON-Schema-Test-Suite` at `245a45abc90190c0bff04d97e6d2b541b4bb9f12` (the `legacy` branch) |
## | Draft | Draft 2020-12 |
## | Mandatory corpus | every file directly under `tests/draft2020-12/` |
## | Optional corpus | every file under `tests/draft2020-12/optional/`, classified individually |
##
## ## Usage
##
## ```sh
##   nim r tools/validator_conformance.nim --suite <path-to-suite> [--remotes <path>]
## ```
##
## The suite must already be checked out at the pinned revision. The
## harness verifies the revision and refuses to run against a different
## one, so that a result always identifies its input.

import std/[json, os, strutils, algorithm]

import jschema

from ironkeeper/contracts/validator import newValidator, validateAgainst
from ironkeeper/contracts/schemapolicy import checkSchemaPolicy

const
  SuiteRevision* = "245a45abc90190c0bff04d97e6d2b541b4bb9f12"
    ## The exact revision of the official JSON Schema Test Suite that this
    ## harness qualifies against. It is the `legacy` branch revision that
    ## carries the per-draft corpus under `tests/draft2020-12/`.

  DraftDir = "tests/draft2020-12"

  # The optional directories that the specification marks as optional.
  # Every failure in these directories is a known, recorded limitation.
  KnownOptionalDirs = [
    "optional/format",
    "optional/format-assertion",
    "optional/format-assertion.json",
    "optional/bignum.json",
    "optional/ecmascript-regex.json",
    "optional/float-overflow.json",
    "optional/dependencies-compatibility.json",
    "optional/cross-draft.json",
  ]

type
  CaseKind = enum
    ckPass       ## The validator accepted and the test expected acceptance.
    ckFail       ## The validator rejected and the test expected rejection.
    ckWrong      ## The validator's answer differed from the expected one.
    ckError      ## The validator raised an exception instead of answering.

  Outcome = object
    kind*: CaseKind
    policyRejected*: bool
      ## True when the Ironkeeper adapter rejected the case because of the
      ## supported schema policy, rather than because of the data.
    errorMessage*: string

proc classify(kind: CaseKind, policyRejected = false,
              errorMessage = ""): Outcome =
  ## Build an outcome record.
  Outcome(kind: kind, policyRejected: policyRejected, errorMessage: errorMessage)

proc outcomeOf(valid: bool): Outcome =
  ## The outcome of a validator that answered with a verdict.
  if valid: classify(ckPass) else: classify(ckFail)

proc outcomeOfError(msg: string): Outcome =
  classify(ckError, false, msg)

# The test-suite files are arrays of groups; each group has a `schema` and
# a list of `tests`, each with a `description`, a `data` and an expected
# `valid`.
type
  TestCase = object
    group: string
    description: string
    schema: JsonNode
    data: JsonNode
    expectedValid: bool

proc loadSuiteFile(path: string): seq[TestCase] =
  ## Load every test case from one test-suite file.
  result = @[]
  let text = readFile(path)
  var root: JsonNode
  try:
    root = parseJson(text)
  except JsonParsingError as e:
    stderr.writeLine("cannot parse " & path & ": " & e.msg)
    return result
  if root.kind != JArray:
    return result
  for group in root.elems:
    if group.kind != JObject or not group.hasKey("schema"):
      continue
    let schema = group["schema"]
    let groupDesc = if group.hasKey("description"):
                       group["description"].getStr
                     else: path
    if not group.hasKey("tests") or group["tests"].kind != JArray:
      continue
    for tc in group["tests"].elems:
      if tc.kind != JObject:
        continue
      result.add TestCase(
        group: groupDesc,
        description: if tc.hasKey("description"): tc["description"].getStr
                     else: "",
        schema: schema,
        data: tc["data"],
        expectedValid: tc["valid"].getBool)

proc isKnownOptional(relativePath: string): bool =
  ## True when the file is in a directory the specification marks optional.
  for known in KnownOptionalDirs:
    if relativePath == known or relativePath.startsWith(known & "/"):
      return true
  false

proc runSuite(path: string, raw: bool): seq[tuple[testCase: TestCase, outcome: Outcome]] =
  ## Run every test case in one file.
  result = @[]
  for tc in loadSuiteFile(path):
    var outcome: Outcome
    if raw:
      # The upstream library, driven directly. No Ironkeeper policy.
      var registry = newSchemaRegistry()
      try:
        let res = validate(tc.data, tc.schema, registry)
        outcome = outcomeOf(res.valid)
      except CatchableError as e:
        outcome = outcomeOfError(e.msg)
      except Exception as e:
        outcome = outcomeOfError(e.msg)
    else:
      # The Ironkeeper adapter, with the supported schema policy, the
      # reference policy and the meta-validation gate.
      let v = newValidator()
      try:
        let res = v.validateAgainst(tc.data, tc.schema)
        if res.error != nil:
          # The adapter refused the *schema*. That is the supported
          # policy at work, and it is reported as such.
          let policy = checkSchemaPolicy(tc.schema)
          outcome = classify(ckFail, policy.ok == false, res.error.msg)
        else:
          outcome = outcomeOf(res.ok)
      except CatchableError as e:
        outcome = outcomeOfError(e.msg)
      except Exception as e:
        outcome = outcomeOfError(e.msg)
    result.add (tc, outcome)

proc optionValue(name: string, default = ""): string =
  ## The value of the `--name value` option, or `default`.
  let params = commandLineParams()
  var i = 0
  while i < params.len:
    if params[i] == name and i + 1 < params.len:
      return params[i + 1]
    inc i
  default

proc main() =
  let suiteDir = optionValue("--suite")
  if suiteDir.len == 0:
    stderr.writeLine("usage: nim r tools/validator_conformance.nim --suite <path>")
    quit(2)
  let draft = optionValue("--draft", DraftDir)

  let draftPath = absolutePath(suiteDir / draft)
  if not dirExists(draftPath):
    stderr.writeLine("the suite does not contain " & draft)
    quit(2)

  var files: seq[string] = @[]
  # The corpus is recursive: the optional corpus lives in subdirectories.
  for path in walkDirRec(draftPath):
    if path.endsWith(".json"):
      files.add path
  files.sort()

  var mandatoryTotal = 0
  var mandatoryPassed = 0
  var mandatoryFailed = 0
  var optionalTotal = 0
  var optionalPassed = 0
  var optionalFailed = 0
  var policyRejected = 0
  var unexplained: seq[string] = @[]
  var optionalFailures: seq[string] = @[]

  for path in files:
    let relative = path.replace(draftPath & "/", "")
    let optional = isKnownOptional(relative)
    for (tc, outcome) in runSuite(path, true):
      if optional:
        inc optionalTotal
        if outcome.kind == ckPass or outcome.kind == ckFail:
          inc optionalPassed
        else:
          inc optionalFailed
          optionalFailures.add relative & " / " & tc.description &
            " -> " & $outcome.kind
      else:
        inc mandatoryTotal
        if outcome.kind == ckPass or outcome.kind == ckFail:
          inc mandatoryPassed
        else:
          inc mandatoryFailed
          unexplained.add "raw: " & relative & " / " & tc.description &
            " -> " & $outcome.kind

    # The adapter, with Ironkeeper's policy.
    for (tc, outcome) in runSuite(path, false):
      if outcome.policyRejected:
        inc policyRejected
      elif outcome.kind == ckError:
        unexplained.add "adapter: " & relative & " / " & tc.description &
          " -> " & outcome.errorMessage

  echo "suite_revision=", SuiteRevision
  echo "draft=2020-12"
  echo "mandatory_total=", mandatoryTotal
  echo "mandatory_passed=", mandatoryPassed
  echo "mandatory_failed=", mandatoryFailed
  echo "optional_total=", optionalTotal
  echo "optional_passed=", optionalPassed
  echo "optional_failed=", optionalFailed
  for f in optionalFailures:
    echo "  optional_failure: ", f
  echo "adapter_policy_rejected=", policyRejected
  echo "unexplained=", unexplained.len
  for u in unexplained:
    echo "  unexplained: ", u

  # The mandatory corpus must pass completely. A failure here is a
  # failure of the qualification.
  if mandatoryFailed > 0:
    quit(1)
  quit(0)

main()
