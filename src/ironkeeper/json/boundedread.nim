## Descriptor-based bounded reading of a JSON document.
##
## ## Why a descriptor and not a path
##
## The previous reader opened the path with a blocking `open`, and only
## then checked that the handle referred to a regular file. Between the
## `open` and the check, a regular file can be replaced by a FIFO. The
## blocking `open` of a FIFO with no writer blocks forever, and the
## process hangs before the check ever runs.
##
## A pathname pre-check does not close the window either: `stat` on the
## path and `open` on the path are two separate operations, and the file
## can be replaced between them. This module therefore **never trusts the
## pathname**. It opens the path once, with flags that cannot block, and
## then verifies the *opened descriptor* with `fstat`. The descriptor is
## the only thing that is read from, and it is verified before a single
## byte is consumed.
##
## ## The flags
##
##   * `O_RDONLY` — the input is never written to.
##   * `O_NONBLOCK` — opening a FIFO returns immediately instead of
##     waiting for a writer.
##   * `O_CLOEXEC` — the descriptor does not leak into a child process.
##
## The check is made on the descriptor, so the substitution is detected
## whatever the timing: a substituted FIFO is not a regular file, and the
## reader refuses it.
##
## ## The bound
##
## The reader consumes at most `limit + 1` bytes. The extra byte is the
## overflow discriminator: if it is present, the document exceeds the
## limit. The reader never reads the whole of an endless source into
## memory.
##
## ## Read errors
##
## A read error is classified independently of end-of-file. A short read
## is not an error; a failed read is an error, and it is reported as one.

when defined(windows):
  import std/winlean
else:
  import std/posix

proc openFlags*(): cint =
  ## The flags every document open uses.
  ##
  ## `O_RDONLY` — the input is never written to.
  ## `O_NONBLOCK` — opening a FIFO returns immediately instead of
  ## waiting for a writer.
  ## `O_CLOEXEC` — the descriptor does not leak into a child process.
  ##
  ## The flags are computed at run time because on some platforms they
  ## are imported constants rather than compile-time constants.
  O_RDONLY or O_NONBLOCK or O_CLOEXEC

type
  FileDescriptor* = distinct cint
    ## An open file descriptor.
    ##
    ## The type is distinct so that a descriptor cannot be confused with
    ## an ordinary integer, and so that a descriptor can never be used
    ## where a path is expected.

  OpenFailure* = enum
    ## The reason an open did not produce a usable descriptor.
    ofCouldNotOpen
      ## The path could not be opened at all.
    ofNotRegularFile
      ## The opened descriptor does not refer to a regular file.

  OpenResult* = object
    ## The outcome of opening a document.
    ok*: bool
    descriptor*: FileDescriptor
      ## The descriptor. It is valid only when `ok` is true.
    failure*: OpenFailure
      ## The reason the open failed.
    message*: string
      ## A human-readable description of the failure.

  ReadFailure* = enum
    ## The reason a read did not complete.
    rfNone
      ## The read completed.
    rfCouldNotRead
      ## The descriptor could not be read.
    rfTooLarge
      ## The document exceeded the limit.

  ReadResult* = object
    ## The outcome of a bounded read.
    ok*: bool
    text*: string
      ## The bytes that were read. It is valid only when `ok` is true.
    failure*: ReadFailure
      ## The reason the read failed.
    message*: string
      ## A human-readable description of the failure.

proc closeDocument*(descriptor: FileDescriptor) =
  ## Close a descriptor opened by `openDocument`.
  discard posix.close(cint(descriptor))

proc readDocument*(descriptor: FileDescriptor, limit: int): ReadResult =
  ## Read at most `limit + 1` bytes from `descriptor`.
  ##
  ## A read error is reported as an error and is never confused with
  ## end-of-file. The caller classifies the failure.
  var buffer = newString(limit + 1)
  var total = 0
  while total < buffer.len:
    let read = posix.read(cint(descriptor), addr buffer[total],
                           buffer.len - total)
    if read < 0:
      # A failed read is an error. It is not end-of-file.
      return ReadResult(ok: false, failure: rfCouldNotRead,
                        message: "the file could not be read")
    if read == 0:
      # End of file.
      break
    total += read
  if total > limit:
    return ReadResult(ok: false, failure: rfTooLarge,
                      message: "the document exceeds the maximum size of " &
                               $limit & " bytes")
  ReadResult(ok: true, text: buffer[0 ..< total])

type
  OpenObserver* = proc (path: string) {.closure.}
    ## A hook that observes an open attempt.
    ##
    ## The hook exists so that a test can substitute the file between the
    ## moment the path is named and the moment the descriptor is opened.
    ## It is the deterministic reproduction of the substitution race that
    ## a pathname pre-check cannot close.

var
  openObserver: OpenObserver = nil
    ## The installed observer. It is nil in production.

proc setOpenObserver*(observer: OpenObserver) =
  ## Install an open observer. Pass nil to remove it.
  openObserver = observer

proc openDocument*(path: string): OpenResult =
  ## Open `path` for reading, and verify that the opened descriptor
  ## refers to a regular file.
  ##
  ## The descriptor is opened with `O_NONBLOCK`, so a FIFO does not
  ## block the open. The regularity is decided by `fstat` on the
  ## *descriptor*, never by a `stat` on the path.
  ##
  ## When an open observer is installed, it is called with the path
  ## *before* the descriptor is opened. A test uses it to substitute the
  ## file.
  if not openObserver.isNil:
    openObserver(path)
  var raw: cint
  try:
    raw = posix.open(path.cstring, openFlags())
  except CatchableError as e:
    return OpenResult(ok: false, failure: ofCouldNotOpen,
                      message: e.msg)
  if raw < 0:
    return OpenResult(ok: false, failure: ofCouldNotOpen,
                      message: "the file could not be opened")
  var info: Stat
  if posix.fstat(raw, info) != 0:
    discard posix.close(raw)
    return OpenResult(ok: false, failure: ofCouldNotOpen,
                      message: "the opened file could not be inspected")
  if not S_ISREG(info.st_mode):
    discard posix.close(raw)
    return OpenResult(ok: false, failure: ofNotRegularFile,
                      message: "the opened file is not a regular file")
  OpenResult(ok: true, descriptor: FileDescriptor(raw))
