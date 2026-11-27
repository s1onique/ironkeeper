## The reference policy of Ironkeeper.
##
## ## Why a separate policy
##
## A reference is a reference only where the specification says a keyword
## may appear. `{"const": {"$ref": "#/$defs/x"}}` carries a `$ref` *key*,
## but the member is a member of a `const` **value**: it is data, and it is
## never resolved. The same is true of `{"examples": [{"$ref": "..."}]}`.
##
## Treating those as references is not a harmless over-restriction: it
## refuses schemas that are perfectly ordinary, and it makes the policy
## disagree with the evaluation. The policy module and the reference
## collector therefore share one interpretation of the document, the
## **schema-position walker** in `schemawalk`.
##
## ## The supported reference subset
##
## Ironkeeper supports a narrow, predictable set of references:
##
##   * a **local JSON Pointer** (`#/$defs/x`) that resolves to a
##     schema-bearing position of the same document;
##   * a **local anchor** (`#name`) that names an `$anchor` declared at a
##     schema-bearing position of the same document;
##   * the **bundled metaschema URI**, which resolves entirely offline.
##
## Everything else is refused:
##
##   * an **external reference** would require a network fetch;
##   * a **dynamic reference** (`$dynamicRef`, `$dynamicAnchor`) has no
##     bounded, auditable meaning in Ironkeeper's contracts;
##   * a reference to a **non-schema-bearing location** — a pointer into a
##     `const` value, say — has no schema to apply;
##   * an **unresolvable local reference** is a defect in the schema.
##
## ## Nested identifiers
##
## A nested `$id` establishes a new base URI, which would change the
## meaning of every relative reference beneath it. Ironkeeper resolves
## references within one document only, so a nested `$id` could not be
## honoured without implementing a general resolver. It is therefore
## refused, exactly like a nested `$schema`.
##
## The root `$id` and the root `$vocabulary` are accepted: they describe
## the document itself and change nothing about how its references resolve.

import std/[json, sets, strutils]

from ironkeeper/contracts/schemawalk import walkSchema, collectSchemaPaths,
  SchemaMember, MemberKind, escapePointer, unescapePointer

const
  MetaschemaUri* = "https://json-schema.org/draft/2020-12/schema"
    ## The only dialect Ironkeeper implements. It is bundled, so a
    ## reference to it resolves entirely offline.

type
  ReferenceKind* = enum
    rkLocalPointer
      ## A JSON Pointer into the same document.
    rkLocalAnchor
      ## A plain-name fragment naming an `$anchor` of the same document.
    rkMetaschema
      ## The bundled Draft 2020-12 metaschema.
    rkExternal
      ## A reference that would require a fetch.
    rkDynamic
      ## A dynamic reference.

  ReferenceIssue* = object
    ## One reason a schema's references are outside the supported policy.
    location*: string
      ## JSON Pointer to the offending reference in the schema.
    message*: string

  ReferenceResult* = object
    ok*: bool
    issues*: seq[ReferenceIssue]

proc classifyReference(target: string): ReferenceKind =
  ## The kind of a reference target.
  if target == MetaschemaUri:
    return rkMetaschema
  if target.startsWith("#"):
    let fragment = target[1 .. ^1]
    if fragment.len > 0 and fragment[0] == '/':
      return rkLocalPointer
    return rkLocalAnchor
  rkExternal

proc resolvePointer(root: JsonNode, pointer: string): JsonNode =
  ## Resolve a JSON Pointer within `root`.
  ##
  ## Returns a nil node when the pointer does not resolve. The pointer is
  ## the fragment of a reference, without its leading `#`.
  var node = root
  if pointer.len == 0:
    return node
  if pointer[0] != '/':
    return nil
  for rawToken in pointer[1 .. ^1].split('/'):
    let token = unescapePointer(rawToken)
    case node.kind
    of JObject:
      if not node.hasKey(token):
        return nil
      node = node[token]
    of JArray:
      var index: int
      try:
        index = parseInt(token)
      except ValueError:
        return nil
      if index < 0 or index >= node.elems.len:
        return nil
      node = node.elems[index]
    else:
      return nil
  node

proc collectAnchors(schema: JsonNode): HashSet[string] =
  ## The `$anchor` names declared at schema-bearing positions.
  var names = initHashSet[string]()
  var visitor: proc (member: SchemaMember) {.closure.}
  visitor = proc (member: SchemaMember) =
    if member.keyword == "$anchor" and member.value.kind == JString:
      names.incl member.value.getStr
  walkSchema(schema, visitor)
  names

proc checkReferencePolicy*(schema: JsonNode): ReferenceResult =
  ## Check the references of a schema document against the supported
  ## reference policy.
  ##
  ## The check is structural: it resolves nothing over the network, and it
  ## performs no I/O.
  var issues: seq[ReferenceIssue]

  let schemaPaths = collectSchemaPaths(schema)
  let anchors = collectAnchors(schema)

  var visitor: proc (member: SchemaMember) {.closure.}
  visitor = proc (member: SchemaMember) =
    if member.keyword == "$dynamicRef" or member.keyword == "$dynamicAnchor":
      issues.add ReferenceIssue(location: member.path,
        message: "the keyword '" & member.keyword &
          "' is a dynamic reference and is not supported by Ironkeeper")
      return
    if member.keyword != "$ref":
      # A nested `$id` would change the base URI of every reference
      # beneath it, which the supported resolution model cannot honour.
      if member.keyword == "$id" and member.parent.len > 0:
        issues.add ReferenceIssue(location: member.path,
          message: "a nested '$id' declaration is not permitted")
      if member.keyword == "$vocabulary" and member.parent.len > 0:
        issues.add ReferenceIssue(location: member.path,
          message: "a nested '$vocabulary' declaration is not permitted")
      return
    if member.value.kind != JString:
      issues.add ReferenceIssue(location: member.path,
        message: "a '$ref' must be a string")
      return
    let target = member.value.getStr
    case classifyReference(target)
    of rkMetaschema:
      discard
    of rkExternal:
      issues.add ReferenceIssue(location: member.path,
        message: "the external reference '" & target &
          "' is not permitted: it would require a network fetch")
    of rkDynamic:
      issues.add ReferenceIssue(location: member.path,
        message: "the dynamic reference '" & target & "' is not permitted")
    of rkLocalAnchor:
      let name = target[1 .. ^1]
      if name notin anchors:
        issues.add ReferenceIssue(location: member.path,
          message: "the local reference '" & target &
            "' does not resolve to an '$anchor' of this document")
    of rkLocalPointer:
      let pointer = target[1 .. ^1]
      let resolved = resolvePointer(schema, pointer)
      if resolved.isNil:
        issues.add ReferenceIssue(location: member.path,
          message: "the local reference '" & target &
            "' does not resolve within this document")
      elif pointer notin schemaPaths:
        issues.add ReferenceIssue(location: member.path,
          message: "the local reference '" & target &
            "' does not resolve to a schema-bearing position")
  walkSchema(schema, visitor)

  ReferenceResult(ok: issues.len == 0, issues: issues)
