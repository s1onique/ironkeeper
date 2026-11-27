## The acquisition result of one requested observation operation.
##
## ## Why this module exists
##
## The presence of an execution record says only that a process ran. It
## says nothing about what the process produced. A tool that was launched,
## timed out, produced truncated output, produced malformed JSON, or
## omitted a field that the operation needs leaves an execution record
## behind - and a bundle whose completeness is derived from that record
## claims complete evidence that does not exist.
##
## The acquisition result therefore keeps five things apart, because
## collapsing any two of them produces a wrong answer:
##
##   1. **execution outcome** - did the process run? (`ExecOutcome`)
##   2. **requested observation coverage** - were the requested
##      observations obtained? (`AcquisitionResult`)
##   3. **device-reported health** - what does the device say about
##      itself? (an ordinary observation value)
##   4. **attribution** - are the observations bound to the selected
##      device? (`Identity`)
##   5. **collection completeness** - the authoritative value that the
##      observation document, the evidence manifest, the human-readable
##      output and the process exit status all carry.
##
## ## The rules
##
## The coverage is incomplete when
##
##   * the tool could not be launched, timed out, or was terminated;
##   * the output was truncated by the configured bound;
##   * the response could not be ingested as JSON;
##   * a **mandatory** observation of the operation is missing;
##   * the observations contradict each other; or
##   * the attribution was refused.
##
## The coverage is **not** incomplete because
##
##   * the device reported an unhealthy status - a failing disk is a
##     device-reported health observation, and it may accompany a
##     complete acquisition; or
##   * an **optional** field was unavailable.
##
## Absence of evidence is never evidence of absence: a missing mandatory
## observation makes the acquisition incomplete, and the reason says which
## observation was missing.

import std/strutils

type
  AcquisitionState* = enum
    ## The authoritative completeness of one requested operation.
    asComplete
      ## Every mandatory observation of the operation was obtained.
    asIncomplete
      ## At least one mandatory observation is missing or contradicted.

  MandatoryObservation* = object
    ## One mandatory observation of a requested operation.
    name*: string
      ## The stable name of the observation.
    obtained*: bool
      ## True when the observation was obtained and is not contradicted.
    reason*: string
      ## Why the observation is missing or contradicted.

  AcquisitionResult* = object
    ## The coverage of one requested observation operation.
    state*: AcquisitionState
    mandatory*: seq[MandatoryObservation]
      ## The mandatory observations of the operation and their coverage.
    reasons*: seq[string]
      ## Human-readable explanations of the incomplete coverage.

proc newAcquisitionResult*(): AcquisitionResult =
  ## A result that claims nothing yet.
  result.state = asComplete
  result.mandatory = @[]
  result.reasons = @[]

proc require*(result: var AcquisitionResult, name: string) =
  ## Declare one mandatory observation of the operation.
  result.mandatory.add MandatoryObservation(name: name, obtained: false,
                                            reason: "")

proc obtained*(result: var AcquisitionResult, name: string) =
  ## Record that a mandatory observation was obtained.
  for m in result.mandatory.mitems:
    if m.name == name:
      m.obtained = true
      m.reason = ""
      return

proc missing*(result: var AcquisitionResult, name: string, reason: string) =
  ## Record that a mandatory observation is missing.
  for m in result.mandatory.mitems:
    if m.name == name:
      m.obtained = false
      m.reason = reason
      if reason.len > 0 and reason notin result.reasons:
        result.reasons.add reason
      result.state = asIncomplete
      return
  result.mandatory.add MandatoryObservation(name: name, obtained: false,
                                            reason: reason)
  if reason.len > 0 and reason notin result.reasons:
    result.reasons.add reason
  result.state = asIncomplete

proc contradicted*(result: var AcquisitionResult, name: string,
                    reason: string) =
  ## Record that a mandatory observation was contradicted.
  result.missing(name, reason)

proc refuseAttribution*(result: var AcquisitionResult, reason: string) =
  ## Record that the attribution of the observations was refused.
  ##
  ## Refused attribution makes the acquisition incomplete: the evidence
  ## exists, but it is not evidence *of the selected device*.
  result.state = asIncomplete
  if reason.len > 0 and reason notin result.reasons:
    result.reasons.add reason

proc incomplete*(result: var AcquisitionResult, reason: string) =
  ## Record that the acquisition did not complete.
  result.state = asIncomplete
  if reason.len > 0 and reason notin result.reasons:
    result.reasons.add reason

proc isComplete*(acquisition: AcquisitionResult): bool =
  ## True when the acquisition covered every mandatory observation.
  acquisition.state == asComplete

proc completenessName*(state: AcquisitionState): string =
  ## The stable wire name of the completeness state.
  ##
  ## The name is the one that the evidence manifest carries.
  case state
  of asComplete: "complete"
  of asIncomplete: "partial"

proc completenessReason*(acquisition: AcquisitionResult): string =
  ## The single-line reason of the completeness state.
  ##
  ## An incomplete acquisition always names its reason; an empty reason
  ## would let a reader assume that nothing is missing.
  if acquisition.isComplete:
    return ""
  if acquisition.reasons.len == 0:
    return "the acquisition did not complete"
  acquisition.reasons.join("; ")
