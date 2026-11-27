## The corpus reader of the validator qualification.
##
## ## What a corpus is
##
## The official JSON Schema Test Suite stores its cases as JSON arrays of
## *groups*. Each group has a `schema` and a list of `tests`; each test has a
## `description`, a `data` value and a `valid` flag. This module turns that
## shape into a flat, deterministically ordered list of cases, each with a
## stable identity.
##
## ## Corpus integrity
##
## A qualification result is only meaningful if it identifies the corpus it
## was measured against. The reader therefore:
##
##   * refuses an empty corpus;
##   * refuses a corpus file that is not well-formed JSON, instead of
##     silently skipping it;
##   * refuses a group or a test that lacks the fields the suite format
##     guarantees;
##   * assigns every case a deterministic identity, so that two runs over
##     the same corpus produce the same case identities in the same order;
##   * computes a digest over the corpus files it actually read, so that the
##     result identifies the *tested* corpus and not merely a checkout.
##
## ## Numeric representation
##
## The reader preserves numeric precision as far as the JSON document model
## allows. An integer literal that does not fit into a 64-bit signed
## integer cannot be represented at all, and a float that overflows cannot
## be represented exactly. Such cases are **not** counted as validator
## failures: they are marked as representation-limited, with the reason
## recorded. Claiming that a validator failed a bignum case would be a
## claim about the test harness, not about the validator.

import std/[json, os, strutils, algorithm]

from ironkeeper/qualification/jsonvalue import parsePrecise

type
  CorpusCase* = object
    ## One test case from the corpus.
    identity*: string
      ## The stable identity of the case. It names the corpus file, the
      ## group index and the test index, so that a failure can be located
      ## in the corpus without ambiguity.
    file*: string
      ## The corpus file the case came from, relative to the corpus root.
    groupIndex*: int
    testIndex*: int
    description*: string
      ## The description of the test.
    schema*: JsonNode
      ## The schema the case is evaluated against.
    data*: JsonNode
      ## The instance the case presents.
    expectedValid*: bool
      ## The verdict the corpus expects. This is the oracle: it is the
      ## only authority against which an observed verdict is compared.
    optional*: bool
      ## True when the case comes from the optional part of the corpus.
    representationLimited*: bool
      ## True when the case's data carries a number that the document
      ## model cannot represent exactly.
    representationReason*: string
      ## Why the case is representation-limited, when it is.

  CorpusProblem* = object
    ## A problem with the corpus itself.
    file*: string
    message*: string

  Corpus* = object
    cases*: seq[CorpusCase]
      ## Every case, in deterministic order.
    problems*: seq[CorpusProblem]
      ## The problems found while reading. A non-empty list means the
      ## corpus is not usable and the qualification must not run.
    digest*: string
      ## A digest over the corpus files that were actually read. It is an
      ## integrity check over the bytes, not a proof of provenance.
    fileCount*: int
      ## The number of corpus files that were read.

const
  Draft2020_12Dir* = "tests/draft2020-12"
    ## The directory of the Draft 2020-12 corpus inside the official suite.

  OptionalDirName* = "optional"
    ## The directory the official suite uses to mark optional tests. The
    ## optional membership of a case is derived from the corpus structure,
    ## not from a hand-maintained list of file names.

proc isOptionalPath(relativePath: string): bool =
  ## True when the corpus file lies in the optional part of the corpus.
  ##
  ## The membership is derived from the corpus structure: the official suite
  ## places optional tests in a directory named `optional`. It is not a
  ## hand-maintained list of file names, so a new optional file is
  ## classified correctly without editing the harness.
  for part in relativePath.split('/'):
    if part == OptionalDirName:
      return true
  false

proc identityOf(file: string, groupIndex, testIndex: int): string =
  ## The stable identity of one case.
  file & "#" & $groupIndex & "." & $testIndex

proc readCaseFile(path, relativePath: string,
                  optional: bool): tuple[cases: seq[CorpusCase],
                                        problems: seq[CorpusProblem]] =
  ## Read every case from one corpus file.
  var text: string
  try:
    text = readFile(path)
  except IOError as e:
    result.problems.add CorpusProblem(file: relativePath,
      message: "the corpus file could not be read: " & e.msg)
    return
  let parsed = parsePrecise(text)
  if parsed.problem.message.len > 0:
    result.problems.add CorpusProblem(file: relativePath,
      message: "the corpus file is not well-formed JSON: " &
               parsed.problem.message)
    return
  let root = parsed.node
  if root.kind != JArray:
    result.problems.add CorpusProblem(file: relativePath,
      message: "the corpus file is not a JSON array of groups")
    return
  for groupIndex, group in root.elems:
    if group.kind != JObject:
      result.problems.add CorpusProblem(file: relativePath,
        message: "the corpus group " & $groupIndex & " is not an object")
      continue
    if not group.hasKey("schema"):
      result.problems.add CorpusProblem(file: relativePath,
        message: "the corpus group " & $groupIndex & " has no schema")
      continue
    if not group.hasKey("tests") or group["tests"].kind != JArray:
      result.problems.add CorpusProblem(file: relativePath,
        message: "the corpus group " & $groupIndex & " has no test list")
      continue
    for testIndex, test in group["tests"].elems:
      if test.kind != JObject:
        result.problems.add CorpusProblem(file: relativePath,
          message: "the test " & $groupIndex & "." & $testIndex &
            " is not an object")
        continue
      if not test.hasKey("data") or not test.hasKey("valid"):
        result.problems.add CorpusProblem(file: relativePath,
          message: "the test " & $groupIndex & "." & $testIndex &
            " has no data or no expected verdict")
        continue
      if test["valid"].kind != JBool:
        result.problems.add CorpusProblem(file: relativePath,
          message: "the test " & $groupIndex & "." & $testIndex &
            " has an expected verdict that is not a boolean")
        continue
      # The precise reader reports the exact position of every number the
      # document model cannot represent. The case that carries such a
      # number is marked with the reason; the other cases are unaffected.
      var reason = ""
      let dataPath = "/" & $groupIndex & "/tests/" & $testIndex & "/data"
      for i, path in parsed.unrepresentablePaths:
        if path.startsWith(dataPath):
          reason = "the instance carries the number " &
                   parsed.unrepresentable[i] &
                   ", which the document model cannot represent exactly"
      result.cases.add CorpusCase(
        identity: identityOf(relativePath, groupIndex, testIndex),
        file: relativePath,
        groupIndex: groupIndex,
        testIndex: testIndex,
        description: if test.hasKey("description"): test["description"].getStr
                     else: "",
        schema: group["schema"],
        data: test["data"],
        expectedValid: test["valid"].getBool,
        optional: optional,
        representationLimited: reason.len > 0,
        representationReason: reason)

type
  CorpusDigest* = object
    ## An FNV-1a digest over the bytes of the corpus files.
    ##
    ## The digest is an integrity check over the bytes that were read. It
    ## is not a cryptographic proof of provenance, and it is not used as
    ## one.
    hash*: uint64
    bytes*: uint64

const
  FnvOffset* = 14695981039346656037'u64
  FnvPrime* = 1099511628211'u64

proc digestInit*(): CorpusDigest =
  ## The initial state of the digest.
  CorpusDigest(hash: FnvOffset, bytes: 0)

proc digestUpdate*(d: var CorpusDigest, data: openArray[char]) =
  ## Fold `data` into the digest.
  for ch in data:
    d.hash = (d.hash xor uint64(ch.ord)) * FnvPrime
    inc d.bytes

proc digestOf*(d: CorpusDigest): string =
  ## The hexadecimal rendering of the digest.
  var hex = ""
  for i in 0 ..< 8:
    let byte = uint8((d.hash shr (8 * i)) and 0xFF'u64)
    hex.add toHex(byte, 2)
  hex

proc corpusFiles(root: string): seq[tuple[path, relative: string]] =
  ## Every corpus file under `root`, in deterministic order.
  var found: seq[tuple[path, relative: string]] = @[]
  for path in walkDirRec(root):
    if path.endsWith(".json"):
      let relative = path[root.len .. ^1]
      found.add (path, relative.strip(chars = {'/'}))
  found.sort(proc (a, b: tuple[path, relative: string]): int =
    cmp(a.relative, b.relative))
  found

proc readCorpus*(root: string): Corpus =
  ## Read every case under `root`.
  ##
  ## The problems list is not an error report that can be ignored: a corpus
  ## with a problem is not a usable corpus, and the caller must refuse to
  ## qualify against it.
  var files = corpusFiles(root)
  var digest = digestInit()
  for f in files:
    let optional = isOptionalPath(f.relative)
    let read = readCaseFile(f.path, f.relative, optional)
    result.cases.add read.cases
    result.problems.add read.problems
    # The digest is computed over the bytes that were actually read, so
    # that the result identifies the tested corpus.
    digestUpdate(digest, $f.relative & "\n")
    try:
      digestUpdate(digest, readFile(f.path))
    except IOError:
      discard
    inc result.fileCount
  result.digest = digestOf(digest)

proc empty*(c: Corpus): bool =
  ## True when the corpus carries no cases at all.
  c.cases.len == 0
