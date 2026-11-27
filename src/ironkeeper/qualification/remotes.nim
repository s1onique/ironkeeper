## The remote schemas of the official test suite.
##
## ## Why this module exists
##
## The qualification consumes **two** trees of the pinned suite:
##
##   * `tests/draft2020-12/` — the corpus of cases; and
##   * `remotes/` — the schemas that corpus cases reference.
##
## A digest over the corpus alone does not identify the input: the
## referenced remote schemas are part of what was measured, and a
## modified remote schema changes the answer without changing the
## corpus. Both trees are therefore bound to the pinned revision.
##
## ## Failure is not skipped
##
## A remote schema that cannot be parsed is a **problem**, not a file to
## be passed over. A qualification that silently skipped a malformed
## remote schema would report conformance over a corpus it did not
## actually measure.
##
## ## Offline resolution
##
## The documents are read from the checkout. Nothing is fetched, and no
## network access occurs. The retrieval URIs are the ones the official
## suite documents, so that a case that references a remote schema finds
## it under the URI it expects.

import std/[json, os, strutils, algorithm]

from ironkeeper/qualification/corpus import CorpusDigest, digestInit,
  digestUpdate, digestOf

type
  RemoteSchema* = object
    ## One remote schema of the suite.
    relativePath*: string
      ## The path of the document relative to the remotes root.
    uri*: string
      ## The retrieval URI the document is registered under.
    document*: JsonNode
      ## The parsed document.

  RemoteProblem* = object
    ## A problem with the remote schema tree.
    file*: string
    message*: string

  RemoteRegistration* = object
    ## The remote schemas of the suite, and the problems found.
    schemas*: seq[RemoteSchema]
      ## Every remote schema, in deterministic order.
    problems*: seq[RemoteProblem]
      ## The problems found while reading. A non-empty list means the
      ## remote tree is not usable and the qualification must not run.
    digest*: string
      ## A digest over the remote files that were actually read. It is an
      ## integrity check over the bytes, not a proof of provenance.
    fileCount*: int
      ## The number of remote files that were read.

proc remoteFiles(root: string): seq[tuple[path, relative: string]] =
  ## Every remote file under `root`, in deterministic order.
  var found: seq[tuple[path, relative: string]] = @[]
  for path in walkDirRec(root):
    if path.endsWith(".json"):
      let relative = relativePath(path, root).strip(chars = {'/'})
      found.add (path, relative)
  found.sort(proc (a, b: tuple[path, relative: string]): int =
    cmp(a.relative, b.relative))
  found

proc readRemoteSchemas*(remotesDir: string, baseUri: string): RemoteRegistration =
  ## Read every remote schema of the suite.
  ##
  ## A file that cannot be parsed produces a problem. It is never
  ## skipped: the caller must refuse to qualify against a remote tree
  ## that was not fully read.
  if not dirExists(remotesDir):
    result.problems.add RemoteProblem(file: remotesDir,
      message: "the remote schema directory does not exist")
    return
  var digest = digestInit()
  for f in remoteFiles(remotesDir):
    var text: string
    try:
      text = readFile(f.path)
    except IOError as e:
      result.problems.add RemoteProblem(file: f.relative,
        message: "the remote schema could not be read: " & e.msg)
      continue
    var document: JsonNode
    try:
      document = parseJson(text)
    except CatchableError as e:
      result.problems.add RemoteProblem(file: f.relative,
        message: "the remote schema is not well-formed JSON: " & e.msg)
      continue
    result.schemas.add RemoteSchema(relativePath: f.relative,
      uri: baseUri & "/" & f.relative, document: document)
    # The digest is computed over the bytes that were actually read, so
    # that the result identifies the tree that was measured.
    digestUpdate(digest, f.relative & "\n")
    digestUpdate(digest, text)
    inc result.fileCount
  result.digest = digestOf(digest)
