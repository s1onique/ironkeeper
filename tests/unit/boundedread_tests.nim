## Tests for the descriptor-based bounded reader.
##
## The reader is the boundary between the outside world and the strict
## JSON ingestion. It must never block on a FIFO, never read an endless
## source, never read more than the limit plus the overflow
## discriminator, and never leave a descriptor open.
##
## The substitution race is reproduced deterministically: the reader
## installs an open observer, and the test uses it to replace a regular
## file with a FIFO between the moment the path is named and the moment
## the descriptor is opened.

import std/[os, strutils]

import std/posix

import testkit

from ironkeeper/json/boundedread import openDocument, closeDocument,
  readDocument, setOpenObserver, ofNotRegularFile, rfTooLarge, rfCouldNotRead

proc createFifo(path: string) =
  ## Create a FIFO at `path`.
  ##
  ## The FIFO is a synthetic fixture. It is never written to and never
  ## read from: the reader must refuse it.
  if posix.mkfifo(path.cstring, posix.Mode(0o600)) != 0:
    raise newException(IOError, "cannot create the FIFO " & path)

proc runSuite*(): int =
  var t = newTestSuite("boundedread")

  let work = getTempDir() / ("ironkeeper-boundedread-" & $getCurrentProcessId())
  createDir(work)
  defer: removeDir(work)

  # --- an ordinary file -----------------------------------------------------
  let ordinary = work / "ordinary.json"
  writeFile(ordinary, "{\"a\": 1}")
  var opened = openDocument(ordinary)
  t.check("an ordinary file opens", opened.ok)
  if opened.ok:
    var read = readDocument(opened.descriptor, 1024)
    closeDocument(opened.descriptor)
    t.check("an ordinary file is read", read.ok)
    t.checkEq("the ordinary file is read exactly",
              if read.ok: read.text else: "", "{\"a\": 1}")

  # --- an oversized file ----------------------------------------------------
  let oversized = work / "oversized.json"
  writeFile(oversized, "x".repeat(4096))
  opened = openDocument(oversized)
  t.check("an oversized file opens", opened.ok)
  if opened.ok:
    var read = readDocument(opened.descriptor, 1024)
    closeDocument(opened.descriptor)
    t.check("an oversized file is refused", not read.ok)
    t.check("the refusal names the size limit",
            read.failure == rfTooLarge)

  # --- a directory ----------------------------------------------------------
  let directory = work / "directory"
  createDir(directory)
  opened = openDocument(directory)
  t.check("a directory does not open as a document", not opened.ok)
  t.check("the directory is refused as not a regular file",
          opened.failure == ofNotRegularFile)

  # --- a FIFO ---------------------------------------------------------------
  # The FIFO is opened with O_NONBLOCK, so the open returns immediately.
  # The descriptor is then refused because it is not a regular file.
  let fifo = work / "fifo"
  createFifo(fifo)
  opened = openDocument(fifo)
  t.check("a FIFO does not open as a document", not opened.ok)
  t.check("the FIFO is refused as not a regular file",
          opened.failure == ofNotRegularFile)

  # --- the substitution race ------------------------------------------------
  # A regular file is named, and it is replaced by a FIFO before the
  # descriptor is opened. The reader must refuse it, and it must not
  # block.
  let substituted = work / "substituted.json"
  writeFile(substituted, "{\"a\": 1}")
  let fifoTarget = work / "substituted-fifo"
  createFifo(fifoTarget)
  setOpenObserver(proc (path: string) =
    discard path
    removeFile(substituted)
    createFifo(substituted))
  var substitutedOpened = openDocument(substituted)
  setOpenObserver(nil)
  t.check("the substituted path does not open as a document",
          not substitutedOpened.ok)
  t.check("the substitution is refused as not a regular file",
          substitutedOpened.failure == ofNotRegularFile)

  # --- a symlink ------------------------------------------------------------
  # A symlink to a regular file is followed, and the *descriptor* is what
  # is verified. A symlink to a FIFO is refused.
  let target = work / "symlink-target.json"
  writeFile(target, "{\"b\": 2}")
  let link = work / "link.json"
  discard posix.symlink(target.cstring, link.cstring)
  opened = openDocument(link)
  t.check("a symlink to a regular file opens", opened.ok)
  if opened.ok:
    var read = readDocument(opened.descriptor, 1024)
    closeDocument(opened.descriptor)
    t.check("the symlink target is read", read.ok)
    t.checkEq("the symlink target is read exactly",
              if read.ok: read.text else: "", "{\"b\": 2}")

  let fifoLink = work / "fifo-link.json"
  discard posix.symlink(fifoTarget.cstring, fifoLink.cstring)
  opened = openDocument(fifoLink)
  t.check("a symlink to a FIFO is refused", not opened.ok)
  t.check("the symlink to a FIFO is refused as not a regular file",
          opened.failure == ofNotRegularFile)

  # --- a missing file -------------------------------------------------------
  opened = openDocument(work / "does-not-exist.json")
  t.check("a missing file does not open", not opened.ok)

  # --- the limit boundary ---------------------------------------------------
  # A document of exactly the limit is read; one byte more is refused.
  let exact = work / "exact.json"
  writeFile(exact, "y".repeat(1000))
  opened = openDocument(exact)
  t.check("the exact-size file opens", opened.ok)
  if opened.ok:
    var read = readDocument(opened.descriptor, 1000)
    closeDocument(opened.descriptor)
    t.check("a document of exactly the limit is read", read.ok)
    t.checkEq("the exact-size document is read in full",
              if read.ok: read.text.len else: -1, 1000)

  opened = openDocument(exact)
  if opened.ok:
    var read = readDocument(opened.descriptor, 999)
    closeDocument(opened.descriptor)
    t.check("a document one byte over the limit is refused", not read.ok)
    t.check("the over-limit refusal names the size limit",
            read.failure == rfTooLarge)

  t.finish()
