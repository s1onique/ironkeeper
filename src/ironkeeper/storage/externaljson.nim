## Lossless ingestion of *external* JSON.
##
## Ironkeeper's own contracts use a strict numeric policy: an integer that
## does not fit in `int64`, or that exceeds 2^53, is rejected. That policy
## is **not** applied to third-party telemetry. A `smartctl -x -j` response
## may legitimately contain a counter that exceeds an unsigned 64-bit
## integer, and it may contain it in several representations at once.
##
## This module therefore implements a *separate*, lossless reader:
##
##   1. the raw bytes are preserved by the caller;
##   2. the encoding is validated (strict UTF-8: no overlong forms, no
##      surrogates, no code points above U+10FFFF);
##   3. the JSON syntax is validated, and **duplicate object member names
##      are detected before any information is lost**;
##   4. every number keeps its **exact source lexeme**, so no value ever
##      passes through a binary64 conversion;
##   5. the tree is read-only and ordered.
##
## ## The UTF-8 collision follow-up
##
## The foundation left one open item: two distinct external member names
## that repair to the same text were not distinguished. This module closes
## it by **never repairing** an external member name. A name that is not
## valid UTF-8 is a rejected document, not a repaired one, so two distinct
## names can never collapse into one. The names are also compared *after*
## JSON unescaping, so `"\u0061"` and `"a"` are the same name and are
## rejected as a duplicate.

import std/[strutils, unicode, tables]

from ironkeeper/json/strictjson import isValidUtf8

const
  MaxExternalDocumentBytes* = 16 * 1024 * 1024
    ## The bound on the size of an external JSON document.
  MaxExternalDepth* = 64
    ## The bound on the nesting depth of an external JSON document.

type
  ExtKind* = enum
    ## The kind of an external JSON value.
    ekNull
    ekBool
    ekNumber
    ekString
    ekArray
    ekObject

  ExtNode* = ref object
    ## One node of a losslessly ingested external JSON document.
    kind*: ExtKind
    str*: string
      ## The string value, or the exact number lexeme.
    boolean*: bool
    items*: seq[ExtNode]
      ## The elements of an array.
    members*: seq[tuple[key: string, value: ExtNode]]
      ## The members of an object, in document order.

  ExtJsonError* = object
    ## A classified ingestion failure.
    message*: string
    offset*: int

  ExtJsonResult* = object
    ## The outcome of a lossless ingestion.
    ok*: bool
    root*: ExtNode
    error*: ExtJsonError

  ExtReader = object
    src: string
    pos: int
    depth: int

proc failed(msg: string, offset = 0): ExtJsonResult =
  ExtJsonResult(ok: false, error: ExtJsonError(message: msg, offset: offset))

proc atEnd(r: ExtReader): bool = r.pos >= r.src.len

proc peek(r: ExtReader): char =
  if atEnd(r): '\0' else: r.src[r.pos]

proc skipWs(r: var ExtReader) =
  while not atEnd(r) and r.src[r.pos] in {' ', '\t', '\n', '\r'}:
    inc r.pos

proc failAt(r: var ExtReader, msg: string): ExtJsonResult =
  failed(msg, r.pos)

proc parseExtValue(r: var ExtReader): ExtJsonResult

proc parseExtString(r: var ExtReader): ExtJsonResult =
  ## Parse a JSON string, rejecting raw control characters.
  let start = r.pos
  inc r.pos # opening quote
  var text = ""
  while true:
    if atEnd(r):
      r.pos = start
      return failAt(r, "unterminated string")
    let c = r.src[r.pos]
    if c == '"':
      inc r.pos
      var node = ExtNode(kind: ekString, str: text)
      return ExtJsonResult(ok: true, root: node)
    elif c == '\\':
      inc r.pos
      if atEnd(r):
        r.pos = start
        return failAt(r, "unterminated escape sequence")
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
          return failAt(r, "truncated \\u escape")
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
            return failAt(r, "invalid \\u escape: " & hex)
          cp = cp * 16 + d
        r.pos += 4
        if cp in 0xD800..0xDBFF:
          if r.pos + 6 > r.src.len or r.src[r.pos] != '\\' or r.src[r.pos+1] != 'u':
            r.pos = start
            return failAt(r, "unpaired high surrogate in \\u escape")
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
              return failAt(r, "invalid low surrogate in \\u escape")
            lo = lo * 16 + d
          if lo notin 0xDC00..0xDFFF:
            r.pos = start
            return failAt(r, "unpaired high surrogate in \\u escape")
          r.pos += 6
          cp = 0x10000 + ((cp - 0xD800) shl 10) + (lo - 0xDC00)
        elif cp in 0xDC00..0xDFFF:
          r.pos = start
          return failAt(r, "unpaired low surrogate in \\u escape")
        text.add Rune(cp).toUTF8
      else:
        r.pos = start
        return failAt(r, "invalid escape character: \\" & e)
    elif c.ord < 0x20:
      r.pos = start
      return failAt(r, "unescaped control character in string")
    else:
      text.add c
      inc r.pos

proc parseExtNumber(r: var ExtReader): ExtJsonResult =
  ## Parse a JSON number and keep its **exact** source lexeme.
  ##
  ## No conversion happens here at all: the lexeme is the value. The
  ## consumer decides whether the number is integral, and the exact
  ## decimal value is computed from the digits when it is needed.
  let start = r.pos
  if not atEnd(r) and r.src[r.pos] == '-':
    inc r.pos
  if atEnd(r):
    r.pos = start
    return failAt(r, "truncated number")
  if r.src[r.pos] == '0':
    inc r.pos
    if not atEnd(r) and r.src[r.pos] in {'0' .. '9'}:
      r.pos = start
      return failAt(r, "number has a leading zero")
  elif r.src[r.pos] in {'1' .. '9'}:
    while not atEnd(r) and r.src[r.pos] in {'0' .. '9'}:
      inc r.pos
  else:
    r.pos = start
    return failAt(r, "invalid number")
  if not atEnd(r) and r.src[r.pos] == '.':
    inc r.pos
    if atEnd(r) or r.src[r.pos] notin {'0' .. '9'}:
      r.pos = start
      return failAt(r, "number has no digits after the decimal point")
    while not atEnd(r) and r.src[r.pos] in {'0' .. '9'}:
      inc r.pos
  if not atEnd(r) and (r.src[r.pos] == 'e' or r.src[r.pos] == 'E'):
    inc r.pos
    if not atEnd(r) and (r.src[r.pos] == '+' or r.src[r.pos] == '-'):
      inc r.pos
    if atEnd(r) or r.src[r.pos] notin {'0' .. '9'}:
      r.pos = start
      return failAt(r, "number has no digits in the exponent")
    while not atEnd(r) and r.src[r.pos] in {'0' .. '9'}:
      inc r.pos
  let lexeme = r.src[start ..< r.pos]
  var node = ExtNode(kind: ekNumber, str: lexeme)
  ExtJsonResult(ok: true, root: node)

proc parseExtObject(r: var ExtReader): ExtJsonResult =
  ## Parse an object, rejecting duplicate member names.
  inc r.pos # opening brace
  var members: seq[tuple[key: string, value: ExtNode]] = @[]
  var seen = initTable[string, bool]()
  skipWs(r)
  if peek(r) == '}':
    inc r.pos
    var node = ExtNode(kind: ekObject, members: members)
    return ExtJsonResult(ok: true, root: node)
  while true:
    skipWs(r)
    if peek(r) != '"':
      return failAt(r, "expected a member name string")
    let keyRes = parseExtString(r)
    if not keyRes.ok:
      return keyRes
    let key = keyRes.root.str
    if seen.hasKey(key):
      r.pos = 0
      return failed("duplicate object member name: " & key)
    seen[key] = true
    skipWs(r)
    if peek(r) != ':':
      return failAt(r, "expected ':'")
    inc r.pos
    let valueRes = parseExtValue(r)
    if not valueRes.ok:
      return valueRes
    members.add (key: key, value: valueRes.root)
    skipWs(r)
    let c = peek(r)
    if c == ',':
      inc r.pos
      continue
    elif c == '}':
      inc r.pos
      var node = ExtNode(kind: ekObject, members: members)
      return ExtJsonResult(ok: true, root: node)
    else:
      return failAt(r, "expected ',' or '}'")

proc parseExtArray(r: var ExtReader): ExtJsonResult =
  ## Parse an array.
  inc r.pos # opening bracket
  var items: seq[ExtNode] = @[]
  skipWs(r)
  if peek(r) == ']':
    inc r.pos
    var node = ExtNode(kind: ekArray, items: items)
    return ExtJsonResult(ok: true, root: node)
  while true:
    let valueRes = parseExtValue(r)
    if not valueRes.ok:
      return valueRes
    items.add valueRes.root
    skipWs(r)
    let c = peek(r)
    if c == ',':
      inc r.pos
      continue
    elif c == ']':
      inc r.pos
      var node = ExtNode(kind: ekArray, items: items)
      return ExtJsonResult(ok: true, root: node)
    else:
      return failAt(r, "expected ',' or ']'")

proc parseExtLiteral(r: var ExtReader, lit: string, kind: ExtKind,
                     boolean: bool): ExtJsonResult =
  if r.pos + lit.len > r.src.len or r.src[r.pos ..< r.pos + lit.len] != lit:
    return failAt(r, "invalid literal")
  r.pos += lit.len
  var node = ExtNode(kind: kind, boolean: boolean)
  ExtJsonResult(ok: true, root: node)

proc member*(node: ExtNode, key: string): ExtNode =
  ## The member of an object with the given name, or nil.
  if node.isNil or node.kind != ekObject:
    return nil
  for m in node.members:
    if m.key == key:
      return m.value
  nil

proc hasMember*(node: ExtNode, key: string): bool =
  ## True when an object carries the named member.
  not member(node, key).isNil

proc asString*(node: ExtNode): string =
  ## The string value of a node, or the empty string.
  if node.isNil:
    return ""
  if node.kind == ekString:
    return node.str
  if node.kind == ekNumber:
    return node.str
  ""

proc decMulAddSmall(text: string, mul: int, add: int): string =
  ## Multiply a canonical non-negative decimal string by `mul` and add `add`.
  ##
  ## This is exact decimal arithmetic on strings: no value ever passes
  ## through a binary64 conversion, so a counter with more than 2^53
  ## significant digits keeps every digit.
  var digitsText = text
  if digitsText.len == 0:
    digitsText = "0"
  var carry = add
  var digitsOut = ""
  for i in countdown(digitsText.len - 1, 0):
    let d = (digitsText[i].ord - '0'.ord) * mul + carry
    carry = d div 10
    digitsOut.add $(d mod 10)
  while carry > 0:
    digitsOut.add $(carry mod 10)
    carry = carry div 10
  var result = ""
  for i in countdown(digitsOut.len - 1, 0):
    result.add digitsOut[i]
  # Only the **leading** zeros are removed. A trailing zero is a
  # significant digit: `10 * 10` is `100`, not `1`.
  var lead = 0
  while lead < result.len - 1 and result[lead] == '0':
    inc lead
  let trimmed = result[lead .. ^1]
  if trimmed.len == 0:
    "0" else: trimmed

proc hexToDecimal*(hex: string): string =
  ## Convert a hexadecimal digit string to an exact decimal string.
  ##
  ## Returns the empty string when the input is not a hexadecimal number.
  let text = hex.strip()
  if text.len == 0:
    return ""
  var value = "0"
  for ch in text:
    let d = case ch
      of '0'..'9': ch.ord - '0'.ord
      of 'a'..'f': ch.ord - 'a'.ord + 10
      of 'A'..'F': ch.ord - 'A'.ord + 10
      else: return ""
    value = decMulAddSmall(value, 16, d)
  value

proc exactIntegerText*(lexeme: string): string =
  ## The canonical decimal text of an integral number, or the empty string.
  ##
  ## The number is analysed **from its digits**. A value that is written
  ## with a fraction or an exponent is integral only when its scale is
  ## non-negative or when the implied trailing digits are zero. A
  ## non-integral value yields the empty string: it is not rounded.
  let text = lexeme.strip()
  if text.len == 0:
    return ""
  var negative = false
  var idx = 0
  if text[0] == '-':
    negative = true
    idx = 1
  elif text[0] == '+':
    idx = 1
  if idx >= text.len:
    return ""
  let intStart = idx
  while idx < text.len and text[idx] in {'0' .. '9'}:
    inc idx
  let intPart = text[intStart ..< idx]
  if intPart.len == 0:
    return ""
  var fracPart = ""
  if idx < text.len and text[idx] == '.':
    inc idx
    let fracStart = idx
    while idx < text.len and text[idx] in {'0' .. '9'}:
      inc idx
    fracPart = text[fracStart ..< idx]
    if fracPart.len == 0:
      return ""
  var exponent = 0
  if idx < text.len and (text[idx] == 'e' or text[idx] == 'E'):
    inc idx
    var expNegative = false
    if idx < text.len and (text[idx] == '+' or text[idx] == '-'):
      expNegative = text[idx] == '-'
      inc idx
    let expStart = idx
    while idx < text.len and text[idx] in {'0' .. '9'}:
      inc idx
    let expDigits = text[expStart ..< idx]
    if expDigits.len == 0 or expDigits.len > 9:
      return ""
    exponent = parseBiggestInt(expDigits)
    if expNegative:
      exponent = -exponent
  if idx != text.len:
    return ""

  var digits = intPart & fracPart
  var scale = exponent - int64(fracPart.len)
  # Strip leading zeros.
  var lead = 0
  while lead < digits.len - 1 and digits[lead] == '0':
    inc lead
  digits = digits[lead .. ^1]
  # Strip trailing zeros, raising the scale.
  while digits.len > 1 and digits[^1] == '0':
    digits.setLen(digits.len - 1)
    inc scale
  if digits == "0":
    return "0"
  if scale < 0:
    # The value has a fractional part. It is integral only when the
    # implied trailing digits are zero, which the trailing-zero stripping
    # above has already removed, so it is not integral.
    return ""
  var value = digits
  for _ in 0 ..< int(scale):
    value = decMulAddSmall(value, 10, 0)
  if negative:
    "-" & value else: value


proc parseExtValue(r: var ExtReader): ExtJsonResult =
  ## Parse any external JSON value.
  inc r.depth
  defer: dec r.depth
  if r.depth > MaxExternalDepth:
    return failAt(r, "maximum nesting depth exceeded")
  skipWs(r)
  if atEnd(r):
    return failAt(r, "unexpected end of input")
  case peek(r)
  of '{': parseExtObject(r)
  of '[': parseExtArray(r)
  of '"': parseExtString(r)
  of 't': parseExtLiteral(r, "true", ekBool, true)
  of 'f': parseExtLiteral(r, "false", ekBool, false)
  of 'n': parseExtLiteral(r, "null", ekNull, false)
  of '-', '0'..'9': parseExtNumber(r)
  else: failAt(r, "unexpected character")

proc parseExternal*(src: string): ExtJsonResult =
  ## Ingest an external JSON document losslessly.
  ##
  ## The raw bytes are the caller's responsibility; this function only
  ## validates and reads them. A document that is not valid UTF-8, that
  ## has a duplicate member name, or that is not well-formed JSON is
  ## refused; it is never repaired.
  if src.len > MaxExternalDocumentBytes:
    return failed("the external document exceeds the maximum size of " &
      $MaxExternalDocumentBytes & " bytes")
  if not isValidUtf8(src):
    return failed("the external document is not valid UTF-8")
  var r = ExtReader(src: src, pos: 0, depth: 0)
  let res = parseExtValue(r)
  if not res.ok:
    return res
  skipWs(r)
  if not atEnd(r):
    return failed("trailing content after the external JSON document")
  res

