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

import std/[json]

import jschema

from ironkeeper/contracts/schemapolicy import checkSchemaPolicy
from ironkeeper/contracts/schemarefs import checkReferencePolicy

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

  ValidationFailureKind* = enum
    ## The kind of a validation failure.
    ##
    ## The kind is a *typed* classification. A consumer never has to
    ## interpret an error message to find out what went wrong, and an
    ## internal defect can never be mistaken for an ordinary rejection.
    vfkNone
      ## No failure.
    vfkUnsupportedDialect
      ## The schema declared a dialect this build does not implement.
    vfkSchemaPolicy
      ## The schema is outside the supported keyword policy.
    vfkReferencePolicy
      ## The schema is outside the supported reference policy.
    vfkInternal
      ## An internal defect occurred while evaluating the schema.

  ValidationOutcome* = object
    ok*: bool
    issues*: seq[SchemaIssue]
    error*: ref Exception
      ## Set when the failure was an internal defect rather than a normal
      ## validation failure.
    failure*: ValidationFailureKind
      ## The typed classification of the failure. It is `vfkNone` when
      ## the outcome is a successful validation.

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
  ## The schema passes three gates before it is used to validate data:
  ##
  ##   1. **meta-validation** against the bundled Draft 2020-12 metaschema;
  ##   2. the **supported schema policy**: every keyword in a
  ##      schema-bearing position must be one Ironkeeper supports, and no
  ##      prohibited construct may appear;
  ##   3. the **reference policy**: every reference must be a local JSON
  ##      Pointer, a local `$anchor`, or the bundled metaschema URI, and
  ##      must resolve to a schema-bearing position.
  ##
  ## Gate 2 is not implied by gate 1. A misspelled keyword is a valid
  ## Draft 2020-12 schema, so meta-validation accepts it and the keyword's
  ## *intent* - a closed object boundary, a numeric bound - is silently
  ## lost. The policy gate rejects it instead.
  ##
  ## Returns an outcome whose `ok` field is true only when the data
  ## satisfies the schema *and* the schema itself is well-formed and inside
  ## the supported subset. `error` is set when an internal defect occurred;
  ## in that case the outcome must be treated as a failure.
  let dialect = draftOf(schema)
  if dialect.len > 0 and dialect != Draft2020_12:
    return ValidationOutcome(
      ok: false,
      failure: vfkUnsupportedDialect,
      error: newException(ValueError,
        "unsupported JSON Schema dialect: " & dialect))

  # Meta-validation first: a schema that is not a valid Draft 2020-12
  # schema is refused as an ordinary validation failure, before the
  # supported-policy gate and before evaluation. This is what neutralises
  # the upstream defect: the Draft 4 boolean form of `exclusiveMaximum`
  # is not a valid 2020-12 schema, so it never reaches the evaluator.
  let meta = metaValidate(v, schema)
  if not meta.ok:
    return ValidationOutcome(ok: false, issues: meta.issues)

  # The supported schema policy. A schema outside the policy is a defect
  # in the schema, not an invalid instance, so it is reported as an
  # internal failure rather than as a list of instance issues.
  let policy = checkSchemaPolicy(schema)
  if not policy.ok:
    var parts = ""
    for issue in policy.issues:
      if parts.len > 0:
        parts.add "; "
      parts.add issue.location & ": " & issue.message
    return ValidationOutcome(
      ok: false,
      failure: vfkSchemaPolicy,
      error: newException(ValueError,
        "the schema is outside the supported schema policy: " & parts))

  # The reference policy. It is checked in the same positions the schema
  # policy uses, so that a `$ref` inside a `const` value is never mistaken
  # for a reference.
  let references = checkReferencePolicy(schema)
  if not references.ok:
    var parts = ""
    for issue in references.issues:
      if parts.len > 0:
        parts.add "; "
      parts.add issue.location & ": " & issue.message
    return ValidationOutcome(
      ok: false,
      failure: vfkReferencePolicy,
      error: newException(ValueError,
        "the schema is outside the supported reference policy: " & parts))

  try:
    let res = validate(data, schema, v.registry)
    var issues: seq[SchemaIssue]
    for e in res.errors:
      issues.add SchemaIssue(location: e.instanceLocation,
                             keywordLocation: e.keywordLocation,
                             message: e.message)
    ValidationOutcome(ok: res.valid, issues: issues)
  except CatchableError as e:
    ValidationOutcome(ok: false, error: e, failure: vfkInternal)
  except Exception as e:
    # Upstream defects (for example the Draft 4 boolean `exclusiveMaximum`
    # dereference) surface as `Defect`, which is not a `CatchableError`.
    # They are converted into an ordinary failure so that a hostile schema
    # can never terminate the process.
    ValidationOutcome(ok: false, error: e, failure: vfkInternal)
