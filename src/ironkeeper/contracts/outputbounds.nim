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

const
  MaxMessageLength* = 4096
    ## The maximum length of a human-readable message.

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

proc boundText*(value: string, limit: int): string =
  ## Shorten `value` to at most `limit` characters.
  ##
  ## The marker is included in the limit, so the result never exceeds it.
  ## The result is never empty when the input was not empty, so a
  ## truncated message still satisfies the `minLength` of the contract.
  if value.len <= limit:
    return value
  if limit <= TruncationMarker.len:
    return value[0 ..< limit]
  result = value[0 ..< limit - TruncationMarker.len] & TruncationMarker

proc boundMessage*(value: string): string =
  ## Shorten a message to the contract's limit.
  boundText(value, MaxMessageLength)

proc boundLocation*(value: string): string =
  ## Shorten a location to the contract's limit.
  boundText(value, MaxLocationLength)

proc boundCode*(value: string): string =
  ## Shorten a code to the contract's limit.
  boundText(value, MaxCodeLength)

proc boundDetail*(value: string): string =
  ## Shorten a detail to the contract's limit.
  boundText(value, MaxDetailLength)
