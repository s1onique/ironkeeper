## The exit-status semantics of `smartctl`.
##
## The exit status of `smartctl` is a **bitmask**, not a Boolean. Each bit
## has its own meaning, and the meanings differ between protocols: the
## ATA bits do not apply identically to SCSI and NVMe.
##
## ## The upstream definitions
##
## The bits are the ones that `smartctl` itself defines
## (`smartmontools/smartctl.h`):
##
## | bit | upstream name | meaning |
## |---|---|---|
## | 0 | `FAILCMD` | the command line did not parse, or an internal error occurred |
## | 1 | `FAILDEV` / `FAILPOWER` / `FAILID` | the device could not be opened, identified, or was in a power state that forbids the command |
## | 2 | `FAILSMART` | a SMART or other device command failed |
## | 3 | `FAILSTATUS` | the device reported a failing SMART status |
## | 4 | `FAILATTR` | a prefail attribute is at or below its threshold **now** |
## | 5 | `FAILAGE` | an attribute failed **in the past** |
## | 6 | `FAILERR` | the error log contains error records |
## | 7 | `FAILLOG` | the self-test log contains error records |
##
## The bits are decoded **independently**, and the original numeric status
## is preserved. A nonzero status does **not** mean that the collection
## failed: bit 3 in particular reports a *device-reported failing
## condition*, which is a health observation, not a collection failure.
##
## A status that embeds a different interpretation in the JSON document is
## a **contradiction** to be reported, not a value to be reconciled by
## picking the healthier answer.
##
## ## The limit of the decoding
##
## The exit status is a **bitmask of a process that ran**. A status that
## the process never produced - the synthetic `-1` of a launch failure, or
## the placeholder of a timeout - carries no bits at all. Such a status is
## never decoded as a bitmask; it is reported as the absence of an
## observation.

import std/strutils

from ironkeeper/storage/types import Observation, ObservationStatus, osObserved,
  osUnsupported, osUnavailable

const
  SmartBitCommandLine* = 1 shl 0
    ## The command line did not parse, or an internal error occurred.
  SmartBitDeviceOpen* = 1 shl 1
    ## The device could not be opened, identified, or was in a forbidden
    ## power state.
  SmartBitCommandFailed* = 1 shl 2
    ## A SMART or other device command failed.
  SmartBitFailingStatus* = 1 shl 3
    ## The device reported a failing SMART status.
  SmartBitPrefailThreshold* = 1 shl 4
    ## A prefail attribute is at or below its threshold now.
  SmartBitHistoricalThreshold* = 1 shl 5
    ## An attribute failed in the past.
  SmartBitErrorLog* = 1 shl 6
    ## The error log contains error records.
  SmartBitSelfTestLog* = 1 shl 7
    ## The self-test log contains error records.

type
  SmartExitBits* = object
    ## The decoded bits of a `smartctl` exit status.
    status*: int
      ## The original numeric status.
    observed*: bool
      ## True when the status came from a process that actually ran.
      ##
      ## A launch failure or a timeout produces no status; the bits are
      ## then not decoded at all.
    commandLine*: bool
    deviceOpen*: bool
    commandFailed*: bool
    failingStatus*: bool
    prefailThreshold*: bool
    historicalThreshold*: bool
    errorLog*: bool
    selfTestLog*: bool

proc decodeSmartExit*(status: int): SmartExitBits =
  ## Decode the exit status of `smartctl`.
  ##
  ## The status must be a status that a process produced. A negative
  ## status is the synthetic marker of a launch failure or a timeout; it
  ## is never decoded, because decoding it would invent an observation.
  result.status = status
  result.observed = status >= 0
  if not result.observed:
    return
  result.commandLine = (status and SmartBitCommandLine) != 0
  result.deviceOpen = (status and SmartBitDeviceOpen) != 0
  result.commandFailed = (status and SmartBitCommandFailed) != 0
  result.failingStatus = (status and SmartBitFailingStatus) != 0
  result.prefailThreshold = (status and SmartBitPrefailThreshold) != 0
  result.historicalThreshold = (status and SmartBitHistoricalThreshold) != 0
  result.errorLog = (status and SmartBitErrorLog) != 0
  result.selfTestLog = (status and SmartBitSelfTestLog) != 0

proc exitBitObservations*(bits: SmartExitBits, source: string,
                           collectedAt: string): seq[Observation] =
  ## Turn the decoded exit status into observations.
  ##
  ## A bit that is not set is reported as `observed` with the value
  ## `false`: the fact that the bit is absent is itself an observation.
  ## A bit whose meaning is protocol-dependent is reported with the
  ## protocol caveat in the reason.
  ##
  ## A status that no process produced yields **no** bit observations: the
  ## absence of an exit status is reported as an unavailable observation,
  ## never as eight `false` bits.
  result = @[]
  if not bits.observed:
    result.add Observation(
      name: "smartctl.exit.status", status: osUnavailable, value: "",
      unit: "bitmask", source: source,
      sourceField: "smartctl exit status", collectedAt: collectedAt,
      reason: "no tool process produced an exit status")
    return
  template add(bitName: string, bitValue: bool, note: string) =
    result.add Observation(
      name: "smartctl.exit." & bitName,
      status: osObserved,
      value: (if bitValue: "true" else: "false"),
      unit: "boolean", source: source,
      sourceField: "smartctl exit status bit",
      collectedAt: collectedAt, reason: note)
  add("command_line", bits.commandLine,
    "the command line of the tool did not parse, or an internal error occurred")
  add("device_open", bits.deviceOpen,
    "the device could not be opened, identified, or was in a power state " &
    "that forbids the command")
  add("command_failed", bits.commandFailed,
    "a SMART or other device command failed")
  add("device_reported_failing", bits.failingStatus,
    "the device reported a failing SMART status; this is a device-reported " &
    "health observation and not a collection failure")
  add("prefail_threshold", bits.prefailThreshold,
    "a prefail attribute is at or below its threshold now")
  add("historical_threshold", bits.historicalThreshold,
    "an attribute failed in the past")
  add("error_log", bits.errorLog,
    "the error log contains error records")
  add("self_test_log", bits.selfTestLog,
    "the self-test log contains error records")
