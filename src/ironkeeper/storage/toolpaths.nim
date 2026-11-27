## The closed set of external observation tools.
##
## The executable paths are **fixed absolute paths**. There is no
## configuration file, no environment variable and no command line option
## through which an ordinary invocation can execute an arbitrary program.
##
## ## The test seam is a compile-time property
##
## The test harness injects controlled executables through the
## `IRONKEEPER_TEST_TOOL_DIR` seam. That seam exists **only** in a binary
## that was compiled with the `ironkeeperTesting` definition. A production
## binary does not read the variable at all, so an environment variable
## cannot make it execute an arbitrary program.
##
## The seam is not a plugin mechanism: it names a directory that holds an
## executable of the **same name** as the canonical tool, and nothing
## else. It does not widen the set of supported operations.

import std/[os, strutils]

from ironkeeper/core/version import TestingBuild, BuildVariant

const
  SmartctlPath* = "/usr/sbin/smartctl"
    ## The absolute path of `smartctl`.
  SgReadcapPath* = "/usr/bin/sg_readcap"
    ## The absolute path of `sg_readcap`.

  TestToolDirEnv* = "IRONKEEPER_TEST_TOOL_DIR"
    ## The environment variable through which the test harness injects
    ## controlled executables.
    ##
    ## It is honoured **only** by a test-enabled build.

type
  ToolPaths* = object
    ## The resolved paths of the observation tools.
    smartctl*: string
    sgReadcap*: string
    variant*: string
      ## The build variant that resolved the paths.

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
  ## The canonical absolute path is used unless this is a test-enabled
  ## build **and** the test seam names a directory that holds an
  ## executable of the same name.
  when TestingBuild:
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
            sgReadcap: resolveTool(SgReadcapPath),
            variant: BuildVariant)
