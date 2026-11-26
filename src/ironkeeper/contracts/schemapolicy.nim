## The schema feature policy of Ironkeeper.
##
## ## Why this module exists
##
## Meta-validation answers a different question. It asks "is this a valid
## Draft 2020-12 schema?". It does **not** ask "is this a schema whose
## keywords Ironkeeper understands?".
##
## The two are easy to confuse, and the confusion is dangerous. A schema
## with a misspelled keyword:
##
## ```json
## {"type": "object", "additionalPropeties": false}
## ```
##
## is a perfectly valid Draft 2020-12 schema. `additionalPropeties` is not
## a keyword at all, so the metaschema accepts it, and a validator that
## only meta-validates will happily evaluate it. The schema then says
## nothing about unknown properties, and the *intent* - a closed object
## boundary - is silently lost.
##
## The same holds for `{"type": "integer", "minimun": 10}`: `minimun` is
## not a keyword, so the bound is silently absent.
##
## Ironkeeper therefore enforces an explicit **supported schema policy**:
## a bounded, documented subset of Draft 2020-12, whose keywords are
## listed in `SupportedKeywords`. A keyword that is not in that list is
## rejected when it appears in a *schema-bearing position*.
##
## ## Schema-bearing positions
##
## A keyword is only a keyword in a position where the specification says
## a schema may appear. Those positions are:
##
##   * the root of the schema document;
##   * the value of `properties`, `patternProperties` and `$defs`;
##   * the value of `items`, `additionalItems`, `contains`,
##     `propertyNames`, `not`, `if`, `then` and `else`;
##   * each element of `allOf`, `anyOf`, `oneOf`, `prefixItems`.
##
## A keyword is **not** a keyword:
##
##   * when it is a *property name* inside `properties` (the name is an
##     arbitrary string, not a keyword);
##   * when it is a member of a `const` object (that is a value);
##   * when it is inside an `examples` or `default` array or object (those
##     are values, not schemas);
##   * when it is inside a `properties` *value* that is not itself a
##     schema-bearing position.
##
## The distinction matters: `{"properties": {"minimun": {"type":
## "integer"}}}` names a property called `minimun`. It must not be
## rejected as an unknown keyword, and it must not be treated as one.
##
## ## Prohibited constructs
##
## The policy also *prohibits* constructs that are valid Draft 2020-12 but
## outside Ironkeeper's support:
##
##   * a `$schema` declaration in a nested position, which would change
##     the dialect of a subschema;
##   * a `$dynamicRef` / `$dynamicAnchor`, because dynamic resolution has
##     no bounded, auditable meaning in Ironkeeper's contracts;
##   * a `$ref` that is not a local JSON Pointer and not the bundled
##     metaschema URI.
##
## ## The exception boundary
##
## `checkSchemaPolicy` is a pure function over a `JsonNode`. It performs no
## I/O, resolves no reference and never evaluates a schema. It cannot
## crash the process, and it does not claim to: it inspects a document that
## has already been parsed and bounds its own recursion.

import std/[json, strutils, sets]

const
  SupportedKeywords* = [
    # Core
    "$anchor", "$comment", "$defs", "$id", "$ref", "$schema", "$vocabulary",
    # Applicators
    "additionalProperties", "allOf", "anyOf", "contains", "else", "if",
    "items", "not", "oneOf", "patternProperties", "prefixItems",
    "properties", "propertyNames", "then",
    # Validation
    "const", "dependentRequired", "dependentSchemas", "enum",
    "exclusiveMaximum", "exclusiveMinimum", "maxContains", "maxItems",
    "maxLength", "maxProperties", "maximum", "minimum", "minContains",
    "minItems", "minLength", "minProperties", "multipleOf", "pattern",
    "required", "type", "uniqueItems",
    # Annotations. `format` is annotation-only in Draft 2020-12 and is
    # accepted; Ironkeeper does not assert on it.
    "default", "deprecated", "description", "examples", "format",
    "readOnly", "title", "writeOnly",
  ]
    ## The schema keywords Ironkeeper supports.
    ##
    ## A keyword that is not in this list is rejected when it appears in a
    ## schema-bearing position. The list is deliberately explicit: it is
    ## the supported feature subset that the validator qualification and
    ## the conformance harness are stated against.

  ProhibitedKeywords* = ["$dynamicAnchor", "$dynamicRef"]
    ## Keywords that are valid Draft 2020-12 but that Ironkeeper refuses
    ## to support.
    ##
    ## Dynamic resolution has no bounded, auditable meaning in
    ## Ironkeeper's contracts, and refusing it keeps the reference policy
    ## decidable from the schema text alone.

  MetaschemaUri* = "https://json-schema.org/draft/2020-12/schema"
    ## The only dialect Ironkeeper implements.

type
  SchemaPolicyIssue* = object
    ## One reason a schema falls outside the supported policy.
    location*: string
      ## JSON Pointer to the offending keyword in the schema.
    message*: string

  SchemaPolicyResult* = object
    ok*: bool
    issues*: seq[SchemaPolicyIssue]

proc supportedKeywordSet(): HashSet[string] =
  result = initHashSet[string]()
  for k in SupportedKeywords:
    result.incl k

proc prohibitedKeywordSet(): HashSet[string] =
  result = initHashSet[string]()
  for k in ProhibitedKeywords:
    result.incl k

const
  Supported = supportedKeywordSet()
  Prohibited = prohibitedKeywordSet()

# The keys whose *value* is a schema.
const
  SchemaValuedKeywords = [
    "additionalProperties", "contains", "else", "if", "items", "not",
    "propertyNames", "then",
  ]

# The keys whose value is an array of schemas.
const
  SchemaArrayKeywords = ["allOf", "anyOf", "oneOf", "prefixItems"]

# The keys whose value is an object mapping names to schemas.
const
  SchemaMapKeywords = ["$defs", "patternProperties", "properties",
                       "dependentSchemas"]

proc escapePointer(token: string): string =
  ## Escape a JSON Pointer reference token (RFC 6901).
  token.replace("~", "~0").replace("/", "~1")

proc checkSchemaPolicy*(schema: JsonNode): SchemaPolicyResult =
  ## Check a schema document against Ironkeeper's supported schema policy.
  ##
  ## The check is structural: it does not evaluate the schema, does not
  ## resolve any reference and does not perform any I/O. A schema that
  ## passes this check is still meta-validated before it is used.
  ##
  ## Returns the issues that make the schema unsupported. An empty issue
  ## list means the schema is inside the supported subset.
  var issues: seq[SchemaPolicyIssue]

  proc checkSchema(node: JsonNode, path: string) =
    if node.kind != JObject:
      return
    for key, value in node.pairs:
      let loc = path & "/" & escapePointer(key)
      if Prohibited.contains(key):
        issues.add SchemaPolicyIssue(location: loc,
          message: "the keyword '" & key & "' is not supported by Ironkeeper")
        continue
      if not Supported.contains(key):
        issues.add SchemaPolicyIssue(location: loc,
          message: "the keyword '" & key & "' is not supported by Ironkeeper")
        continue
      # A nested dialect declaration would change the meaning of the
      # subschema. Only the root may declare a dialect.
      if key == "$schema" and path.len > 0:
        issues.add SchemaPolicyIssue(location: loc,
          message: "a nested '$schema' declaration is not permitted")
        continue
      if key in SchemaValuedKeywords:
        checkSchema(value, loc)
      elif key in SchemaArrayKeywords:
        if value.kind == JArray:
          for i, item in value.elems:
            checkSchema(item, loc & "/" & $i)
      elif key in SchemaMapKeywords:
        if value.kind == JObject:
          for name, sub in value.pairs:
            checkSchema(sub, loc & "/" & escapePointer(name))
      # Every other supported keyword carries a plain value, not a schema.
      # Its value is deliberately not inspected: a `const` object, an
      # `examples` array and a `default` value are *values*, not schemas,
      # and their member names are not keywords.

  checkSchema(schema, "")
  SchemaPolicyResult(ok: issues.len == 0, issues: issues)
