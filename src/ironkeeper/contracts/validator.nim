## Fail-closed JSON Schema validation adapter.
##
## Ironkeeper delegates JSON Schema evaluation to `jschema`, a MIT-licensed
## Draft 2020-12 validator that depends only on the Nim standard library and
## never performs network access. See `docs/architecture/overview.md`,
## section "Validator qualification", for the recorded conformance results.
##
## This adapter exists because the upstream library cannot be trusted with an
## arbitrary schema document:
##
##   * Upstream assumes Draft 2020-12 semantics for `exclusiveMaximum` and
##     `exclusiveMinimum`, which are numbers in that draft. Given the
##     Draft 4 boolean form (`{"maximum": 3.0, "exclusiveMaximum": true}`)
##     it dereferences a boolean as a number and terminates the process with
##     an uncaught `FieldDefect`.
##
## The adapter therefore applies a two-stage, fail-closed protocol:
##
##   1. **Meta-validation.** The schema document is first validated against
##      the bundled Draft 2020-12 metaschema. A schema that is not a valid
##      Draft 2020-12 schema is rejected before it is ever used to validate
##      data. This alone neutralises the upstream defect, because the
##      offending boolean form is not a valid 2020-12 schema.
##   2. **Evaluation.** The pre-validated schema is used to validate data.
##      Any residual defect raised by the library is caught and reported as an
##      internal failure rather than terminating the process.
##
## The adapter also enforces Ironkeeper's own rules:
##
##   * Only Draft 2020-12 is accepted. Other `$schema` values are rejected
##     with an unsupported-schema-version error.
##   * External references are prohibited. A schema that references a URI
##     outside its own document is rejected; resolution never reaches the
##     network.
##   * The data is validated exactly as parsed. No coercion is performed.

import std/[json, strutils]

import jschema


const
  Draft2020_12* = "https://json-schema.org/draft/2020-12/schema"
    ## The only JSON Schema dialect Ironkeeper implements.

  MetaschemaRef* = "https://json-schema.org/draft/2020-12/schema"
    ## Retrieval URI of the Draft 2020-12 metaschema, bundled by `jschema`.

type
  SchemaIssue* = object
    ## One concrete reason a document failed validation.
    location*: string
      ## JSON Pointer to the offending position in the *data*, when known.
    keywordLocation*: string
      ## JSON Pointer to the offending keyword in the *schema*.
    message*: string

  ValidationOutcome* = object
    ok*: bool
    issues*: seq[SchemaIssue]
    error*: ref Exception
      ## Set when the failure was an internal defect rather than a normal
      ## validation failure.

  Validator = object
    registry: SchemaRegistry

proc newValidator*(): Validator =
  ## Create a validator with the Draft 2020-12 metaschemas pre-registered.
  ##
  ## The registry never fetches anything: a document that is not already
  ## registered cannot be resolved.
  Validator(registry: newSchemaRegistry())

proc draftOf(schema: JsonNode): string =
  ## Declared dialect of `schema`, or the empty string when none is declared.
  if schema.kind == JObject and schema.hasKey("$schema"):
    let v = schema["$schema"]
    if v.kind == JString:
      return v.getStr
  ""

proc collectExternalRefs(schema: JsonNode, prefix = ""): seq[string] =
  ## Collect every `$ref` in `schema` that is not a local JSON Pointer and
  ## not the bundled Draft 2020-12 metaschema.
  ##
  ## Only `#`-prefixed pointers are considered local. The metaschema URI is
  ## allowed because it is bundled in the registry and resolved entirely
  ## offline; it is the only absolute reference Ironkeeper permits.
  ## Everything else is prohibited, because resolving it would require a
  ## network fetch.
  if schema.kind == JObject:
    for key, value in schema.pairs:
      let loc = if prefix.len == 0: "/" & key else: prefix & "/" & key
      if key == "$ref" and value.kind == JString:
        let target = value.getStr
        if not target.startsWith("#") and target != MetaschemaRef:
          result.add target
      else:
        result.add collectExternalRefs(value, loc)
  elif schema.kind == JArray:
    for i, value in schema.elems:
      result.add collectExternalRefs(value, prefix & "/" & $i)

proc metaValidate(v: Validator, schema: JsonNode): ValidationOutcome =
  ## Validate `schema` against the Draft 2020-12 metaschema.
  ##
  ## The meta-schema document is the single reference schema
  ## `{"$ref": "https://json-schema.org/draft/2020-12/schema"}`, which
  ## resolves entirely inside the bundled registry.
  let metaRef = parseJson("""{"$ref": "https://json-schema.org/draft/2020-12/schema"}""")
  let res = validate(schema, metaRef, v.registry)
  var issues: seq[SchemaIssue]
  for e in res.errors:
    issues.add SchemaIssue(location: e.instanceLocation,
                           keywordLocation: e.keywordLocation,
                           message: e.message)
  ValidationOutcome(ok: res.valid, issues: issues)

proc validateAgainst*(v: Validator, data, schema: JsonNode): ValidationOutcome =
  ## Validate `data` against `schema` under Ironkeeper's fail-closed rules.
  ##
  ## Returns an outcome whose `ok` field is true only when the data satisfies
  ## the schema *and* the schema itself is a well-formed Draft 2020-12
  ## schema. `error` is set when an internal defect occurred; in that case
  ## the outcome must be treated as a failure.
  let dialect = draftOf(schema)
  if dialect.len > 0 and dialect != Draft2020_12:
    return ValidationOutcome(
      ok: false,
      error: newException(ValueError,
        "unsupported JSON Schema dialect: " & dialect))

  let externalRefs = collectExternalRefs(schema)
  if externalRefs.len > 0:
    return ValidationOutcome(
      ok: false,
      error: newException(ValueError,
        "external schema reference is not permitted: " & externalRefs[0]))

  let meta = metaValidate(v, schema)
  if not meta.ok:
    return ValidationOutcome(ok: false, issues: meta.issues)

  try:
    let res = validate(data, schema, v.registry)
    var issues: seq[SchemaIssue]
    for e in res.errors:
      issues.add SchemaIssue(location: e.instanceLocation,
                             keywordLocation: e.keywordLocation,
                             message: e.message)
    ValidationOutcome(ok: res.valid, issues: issues)
  except CatchableError as e:
    ValidationOutcome(ok: false, error: e)
  except Exception as e:
    # Upstream defects (for example the Draft 4 boolean `exclusiveMaximum`
    # dereference) surface as `Defect`, which is not a `CatchableError`.
    # They are converted into an ordinary failure so that a hostile schema
    # can never terminate the process.
    ValidationOutcome(ok: false, error: e)
