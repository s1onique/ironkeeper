## Authoritative version source for Ironkeeper.
##
## This module is the single place where the application version is declared.
## `ironkeeper.nimble` mirrors this value; the contract test
## `tests/contract/version_contract.nim` asserts that they agree.

const
  Version* = "0.1.0-dev"
    ## Semantic version of the Ironkeeper application.
    ##
    ## The `-dev` suffix marks a pre-release build. It is deliberately a plain
    ## string: no part of the codebase may parse or infer semantics from it
    ## beyond "this is not a stable release".

  VersionMajor* = 0
  VersionMinor* = 1
  VersionPatch* = 0

  ApplicationName* = "ironkeeper"
    ## Stable program name used in diagnostics, reports and usage strings.

proc versionString*(): string =
  ## Machine-readable version identity of the running binary.
  ApplicationName & " " & Version
