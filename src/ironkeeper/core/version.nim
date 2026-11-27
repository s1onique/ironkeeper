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

const
  TestingBuild* = defined(ironkeeperTesting)
    ## True when this binary was compiled with the test build definition.
    ##
    ## The test build exists so that the *production* code paths can be
    ## exercised against controlled fixtures. It is a **compile-time**
    ## property: a shipped binary either has the test seams or it does
    ## not, and the decision cannot be changed by an environment
    ## variable.
  BuildVariant* = (when TestingBuild: "testing" else: "production")
    ## The identity of the build variant of the running binary.
    ##
    ## The variant is reported by `ironkeeper version --json` and is
    ## recorded in the evidence manifest, so that a test-enabled binary
    ## can never be mistaken for a production one.
  BuildDefinition* = (when TestingBuild: "ironkeeperTesting" else: "none")
    ## The compile-time definition that the running binary carries.