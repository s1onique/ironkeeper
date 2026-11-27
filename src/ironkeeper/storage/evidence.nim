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
##     the directory the operator supplied. The directory is created with
##     **restrictive permissions at creation** and with an **exclusive**
##     creation, so that a name collision is resolved by the kernel and
##     never by a check-then-create race.
##   * Every artefact is created **exclusively**: an existing file is
##     never overwritten, and a symlink is never followed.
##   * The identity of the parent directory is checked before and after
##     the export, so that a caller-controlled replacement of the parent
##     cannot silently redirect the write.
##   * The manifest is published **after** the artefacts it references are
##     finalised. A bundle without a manifest is a partial export, and it
##     never masquerades as a complete one.
##   * A SHA-256 digest is an integrity check over the preserved bytes. It
##     is not a proof of provenance or of authenticity.
##   * Malformed or incomplete tool output is preserved, and it is marked
##     as such in the manifest.

import std/[os, json, strutils, times, posix]

from ironkeeper/storage/types import DeviceRecord, Observation, ExecOutcome,
  confidenceName
from ironkeeper/storage/documents import nowUtc
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

proc parentIdentity(path: string): tuple[ok: bool, dev: int64, ino: int64] =
  ## The identity of the parent directory.
  ##
  ## The identity is the device number and the inode number. A caller
  ## that replaces the parent directory between the check and the write
  ## changes at least one of them.
  var st: Stat
  if stat(path.cstring, st) != 0:
    return (ok: false, dev: 0, ino: 0)
  (ok: true, dev: int64(st.st_dev), ino: int64(st.st_ino))

proc createExclusiveDir(path: string): bool =
  ## Create one directory with restrictive permissions, exclusively.
  ##
  ## The directory is created with mode 0700 **at creation**, so that it
  ## is never observable with wider permissions. The creation is
  ## exclusive: an existing directory makes it fail, and the caller
  ## chooses another name.
  # The mode is expressed through the `Mode` type of the platform, so that
  # the same source compiles where `mode_t` is 16 bits and where it is 32
  # bits.
  if mkdir(path.cstring, Mode(0x1c0)) != 0:
    return false
  true

proc writeExclusive(path: string, content: string): bool =
  ## Write one file exclusively, with restrictive permissions.
  ##
  ## The file is created with `O_EXCL`, so an existing file is never
  ## overwritten and a symlink is never followed. The permissions are
  ## 0600.
  let fd = posix.open(path.cstring, O_WRONLY or O_CREAT or O_EXCL,
                      Mode(0x180))
  if fd < 0:
    return false
  var bytes = newSeq[byte](content.len)
  if content.len > 0:
    copyMem(addr bytes[0], unsafeAddr content[0], content.len)
  var written = 0
  while written < bytes.len:
    let n = posix.write(fd, addr bytes[written], bytes.len - written)
    if n <= 0:
      discard posix.close(fd)
      return false
    written += n
  discard posix.close(fd)
  true

proc writeBundle*(parent: string, bundleId: string, device: DeviceRecord,
                  artifacts: seq[EvidenceArtifact],
                  observationDocument: JsonNode,
                  attributionBound: bool, attributionReason: string,
                  completeness: string, completenessReason = ""): EvidenceBundle =
  ## Write one evidence bundle below `parent`.
  ##
  ## The directory is created exclusively and with restrictive
  ## permissions, every artefact is created exclusively, and the manifest
  ## is published last. A bundle that was not finalised has no manifest,
  ## so a partial export never masquerades as a complete one.
  if not dirExists(parent):
    raise newException(IOError, "the evidence parent directory does not exist: " &
      parent)
  let before = parentIdentity(parent)
  if not before.ok:
    raise newException(IOError, "the evidence parent directory could not be " &
      "identified: " & parent)

  var directory = ""
  var counter = 0
  while directory.len == 0:
    var candidate = parent / uniqueDirectoryName()
    if counter > 0:
      candidate = parent / (uniqueDirectoryName() & "-" & $counter)
    inc counter
    if createExclusiveDir(candidate):
      directory = candidate

  var manifestArtifacts = newJArray()
  for a in artifacts:
    let path = directory / a.name
    if not writeExclusive(path, a.content):
      raise newException(IOError, "the evidence artefact could not be " &
        "created exclusively: " & path)
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
  if completenessReason.len > 0:
    complete["reason"] = newJString(completenessReason)
  manifest["completeness"] = complete
  manifest["artifacts"] = manifestArtifacts

  # The manifest is written last: it is published only after the artefacts
  # it references are finalised. It is created exclusively as well, so
  # that it can never replace a caller-owned file.
  let manifestPath = directory / "manifest.json"
  if not writeExclusive(manifestPath, manifest.pretty(2) & "\n"):
    raise newException(IOError, "the evidence manifest could not be " &
      "created exclusively: " & manifestPath)

  # The parent must still be the same directory. A caller-controlled
  # replacement of the parent is refused rather than silently accepted.
  let after = parentIdentity(parent)
  if not after.ok or after.dev != before.dev or after.ino != before.ino:
    raise newException(IOError, "the evidence parent directory changed " &
      "during the export: " & parent)

  EvidenceBundle(directory: directory, manifest: manifest)
