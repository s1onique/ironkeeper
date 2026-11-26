## Regenerate `src/ironkeeper/contracts/schemaregistry.nim` from `schemas/v1/`.
##
## The generated module embeds the *exact bytes* of each repository schema.
## The contract test `tests/contract/schema_embedding.nim` re-reads the
## repository files and asserts that the embedded copies are byte-for-byte
## identical, so a schema edit that is not re-embedded is caught by the test
## suite rather than by a reviewer.
##
## Usage:
##
##   nim r tools/embed_schemas.nim           # regenerate
##   nim r tools/embed_schemas.nim --check   # verify only, non-zero on drift
##
## The `--check` mode is what CI runs. It never writes.

import std/[os, strutils, algorithm]

const
  SchemaDirName = "schemas/v1"
  OutputFileName = "src/ironkeeper/contracts/schemaregistry.nim"

proc findRepoRoot(): string =
  ## Locate the repository root by walking up from the working directory
  ## until the schema directory is found.
  ##
  ## The tool must work regardless of the working directory it is invoked
  ## from, because CI and a developer workstation do not necessarily
  ## agree on it. `currentSourcePath()` is not usable here: at run time it
  ## points at the compiled binary in the Nim cache, and at compile time
  ## it points at the cached copy of this file.
  var dir = getCurrentDir()
  while true:
    if dirExists(dir / SchemaDirName):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      return ""
    dir = parent

proc repoRoot(): string = findRepoRoot()

proc schemaDir(): string = repoRoot() / SchemaDirName

proc outputFile(): string = repoRoot() / OutputFileName

const
  Header = """## Embedded JSON Schema registry.
##
## THIS FILE IS GENERATED. Do not edit it by hand.
##
## Regenerate with:  nim r tools/embed_schemas.nim
## Verify with:      nim r tools/embed_schemas.nim --check
##
## Source: `schemas/v1/*.schema.json`. The embedded bytes are byte-for-byte
## identical to the repository files.

import std/json

const
  EmbeddedSchemaNames* = [
"""

proc die(msg: string) =
  stderr.writeLine("embed_schemas: " & msg)
  quit(1)

proc nimStringLiteral(s: string): string =
  ## Render `s` as a Nim triple-quoted string literal.
  ## JSON schema text never contains `"""`, but check anyway.
  if s.contains("\"\"\""):
    die("schema text contains a triple quote and cannot be embedded verbatim")
  result = "\"\"\"" & s & "\"\"\""

proc main() =
  let checkOnly = "--check" in commandLineParams()

  if repoRoot() == "" or not dirExists(schemaDir()):
    die("schema directory not found; run this from inside the repository: " &
      schemaDir())

  var names: seq[string]
  for kind, path in walkDir(schemaDir()):
    if kind == pcFile and path.endsWith(".schema.json"):
      names.add path.extractFilename().replace(".schema.json", "")
  names.sort()

  if names.len == 0:
    die("no schemas found in " & schemaDir())

  var body = Header
  for n in names:
    body.add "    \"" & n & "\",\n"
  body.add "  ]\n"
  body.add "    ## Names of the schemas embedded in the binary.\n\n"

  # The schema texts live in a `let` block: a `const` array cannot have its
  # elements assigned individually.
  body.add "let\n  embeddedSchemaTexts = [\n"
  for n in names:
    let text = readFile(schemaDir() / (n & ".schema.json"))
    body.add "    " & nimStringLiteral(text) & ",\n"
  body.add "  ]\n\n"

  body = body & """proc schemaText*(name: string): string =
  ## Raw JSON text of the embedded schema called `name`.
  ##
  ## Raises `ValueError` if the name is unknown. Callers that accept
  ## user-supplied names must check membership first.
  for i in 0 ..< EmbeddedSchemaNames.len:
    if EmbeddedSchemaNames[i] == name:
      return embeddedSchemaTexts[i]
  raise newException(ValueError, "unknown embedded schema: " & name)

proc schemaNode*(name: string): JsonNode =
  ## Parsed form of the embedded schema called `name`.
  ##
  ## The embedded documents are produced by the build step and are known to be
  ## well-formed; a parse failure here is an internal defect.
  parseJson(schemaText(name))
"""

  if checkOnly:
    if not fileExists(outputFile()):
      die("output file does not exist: " & outputFile())
    let current = readFile(outputFile())
    if current != body:
      die("embedded schemas are out of date; run: nim r tools/embed_schemas.nim")
    echo "embed_schemas: OK (" & $names.len & " schemas, no drift)"
  else:
    writeFile(outputFile(), body)
    echo "embed_schemas: wrote " & outputFile() & " (" & $names.len & " schemas)"

main()
