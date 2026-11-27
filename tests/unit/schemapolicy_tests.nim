## Tests for the supported schema policy and the reference policy.
##
## The two policies must agree about where a keyword may appear. A
## keyword-shaped *name* is data; a keyword in a schema-bearing position
## is a keyword. The reference policy in particular must not treat a
## `$ref` inside a `const` value or an `examples` array as a reference,
## because those are values, not schemas.

import std/[json]

import testkit

from ironkeeper/contracts/schemapolicy import checkSchemaPolicy
from ironkeeper/contracts/schemarefs import checkReferencePolicy

proc accepts(schema: string): bool =
  ## True when the schema satisfies the supported keyword policy.
  checkSchemaPolicy(parseJson(schema)).ok

proc refuses(schema: string): bool =
  ## True when the schema violates the supported keyword policy.
  not checkSchemaPolicy(parseJson(schema)).ok

proc refAccepts(schema: string): bool =
  ## True when the schema satisfies the supported reference policy.
  checkReferencePolicy(parseJson(schema)).ok

proc refRefuses(schema: string): bool =
  ## True when the schema violates the supported reference policy.
  not checkReferencePolicy(parseJson(schema)).ok

proc runSuite*(): int =
  var t = newTestSuite("schemapolicy")

  # --- keyword-shaped names are data ---------------------------------------
  t.check("a property named like a keyword is accepted",
          accepts("""{"type":"object","properties":{"minimun":{"type":"integer"}}}"""))
  t.check("a property named $ref is accepted",
          accepts("""{"type":"object","properties":{"$ref":{"type":"string"}}}"""))
  t.check("a property named $id is accepted",
          accepts("""{"type":"object","properties":{"$id":{"type":"string"}}}"""))

  # A keyword in a schema-bearing position is a keyword.
  t.check("an unknown keyword in a schema position is refused",
          refuses("""{"type":"object","additionalPropeties":false}"""))
  t.check("an unknown keyword in a subschema is refused",
          refuses("""{"type":"object","properties":{"a":{"minimun":10}}}"""))
  t.check("a known keyword in a subschema is accepted",
          accepts("""{"type":"object","properties":{"a":{"minimum":10}}}"""))

  # --- the reference policy is position-aware ------------------------------
  # A `$ref` inside a literal `const` object is a value.
  t.check("a $ref inside a const object is data, not a reference",
          refAccepts("""{"const":{"$ref":"https://example.invalid/x.json"}}"""))
  # A `$ref` inside `examples` is a value.
  t.check("a $ref inside examples is data, not a reference",
          refAccepts("""{"examples":[{"$ref":"https://example.invalid/x.json"}]}"""))
  t.check("a $ref inside a default is data, not a reference",
          refAccepts("""{"default":{"$ref":"#/$defs/x"}}"""))

  # --- permitted and refused references ------------------------------------
  t.check("a local JSON Pointer is permitted",
          refAccepts("""{"$defs":{"x":{"type":"string"}},"$ref":"#/$defs/x"}"""))
  t.check("a local anchor is permitted",
          refAccepts("""{"$defs":{"x":{"$anchor":"x","type":"string"}},"$ref":"#x"}"""))
  t.check("the bundled metaschema is permitted",
          refAccepts("""{"$ref":"https://json-schema.org/draft/2020-12/schema"}"""))

  t.check("an external reference is refused",
          refRefuses("""{"$ref":"https://example.invalid/x.json"}"""))
  t.check("a relative external reference is refused",
          refRefuses("""{"$ref":"other.json"}"""))
  t.check("a dynamic reference is refused",
          refRefuses("""{"$dynamicRef":"#node"}"""))
  t.check("a dynamic anchor is refused",
          refRefuses("""{"$defs":{"x":{"$dynamicAnchor":"node"}}}"""))

  # --- unresolvable and non-schema targets --------------------------------
  t.check("an unresolvable local reference is a defect",
          refRefuses("""{"$ref":"#/$defs/missing"}"""))
  t.check("a local reference to a non-schema-bearing position is refused",
          refRefuses("""{"const":{"a":1},"$ref":"#/const"}"""))
  t.check("a local reference to a schema-bearing position is accepted",
          refAccepts("""{"$defs":{"x":{"type":"string"}},"$ref":"#/$defs/x"}"""))
  t.check("an anchor that does not exist is a defect",
          refRefuses("""{"$ref":"#missing"}"""))

  # --- nested identifiers ---------------------------------------------------
  t.check("a nested $id is refused",
          refRefuses("""{"$defs":{"x":{"$id":"https://example.invalid/x"}}}"""))
  t.check("a root $id is accepted",
          refAccepts("""{"$id":"https://ironkeeper.invalid/schemas/v1/x.json","type":"string"}"""))
  t.check("a nested $vocabulary is refused",
          refRefuses("""{"$defs":{"x":{"$vocabulary":{"https://json-schema.org/draft/2020-12/vocab/validation":true}}}}"""))
  t.check("a root $vocabulary is accepted",
          refAccepts("""{"$vocabulary":{"https://json-schema.org/draft/2020-12/vocab/validation":true}}"""))

  t.finish()
