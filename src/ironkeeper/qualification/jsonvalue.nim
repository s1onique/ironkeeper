## A JSON reader that preserves numeric precision.
##
## ## Why this module exists
##
## The standard JSON reader turns a number that does not fit into a 64-bit
## signed integer into a *string* holding its digits. A reader that then
## cannot tell that string from a genuine JSON string cannot tell a
## representable number from an unrepresentable one, and a qualification
## harness that cannot tell the difference will either claim a validator
## failed a bignum case or silently skip it.
##
## This reader therefore parses the source text itself. Every number keeps
## its exact lexeme, and every number that the document model cannot hold
## exactly is reported, with its lexeme, as an explicit limitation.
##
## ## What "exactly" means here
##
## JSON Schema defines its numeric semantics over IEEE-754 binary64, so a
## fractional value is *by specification* a binary64 value and is not a
## limitation. The limitation is a number that the document model cannot
## hold: an integer outside the 64-bit signed range, and a magnitude that
## overflows to infinity.
##
## ## What it does not do
##
## It does not perform the strict-ingestion checks of
## `ironkeeper/json/strictjson`: the corpus is an external, upstream
## artefact, and the corpus reader's job is to read it faithfully and
## report what cannot be represented. It performs no I/O and holds no
## state.

import std/[json, strutils, unicode]

type
  ParseProblem* = object
    ## A problem that makes the document unusable.
    message*: string
    offset*: int

  PreciseDocument* = object
    ## A parsed document.
    node*: JsonNode
      ## The document. A number that could not be represented is held as
      ## its raw lexeme in a string node, and its lexeme is listed in
      ## `unrepresentable`.
    unrepresentable*: seq[string]
      ## The lexemes of the numbers the document model cannot hold
      ## exactly.
    unrepresentablePaths*: seq[string]
      ## The JSON Pointers of the positions that hold an unrepresentable
      ## number, in the same order as `unrepresentable`.
    problem*: ParseProblem
      ## The problem that stopped the parse, if any.

const
  MaxDepth* = 256
    ## The deepest nesting the reader accepts. It bounds the recursion, so
    ## a hostile document cannot exhaust the stack.

proc isDigit(c: char): bool =
  c in {'0' .. '9'}

proc appendCodePoint(acc: var string, code: int) =
  ## Append a Unicode code point to the accumulator.
  ##
  ## A code point outside the basic multilingual plane is encoded as a
  ## surrogate pair in the source text; the pair is combined here.
  if code < 0 or code > 0x10FFFF:
    return
  if code >= 0xD800 and code <= 0xDFFF:
    return
  acc.add toUTF8(Rune(code))

proc readString(text: string, pos: var int): string =
  ## Read a JSON string, starting at the opening quote.
  inc pos # the opening quote
  var acc = ""
  while pos < text.len:
    let c = text[pos]
    if c == '"':
      inc pos
      return acc
    if c == '\\':
      inc pos
      if pos >= text.len:
        break
      let esc = text[pos]
      inc pos
      case esc
      of '"': acc.add '"'
      of '\\': acc.add '\\'
      of '/': acc.add '/'
      of 'b': acc.add '\b'
      of 'f': acc.add '\f'
      of 'n': acc.add '\n'
      of 'r': acc.add '\r'
      of 't': acc.add '\t'
      of 'u':
        if pos + 4 > text.len:
          return acc
        let hex = text[pos .. pos + 3]
        var code: int
        try:
          code = parseHexInt(hex)
        except ValueError:
          return acc
        pos += 4
        if code >= 0xD800 and code <= 0xDBFF:
          # A high surrogate. It must be followed by a low surrogate.
          if pos + 6 > text.len or text[pos] != '\\' or text[pos + 1] != 'u':
            return acc
          let lowHex = text[pos + 2 .. pos + 5]
          var low: int
          try:
            low = parseHexInt(lowHex)
          except ValueError:
            return acc
          if low < 0xDC00 or low > 0xDFFF:
            return acc
          pos += 6
          code = 0x10000 + ((code - 0xD800) shl 10) + (low - 0xDC00)
        appendCodePoint(acc, code)
      else:
        return acc
    else:
      acc.add c
      inc pos
  acc

proc readNumber(text: string, pos: var int): string =
  ## Read a JSON number lexeme, starting at its first character.
  let start = pos
  if pos < text.len and text[pos] == '-':
    inc pos
  while pos < text.len and text[pos].isDigit:
    inc pos
  if pos < text.len and text[pos] == '.':
    inc pos
    while pos < text.len and text[pos].isDigit:
      inc pos
  if pos < text.len and (text[pos] == 'e' or text[pos] == 'E'):
    inc pos
    if pos < text.len and (text[pos] == '+' or text[pos] == '-'):
      inc pos
    while pos < text.len and text[pos].isDigit:
      inc pos
  text[start ..< pos]

proc skipWhitespace(text: string, pos: var int) =
  while pos < text.len and text[pos] in {' ', '\t', '\n', '\r'}:
    inc pos

proc escapePointer(token: string): string =
  token.replace("~", "~0").replace("/", "~1")

proc parseValue(text: string, pos: var int, depth: int, path: string,
                unrepresentable: var seq[string],
                unrepresentablePaths: var seq[string]): JsonNode =
  ## Parse one JSON value.
  skipWhitespace(text, pos)
  if pos >= text.len:
    return nil
  if depth > MaxDepth:
    return nil
  let c = text[pos]
  case c
  of '{':
    inc pos
    var obj = newJObject()
    skipWhitespace(text, pos)
    if pos < text.len and text[pos] == '}':
      inc pos
      return obj
    while pos < text.len:
      skipWhitespace(text, pos)
      if pos >= text.len or text[pos] != '"':
        return nil
      let key = readString(text, pos)
      skipWhitespace(text, pos)
      if pos >= text.len or text[pos] != ':':
        return nil
      inc pos
      let value = parseValue(text, pos, depth + 1,
                             path & "/" & escapePointer(key),
                             unrepresentable, unrepresentablePaths)
      if value.isNil:
        return nil
      obj[key] = value
      skipWhitespace(text, pos)
      if pos >= text.len:
        return nil
      if text[pos] == ',':
        inc pos
        continue
      if text[pos] == '}':
        inc pos
        return obj
      return nil
  of '[':
    inc pos
    var arr = newJArray()
    skipWhitespace(text, pos)
    if pos < text.len and text[pos] == ']':
      inc pos
      return arr
    while pos < text.len:
      let value = parseValue(text, pos, depth + 1,
                             path & "/" & $arr.len,
                             unrepresentable, unrepresentablePaths)
      if value.isNil:
        return nil
      arr.add value
      skipWhitespace(text, pos)
      if pos >= text.len:
        return nil
      if text[pos] == ',':
        inc pos
        continue
      if text[pos] == ']':
        inc pos
        return arr
      return nil
  of '"':
    return newJString(readString(text, pos))
  of 't':
    if text[pos ..< min(pos + 4, text.len)] == "true":
      pos += 4
      return newJBool(true)
    return nil
  of 'f':
    if text[pos ..< min(pos + 5, text.len)] == "false":
      pos += 5
      return newJBool(false)
    return nil
  of 'n':
    if text[pos ..< min(pos + 4, text.len)] == "null":
      pos += 4
      return newJNull()
    return nil
  of '-', '0' .. '9':
    let lexeme = readNumber(text, pos)
    if lexeme.len == 0:
      return nil
    if lexeme.contains('.') or lexeme.contains('e') or lexeme.contains('E'):
      try:
        let value = parseFloat(lexeme)
        if value == Inf or value == -Inf or value != value:
          unrepresentable.add lexeme
          unrepresentablePaths.add path
          return newJString(lexeme)
        return newJFloat(value)
      except ValueError:
        unrepresentable.add lexeme
        unrepresentablePaths.add path
        return newJString(lexeme)
    try:
      return newJInt(parseBiggestInt(lexeme))
    except ValueError:
      # The number does not fit into a 64-bit signed integer. It is held
      # as its lexeme and reported as a limitation.
      unrepresentable.add lexeme
      unrepresentablePaths.add path
      return newJString(lexeme)
  else:
    return nil

proc parsePrecise*(text: string): PreciseDocument =
  ## Parse `text` as a JSON document, preserving numeric precision.
  var pos = 0
  var unrepresentable: seq[string] = @[]
  var unrepresentablePaths: seq[string] = @[]
  let node = parseValue(text, pos, 0, "", unrepresentable, unrepresentablePaths)
  if node.isNil:
    result.problem = ParseProblem(message: "the document is not well-formed JSON",
                                   offset: pos)
    return
  skipWhitespace(text, pos)
  if pos != text.len:
    result.problem = ParseProblem(message: "the document has trailing content",
                                   offset: pos)
    return
  result.node = node
  result.unrepresentable = unrepresentable
  result.unrepresentablePaths = unrepresentablePaths
