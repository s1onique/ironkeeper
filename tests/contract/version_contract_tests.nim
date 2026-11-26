## Contract test for the version contract.
##
## Ironkeeper has exactly one authoritative version source: the `Version`
## constant in `src/ironkeeper/core/version.nim`. The Nimble manifest
## mirrors it, and this test asserts that the two agree. A release that
## forgets to update the manifest fails here rather than in production.

import std/[os, strutils]

import testkit
import ironkeeper/core/version

proc hasSemanticShape(v: string): bool =
  ## True when `v` is `major.minor.patch` with an optional pre-release
  ## suffix, which is the shape the version contract requires.
  let core = v.split('-')[0]
  let parts = core.split('.')
  if parts.len != 3:
    return false
  for part in parts:
    if part.len == 0:
      return false
    for ch in part:
      if not ch.isDigit:
        return false
  true

proc runSuite*(): int =
  var t = newTestSuite("version-contract")

  t.check("the version is not empty", Version.len > 0)
  t.check("the version starts with a digit", Version[0].isDigit)
  t.check("the version has a semantic shape", hasSemanticShape(Version))

  # The Nimble manifest must carry the same version.
  #
  # Nimble only accepts a version made of numbers and dots, so the manifest
  # carries the numeric part of the application version. The `-dev`
  # pre-release marker lives in the authoritative constant.
  if not fileExists("ironkeeper.nimble"):
    t.check("the Nimble manifest is present", false)
  else:
    let manifest = readFile("ironkeeper.nimble")
    let numeric = Version.split('-')[0]
    let expected = "version       = \"" & numeric & "\""
    t.checkContains("the Nimble manifest declares the authoritative version",
      manifest, expected)
    # The manifest version must be a bare dotted number, because Nimble
    # rejects any other form.
    for line in manifest.splitLines():
      if line.startsWith("version"):
        let value = line.split("=")[1].strip().strip(chars = {'"'})
        var dotted = true
        for part in value.split('.'):
          if part.len == 0:
            dotted = false
          for ch in part:
            if not ch.isDigit:
              dotted = false
        t.check("the Nimble manifest version is a dotted number", dotted)

  # The version identity helper agrees with the constant.
  t.checkEq("the version string carries the application name",
    versionString(), ApplicationName & " " & Version)

  t.finish()

