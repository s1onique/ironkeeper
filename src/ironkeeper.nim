## Ironkeeper - evidence-driven storage fleet housekeeping daemon.
##
## This module is the process entry point. It does exactly three things:
## collect the command line, hand it to the CLI application, and exit with
## the returned status.
##
## Everything else lives under `src/ironkeeper/`:
##
##   `cli/`        command surface, argument parsing, output conventions
##   `config/`     configuration decoding and semantic validation
##   `contracts/`  JSON Schema contracts, validation and the report model
##   `core/`       version identity and the error taxonomy
##   `json/`       strict JSON ingestion
##
## See `docs/architecture/overview.md` for the architectural boundaries and
## `AGENTS.md` for the engineering rules that apply to changes here.

import std/os

import ironkeeper/cli/app

when isMainModule:
  quit(app.run(commandLineParams()))
