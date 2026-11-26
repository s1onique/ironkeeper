## Unit tests for command line argument handling.
##
## The argument parser is the outermost gate: an unknown option must be a
## hard failure, never a silently ignored argument.

import std/[tables]

import testkit
import ironkeeper/cli/args as argmod
import ironkeeper/core/errors

proc runSuite*(): int =
  var t = newTestSuite("cli-args")

  # --- Command path --------------------------------------------------------
  t.checkEq("finds a single-word command",
    (argmod.commandPath(@["version"])).len, 1)
  t.checkEq("finds a two-word command",
    (argmod.commandPath(@["config", "validate"])).len, 2)
  t.checkEq("stops at the first option",
    (argmod.commandPath(@["config", "validate", "--file", "x"])).len, 2)

  # --- Options -------------------------------------------------------------
  let parsed = argmod.parseArgs(@["--file", "examples/ironkeeper.json"], @["file"], @[])
  t.check("finds the option", parsed.options.hasKey("file"))
  t.checkEq("reads an option value", parsed.options["file"],
            "examples/ironkeeper.json")
  t.check("does not report --file as a flag", not parsed.flags.hasKey("file"))

  let inline = argmod.parseArgs(@["--file=examples/ironkeeper.json"], @["file"], @[])
  t.checkEq("reads an inline option value", inline.options["file"],
            "examples/ironkeeper.json")

  let withJson = argmod.parseArgs(@["--json"], @["file"], @[])
  t.check("recognises the --json flag", withJson.json)

  let withHelp = argmod.parseArgs(@["--help"], @["file"], @[])
  t.check("recognises the --help flag", withHelp.help)

  # --- Failures ------------------------------------------------------------
  var unknownRejected = false
  try:
    discard argmod.parseArgs(@["--nonsense"], @["file"], @[])
  except IrkErrorImpl as e:
    unknownRejected = e.data.kind == EInvalidInvocation
  t.check("rejects an unknown option", unknownRejected)

  var missingValue = false
  try:
    discard argmod.parseArgs(@["--file"], @["file"], @[])
  except IrkErrorImpl as e:
    missingValue = e.data.kind == EInvalidInvocation
  t.check("rejects an option without its value", missingValue)

  var valueForFlag = false
  try:
    discard argmod.parseArgs(@["--json=yes"], @["file"], @[])
  except IrkErrorImpl as e:
    valueForFlag = e.data.kind == EInvalidInvocation
  t.check("rejects a value given to a boolean flag", valueForFlag)

  var shortUnknown = false
  try:
    discard argmod.parseArgs(@["-x"], @["file"], @[])
  except IrkErrorImpl as e:
    shortUnknown = e.data.kind == EInvalidInvocation
  t.check("rejects an unknown short option", shortUnknown)

  # --- Required options ----------------------------------------------------
  var missingRequired = false
  try:
    discard argmod.requireOption(parsed, "absent")
  except IrkErrorImpl as e:
    missingRequired = e.data.kind == EInvalidInvocation
  t.check("rejects a missing required option", missingRequired)

  t.checkEq("returns the required option value",
    argmod.requireOption(parsed, "file"), "examples/ironkeeper.json")

  t.finish()

