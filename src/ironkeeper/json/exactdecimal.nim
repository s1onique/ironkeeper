## Exact decimal arithmetic on strings.
##
## Ironkeeper never passes a capacity or a counter through a binary64
## conversion: a value that the source states exactly must keep every
## digit. This module is the **single** exact-decimal primitive of the
## codebase; the external JSON reader and the SCSI capacity decoder both
## use it, so the two cannot disagree about a trailing zero.
##
## The arithmetic is performed on the decimal digits. The result is carried
## as a canonical decimal string: no digit is ever lost and no rounding
## ever happens.
##
## ## The trailing-zero defect
##
## A decimal string is trimmed of its **leading** zeros only. A trailing
## zero is a significant digit: `1000 * 512` is `512000`, not `512`. A
## primitive that trims both ends silently divides a capacity by a power of
## ten.

import std/strutils

type
  DecimalResult* = object
    ## The outcome of one exact decimal operation.
    ok*: bool
    value*: string
      ## The canonical decimal result. Empty when the operation failed.
    reason*: string
      ## Why the operation failed.

proc failed(reason: string): DecimalResult =
  DecimalResult(ok: false, value: "", reason: reason)

proc trimLeadingZeros*(text: string): string =
  ## Remove the **leading** zeros of a decimal string.
  ##
  ## Only the leading zeros are removed. A trailing zero is a significant
  ## digit and is preserved.
  var lead = 0
  while lead < text.len - 1 and text[lead] == '0':
    inc lead
  result = text[lead .. ^1]
  if result.len == 0:
    result = "0"

proc isCanonicalDecimal*(text: string): bool =
  ## True when the text is a canonical decimal integer.
  ##
  ## The text must be nonempty, must consist only of digits, and must not
  ## carry a leading zero unless it is exactly `"0"`.
  if text.len == 0:
    return false
  for ch in text:
    if ch notin {'0' .. '9'}:
      return false
  if text.len > 1 and text[0] == '0':
    return false
  true

proc mulSmall*(a: string, b: int64): DecimalResult =
  ## Multiply an exact decimal string by a small non-negative integer.
  ##
  ## The multiplication is performed digit by digit, so the result is
  ## exact for every value that fits in the string representation. A
  ## negative multiplier is refused: the primitive never wraps around.
  if not isCanonicalDecimal(a):
    return failed("the multiplicand is not a canonical decimal integer")
  if b < 0:
    return failed("the multiplier is negative")
  if b == 0:
    return DecimalResult(ok: true, value: "0")
  var carry = 0'i64
  var digits = ""
  for i in countdown(a.len - 1, 0):
    let d = (a[i].ord - '0'.ord).int64 * b + carry
    carry = d div 10
    digits.add $(d mod 10)
  while carry > 0:
    digits.add $(carry mod 10)
    carry = carry div 10
  var reversed = ""
  for i in countdown(digits.len - 1, 0):
    reversed.add digits[i]
  DecimalResult(ok: true, value: trimLeadingZeros(reversed))

proc addSmall*(a: string, b: int64): DecimalResult =
  ## Add a small non-negative integer to an exact decimal string.
  if not isCanonicalDecimal(a):
    return failed("the addend is not a canonical decimal integer")
  if b < 0:
    return failed("the addend is negative")
  if b == 0:
    return DecimalResult(ok: true, value: a)
  var carry = b
  var digits = ""
  for i in countdown(a.len - 1, 0):
    let d = (a[i].ord - '0'.ord).int64 + carry
    carry = d div 10
    digits.add $(d mod 10)
  while carry > 0:
    digits.add $(carry mod 10)
    carry = carry div 10
  var reversed = ""
  for i in countdown(digits.len - 1, 0):
    reversed.add digits[i]
  DecimalResult(ok: true, value: trimLeadingZeros(reversed))

proc leBytesToDecimal*(bytes: openArray[int]): DecimalResult =
  ## Convert a little-endian byte array into an exact decimal string.
  ##
  ## The first byte is the **least** significant one, which is what the
  ## `KEY_le` companion of `smartctl` means: the byte at index `i` carries
  ## the weight `256^i`. Every byte must be in the range 0..255; a byte
  ## outside that range is refused rather than masked, because masking
  ## would silently change the value.
  ##
  ## The array is consumed from its **last** byte to its first, so that
  ## the accumulation is a plain `value * 256 + byte`. Every intermediate
  ## value is exact.
  var value = "0"
  var i = bytes.len - 1
  while i >= 0:
    let b = bytes[i]
    if b < 0 or b > 255:
      return failed("a little-endian byte is outside the range 0..255")
    let shifted = mulSmall(value, 256)
    if not shifted.ok:
      return shifted
    let sum = addSmall(shifted.value, int64(b))
    if not sum.ok:
      return sum
    value = sum.value
    dec i
  DecimalResult(ok: true, value: value)

proc addOne*(a: string): DecimalResult =
  ## Add one to an exact decimal string.
  if not isCanonicalDecimal(a):
    return failed("the operand is not a canonical decimal integer")
  var carry = 1
  var digits = ""
  for i in countdown(a.len - 1, 0):
    let d = (a[i].ord - '0'.ord) + carry
    carry = d div 10
    digits.add $(d mod 10)
  while carry > 0:
    digits.add $(carry mod 10)
    carry = carry div 10
  var reversed = ""
  for i in countdown(digits.len - 1, 0):
    reversed.add digits[i]
  DecimalResult(ok: true, value: trimLeadingZeros(reversed))
