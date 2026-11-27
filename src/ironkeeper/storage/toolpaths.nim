## The closed set of external observation tools.
##
## The executable paths are **fixed absolute paths**. There is no
## configuration file, no environment variable and no command line option
## through which an ordinary invocation can execute an arbitrary program.
##
## The test harness injects a controlled executable through the
## `IRONKEEPER_TEST_TOOL_DIR` seam, which is honoured **only** when the
## directory exists and the resolved executable is a regular, executable
## file. The seam exists so that the tests exercise the production code
## path; it does not widen the set of supported operations.

import std/[os, strutils]

const
  SmartctlPath* = "/usr/sbin/smartctl"
    ## The absolute path of `smartctl`.
  SgReadcapPath* = "/usr/bin/sg_readcap"
    ## The absolute path of `sg_readcap`.

  TestToolDirEnv* = "IRONKEEPER_TEST_TOOL_DIR"
    ## The environment variable through which the test harness injects
    ## controlled executables.

type
  ToolPaths* = object
    ## The resolved paths of the observation tools.
    smartctl*: string
    sgReadcap*: string

proc posixAccessExecutable(path: string): bool =
  ## True when the file is executable by the current user.
  try:
    let info = getFileInfo(path)
    if info.permissions.contains(fpUserExec) or info.permissions.contains(fpGroupExec) or
       info.permissions.contains(fpOthersExec):
      return true
  except OSError:
    return false
  false

proc resolveTool*(canonical: string): string =
  ## Resolve the executable of one tool.
  ##
  ## The canonical absolute path is used unless the test seam names a
  ## directory that holds an executable of the same name.
  let testDir = getEnv(TestToolDirEnv)
  if testDir.len > 0 and dirExists(testDir):
    let candidate = testDir / canonical.extractFilename()
    if fileExists(candidate):
      try:
        if posixAccessExecutable(candidate):
          return candidate.absolutePath
      except OSError:
        discard
  canonical

proc defaultToolPaths*(): ToolPaths =
  ## The resolved tool paths of this invocation.
  ToolPaths(smartctl: resolveTool(SmartctlPath),
            sgReadcap: resolveTool(SgReadcapPath))
