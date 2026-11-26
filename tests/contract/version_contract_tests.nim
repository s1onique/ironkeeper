## Contract test for the version contract.
##
## Ironkeeper has exactly one authoritative version source: the `Version`
## constant in `src/ironkeeper/core/version.nim`. The Nimble manifest
## mirrors it, and this test asserts that the two agree. A release that
## forgets to update the manifest fails here rather than in production.

import std/[os, strutils, re]

import testkit
import ironkeeper/core/version

proc runSuite*(): int =
  var t = newTestSuite("version-contract")

  t.check("the version is not empty", Version.len > 0)
  t.check("the version starts with a digit", Version[0].isDigit)
  t.check("the version has a semantic shape",
    Version.match(re"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$"))

  # The Nimble manifest must carry the same version.
  if fileExists("ironkeeper.nimble"):
    let manifest = readFile("ironkeeper.nimble")
    let expected = "version       = \"" & Version & "\""
    t.checkContains("the Nimble manifest declares the authoritative version",
      manifest, expected)
  else:
    t.check("the Nimble manifest is present", false)

  # The version identity helper agrees with the constant.
  t.checkEq("the version string carries the application name",
    versionString(), ApplicationName & " " & Version)

  t.finish()

