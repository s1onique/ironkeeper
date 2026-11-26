## Unit tests for the fail-closed JSON Schema validation adapter.
##
## The adapter sits between Ironkeeper and the upstream `jschema` library.
## These tests pin down the guarantees the adapter provides:
##
##   * a schema that is not a valid Draft 2020-12 schema is rejected before
##     it is used to validate anything,
##   * a schema that would make the upstream library abort the process is
##     rejected safely,
##   * external references are prohibited,
##   * unsupported dialects are rejected,
##   * data is validated exactly as parsed, with no coercion.

import std/[json]

import testkit
import ironkeeper/contracts/validator

proc runSuite*(): int =
  var t = newTestSuite("validator-adapter")
  let v = newValidator()

  # --- Ordinary validation -----------------------------------------------
  let simple = parseJson("""{"type":"object","required":["a"],"properties":{"a":{"type":"string"}},"additionalProperties":false}""")
  t.check("accepts a valid document",
    v.validateAgainst(parseJson("""{"a":"x"}"""), simple).ok)
  t.check("rejects a document with a missing member",
    not v.validateAgainst(parseJson("""{}"""), simple).ok)
  t.check("rejects a document with an unknown member",
    not v.validateAgainst(parseJson("""{"a":"x","b":1}"""), simple).ok)
  t.check("rejects a document with the wrong member type",
    not v.validateAgainst(parseJson("""{"a":1}"""), simple).ok)

  # A string must not be accepted where a boolean is required.
  let boolSchema = parseJson("""{"type":"object","properties":{"b":{"type":"boolean"}}}""")
  t.check("rejects a string where a boolean is required",
    not v.validateAgainst(parseJson("""{"b":"true"}"""), boolSchema).ok)
  t.check("accepts a boolean",
    v.validateAgainst(parseJson("""{"b":true}"""), boolSchema).ok)

  # An integer must not be accepted where a number is required, and a
  # number with a zero fractional part is an integer.
  let numSchema = parseJson("""{"type":"number"}""")
  t.check("accepts an integer for a number",
    v.validateAgainst(parseJson("1"), numSchema).ok)
  t.check("accepts a float for a number",
    v.validateAgainst(parseJson("1.5"), numSchema).ok)
  t.check("rejects a string for a number",
    not v.validateAgainst(parseJson("\"1\""), numSchema).ok)

  # --- The schema itself must be a valid 2020-12 schema --------------------
  # This is the regression witness for the upstream defect: the Draft 4
  # boolean form of exclusiveMaximum makes the upstream library dereference
  # a boolean as a number and terminate the process. Meta-validation rejects
  # the schema first.
  let badExclusive = parseJson("""{"maximum": 3.0, "exclusiveMaximum": true}""")
  let outcome = v.validateAgainst(parseJson("3"), badExclusive)
  t.check("rejects a schema with a boolean exclusiveMaximum", not outcome.ok)
  t.check("reports it as a validation failure, not a crash",
    outcome.error == nil)

  let badType = parseJson("""{"type":"nonsense"}""")
  t.check("rejects a schema with an unknown type",
    not v.validateAgainst(parseJson("3"), badType).ok)

  let badKeywordType = parseJson("""{"maxLength":"5"}""")
  t.check("rejects a schema with a wrongly typed keyword",
    not v.validateAgainst(parseJson("\"abcde\""), badKeywordType).ok)

  # --- Unsupported dialects are rejected ----------------------------------
  let draft7 = parseJson("""{"$schema":"http://json-schema.org/draft-07/schema#","type":"string"}""")
  let dialectOutcome = v.validateAgainst(parseJson("\"x\""), draft7)
  t.check("rejects an unsupported dialect", not dialectOutcome.ok)
  t.checkContains("names the unsupported dialect",
    dialectOutcome.error.msg, "unsupported JSON Schema dialect")

  # --- External references are prohibited ---------------------------------
  let external = parseJson("""{"$ref":"https://example.invalid/other.json"}""")
  let extOutcome = v.validateAgainst(parseJson("{}"), external)
  t.check("rejects an external reference", not extOutcome.ok)
  t.checkContains("explains why",
    extOutcome.error.msg, "external schema reference is not permitted")

  # A local reference is allowed.
  let local = parseJson("""{"$defs":{"s":{"type":"string"}},"$ref":"#/$defs/s"}""")
  t.check("accepts a local reference",
    v.validateAgainst(parseJson("\"x\""), local).ok)
  t.check("rejects data that violates a local reference",
    not v.validateAgainst(parseJson("1"), local).ok)

  # --- Numeric bounds ------------------------------------------------------
  let bounded = parseJson("""{"type":"integer","minimum":0,"maximum":10}""")
  t.check("accepts a value inside the bounds",
    v.validateAgainst(parseJson("5"), bounded).ok)
  t.check("rejects a value above the bound",
    not v.validateAgainst(parseJson("11"), bounded).ok)
  t.check("rejects a value below the bound",
    not v.validateAgainst(parseJson("-1"), bounded).ok)

  # --- Enumerations and constants -----------------------------------------
  let enumSchema = parseJson("""{"enum":["a","b"]}""")
  t.check("accepts a member of the enumeration",
    v.validateAgainst(parseJson("\"a\""), enumSchema).ok)
  t.check("rejects a value outside the enumeration",
    not v.validateAgainst(parseJson("\"c\""), enumSchema).ok)

  let constSchema = parseJson("""{"const":42}""")
  t.check("accepts the constant value",
    v.validateAgainst(parseJson("42"), constSchema).ok)
  t.check("rejects a different value",
    not v.validateAgainst(parseJson("43"), constSchema).ok)

  # --- Array constraints ----------------------------------------------------
  let arraySchema = parseJson("""{"type":"array","minItems":1,"maxItems":2,"uniqueItems":true}""")
  t.check("accepts an array within the bounds",
    v.validateAgainst(parseJson("[1,2]"), arraySchema).ok)
  t.check("rejects an empty array",
    not v.validateAgainst(parseJson("[]"), arraySchema).ok)
  t.check("rejects a long array",
    not v.validateAgainst(parseJson("[1,2,3]"), arraySchema).ok)
  t.check("rejects duplicate items",
    not v.validateAgainst(parseJson("[1,1]"), arraySchema).ok)

  # --- Composition ----------------------------------------------------------
  let allOfSchema = parseJson("""{"allOf":[{"type":"string"},{"minLength":2}]}""")
  t.check("accepts a value satisfying every branch",
    v.validateAgainst(parseJson("\"ab\""), allOfSchema).ok)
  t.check("rejects a value failing one branch",
    not v.validateAgainst(parseJson("\"a\""), allOfSchema).ok)

  let anyOfSchema = parseJson("""{"anyOf":[{"type":"string"},{"type":"integer"}]}""")
  t.check("accepts a value satisfying one branch",
    v.validateAgainst(parseJson("1"), anyOfSchema).ok)

  let oneOfSchema = parseJson("""{"oneOf":[{"type":"string"},{"minLength":2}]}""")
  t.check("rejects a value satisfying more than one branch",
    not v.validateAgainst(parseJson("\"ab\""), oneOfSchema).ok)
  t.check("accepts a value satisfying exactly one branch",
    v.validateAgainst(parseJson("\"a\""), oneOfSchema).ok)

  # --- No implicit coercion -------------------------------------------------
  let strictString = parseJson("""{"type":"string"}""")
  t.check("does not coerce a number to a string",
    not v.validateAgainst(parseJson("1"), strictString).ok)
  t.check("does not coerce a boolean to a string",
    not v.validateAgainst(parseJson("true"), strictString).ok)

  t.finish()

