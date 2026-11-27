## The bounded external-tool execution boundary of Ironkeeper.
##
## Every observation tool (`smartctl`, `sg_readcap`) is executed through
## this module and through nothing else. It is a *boundary*, not a workflow
## engine: there is no plugin mechanism, no job queue and no background
## worker pool.
##
## ## The guarantees
##
##   * the executable is an **absolute path**; there is no PATH search and
##     no shell interpolation anywhere;
##   * the arguments are an **argument vector**;
##   * the environment is **controlled**: the child receives exactly the
##     variables the caller specified, plus a fixed `LC_ALL=C` and
##     `LANG=C`, so that the tool's output does not depend on the
##     operator's locale;
##   * stdout and stderr are captured **separately** and are bounded
##     **independently**;
##   * both streams are drained concurrently, so a tool that fills one pipe
##     while the parent fills the other cannot deadlock;
##   * a **monotonic wall-clock deadline** is enforced;
##   * on timeout or on an output-limit violation the whole **process
##     group** is terminated, so no descendant is left running;
##   * the child is always **reaped**;
##   * the actual outcome is classified: timeout, launch failure, signal
##     termination, output-limit violation and an ordinary nonzero exit
##     are five different things.
##
## ## The tool override seam
##
## The executable path is a parameter of `runTool`, but the *public* CLI
## never passes a caller-supplied path. The test harness injects a
## controlled executable through an explicit, documented seam; ordinary
## live invocations use the fixed, trusted absolute paths of `toolpaths.nim`.

import std/[os, posix, strutils, monotimes, times, sets]

from ironkeeper/storage/types import ExecOutcome, eoSucceeded, eoNonZeroExit,
  eoTimedOut, eoLaunchFailed, eoOutputLimit, eoSignalled

const
  DefaultDeadlineMs* = 30000
    ## The default wall-clock deadline of one tool invocation.
  DefaultMaxStdoutBytes* = 4 * 1024 * 1024
    ## The default bound on the captured standard output.
  DefaultMaxStderrBytes* = 256 * 1024
    ## The default bound on the captured standard error.

type
  ExecLimits* = object
    ## The bounds of one invocation.
    deadlineMs*: int
    maxStdoutBytes*: int
    maxStderrBytes*: int

  ExecRequest* = object
    ## One bounded invocation.
    path*: string
      ## The absolute path of the executable.
    args*: seq[string]
      ## The argument vector, without the program name.
    limits*: ExecLimits
    env*: seq[string]
      ## The controlled environment, as `NAME=VALUE` entries.

  ExecResult* = object
    ## The classified outcome of one invocation.
    outcome*: ExecOutcome
    exitCode*: int
      ## The exit status of the process. Meaningful for `eoSucceeded` and
      ## `eoNonZeroExit`.
    signal*: int
      ## The terminating signal, when the process was signalled.
    stdout*: string
    stderr*: string
    stdoutTruncated*: bool
    stderrTruncated*: bool
    ioFailed*: bool
      ## True when a poll or a read of a stream failed.
      ##
      ## A failed capture is never reported as a complete capture.
    unreaped*: bool
      ## True when the child could not be reaped within the supported
      ## policy.
      ##
      ## The process state is then **unresolved**: the result never claims
      ## a clean completion.
    durationMs*: int
    message*: string
      ## A human-readable explanation of a failure.

proc defaultLimits*(): ExecLimits =
  ## The default bounds.
  ExecLimits(deadlineMs: DefaultDeadlineMs,
             maxStdoutBytes: DefaultMaxStdoutBytes,
             maxStderrBytes: DefaultMaxStderrBytes)

var
  keepAlive: seq[string]
    ## The strings whose bytes the argument and environment vectors point
    ## into.
    ##
    ## The vectors must stay valid until `execve` has read them, which
    ## happens in the child process. The strings are therefore kept here,
    ## for the lifetime of the process, instead of in a local scope that
    ## would release them before the call.

  keepVectors: seq[seq[cstring]]
    ## The vector storage itself.
    ##
    ## The array of pointers is allocated on the heap and must not be
    ## released before `execve` has read it. The arrays are therefore
    ## retained for the lifetime of the process.

proc toCStringArray(items: seq[string]): ptr UncheckedArray[cstring] =
  ## Build a NUL-terminated `char**` from a sequence of strings.
  ##
  ## The bytes of the strings and the array of pointers are retained for
  ## the lifetime of the process, because the vector is read by `execve`
  ## after this procedure has returned.
  var pointers = newSeq[cstring](items.len + 1)
  for i, item in items:
    keepAlive.add item
    pointers[i] = keepAlive[^1].cstring
  pointers[items.len] = nil
  keepVectors.add pointers
  cast[ptr UncheckedArray[cstring]](addr keepVectors[^1][0])

proc decodeStatus(status: cint): tuple[exited: bool, code: int, signal: int] =
  ## Decode a wait status without relying on the platform macros.
  let raw = cast[cint](status)
  if (raw and 0x7f) == 0:
    (exited: true, code: (raw shr 8) and 0xff, signal: 0)
  else:
    (exited: false, code: 0, signal: raw and 0x7f)


proc runTool*(req: ExecRequest): ExecResult =
  ## Execute one trusted tool under the documented bounds.
  ##
  ## The function never raises for an ordinary failure: every outcome is
  ## reported in the result.
  result.outcome = eoLaunchFailed
  result.exitCode = -1
  result.signal = 0
  result.durationMs = 0

  if not req.path.startsWith("/"):
    result.message = "the tool path is not absolute: " & req.path
    return
  if not fileExists(req.path):
    result.message = "the tool does not exist: " & req.path
    return

  let limits =
    if req.limits.deadlineMs > 0: req.limits else: defaultLimits()
  let maxOut =
    if req.limits.maxStdoutBytes > 0: req.limits.maxStdoutBytes
    else: DefaultMaxStdoutBytes
  let maxErr =
    if req.limits.maxStderrBytes > 0: req.limits.maxStderrBytes
    else: DefaultMaxStderrBytes

  let started = getMonoTime()

  var outPipe: array[2, cint]
  var errPipe: array[2, cint]
  var execPipe: array[2, cint]
  if pipe(outPipe) != 0:
    result.message = "the output pipe could not be created"
    return
  if pipe(errPipe) != 0:
    discard close(outPipe[0]); discard close(outPipe[1])
    result.message = "the error pipe could not be created"
    return
  if pipe(execPipe) != 0:
    discard close(outPipe[0]); discard close(outPipe[1])
    discard close(errPipe[0]); discard close(errPipe[1])
    result.message = "the launch-status pipe could not be created"
    return
  # The write end of the launch-status pipe is closed by `execve` itself.
  # The parent therefore sees end of file when the program started, and
  # the error code when it did not.
  discard fcntl(execPipe[1], F_SETFD, FD_CLOEXEC)

  var argv = @[req.path]
  for a in req.args:
    argv.add a
  # A controlled environment: the caller's variables, plus a fixed locale.
  var env = @["LC_ALL=C", "LANG=C", "PATH=/usr/sbin:/usr/bin:/sbin:/bin"]
  for e in req.env:
    env.add e

  let pid = fork()
  if pid < 0:
    discard close(outPipe[0]); discard close(outPipe[1])
    discard close(errPipe[0]); discard close(errPipe[1])
    discard close(execPipe[0]); discard close(execPipe[1])
    result.message = "the process could not be forked"
    return

  if pid == 0:
    # ---- the child -------------------------------------------------------
    # Its own process group, so that the whole group can be terminated.
    discard setpgid(0, 0)
    discard dup2(outPipe[1], 1)
    discard dup2(errPipe[1], 2)
    discard close(outPipe[0]); discard close(outPipe[1])
    discard close(errPipe[0]); discard close(errPipe[1])
    discard close(execPipe[0])
    let cargv = toCStringArray(argv)
    let cenv = toCStringArray(env)
    discard execve(req.path.cstring, cargv, cenv)
    # `execve` returns only on failure. The error code is reported to the
    # parent, so that a failed launch is never confused with a program
    # that ran and exited with status 127.
    let code = osLastError().int32
    var codeBytes: array[4, char]
    copyMem(addr codeBytes[0], addr code, 4)
    discard posix.write(execPipe[1], addr codeBytes[0], 4)
    # The child leaves immediately after the failed launch. It does not
    # flush the standard streams: a flush in a forked child would repeat
    # whatever the parent had buffered.
    discard kill(getpid(), SIGKILL)

  # ---- the parent --------------------------------------------------------
  # The child sets its own process group; setting it here as well closes
  # the race in which the parent would signal the wrong group.
  discard setpgid(pid, pid)
  discard close(outPipe[1])
  discard close(errPipe[1])
  discard close(execPipe[1])

  # ---- did the program start? ---------------------------------------------
  # End of file on the launch-status pipe means that `execve` succeeded.
  # A code on it means that the program never started.
  var launchCode = 0'i32
  var launchBytes: array[4, char]
  var launchRead = 0
  while launchRead < 4:
    let n = posix.read(execPipe[0], addr launchBytes[launchRead], 4 - launchRead)
    if n <= 0:
      break
    launchRead += n
  discard close(execPipe[0])
  if launchRead == 4:
    copyMem(addr launchCode, addr launchBytes[0], 4)
    discard close(outPipe[0])
    discard close(errPipe[0])
    var status: cint = 0
    discard waitpid(pid, status, 0)
    result.message = "the tool could not be executed: " & osErrorMsg(
      OSErrorCode(launchCode))
    return

  var stdoutBuf = newStringOfCap(4096)
  var stderrBuf = newStringOfCap(1024)
  var outTruncated = false
  var errTruncated = false
  var outOpen = true
  var errOpen = true
  var timedOut = false
  var ioFailed = false
  var reaped = false
  var status: cint = 0

  let deadline = started + initDuration(milliseconds = limits.deadlineMs)

  var buffer: array[8192, char]

  # The poll descriptor array carries the **identity** of each stream.
  # A descriptor array that is indexed as though stdout were always the
  # first element loses that identity as soon as stdout reaches end of
  # file and stderr takes its place.
  var fds: array[2, TPollfd]
  var streamOf: array[2, int]   # 0 is the standard output, 1 the error output

  while true:
    let now = getMonoTime()
    if now >= deadline:
      # The deadline is authoritative, including after the pipes reached
      # end of file: a child that closed both streams and kept running is
      # still terminated here.
      timedOut = true
      break
    let remaining = (deadline - now).inMilliseconds

    var count = 0
    if outOpen:
      fds[count] = TPollfd(fd: outPipe[0], events: int16(POLLIN))
      streamOf[count] = 0
      inc count
    if errOpen:
      fds[count] = TPollfd(fd: errPipe[0], events: int16(POLLIN))
      streamOf[count] = 1
      inc count

    if count > 0:
      let waitMs = min(remaining, 100).cint
      let ready = poll(addr fds[0], Tnfds(count), waitMs)
      if ready < 0:
        if osLastError() == OSErrorCode(EINTR):
          # An interrupted poll is not a failure: the call is repeated.
          continue
        ioFailed = true
        break
      if ready == 0:
        continue
      for i in 0 ..< count:
        if (fds[i].revents.int and (POLLIN.int or POLLHUP.int or
            POLLERR.int)) == 0:
          continue
        let isOut = streamOf[i] == 0
        let fd = fds[i].fd
        let n = posix.read(fd, addr buffer[0], buffer.len)
        if n > 0:
          var chunk = newString(n)
          copyMem(addr chunk[0], addr buffer[0], n)
          if isOut:
            let room = maxOut - stdoutBuf.len
            if chunk.len > room:
              stdoutBuf.add chunk[0 ..< room]
              outTruncated = true
            else:
              stdoutBuf.add chunk
          else:
            let room = maxErr - stderrBuf.len
            if chunk.len > room:
              stderrBuf.add chunk[0 ..< room]
              errTruncated = true
            else:
              stderrBuf.add chunk
        else:
          # End of stream, or a read error. Either way the capture of this
          # stream ends; it is never reported as a complete capture.
          if isOut: outOpen = false else: errOpen = false
    else:
      # Both streams reached end of file. The child may still be running,
      # so the deadline still applies: the child is awaited, and it is
      # terminated when the deadline expires.
      let got = waitpid(pid, status, WNOHANG)
      if got == pid:
        reaped = true
        break
      if got < 0:
        break
      sleep(10)

    if outTruncated or errTruncated:
      break

  # ---- terminate the group if necessary ----------------------------------
  if timedOut or outTruncated or errTruncated:
    # The child leads its own group, so the negative pid addresses it.
    # A `SIGKILL` is a request, not a guarantee: a task that is blocked in
    # uninterruptible kernel I/O does not die from it.
    discard kill(-pid, SIGTERM)
    sleep(50)
    discard kill(-pid, SIGKILL)

  # ---- reap --------------------------------------------------------------
  if not reaped:
    let reapDeadline = getMonoTime() + initDuration(seconds = 5)
    while getMonoTime() < reapDeadline:
      let got = waitpid(pid, status, WNOHANG)
      if got == pid:
        reaped = true
        break
      if got < 0:
        break
      sleep(10)
  if not reaped:
    # The process could not be reaped within the supported policy. Its
    # state is **unresolved**, and the result says so instead of claiming
    # a clean completion.
    discard kill(-pid, SIGKILL)
    let got = waitpid(pid, status, 0)
    if got == pid:
      reaped = true

  discard close(outPipe[0])
  discard close(errPipe[0])

  result.stdout = stdoutBuf
  result.stderr = stderrBuf
  result.stdoutTruncated = outTruncated
  result.stderrTruncated = errTruncated
  result.ioFailed = ioFailed
  result.durationMs = (getMonoTime() - started).inMilliseconds

  if timedOut:
    result.outcome = eoTimedOut
    result.message = "the tool exceeded the deadline of " &
      $limits.deadlineMs & " ms and was terminated"
    if not reaped:
      result.unreaped = true
      result.message = result.message &
        "; the process could not be reaped within the supported policy and " &
        "its state is unresolved"
    return
  if outTruncated or errTruncated:
    result.outcome = eoOutputLimit
    result.message = "the tool produced more output than the configured bound"
    if not reaped:
      result.unreaped = true
      result.message = result.message &
        "; the process could not be reaped within the supported policy and " &
        "its state is unresolved"
    return
  if not reaped:
    # The termination was requested, but the exit status of the child is
    # unknown. The outcome is therefore not claimed to be clean.
    result.outcome = eoSignalled
    result.unreaped = true
    result.message = "the tool process could not be reaped within the " &
      "supported policy; its state is unresolved"
    return

  let decoded = decodeStatus(status)
  if decoded.exited:
    result.exitCode = decoded.code
    if decoded.code == 0:
      result.outcome = eoSucceeded
    else:
      result.outcome = eoNonZeroExit
      result.message = "the tool exited with status " & $decoded.code
  else:
    result.signal = decoded.signal
    result.outcome = eoSignalled
    result.message = "the tool was terminated by signal " & $decoded.signal
