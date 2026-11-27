## The invocation-scoped evidence bundle.
##
## An evidence bundle is a **directory** that the operator asked for. It
## is not a database, and it is not written unless the operator asked for
## it explicitly.
##
## The bundle contains:
##
##   * `manifest.json` - the manifest of the bundle;
##   * `observation.json` - the normalised observation document;
##   * `smartctl.stdout`, `smartctl.stderr` - the preserved raw responses;
##   * `capacity.stdout`, `capacity.stderr` - the preserved raw responses.
##
## ## The rules
##
##   * The bundle lives in a **unique, invocation-owned** directory below
##     the directory the operator supplied. A caller-owned file is never
##     overwritten, and a caller-owned directory is never removed.
##   * The files are written with **restrictive permissions**.
##   * The manifest is published **after** the artefacts it references are
##     finalised.
##   * A SHA-256 digest is an integrity check over the preserved bytes. It
##     is not a proof of provenance or of authenticity.
##   * Malformed or incomplete tool output is preserved, and it is marked
##     as such in the manifest.

import std/[os, json, strutils, times]

from ironkeeper/storage.types import DeviceRecord, Observation, ExecOutcome,
  confidenceName
from ironkeeper/storage.documents import nowUtc
from ironkeeper/util/sha256 import sha256

type
  EvidenceArtifact* = object
    ## One preserved artefact.
    name*: string
    content*: string
    kind*: string
    tool*: string
    outcome*: string
    exitStatus*: int
    note*: string

  EvidenceBundle* = object
    ## The bundle that was written.
    directory*: string
    manifest*: JsonNode

proc sha256Hex*(data: string): string =
  ## The lowercase hex SHA-256 digest of the bytes.
  ##
  ## The digest is computed over the exact bytes that were written.
  result = sha256(data.toOpenArrayByte(0, data.len - 1))

proc uniqueDirectoryName*(): string =
  ## A unique name for an invocation-owned bundle directory.
  let stamp = now().utc.format("yyyyMMdd'T'HHmmss")
  result = "invocation-" & stamp & "-" & $getCurrentProcessId()

proc writeBundle*(parent: string, bundleId: string, device: DeviceRecord,
                  artifacts: seq[EvidenceArtifact],
                  observationDocument: JsonNode,
                  attributionBound: bool, attributionReason: string,
                  completeness: string): EvidenceBundle =
  ## Write one evidence bundle below `parent`.
  ##
  ## The directory is created with restrictive permissions and is never
  ## merged into an existing directory: a name collision is resolved by
  ## appending a counter, so that a caller-owned file is never
  ## overwritten.
  if not dirExists(parent):
    raise newException(IOError, "the evidence parent directory does not exist: " &
      parent)
  var directory = parent / uniqueDirectoryName()
  var counter = 1
  while dirExists(directory) or fileExists(directory):
    directory = parent / (uniqueDirectoryName() & "-" & $counter)
    inc counter
  createDir(directory)
  setFilePermissions(directory, {fpUserRead, fpUserWrite, fpUserExec})

  var manifestArtifacts = newJArray()
  for a in artifacts:
    let path = directory / a.name
    writeFile(path, a.content)
    setFilePermissions(path, {fpUserRead, fpUserWrite})
    var entry = newJObject()
    entry["name"] = newJString(a.name)
    entry["byte_length"] = newJInt(a.content.len)
    entry["sha256"] = newJString(sha256Hex(a.content))
    entry["kind"] = newJString(a.kind)
    if a.tool.len > 0:
      entry["tool"] = newJString(a.tool)
    if a.outcome.len > 0:
      entry["outcome"] = newJString(a.outcome)
    entry["exit_status"] = newJInt(a.exitStatus)
    if a.note.len > 0:
      entry["note"] = newJString(a.note)
    manifestArtifacts.add entry

  var manifest = newJObject()
  manifest["schema_version"] = newJInt(1)
  manifest["bundle_id"] = newJString(bundleId)
  manifest["created_at"] = newJString(nowUtc())
  var target = newJObject()
  target["kernel_name"] = newJString(device.kernelName)
  var paths = newJArray()
  for p in device.paths:
    paths.add newJString(p)
  target["paths"] = paths
  target["identity_confidence"] = newJString(confidenceName(device.identity.confidence))
  manifest["target"] = target
  var attribution = newJObject()
  attribution["status"] = newJString(if attributionBound: "bound" else: "refused")
  if attributionReason.len > 0:
    attribution["reason"] = newJString(attributionReason)
  manifest["attribution"] = attribution
  var complete = newJObject()
  complete["status"] = newJString(completeness)
  manifest["completeness"] = complete
  manifest["artifacts"] = manifestArtifacts

  # The manifest is written last: it is published only after the artefacts
  # it references are finalised.
  let manifestPath = directory / "manifest.json"
  writeFile(manifestPath, manifest.pretty(2) & "\n")
  setFilePermissions(manifestPath, {fpUserRead, fpUserWrite})

  EvidenceBundle(directory: directory, manifest: manifest)
