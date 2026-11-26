## Semantic validation of Ironkeeper configuration documents.
##
## Structural validation (JSON Schema) and semantic validation are distinct
## concerns. The schema establishes shape, types and the presence of
## required members. This module establishes the rules that a schema cannot
## express:
##
##   * The safety block is not configurable away in milestone M0.
##     `allow_destructive_operations` must be false, `require_explicit_enrollment`
##     must be true, and `allow_tests_on_in_use_devices` must be false.
##   * Paths must be absolute and must not contain a `..` component, so that
##     a configuration file cannot redirect state or the control socket
##     somewhere unexpected.
##   * The declared `schema_version` must be one this build implements.

import std/[json, strutils]


type
  SemanticIssue* = object
    ## One concrete reason a document failed semantic validation.
    code*: string
      ## Stable machine-readable issue code.
    message*: string
    location*: string
      ## JSON Pointer to the offending position in the document.

  SemanticResult* = object
    ok*: bool
    issues*: seq[SemanticIssue]

const
  SupportedConfigSchemaVersion* = 1
    ## The only configuration schema version this build implements.

proc issue(code, msg, loc: string): SemanticIssue =
  SemanticIssue(code: code, message: msg, location: loc)

proc isAbsoluteCleanPath(p: string): bool =
  ## True when `p` is an absolute path with no `.` or `..` components.
  if not p.startsWith("/"):
    return false
  for part in p.split('/'):
    if part == "." or part == "..":
      return false
  true

proc validateSafety(node: JsonNode, issues: var seq[SemanticIssue]) =
  ## Enforce the mandatory safety policy of milestone M0.
  ##
  ## These values are deliberately *not* configurable. A configuration that
  ## asks for destructive operations is rejected outright; it is not silently
  ## downgraded.
  if node.kind != JObject:
    return
  if node.hasKey("allow_destructive_operations"):
    let v = node["allow_destructive_operations"]
    if v.kind == JBool and v.getBool:
      issues.add issue("safety.destructive_operations_forbidden",
        "allow_destructive_operations must be false; destructive operations are not implemented and cannot be enabled",
        "/safety/allow_destructive_operations")
  if node.hasKey("require_explicit_enrollment"):
    let v = node["require_explicit_enrollment"]
    if v.kind == JBool and not v.getBool:
      issues.add issue("safety.enrollment_required",
        "require_explicit_enrollment must be true; devices are never enrolled implicitly",
        "/safety/require_explicit_enrollment")
  if node.hasKey("allow_tests_on_in_use_devices"):
    let v = node["allow_tests_on_in_use_devices"]
    if v.kind == JBool and v.getBool:
      issues.add issue("safety.tests_on_in_use_forbidden",
        "allow_tests_on_in_use_devices must be false; self-tests are never started on devices that are in use",
        "/safety/allow_tests_on_in_use_devices")

proc validatePaths(node: JsonNode, issues: var seq[SemanticIssue]) =
  ## Enforce that the daemon paths are absolute and free of `.`/`..`.
  if node.kind != JObject:
    return
  const PathFields = [
    ("state_directory", "/daemon/state_directory"),
    ("socket_path", "/daemon/socket_path"),
  ]
  for entry in PathFields:
    let key = entry[0]
    let pointer = entry[1]
    if node.hasKey(key):
      let v = node[key]
      if v.kind == JString:
        let p = v.getStr
        if not isAbsoluteCleanPath(p):
          issues.add issue("daemon.invalid_path",
            key & " must be an absolute path without '.' or '..' components",
            pointer)

proc validateConfigSemantics*(doc: JsonNode): SemanticResult =
  ## Validate the semantics of a configuration document.
  ##
  ## The document is assumed to have already passed schema validation. The
  ## schema version is still re-checked here, because an unsupported version
  ## must be reported as such rather than as a generic semantic failure.
  var issues: seq[SemanticIssue]

  if doc.kind == JObject and doc.hasKey("schema_version"):
    let v = doc["schema_version"]
    if v.kind == JInt and v.getInt != SupportedConfigSchemaVersion:
      return SemanticResult(ok: false, issues: @[issue(
        "config.unsupported_schema_version",
        "unsupported configuration schema_version: " & $v.getInt &
          "; this build implements version " & $SupportedConfigSchemaVersion,
        "/schema_version")])

  if doc.kind == JObject:
    if doc.hasKey("safety"):
      validateSafety(doc["safety"], issues)
    if doc.hasKey("daemon"):
      validatePaths(doc["daemon"], issues)

  SemanticResult(ok: issues.len == 0, issues: issues)
