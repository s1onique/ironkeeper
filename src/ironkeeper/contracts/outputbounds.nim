## The bounds of the public output documents.
##
## ## Why the bounds live here
##
## Every public machine-readable document has a contract, and every
## contract has limits: a maximum message length, a maximum location
## length, a maximum number of issues. A producer that does not honour
## them can emit a document that violates its own contract, and the
## violation is only discovered when a consumer validates it.
##
## The bounds therefore live in the module that produces the documents,
## not in the schema alone. The schema states the limit; this module
## enforces it.
##
## ## Truncation is explicit
##
## A truncated value is marked as truncated. A truncated *collection*
## carries an additional issue that names how many entries were dropped.
## Truncation never turns a failure into a success: a document with a
## dropped issue is still invalid, and the dropped-issue marker is itself
## an issue, so the document cannot be read as "no problems".
##
## ## Length is counted in code points
##
## The JSON Schema `maxLength` keyword counts Unicode code points, not
## bytes. The bounds are therefore expressed in code points, and a cut is
## always taken at a code point boundary, so that a truncated value is
## still valid Unicode. A byte-oriented cut could split a multi-byte
## code point and produce a document that no conforming consumer can
## read.
##
## ## The limits
##
## The values are the limits of the version 1 contracts:
##
## | Limit | Value | Contract |
## |---|---|---|
## | `MaxMessageLength` | 4096 | `error`, `report`, `validation` |
## | `MaxLocationLength` | 1024 | `report`, `validation` |
## | `MaxCodeLength` | 128 | `report`, `validation` |
## | `MaxIssueCount` | 1024 | `report`, `validation` |
## | `MaxDetailLength` | 4096 | `error` |

from ironkeeper/contracts/utf8 import sanitizeUtf8, runeCount, takeRunes,
  InvalidTextPrefix

const
  MaxMessageLength* = 4096
    ## The maximum length of a human-readable message, in code points.

  MaxLocationLength* = 1024
    ## The maximum length of a JSON Pointer that names a position.

  MaxCodeLength* = 128
    ## The maximum length of a stable machine-readable code.

  MaxIssueCount* = 1024
    ## The maximum number of issues or findings in one document.

  MaxDetailLength* = 4096
    ## The maximum length of a secondary detail string.

  TruncationMarker* = " [truncated]"
    ## The marker appended to a value that was shortened.
    ##
    ## The marker is part of the value, so a consumer that compares the
    ## value against the original can tell that it was shortened.

  ShortTruncationMarker* = "\u2026"
    ## The marker used when the bound is too small for `TruncationMarker`.
    ##
    ## The marker always fits inside the bound: a bound that cannot hold
    ## the long marker still holds this one, and a bound that cannot hold
    ## this one holds no marker at all.

proc boundText*(value: string, limit: int): string =
  ## Shorten `value` to at most `limit` code points.
  ##
  ## The result is always valid UTF-8:
  ##
  ##   * bytes that are not valid UTF-8 are replaced by U+FFFD, and the
  ##     value is prefixed with `InvalidTextPrefix`, so that the reader is
  ##     told that the text was not valid UTF-8 rather than being shown a
  ##     silently repaired value;
  ##   * a cut is taken at a code point boundary;
  ##   * the truncation marker is included in the limit, so the result
  ##     never exceeds it, and the marker always fits inside the bound.
  ##
  ## The result is never empty when the input was not empty, so a
  ## truncated message still satisfies the `minLength` of the contract.
  if limit <= 0:
    return ""
  let repaired = sanitizeUtf8(value)
  var text = repaired.text
  if repaired.repaired:
    text = InvalidTextPrefix & text
  let length = runeCount(text)
  if length <= limit:
    return text
  # The marker is part of the value, and it must fit inside the bound.
  if limit <= runeCount(TruncationMarker):
    if limit < runeCount(ShortTruncationMarker):
      return takeRunes(text, limit)
    return takeRunes(text, limit - runeCount(ShortTruncationMarker)) &
      ShortTruncationMarker
  let keep = limit - runeCount(TruncationMarker)
  takeRunes(text, keep) & TruncationMarker

proc boundMessage*(value: string): string =
  ## Shorten a message to the contract's limit.
  boundText(value, MaxMessageLength)

proc boundLocation*(value: string): string =
  ## Shorten a location to the contract's limit.
  boundText(value, MaxLocationLength)

proc boundCode*(value: string): string =
  ## Shorten a code to the contract's limit.
  ##
  ## A code is a stable, machine-readable identifier. Cutting it at the
  ## limit would produce a *different* code, and a consumer that matched
  ## on it would act on an identifier that the producer never issued. The
  ## result therefore carries the truncation marker, which no real code
  ## carries, so a shortened code cannot be read as an unrelated one.
  boundText(value, MaxCodeLength)

proc boundDetail*(value: string): string =
  ## Shorten a detail to the contract's limit.
  boundText(value, MaxDetailLength)
