## The exit-status semantics of `smartctl`.
##
## The exit status of `smartctl` is a **bitmask**, not a Boolean. Each bit
## has its own meaning, and the meanings differ between protocols: the
## ATA bits do not apply identically to SCSI and NVMe.
##
## The bits that `smartctl` documents for the ATA protocol are:
##
## | bit | meaning |
## |---|---|
## | 0 | command line did not parse |
## | 1 | device open failed, or the device is not a SMART device |
## | 2 | some SMART or other ATA command failed |
## | 3 | the device reported that it is failing (pre-fail) |
## | 4 | the device reported a prefail attribute above its threshold |
## | 5 | the SMART log contains a prefail attribute above its threshold |
## | 6 | the SMART log contains an old ATA error record |
## | 7 | the SMART log contains a self-test log error record |
##
## The bits are decoded **independently**, and the original numeric status
## is preserved. A nonzero status does **not** mean that the collection
## failed: bit 3 in particular reports a *device-reported failing
## condition*, which is a health observation, not a collection failure.
##
## A status that embeds a different interpretation in the JSON document is
## a **contradiction** to be reported, not a value to be reconciled by
## picking the healthier answer.

import std/strutils

from ironkeeper/storage/types import Observation, ObservationStatus, osObserved,
  osUnsupported

const
  SmartBitCommandLine* = 1 shl 0
    ## The command line did not parse.
  SmartBitDeviceOpen* = 1 shl 1
    ## The device could not be opened or identified.
  SmartBitCommandFailed* = 1 shl 2
    ## A SMART or other command failed.
  SmartBitFailingStatus* = 1 shl 3
    ## The device reported that it is failing.
  SmartBitPrefailThreshold* = 1 shl 4
    ## A prefail attribute is above its threshold.
  SmartBitOldErrorLog* = 1 shl 5
    ## The SMART log contains an old error record.
  SmartBitSelfTestLog* = 1 shl 6
    ## The SMART log contains a self-test log error record.

type
  SmartExitBits* = object
    ## The decoded bits of a `smartctl` exit status.
    status*: int
      ## The original numeric status.
    commandLine*: bool
    deviceOpen*: bool
    commandFailed*: bool
    failingStatus*: bool
    prefailThreshold*: bool
    oldErrorLog*: bool
    selfTestLog*: bool

proc decodeSmartExit*(status: int): SmartExitBits =
  ## Decode the exit status of `smartctl`.
  result.status = status
  result.commandLine = (status and SmartBitCommandLine) != 0
  result.deviceOpen = (status and SmartBitDeviceOpen) != 0
  result.commandFailed = (status and SmartBitCommandFailed) != 0
  result.failingStatus = (status and SmartBitFailingStatus) != 0
  result.prefailThreshold = (status and SmartBitPrefailThreshold) != 0
  result.oldErrorLog = (status and SmartBitOldErrorLog) != 0
  result.selfTestLog = (status and SmartBitSelfTestLog) != 0

proc exitBitObservations*(bits: SmartExitBits, source: string,
                           collectedAt: string): seq[Observation] =
  ## Turn the decoded exit status into observations.
  ##
  ## A bit that is not set is reported as `observed` with the value
  ## `false`: the fact that the bit is absent is itself an observation.
  ## A bit whose meaning is protocol-dependent is reported with the
  ## protocol caveat in the reason.
  result = @[]
  template add(bitName: string, bitValue: bool, note: string) =
    result.add Observation(
      name: "smartctl.exit." & bitName,
      status: osObserved,
      value: (if bitValue: "true" else: "false"),
      unit: "boolean", source: source,
      sourceField: "smartctl exit status bit",
      collectedAt: collectedAt, reason: note)
  add("command_line", bits.commandLine,
      "the command line of the tool did not parse")
  add("device_open", bits.deviceOpen,
      "the device could not be opened or identified")
  add("command_failed", bits.commandFailed,
      "a SMART or other command failed")
  add("device_reported_failing", bits.failingStatus,
      "the device reported a failing condition; this is a device-reported " &
      "health observation and not a collection failure")
  add("prefail_threshold", bits.prefailThreshold,
      "a prefail attribute is above its threshold")
  add("old_error_log", bits.oldErrorLog,
      "the log contains an old error record")
  add("self_test_log", bits.selfTestLog,
      "the log contains a self-test log error record")
