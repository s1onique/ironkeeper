## Strict JSON ingestion for Ironkeeper.
##
## `std/json` is deliberately permissive: it accepts duplicate member names
## (last one wins), silently accepts trailing content, and happily produces
## `NaN`/`Infinity` values from non-standard numeric literals. Ironkeeper
## treats every one of those as a distinct, observable failure, because a
## document whose meaning depends on parser implementation details is not
## auditable evidence.
##
## This module implements a small, strict, deterministic reader over the raw
## bytes of a document. It enforces, in this order:
##
##   1. The input is well-formed UTF-8 (no overlong forms, no surrogates,
##      no code points above U+10FFFF).
##   2. The input contains exactly one JSON value.
##   3. No trailing non-whitespace content follows that value.
##   4. No object contains the same member name twice. Two names that are
##      equal after JSON string unescaping are the same name, so `"\u0061"`
##      and `"a"` collide.
##   5. No number is non-finite, and every number is classified *exactly*
##      from its source text. A value that cannot be represented exactly is
##      rejected; it is never rounded into the accepted range.
##
## The result is a `JsonNode` tree whose numbers are exact with respect to
## the source text: an integral value that fits in `int64` becomes `JInt`,
## everything else is rejected. The exact classification lives in
## `exactnumber.nim`, which documents the numeric policy.

import std/[json, unicode, tables]

from ironkeeper/json/exactnumber import classifyExact, toInt64, MaxExactIntMagnitude

const
  MaxDocumentBytes* = 4 * 1024 * 1024
    ## Hard upper bound on the size of a JSON document that will be ingested.
    ##
    ## Documented in `docs/architecture/overview.md` as part of the public
    ## resource limits. A larger input is rejected before any parsing work
    ## is done.

  MaxNestingDepth* = 64
    ## Hard upper bound on the nesting depth of a JSON document.
    ##
    ## Bounds stack usage of the recursive descent parser and prevents
    ## pathological nesting from being used to exhaust memory.

type
  StrictJsonError* = object
    ## A classified strict-ingestion failure.
    message*: string
    offset*: int
      ## Byte offset into the source where the failure was detected.

  StrictJsonResult* = object
    ok*: bool
    node*: JsonNode
    error*: StrictJsonError

proc failed*(msg: string, offset = 0): StrictJsonResult =
  StrictJsonResult(ok: false, error: StrictJsonError(message: msg, offset: offset))

proc succeeded*(node: JsonNode): StrictJsonResult =
  StrictJsonResult(ok: true, node: node)

proc isValidUtf8*(s: string): bool =
  ## Strict UTF-8 well-formedness check.
  ##
  ## Rejects overlong encodings, UTF-16 surrogate code points, and code
  ## points above U+10FFFF.
  var i = 0
  let n = s.len
  while i < n:
    let b0 = s[i].ord
    if b0 < 0x80:
      inc i
    elif b0 in 0xC2..0xDF:
      if i + 1 >= n: return false
      if s[i+1].ord notin 0x80..0xBF: return false
      i += 2
    elif b0 == 0xE0:
      if i + 2 >= n: return false
      if s[i+1].ord notin 0xA0..0xBF: return false
      if s[i+2].ord notin 0x80..0xBF: return false
      i += 3
    elif b0 in 0xE1..0xEC:
      if i + 2 >= n: return false
      if s[i+1].ord notin 0x80..0xBF: return false
      if s[i+2].ord notin 0x80..0xBF: return false
      i += 3
    elif b0 == 0xED:
      # Exclude UTF-16 surrogates U+D800..U+DFFF.
      if i + 2 >= n: return false
      if s[i+1].ord notin 0x80..0x9F: return false
      if s[i+2].ord notin 0x80..0xBF: return false
      i += 3
    elif b0 in 0xEE..0xEF:
      if i + 2 >= n: return false
      if s[i+1].ord notin 0x80..0xBF: return false
      if s[i+2].ord notin 0x80..0xBF: return false
      i += 3
    elif b0 == 0xF0:
      if i + 3 >= n: return false
      if s[i+1].ord notin 0x90..0xBF: return false
      if s[i+2].ord notin 0x80..0xBF: return false
      if s[i+3].ord notin 0x80..0xBF: return false
      i += 4
    elif b0 in 0xF1..0xF3:
      if i + 3 >= n: return false
      if s[i+1].ord notin 0x80..0xBF: return false
      if s[i+2].ord notin 0x80..0xBF: return false
      if s[i+3].ord notin 0x80..0xBF: return false
      i += 4
    elif b0 == 0xF4:
      if i + 3 >= n: return false
      if s[i+1].ord notin 0x80..0x8F: return false
      if s[i+2].ord notin 0x80..0xBF: return false
      if s[i+3].ord notin 0x80..0xBF: return false
      i += 4
    else:
      return false
  true

# ---------------------------------------------------------------------------
# Recursive descent reader
# ---------------------------------------------------------------------------

type
  StrictReader = object
    src: string
    pos: int
    depth: int

  ReaderError = object
    msg: string
    offset: int

  ParseOutcome = object
    ok: bool
    node: JsonNode
    err: ReaderError

const
  JsonWs = {' ', '\t', '\n', '\r'}

proc fail(r: var StrictReader, msg: string): ParseOutcome =
  ParseOutcome(ok: false, err: ReaderError(msg: msg, offset: r.pos))

proc atEnd(r: StrictReader): bool = r.pos >= r.src.len

proc peek(r: var StrictReader): char =
  if atEnd(r): '\0' else: r.src[r.pos]

proc skipWs(r: var StrictReader) =
  while not atEnd(r) and r.src[r.pos] in JsonWs:
    inc r.pos

proc expect(r: var StrictReader, c: char): ParseOutcome =
  if atEnd(r):
    return fail(r, "unexpected end of input, expected '" & c & "'")
  if r.src[r.pos] != c:
    return fail(r, "expected '" & c & "' at offset " & $r.pos)
  inc r.pos
  ParseOutcome(ok: true, node: newJNull())

proc parseValue(r: var StrictReader): ParseOutcome

proc parseString(r: var StrictReader): ParseOutcome =
  ## Parse a JSON string, rejecting raw control characters and unescaping
  ## according to RFC 8259. `\u` escapes are decoded to UTF-8 so that the
  ## resulting member name compares equal to its literal spelling.
  let start = r.pos
  inc r.pos # opening quote
  var text = ""
  while true:
    if atEnd(r):
      r.pos = start
      return fail(r, "unterminated string")
    let c = r.src[r.pos]
    if c == '"':
      inc r.pos
      return ParseOutcome(ok: true, node: newJString(text))
    elif c == '\\':
      inc r.pos
      if atEnd(r):
        r.pos = start
        return fail(r, "unterminated escape sequence")
      let e = r.src[r.pos]
      inc r.pos
      case e
      of '"': text.add '"'
      of '\\': text.add '\\'
      of '/': text.add '/'
      of 'b': text.add '\b'
      of 'f': text.add '\f'
      of 'n': text.add '\n'
      of 'r': text.add '\r'
      of 't': text.add '\t'
      of 'u':
        if r.pos + 4 > r.src.len:
          r.pos = start
          return fail(r, "truncated \\u escape")
        let hex = r.src[r.pos ..< r.pos + 4]
        var cp = 0
        for ch in hex:
          let d = case ch
            of '0'..'9': ch.ord - '0'.ord
            of 'a'..'f': ch.ord - 'a'.ord + 10
            of 'A'..'F': ch.ord - 'A'.ord + 10
            else: -1
          if d < 0:
            r.pos = start
            return fail(r, "invalid \\u escape: " & hex)
          cp = cp * 16 + d
        r.pos += 4
        if cp in 0xD800..0xDBFF:
          # High surrogate: a low surrogate must follow.
          if r.pos + 6 > r.src.len or r.src[r.pos] != '\\' or r.src[r.pos+1] != 'u':
            r.pos = start
            return fail(r, "unpaired high surrogate in \\u escape")
          let hex2 = r.src[r.pos + 2 ..< r.pos + 6]
          var lo = 0
          for ch in hex2:
            let d = case ch
              of '0'..'9': ch.ord - '0'.ord
              of 'a'..'f': ch.ord - 'a'.ord + 10
              of 'A'..'F': ch.ord - 'A'.ord + 10
              else: -1
            if d < 0:
              r.pos = start
              return fail(r, "invalid \\u escape: " & hex2)
            lo = lo * 16 + d
          if lo notin 0xDC00..0xDFFF:
            r.pos = start
            return fail(r, "invalid low surrogate in \\u escape")
          r.pos += 6
          cp = 0x10000 + ((cp - 0xD800) shl 10) + (lo - 0xDC00)
        elif cp in 0xDC00..0xDFFF:
          r.pos = start
          return fail(r, "unpaired low surrogate in \\u escape")
        text.add Rune(cp).toUTF8
      else:
        r.pos = start
        return fail(r, "invalid escape character: \\" & e)
    elif c.ord < 0x20:
      r.pos = start
      return fail(r, "unescaped control character in string")
    else:
      text.add c
      inc r.pos

proc parseNumber(r: var StrictReader): ParseOutcome =
  ## Parse a JSON number per RFC 8259.
  ##
  ## Rejects the non-standard `NaN`/`Infinity` literals, leading `+`, leading
  ## zeroes, and a bare `-`.
  ##
  ## The value is classified **exactly**, from its source text, by
  ## `classifyExact`. No binary64 conversion happens before the range
  ## decision, so a value can never be rounded into the accepted range, a
  ## noninteger can never become an integer, and a nonzero number can never
  ## become zero. See `exactnumber.nim` for the policy.
  let start = r.pos
  if peek(r) == '-':
    inc r.pos
  # Integer part.
  if atEnd(r):
    r.pos = start
    return fail(r, "truncated number")
  if r.src[r.pos] == '0':
    inc r.pos
    if not atEnd(r) and r.src[r.pos] in {'0'..'9'}:
      r.pos = start
      return fail(r, "number has a leading zero")
  elif r.src[r.pos] in {'1'..'9'}:
    while not atEnd(r) and r.src[r.pos] in {'0'..'9'}:
      inc r.pos
  else:
    r.pos = start
    return fail(r, "invalid number")
  var isFloat = false
  if not atEnd(r) and r.src[r.pos] == '.':
    isFloat = true
    inc r.pos
    if atEnd(r) or r.src[r.pos] notin {'0'..'9'}:
      r.pos = start
      return fail(r, "number has no digits after the decimal point")
    while not atEnd(r) and r.src[r.pos] in {'0'..'9'}:
      inc r.pos
  if not atEnd(r) and (r.src[r.pos] == 'e' or r.src[r.pos] == 'E'):
    isFloat = true
    inc r.pos
    if not atEnd(r) and (r.src[r.pos] == '+' or r.src[r.pos] == '-'):
      inc r.pos
    if atEnd(r) or r.src[r.pos] notin {'0'..'9'}:
      r.pos = start
      return fail(r, "number has no digits in the exponent")
    while not atEnd(r) and r.src[r.pos] in {'0'..'9'}:
      inc r.pos
  let lexeme = r.src[start ..< r.pos]

  # Exact classification, from the source text.
  let exact = classifyExact(lexeme)
  if not exact.ok:
    r.pos = start
    return fail(r, exact.error.message)
  if not exact.isIntegral:
    r.pos = start
    return fail(r, "number is not an integer and cannot be represented " &
      "exactly: " & lexeme)

  # `isFloat` records how the value was *written*. An integral value that
  # was written in fraction or exponent notation is accepted and is
  # represented exactly as an integer, because the exact classification
  # has already established that it denotes an integer.
  discard isFloat

  ParseOutcome(ok: true, node: newJInt(exact.toInt64))

proc parseObject(r: var StrictReader): ParseOutcome =
  ## Parse a JSON object, rejecting duplicate member names.
  inc r.pos # opening brace
  var fields: OrderedTable[string, JsonNode]
  skipWs(r)
  if peek(r) == '}':
    inc r.pos
    var emptyObj = newJObject()
    for k, v in fields: emptyObj[k] = v
    return ParseOutcome(ok: true, node: emptyObj)
  while true:
    skipWs(r)
    if peek(r) != '"':
      return fail(r, "expected a member name string at offset " & $r.pos)
    let keyRes = parseString(r)
    if not keyRes.ok:
      return keyRes
    let key = keyRes.node.getStr
    skipWs(r)
    let colon = expect(r, ':')
    if not colon.ok:
      return colon
    let valRes = parseValue(r)
    if not valRes.ok:
      return valRes
    if key in fields:
      return fail(r, "duplicate object member name: " & key)
    fields[key] = valRes.node
    skipWs(r)
    let c = peek(r)
    if c == ',':
      inc r.pos
      continue
    elif c == '}':
      inc r.pos
      var obj = newJObject()
      for k, v in fields: obj[k] = v
      return ParseOutcome(ok: true, node: obj)
    else:
      return fail(r, "expected ',' or '}' at offset " & $r.pos)

proc parseArray(r: var StrictReader): ParseOutcome =
  inc r.pos # opening bracket
  var elems: seq[JsonNode]
  skipWs(r)
  if peek(r) == ']':
    inc r.pos
    var emptyArr = newJArray()
    for e in elems: emptyArr.add e
    return ParseOutcome(ok: true, node: emptyArr)
  while true:
    let valRes = parseValue(r)
    if not valRes.ok:
      return valRes
    elems.add valRes.node
    skipWs(r)
    let c = peek(r)
    if c == ',':
      inc r.pos
      continue
    elif c == ']':
      inc r.pos
      var arr = newJArray()
      for e in elems: arr.add e
      return ParseOutcome(ok: true, node: arr)
    else:
      return fail(r, "expected ',' or ']' at offset " & $r.pos)

proc parseLiteral(r: var StrictReader, lit: string, node: JsonNode): ParseOutcome =
  if r.pos + lit.len > r.src.len or r.src[r.pos ..< r.pos + lit.len] != lit:
    return fail(r, "invalid literal at offset " & $r.pos)
  r.pos += lit.len
  ParseOutcome(ok: true, node: node)

proc parseValue(r: var StrictReader): ParseOutcome =
  ## Parse any JSON value, tracking nesting depth.
  inc r.depth
  defer: dec r.depth
  if r.depth > MaxNestingDepth:
    return fail(r, "maximum nesting depth (" & $MaxNestingDepth & ") exceeded")
  skipWs(r)
  if atEnd(r):
    return fail(r, "unexpected end of input")
  case peek(r)
  of '{': parseObject(r)
  of '[': parseArray(r)
  of '"': parseString(r)
  of 't': parseLiteral(r, "true", newJBool(true))
  of 'f': parseLiteral(r, "false", newJBool(false))
  of 'n': parseLiteral(r, "null", newJNull())
  of '-', '0'..'9': parseNumber(r)
  else:
    fail(r, "unexpected character at offset " & $r.pos)

proc parseStrict*(src: string): StrictJsonResult =
  ## Parse `src` under Ironkeeper's strict ingestion rules.
  ##
  ## Returns a `StrictJsonResult`. On failure `error.message` describes the
  ## problem and `error.offset` is the byte offset at which it was detected.
  if src.len > MaxDocumentBytes:
    return failed("document exceeds the maximum size of " & $MaxDocumentBytes & " bytes")
  if not isValidUtf8(src):
    return failed("document is not valid UTF-8")
  var r = StrictReader(src: src, pos: 0, depth: 0)
  let res = parseValue(r)
  if not res.ok:
    return failed(res.err.msg, res.err.offset)
  skipWs(r)
  if not atEnd(r):
    return failed("trailing content after the JSON document at offset " & $r.pos, r.pos)
  succeeded(res.node)
