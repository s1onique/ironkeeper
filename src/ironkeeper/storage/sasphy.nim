## Preliminary SAS PHY observations from sysfs.
##
## The kernel exposes the SAS PHY counters through
## `/sys/class/sas_phy/<phy>/`. The attributes that Ironkeeper reads are:
##
##   * `negotiated_linkrate` - the negotiated rate of *this* link;
##   * `invalid_dword_count`;
##   * `running_disparity_error_count`;
##   * `loss_of_dword_sync_count`;
##   * `phy_reset_problem_count`;
##   * `phy_identifier` and `sas_address`.
##
## Every PHY observation stays associated with the PHY it came from. The
## counters of unrelated PHYs are never aggregated, and the counters are
## never reset: reading them is the whole operation.
##
## ## What this module does not claim
##
## A 12 Gbit negotiation between a drive and an expander says nothing
## about the upstream path. This module records the link it observed and
## does not construct an expander graph, does not diagnose a shared
## transport bottleneck, and does not aggregate counters across ports.

import std/[os, strutils, tables]

from ironkeeper/storage/types import Observation, ObservationStatus, osObserved,
  osUnavailable

type
  SasPhyObservation* = object
    ## The observations of one SAS PHY.
    phyName*: string
    deviceType*: string
    sasAddress*: string
    negotiatedLinkRate*: string
    invalidDwordCount*: string
    runningDisparityErrorCount*: string
    lossOfDwordSyncCount*: string
    phyResetProblemCount*: string
    path*: string

proc readText(path: string): string =
  ## Read a sysfs attribute, or the empty string.
  try:
    if not fileExists(path):
      return ""
    result = readFile(path).strip()
  except IOError, OSError:
    result = ""

proc collectPhys*(sysfsRoot: string): seq[SasPhyObservation] =
  ## Collect the PHY observations of the host.
  ##
  ## The PHYs are read from `/sys/class/sas_phy`. A kernel that does not
  ## expose the SAS PHY class yields an empty collection, which means
  ## "this interface is not available", not "there are no errors".
  result = @[]
  let classDir = sysfsRoot / "class/sas_phy"
  if not dirExists(classDir):
    return
  var names: seq[string] = @[]
  for kind, path in walkDir(classDir):
    if kind == pcFile or dirExists(path) or fileExists(path):
      let name = path.extractFilename()
      if name.len > 0:
        names.add name
  names.sort()
  for name in names:
    let dir = classDir / name
    var observation = SasPhyObservation(phyName: name)
    observation.deviceType = readText(dir / "device_type")
    observation.sasAddress = readText(dir / "sas_address")
    observation.negotiatedLinkRate = readText(dir / "negotiated_linkrate")
    observation.invalidDwordCount = readText(dir / "invalid_dword_count")
    observation.runningDisparityErrorCount =
      readText(dir / "running_disparity_error_count")
    observation.lossOfDwordSyncCount = readText(dir / "loss_of_dword_sync_count")
    observation.phyResetProblemCount = readText(dir / "phy_reset_problem_count")
    observation.path = dir.absolutePath
    result.add observation

proc phyObservations*(phy: SasPhyObservation, collectedAt: string): seq[Observation] =
  ## Turn one PHY record into observations.
  ##
  ## A counter that the kernel does not expose becomes an observation with
  ## the status `unavailable`. It never becomes a zero.
  result = @[]
  template add(name: string, value: string, unit: string, field: string) =
    if value.len > 0:
      result.add Observation(name: name, status: osObserved, value: value,
                             unit: unit, source: "sysfs:sas_phy",
                             sourceField: field, collectedAt: collectedAt)
    else:
      result.add Observation(name: name, status: osUnavailable, value: "",
                             unit: unit, source: "sysfs:sas_phy",
                             sourceField: field, collectedAt: collectedAt,
                             reason: "the kernel did not expose " & field)
  add("sas.phy." & phy.phyName & ".negotiated_link_rate",
      phy.negotiatedLinkRate, "gbit_per_second", "negotiated_linkrate")
  add("sas.phy." & phy.phyName & ".invalid_dword_count",
      phy.invalidDwordCount, "dwords", "invalid_dword_count")
  add("sas.phy." & phy.phyName & ".running_disparity_error_count",
      phy.runningDisparityErrorCount, "dwords", "running_disparity_error_count")
  add("sas.phy." & phy.phyName & ".loss_of_dword_sync_count",
      phy.lossOfDwordSyncCount, "events", "loss_of_dword_sync_count")
  add("sas.phy." & phy.phyName & ".phy_reset_problem_count",
      phy.phyResetProblemCount, "events", "phy_reset_problem_count")
