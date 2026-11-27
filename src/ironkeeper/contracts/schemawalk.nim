## The schema-position walker.
##
## Both the **schema policy** and the **reference policy** must answer the
## same question: *is this member a keyword of a schema, or is it data?*
## When the two answer it differently, the disagreement is a defect: a
## keyword-shaped name inside a `const` object is a value, and a `$ref`
## inside an `examples` array is a string.
##
## This module is the single interpretation of that question. It walks a
## schema document and reports every member of every **schema-bearing
## position**, together with the kind of value that member carries. The
## policy module and the reference module both consume this walk; neither
## traverses the document on its own.
##
## ## The positions
##
## A member of a schema object is one of:
##
##   * a **subschema** (`items`, `not`, `if`, `then`, `else`, `contains`,
##     `propertyNames`, `additionalProperties`);
##   * an **array of subschemas** (`allOf`, `anyOf`, `oneOf`, `prefixItems`);
##   * a **map of subschemas** (`$defs`, `properties`, `patternProperties`,
##     `dependentSchemas`) — here the *member names* are data (they name
##     properties, they are not keywords) and the *values* are subschemas;
##   * a **plain value** — everything else, including `const`, `enum`,
##     `default` and `examples`. Their contents are data and are never
##     traversed.

import std/[json, sets, strutils]

type
  MemberKind* = enum
    mkSchema
      ## The member's value is a subschema.
    mkSchemaArray
      ## The member's value is an array of subschemas.
    mkSchemaMap
      ## The member's value is an object whose member *values* are
      ## subschemas. The member *names* are data.
    mkValue
      ## The member's value is a plain value. It is data, never a schema.

  SchemaMember* = object
    path*: string
      ## JSON Pointer of the member within the schema document.
    parent*: string
      ## JSON Pointer of the schema object that carries the member. The
      ## root schema object is the empty pointer.
    keyword*: string
      ## The member's name.
    value*: JsonNode
      ## The member's value.
    kind*: MemberKind
      ## What the member's value carries.

  SchemaVisitor* = proc (member: SchemaMember) {.closure.}

const
  SchemaValuedKeywords* = [
    "additionalProperties", "contains", "else", "if", "items", "not",
    "propertyNames", "then",
  ]
    ## Keywords whose value is a subschema.

  SchemaArrayKeywords* = ["allOf", "anyOf", "oneOf", "prefixItems"]
    ## Keywords whose value is an array of subschemas.

  SchemaMapKeywords* = ["$defs", "dependentSchemas", "patternProperties",
                         "properties"]
    ## Keywords whose value is an object mapping names to subschemas.

proc escapePointer*(token: string): string =
  ## Escape a JSON Pointer reference token (RFC 6901).
  token.replace("~", "~0").replace("/", "~1")

proc unescapePointer*(token: string): string =
  ## Undo `escapePointer`.
  token.replace("~1", "/").replace("~0", "~")

proc kindOfKeyword(keyword: string): MemberKind =
  ## The kind of value a keyword carries.
  if keyword in SchemaValuedKeywords:
    mkSchema
  elif keyword in SchemaArrayKeywords:
    mkSchemaArray
  elif keyword in SchemaMapKeywords:
    mkSchemaMap
  else:
    mkValue

proc walkSchema*(schema: JsonNode, visit: SchemaVisitor) =
  ## Visit every member of every schema-bearing position in `schema`.
  ##
  ## The root of the document is a schema position. Members of a schema
  ## object are visited; the walk descends into the values of subschema,
  ## subschema-array and subschema-map members, and into nothing else.
  ## A member of a subschema map is visited as a member of the *subschema*
  ## it names, never as a member of the map itself: the map's own member
  ## names are data.
  proc walkSchemaObject(node: JsonNode, path: string) =
    if node.isNil or node.kind != JObject:
      return
    for key, value in node.pairs:
      let loc = if path.len == 0: "/" & escapePointer(key)
                else: path & "/" & escapePointer(key)
      let kind = kindOfKeyword(key)
      visit SchemaMember(path: loc, parent: path, keyword: key, value: value,
                         kind: kind)
      case kind
      of mkSchema:
        walkSchemaObject(value, loc)
      of mkSchemaArray:
        if value.kind == JArray:
          for i, item in value.elems:
            walkSchemaObject(item, loc & "/" & $i)
      of mkSchemaMap:
        if value.kind == JObject:
          for name, sub in value.pairs:
            walkSchemaObject(sub, loc & "/" & escapePointer(name))
      of mkValue:
        discard

  walkSchemaObject(schema, "")

proc collectSchemaPaths*(schema: JsonNode): HashSet[string] =
  ## The JSON Pointers of every schema-bearing position in `schema`.
  ##
  ## The root is always a schema position. A position is a schema position
  ## when it is the root, the value of a subschema keyword, an element of
  ## a subschema array, or the value of a member of a subschema map.
  var paths = initHashSet[string]()
  paths.incl ""
  var visitor: SchemaVisitor
  visitor = proc (member: SchemaMember) =
    case member.kind
    of mkSchema:
      paths.incl member.path
    of mkSchemaArray:
      if member.value.kind == JArray:
        for i in 0 ..< member.value.elems.len:
          paths.incl member.path & "/" & $i
    of mkSchemaMap:
      if member.value.kind == JObject:
        for name, _ in member.value.pairs:
          paths.incl member.path & "/" & escapePointer(name)
    of mkValue:
      discard
  walkSchema(schema, visitor)
  paths
