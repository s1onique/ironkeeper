## Exact decimal classification for Ironkeeper's strict JSON reader.
##
## The defect this module exists to prevent is a *silent* numeric
## corruption: a value that the source text states exactly is rounded by an
## intermediate binary64 conversion, so the resulting document claims
## something the source did not say.
##
## ## The problem with a binary64 intermediate
##
## JSON Schema numeric semantics are defined over IEEE-754 binary64, but
## binary64 cannot represent every decimal exactly:
##
##   * `9007199254740993` (2^53 + 1) rounds to `9007199254740992`;
##   * `1.00000000000000001` rounds to `1.0`;
##   * `1e-400` underflows to `0.0` - a *nonzero* number becomes zero.
##
## Checking the magnitude *after* the conversion cannot help: by then the
## information is already gone. The magnitude must be decided from the
## source text, before any lossy step.
##
## ## The policy
##
## The strict reader classifies every JSON number from its **source text**,
## using exact decimal arithmetic on the digits. It never converts through
## binary64 in order to decide whether a value is in range.
##
## | Form | Condition | Result |
## |---|---|---|
## | integer | fits in `int64` | exact `JInt` |
## | integer | does not fit in `int64` | **rejected** |
## | fraction/exponent | value is not an integer | **rejected** |
## | fraction/exponent | integral value, `abs(v) <= 2^53` | exact `JInt` |
## | fraction/exponent | integral value, `abs(v) > 2^53` | **rejected** |
##
## The rules are deliberately narrow. The strict reader feeds *Ironkeeper's
## own* contracts, whose numeric fields are small integers: schema
## versions, severities, counts. A contract that needs a counter beyond
## 2^53 carries it as a canonical decimal *string*, not as a JSON number.
## See `docs/architecture/overview.md`, "Numeric representation".
##
## ## What this module does not claim
##
## Binary64 does not represent every decimal fraction exactly, and this
## module does not claim that it does. It never represents a fraction at
## all: a non-integral decimal is *rejected* rather than rounded. The
## accepted value set is therefore a subset of what binary64 can hold, and
## every accepted value is exact in binary64.
##
## ## External telemetry
##
## This policy governs **strict internal Ironkeeper JSON contracts**. It is
## deliberately *not* the policy for external hardware JSON acquisition,
## where the original telemetry must be preserved exactly. A future
## storage adapter normalises external numerics into canonical decimal
## strings; it does not route them through this module.

import std/[strutils]

const
  MaxExactIntMagnitude* = 9007199254740992'i64
    ## 2^53. The largest magnitude for which every integer is exactly
    ## representable as an IEEE-754 binary64.
    ##
    ## A value at or below this bound is exactly representable, so a
    ## comparison against it is lossless. A value above it may round to a
    ## *different* integer, so it is rejected.

  Int64MinMagnitude* = 9223372036854775808'u64
    ## The magnitude of `int64.low`. It is spelled as an unsigned literal
    ## because `abs(int64.low)` overflows.

  Int64MaxMagnitude* = 9223372036854775807'u64
    ## The magnitude of `int64.high`.

  MaxExponentDigits* = 9
    ## The number of exponent digits that are supported.
    ##
    ## A longer exponent is rejected rather than parsed. The bound keeps
    ## the decimal scale arithmetic below in a range that is exactly
    ## representable and cannot overflow.

type
  ExactNumberError* = object
    ## A classified numeric failure.
    message*: string

  ExactNumber* = object
    ## The exact classification of a JSON number.
    ok*: bool
    isIntegral*: bool
      ## True when the value denotes an integer.
    negative*: bool
      ## True when the value is negative. Zero is never negative.
    magnitude*: uint64
      ## The absolute value of an integral value that fits in `uint64`.
    error*: ExactNumberError

proc failed(msg: string): ExactNumber =
  ExactNumber(ok: false, error: ExactNumberError(message: msg))

proc isAllZero(s: string): bool =
  for ch in s:
    if ch != '0':
      return false
  true

proc classifyExact*(lexeme: string): ExactNumber =
  ## Classify a JSON number from its source text, exactly.
  ##
  ## The lexeme must be a syntactically valid JSON number; the caller has
  ## already checked that. The classification uses only decimal string
  ## arithmetic, so no value is ever rounded.
  ##
  ## Returns a failure for a value that does not fit in `int64`, for a
  ## value that is not integral, and for an integral value whose magnitude
  ## exceeds 2^53.
  if lexeme.len == 0:
    return failed("empty number")

  var negative = false
  var idx = 0
  if lexeme[0] == '-':
    negative = true
    idx = 1
  if idx >= lexeme.len:
    return failed("invalid number: " & lexeme)

  # ---- the integer part --------------------------------------------------
  let intStart = idx
  while idx < lexeme.len and lexeme[idx] in {'0' .. '9'}:
    inc idx
  let intPart = lexeme[intStart ..< idx]
  if intPart.len == 0:
    return failed("invalid number: " & lexeme)

  # ---- the fraction ------------------------------------------------------
  var fracPart = ""
  if idx < lexeme.len and lexeme[idx] == '.':
    inc idx
    let fracStart = idx
    while idx < lexeme.len and lexeme[idx] in {'0' .. '9'}:
      inc idx
    fracPart = lexeme[fracStart ..< idx]
    if fracPart.len == 0:
      return failed("invalid number: " & lexeme)

  # ---- the exponent ------------------------------------------------------
  var exponent = 0'i64
  if idx < lexeme.len and (lexeme[idx] == 'e' or lexeme[idx] == 'E'):
    inc idx
    var expNegative = false
    if idx < lexeme.len and (lexeme[idx] == '+' or lexeme[idx] == '-'):
      expNegative = lexeme[idx] == '-'
      inc idx
    let expStart = idx
    while idx < lexeme.len and lexeme[idx] in {'0' .. '9'}:
      inc idx
    let expDigits = lexeme[expStart ..< idx]
    if expDigits.len == 0:
      return failed("invalid number: " & lexeme)
    if expDigits.len > MaxExponentDigits:
      return failed("number exponent is out of the supported range: " & lexeme)
    exponent = parseBiggestInt(expDigits)
    if expNegative:
      exponent = -exponent

  if idx != lexeme.len:
    return failed("invalid number: " & lexeme)

  # ---- combine the digits and the scale ----------------------------------
  # The value is  digits * 10^scale, where `digits` is the integer part
  # followed by the fraction part, and
  #   scale = exponent - len(fracPart).
  #
  # A *negative* scale means the value has a fractional part that the
  # digits alone do not express; a *positive* scale means the digits are
  # to be multiplied by a power of ten.
  var digits = intPart & fracPart
  var scale = exponent - int64(fracPart.len)

  # Strip leading zeros so that the magnitude comparison is on significant
  # digits.
  var lead = 0
  while lead < digits.len - 1 and digits[lead] == '0':
    inc lead
  digits = digits[lead .. ^1]

  # Strip trailing zeros; each one increments the scale by one, because
  # (digits / 10) * 10^(scale + 1) == digits * 10^scale.
  while digits.len > 1 and digits[^1] == '0':
    digits.setLen(digits.len - 1)
    inc scale

  # Zero is zero, whatever the scale.
  if isAllZero(digits):
    return ExactNumber(ok: true, isIntegral: true, negative: false,
                       magnitude: 0)

  # ---- the value must be integral -----------------------------------------
  # `scale < 0` means the value has a fractional part. It is integral only
  # when the trailing digits that the negative scale implies are all zero.
  # After the trailing zeros have been stripped, `digits` ends in a nonzero
  # digit, so a negative scale always denotes a fraction.
  if scale < 0:
    return failed("number is not an integer and cannot be represented " &
      "exactly: " & lexeme)

  # ---- the magnitude must fit in uint64 ----------------------------------
  # The magnitude is `digits` scaled by `10^scale`. The scaling is done in
  # decimal, digit by digit, so that no binary64 rounding can occur.
  if digits.len + int(scale) > 20:
    return failed("integer does not fit in a 64-bit signed integer: " & lexeme)

  var magnitude = 0'u64
  for ch in digits:
    let d = uint64(ch.ord - '0'.ord)
    if magnitude > (high(uint64) - d) div 10'u64:
      return failed("integer does not fit in a 64-bit signed integer: " & lexeme)
    magnitude = magnitude * 10'u64 + d

  # Apply the scale. The digit count above bounds the number of
  # multiplications, so the intermediate value cannot overflow.
  for _ in 0 ..< int(scale):
    if magnitude > high(uint64) div 10'u64:
      return failed("integer does not fit in a 64-bit signed integer: " & lexeme)
    magnitude = magnitude * 10'u64

  # ---- the signed range ---------------------------------------------------
  # The magnitude of `int64.low` is one larger than `int64.high`, so the
  # negative and the positive bound differ.
  if negative:
    if magnitude > Int64MinMagnitude:
      return failed("integer does not fit in a 64-bit signed integer: " & lexeme)
  else:
    if magnitude > Int64MaxMagnitude:
      return failed("integer does not fit in a 64-bit signed integer: " & lexeme)

  # ---- the exact-binary64 bound ------------------------------------------
  # The bound is checked against the exact magnitude, never against a
  # binary64 conversion of it.
  if magnitude > uint64(MaxExactIntMagnitude):
    return failed("integer magnitude exceeds the exact binary64 range " &
      "(2^53): " & lexeme)

  ExactNumber(ok: true, isIntegral: true, negative: negative,
              magnitude: magnitude)

proc toInt64*(n: ExactNumber): int64 =
  ## The signed value of an exact integral number.
  ##
  ## Only valid when `n.ok` and `n.isIntegral` hold. The magnitude is
  ## within the `int64` range and at most 2^53, so the conversion is
  ## exact.
  if n.negative:
    # The magnitude is at most 2^53, so it is never `int64.low` and the
    # negation cannot overflow.
    return -cast[int64](n.magnitude)
  cast[int64](n.magnitude)
