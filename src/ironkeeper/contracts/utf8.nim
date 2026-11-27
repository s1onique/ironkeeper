## UTF-8 sanitation for the public output documents.
##
## ## Why this module exists
##
## Every public machine-readable document is JSON, and JSON is defined over
## Unicode text. A producer that emits a byte sequence which is not valid
## UTF-8 emits a document that no conforming consumer can read, even though
## the document is otherwise well formed.
##
## The input to the producers is not always trustworthy: a message may come
## from a configuration file, a validator or an external tool, and any of
## those may carry bytes that are not valid UTF-8. Such bytes must never
## reach the output verbatim.
##
## ## What this module guarantees
##
##   * `sanitizeUtf8` returns a string that is valid UTF-8, whatever the
##     input was. Invalid sequences are replaced by U+FFFD, and the
##     replacement is *reported*, so that a caller can give the reader an
##     explicit diagnostic representation instead of a silently repaired
##     value.
##   * `runeCount` counts code points, not bytes. The JSON Schema
##     `maxLength` keyword counts code points, so the bounds of the public
##     contracts are expressed in code points.
##   * `takeRunes` cuts at a code point boundary, so a cut string is always
##     valid text.
##   * `sanitizeJson` applies the same rule to every string in a document,
##     at any depth.
##
## The module performs no I/O and holds no state.

import std/[json, unicode]

const
  ReplacementChar* = "\uFFFD"
    ## The Unicode replacement character. It stands for a byte sequence
    ## that is not valid UTF-8.

  InvalidTextPrefix* = "[invalid utf-8] "
    ## The explicit diagnostic prefix that marks a value whose bytes were
    ## not valid UTF-8.
    ##
    ## A repaired value is never presented as if it were the original: the
    ## reader is told that the text was not valid UTF-8.

proc isValidUtf8*(value: string): bool =
  ## True when `value` is a valid UTF-8 sequence.
  ##
  ## The Nim standard library reports `-1` for a valid string and the
  ## offset of the first invalid byte otherwise.
  validateUtf8(value) == -1

proc runeCount*(value: string): int =
  ## The number of code points in `value`.
  ##
  ## The count is taken over code points, because that is what the JSON
  ## Schema `maxLength` keyword counts.
  var i = 0
  while i < value.len:
    inc result
    let b = value[i].ord
    if b < 0x80:
      inc i
    elif b < 0xE0:
      i += 2
    elif b < 0xF0:
      i += 3
    else:
      i += 4

proc takeRunes*(value: string, count: int): string =
  ## The first `count` code points of `value`.
  ##
  ## The cut is taken at a code point boundary, so the result is always
  ## valid text. When `count` is zero the result is empty; when `count` is
  ## larger than the number of code points, the whole string is returned.
  if count <= 0:
    return ""
  var taken = 0
  var i = 0
  while i < value.len and taken < count:
    let b = value[i].ord
    var step = 1
    if b >= 0xF0:
      step = 4
    elif b >= 0xE0:
      step = 3
    elif b >= 0xC0:
      step = 2
    i += step
    inc taken
  if i >= value.len:
    value
  else:
    value[0 ..< i]

proc sanitizeUtf8*(value: string): tuple[text: string, repaired: bool] =
  ## Repair `value` so that it is valid UTF-8.
  ##
  ## Every byte sequence that is not valid UTF-8 is replaced by the
  ## replacement character U+FFFD. The `repaired` flag reports whether any
  ## replacement was made, so that the caller can classify the result
  ## explicitly instead of presenting a repaired value as the original.
  if isValidUtf8(value):
    return (text: value, repaired: false)
  var acc = newStringOfCap(value.len)
  var i = 0
  var repaired = false
  while i < value.len:
    let b = value[i].ord
    if b < 0x80:
      acc.add value[i]
      inc i
      continue
    var step = 1
    if b >= 0xF0:
      step = 4
    elif b >= 0xE0:
      step = 3
    elif b >= 0xC0:
      step = 2
    if i + step <= value.len and
       validateUtf8(value[i ..< i + step]) == -1:
      acc.add value[i ..< i + step]
      i += step
    else:
      acc.add ReplacementChar
      repaired = true
      inc i
  (text: acc, repaired: repaired)

proc sanitizeJson*(node: JsonNode): JsonNode =
  ## A copy of `node` in which every string is valid UTF-8.
  ##
  ## The copy is deep: no part of the original document is shared with the
  ## result. A `nil` node is returned unchanged.
  if node.isNil:
    return node
  case node.kind
  of JString:
    newJString(sanitizeUtf8(node.getStr).text)
  of JObject:
    var acc = newJObject()
    for key, value in node.pairs:
      acc[sanitizeUtf8(key).text] = sanitizeJson(value)
    acc
  of JArray:
    var acc = newJArray()
    for value in node.elems:
      acc.add sanitizeJson(value)
    acc
  else:
    node
