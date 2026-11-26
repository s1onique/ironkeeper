## Command line argument parsing for Ironkeeper.
##
## The parser is intentionally small and explicit. It supports:
##
##   * `--help` and `-h` on the top level and on every subcommand,
##   * `--version` and `-V` on the top level,
##   * long options with `--name value` or `--name=value`,
##   * a single global `--json` flag that switches a command to
##     machine-readable output.
##
## There are no abbreviations, no positional arguments other than the
## documented ones, and no implicit defaults for options that carry
## meaning. An unknown option or a missing required option is an
## `EInvalidInvocation` failure, never a silently ignored argument.

import std/[strutils, tables, sets]

from ironkeeper/core/errors import IrkErrorKind, newIrkError

type
  ParsedArgs* = object
    ## Result of parsing a command line.
    command*: seq[string]
      ## The command path, e.g. `["config", "validate"]`.
    options*: Table[string, string]
      ## Options that carry a value, keyed by their long name.
    flags*: Table[string, bool]
      ## Boolean flags, keyed by their long name.
    json*: bool
      ## True when `--json` was requested.
    help*: bool
      ## True when `--help` was requested.

proc fail(msg: string) =
  raise newIrkError(EInvalidInvocation, msg)

proc commandPath*(argv: seq[string]): seq[string] =
  ## Extract the leading command path from `argv`.
  ##
  ## Only the leading positional words are returned. Everything from the
  ## first option onwards is left for the subcommand's own option parser,
  ## so that a subcommand can decide which options it accepts.
  result = @[]
  for a in argv:
    if a.startsWith("-"):
      break
    result.add a

proc parseArgs*(argv: seq[string], valueOptions: seq[string],
                boolFlags: seq[string]): ParsedArgs =
  ## Parse `argv` (without the program name).
  ##
  ## `valueOptions` and `boolFlags` list the long option names that the
  ## calling command accepts. Options outside those lists are rejected.
  var i = 0
  var cmd: seq[string]
  var opts = initTable[string, string]()
  var flags = initTable[string, bool]()
  var wantJson = false
  var wantHelp = false

  let valueSet = valueOptions.toHashSet()
  let flagSet = boolFlags.toHashSet()

  while i < argv.len:
    let a = argv[i]
    if a == "--":
      # Everything after "--" is a positional argument.
      inc i
      while i < argv.len:
        cmd.add argv[i]
        inc i
      break
    elif a.startsWith("--"):
      var name = a[2 .. ^1]
      var inlineValue = ""
      var hasInline = false
      let eq = name.find('=')
      if eq >= 0:
        inlineValue = name[eq + 1 .. ^1]
        name = name[0 ..< eq]
        hasInline = true
      if name == "json":
        if hasInline:
          fail("--json does not take a value")
        wantJson = true
      elif name == "help":
        if hasInline:
          fail("--help does not take a value")
        wantHelp = true
      elif name == "version":
        if hasInline:
          fail("--version does not take a value")
        flags["version"] = true
      elif valueSet.contains(name):
        if hasInline:
          opts[name] = inlineValue
        else:
          if i + 1 >= argv.len:
            fail("option --" & name & " requires a value")
          inc i
          opts[name] = argv[i]
      elif flagSet.contains(name):
        if hasInline:
          fail("option --" & name & " does not take a value")
        flags[name] = true
      else:
        fail("unknown option: --" & name)
    elif a == "-h":
      wantHelp = true
    elif a == "-V":
      flags["version"] = true
    elif a.startsWith("-") and a.len > 1:
      fail("unknown option: " & a)
    else:
      cmd.add a
    inc i

  ParsedArgs(command: cmd, options: opts, flags: flags, json: wantJson,
             help: wantHelp)

proc requireOption*(args: ParsedArgs, name: string): string =
  ## Fetch a required option value, or fail with a clear message.
  if not args.options.hasKey(name):
    fail("missing required option: --" & name)
  result = args.options[name]

proc optionalOption*(args: ParsedArgs, name: string,
                     default = ""): string =
  ## Fetch an optional option value.
  if args.options.hasKey(name):
    args.options[name]
  else:
    default

proc hasFlag*(args: ParsedArgs, name: string): bool =
  args.flags.hasKey(name) and args.flags[name]
