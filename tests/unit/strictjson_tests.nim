## Unit tests for strict JSON ingestion.
##
## These cover the ingestion preconditions that the contract depends on:
## well-formed UTF-8, exactly one JSON value, no trailing content, no
## duplicate member names (including names that are equal only after
## unescaping), no non-finite numbers, and bounded size and depth.

import std/[json]

import testkit
import ironkeeper/json/strictjson

proc runSuite*(): int =
  var t = newTestSuite("strictjson")

  # --- Accepts well-formed documents -------------------------------------
  t.check("accepts an empty object", parseStrict("{}").ok)
  t.check("accepts an empty array", parseStrict("[]").ok)
  t.check("accepts nested structures",
    parseStrict("""{"a":[1,{"b":null}]}""").ok)
  t.check("accepts escaped quotes",
    parseStrict("""{"a":"x\"y"}""").ok)
  t.check("accepts a unicode escape", parseStrict("""{"a":"\u00e9"}""").ok)
  t.check("accepts a surrogate pair",
    parseStrict("""{"a":"\ud83d\ude00"}""").ok)
  t.check("accepts leading whitespace", parseStrict("  \n\t {} \r\n").ok)
  t.check("accepts a negative integer", parseStrict("""{"a":-1}""").ok)
  t.check("accepts an integral value written with an exponent",
    parseStrict("""{"a":1e3}""").ok)

  # The parsed value must reflect the source text exactly.
  let parsed = parseStrict("""{"a":1,"b":"x"}""")
  t.checkEq("parses the member count", parsed.node.len, 2)
  t.checkEq("parses an integer member", $parsed.node["a"], "1")
  t.checkEq("parses a string member", parsed.node["b"].getStr, "x")

  # --- Rejects malformed JSON --------------------------------------------
  t.check("rejects a truncated object", not parseStrict("""{"a":""").ok)
  t.check("rejects a truncated array", not parseStrict("""[1,2""").ok)
  t.check("rejects an unquoted member name", not parseStrict("""{a:1}""").ok)
  t.check("rejects a single-quoted string", not parseStrict("""{'a':1}""").ok)
  t.check("rejects a trailing comma", not parseStrict("""{"a":1,}""").ok)
  t.check("rejects a leading zero", not parseStrict("""{"a":01}""").ok)
  t.check("rejects a leading plus", not parseStrict("""{"a":+1}""").ok)
  t.check("rejects a bare minus", not parseStrict("""{"a":-}""").ok)
  t.check("rejects a missing fraction", not parseStrict("""{"a":1.}""").ok)
  t.check("rejects a missing exponent", not parseStrict("""{"a":1e}""").ok)
  t.check("rejects an unescaped control character",
    not parseStrict("{\"a\":\"x\ty\"}").ok)
  t.check("rejects an invalid escape", not parseStrict("""{"a":"\q"}""").ok)
  t.check("rejects an unpaired high surrogate",
    not parseStrict("""{"a":"\ud83d"}""").ok)
  t.check("rejects an unpaired low surrogate",
    not parseStrict("""{"a":"\ude00"}""").ok)

  # --- Rejects trailing content ------------------------------------------
  t.check("rejects trailing content", not parseStrict("""{} {}""").ok)
  t.check("rejects trailing garbage", not parseStrict("""{}x""").ok)
  t.checkContains("reports the trailing content position",
    parseStrict("""{}x""").error.message, "trailing content")

  # --- Rejects duplicate member names ------------------------------------
  t.check("rejects a duplicate top-level member",
    not parseStrict("""{"a":1,"a":2}""").ok)
  t.checkContains("names the duplicate member",
    parseStrict("""{"a":1,"a":2}""").error.message, "duplicate")
  t.check("rejects a duplicate nested member",
    not parseStrict("""{"o":{"a":1,"a":2}}""").ok)
  # The two names are equal after unescaping, so they collide.
  t.check("rejects a duplicate member written with an escape",
    not parseStrict("""{"a":1,"\u0061":2}""").ok)
  t.check("rejects a duplicate nested member written with an escape",
    not parseStrict("""{"o":{"a":1,"\u0061":2}}""").ok)
  # Distinct members must not collide.
  t.check("accepts distinct members",
    parseStrict("""{"a":1,"b":2}""").ok)

  # --- Rejects invalid UTF-8 ---------------------------------------------
  var invalidUtf8 = "{\"a\":\""
  invalidUtf8.add char(0xC3)   # a lead byte with no continuation
  invalidUtf8.add char(0x28)
  invalidUtf8.add "\"}"
  t.check("rejects invalid UTF-8", not parseStrict(invalidUtf8).ok)
  t.checkContains("reports the UTF-8 problem",
    parseStrict(invalidUtf8).error.message, "UTF-8")

  var overlong = "{\"a\":\""
  overlong.add char(0xC0)
  overlong.add char(0xAF)
  overlong.add "\"}"
  t.check("rejects an overlong UTF-8 encoding", not parseStrict(overlong).ok)

  var surrogate = "{\"a\":\""
  surrogate.add char(0xED)
  surrogate.add char(0xA0)
  surrogate.add char(0x80)
  surrogate.add "\"}"
  t.check("rejects a UTF-8 encoded surrogate", not parseStrict(surrogate).ok)

  # --- Rejects non-finite numbers ----------------------------------------
  t.check("rejects NaN", not parseStrict("""{"a":NaN}""").ok)
  t.check("rejects Infinity", not parseStrict("""{"a":Infinity}""").ok)
  t.check("rejects -Infinity", not parseStrict("""{"a":-Infinity}""").ok)
  t.check("rejects a hex literal", not parseStrict("""{"a":0x10}""").ok)

  # --- Enforces the numeric precision bound ------------------------------
  # 2^53 is exactly representable; 2^53 + 1 is not.
  t.check("accepts 2^53", parseStrict("""{"a":9007199254740992}""").ok)
  t.check("rejects 2^53 + 1",
    not parseStrict("""{"a":9007199254740993}""").ok)
  t.check("rejects a negative value beyond the bound",
    not parseStrict("""{"a":-9007199254740993}""").ok)
  t.check("rejects a float beyond the bound",
    not parseStrict("""{"a":1e300}""").ok)
  t.checkContains("explains the precision bound",
    parseStrict("""{"a":9007199254740993}""").error.message, "2^53")

  # --- The numeric policy is exact, not lossy ----------------------------
  # A value written in a fraction or an exponent must not be rounded into
  # the accepted range. Every mathematically equivalent spelling of the
  # same value must be accepted or rejected together.
  let beyondBound = [
    """{"a":9007199254740993}""",
    """{"a":9007199254740993.0}""",
    """{"a":9.007199254740993e15}""",
    """{"a":9.007199254740993E15}""",
    """{"a":9007199254740993e0}""",
    """{"a":-9007199254740993}""",
    """{"a":-9007199254740993.0}""",
    """{"a":-9.007199254740993e15}""",
  ]
  for lexeme in beyondBound:
    t.check("rejects the out-of-range value " & lexeme,
      not parseStrict(lexeme).ok)

  # A noninteger must not be converted into an integer.
  t.check("rejects a noninteger with 17 significant digits",
    not parseStrict("""{"a":1.00000000000000001}""").ok)
  # A nonzero number must not underflow to zero.
  t.check("rejects a nonzero number that underflows binary64",
    not parseStrict("""{"a":1e-400}""").ok)
  t.check("rejects a fractional number",
    not parseStrict("""{"a":0.1}""").ok)
  t.check("rejects a number that overflows binary64",
    not parseStrict("""{"a":1e309}""").ok)

  # The signed minimum must be rejected as a value, not as an unhandled
  # overflow defect. `abs(int64.low)` raises `OverflowDefect` in Nim.
  t.check("rejects the signed minimum integer without an overflow defect",
    not parseStrict("""{"a":-9223372036854775808}""").ok)
  t.check("rejects a value beyond the signed 64-bit range",
    not parseStrict("""{"a":18446744073709551615}""").ok)

  # Every spelling of the same integral value must yield the same value.
  let spellingsOf100 = [
    """{"a":100}""",
    """{"a":100.0}""",
    """{"a":1e2}""",
    """{"a":10e1}""",
    """{"a":1000e-1}""",
  ]
  for lexeme in spellingsOf100:
    let r = parseStrict(lexeme)
    t.check("accepts the integral value written as " & lexeme, r.ok)
    if r.ok:
      t.checkEq("represents it exactly as 100", $r.node["a"].getInt, "100")

  # An integral value in fraction notation is represented as an integer,
  # never as a rounded float.
  let integralFloat = parseStrict("""{"a":1.0}""")
  t.check("accepts an integral value written as a float", integralFloat.ok)
  if integralFloat.ok:
    t.checkEq("represents it as an integer, not a float",
      $integralFloat.node["a"].kind, "JInt")
  t.check("accepts zero written in fraction notation",
    parseStrict("""{"a":0.0}""").ok)
  t.check("accepts a negative zero as zero",
    parseStrict("""{"a":-0}""").ok)
  let negativeZero = parseStrict("""{"a":-0.0}""")
  if negativeZero.ok:
    t.checkEq("represents a negative zero as zero",
      $negativeZero.node["a"].getInt, "0")

  # --- Enforces the size limit -------------------------------------------
  var tooBig = "["
  for i in 0 ..< MaxDocumentBytes:
    tooBig.add " "
  tooBig.add "]"
  t.check("rejects a document above the size limit",
    not parseStrict(tooBig).ok)
  t.checkContains("reports the size limit",
    parseStrict(tooBig).error.message, "maximum size")

  # --- Enforces the nesting limit ----------------------------------------
  var deep = ""
  for i in 0 ..< MaxNestingDepth + 5:
    deep.add "["
  for i in 0 ..< MaxNestingDepth + 5:
    deep.add "]"
  t.check("rejects a document above the nesting limit",
    not parseStrict(deep).ok)
  t.checkContains("reports the nesting limit",
    parseStrict(deep).error.message, "nesting depth")

  var shallow = ""
  for i in 0 ..< MaxNestingDepth:
    shallow.add "["
  for i in 0 ..< MaxNestingDepth:
    shallow.add "]"
  t.check("accepts a document at the nesting limit",
    parseStrict(shallow).ok)

  t.finish()

