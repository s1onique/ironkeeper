## Typed contracts of the Ironkeeper storage observation domain.
##
## This module owns the vocabulary of M1: device classification, transport,
## identity confidence and the observation envelope. It contains no I/O and
## no policy: it says what a discovery adapter may report and what a
## normalisation adapter may produce, and nothing about what any of it
## means for the health of a device.
##
## ## The five independent domains
##
## M1 deliberately keeps five things apart, because collapsing any two of
## them produces a wrong answer:
##
##   1. **Execution outcome** - did the operation run? (`ExecOutcome`)
##   2. **Observation completeness** - what was actually seen?
##      (`ObservationStatus`)
##   3. **Device-reported health** - what does the device say about itself?
##      (an ordinary observation value, never a verdict)
##   4. **Identity confidence** - how sure are we *which* device this is?
##      (`IdentityConfidence`)
##   5. **Qualification verdict** - not assigned in M1 at all.
##
## A successfully collected SMART response may describe a failing disk.
## An unavailable SMART status is never converted into "SMART OK".

type
  DeviceClass* = enum
    ## The kind of block device Ironkeeper observed.
    dcPhysical
      ## A direct-attached physical disk candidate (SCSI/SAS, SATA, NVMe).
    dcPartition
      ## A partition of another block device.
    dcMapper
      ## A device-mapper device.
    dcRaid
      ## An MD RAID device.
    dcLoop
      ## A loop device.
    dcRam
      ## A RAM-backed device (ramdisk, zram).
    dcOptical
      ## An optical device.
    dcVirtual
      ## A virtual disk exposed through a hypervisor or a cloud interface.
    dcUnknown
      ## A device that could not be classified.

  Transport* = enum
    ## The transport a device is attached through.
    trSas
    trSata
    trNvme
    trScsi
      ## SCSI without a more specific transport attribution.
    trUnknown

  ObservationStatus* = enum
    ## How an observation was obtained.
    osObserved
      ## Read directly from the source.
    osDerived
      ## Computed from observed values by a documented rule.
    osUnavailable
      ## The source was reachable but did not provide the value.
    osUnsupported
      ## The source cannot provide the value for this device or protocol.
    osInvalid
      ## The source provided a value that could not be interpreted.
    osConflicting
      ## The source provided contradictory values.

  IdentityConfidence* = enum
    ## How much authority the identity of a device carries.
    icAuthoritative
      ## A persistent identifier that survives ordinary path changes.
    icProbable
      ## A weaker observation, for example a serial number.
    icAmbiguous
      ## The observations contradict each other, or two devices share them.
    icUnresolved
      ## Nothing that could identify the device was observed.

  ExecOutcome* = enum
    ## The outcome of an external tool invocation.
    eoSucceeded
      ## The process ran to completion and exited with status zero.
    eoNonZeroExit
      ## The process ran to completion and exited with a nonzero status.
    eoTimedOut
      ## The process exceeded the wall-clock deadline and was terminated.
    eoLaunchFailed
      ## The process could not be started.
    eoOutputLimit
      ## The process produced more output than the configured bound allows.
    eoSignalled
      ## The process was terminated by a signal.

  IdentifierKind* = enum
    ## The kind of a persistent identifier.
    ikScsiWwn
      ## A SCSI logical-unit WWN (VPD page 0x80 or the kernel `wwid`).
    ikAtaWwn
      ## An ATA World Wide Name.
    ikNguid
      ## An NVMe namespace global unique identifier.
    ikEui64
      ## An NVMe namespace EUI-64.
    ikNvmeUuid
      ## An NVMe namespace UUID.
    ikSerial
      ## A device serial number. A *weak* identifier on its own.
    ikDiskSeq
      ## The kernel disk sequence number.

  IdentifierNamespace* = enum
    ## Which object an identifier names.
    inLogicalUnit
      ## A SCSI logical unit.
    inNamespace
      ## An NVMe namespace.
    inController
      ## An NVMe controller.

  Identifier* = object
    ## One observed persistent identifier.
    kind*: IdentifierKind
    namespace*: IdentifierNamespace
    value*: string
      ## The canonical form of the identifier.
    original*: string
      ## The value exactly as it was observed, before canonicalisation.
    source*: string
      ## Where the identifier came from, for example `sysfs:wwid`.

  Identity* = object
    ## The reconciled identity of one device.
    confidence*: IdentityConfidence
    identifiers*: seq[Identifier]
    conflicts*: seq[string]
      ## Human-readable descriptions of contradictory observations.
    duplicateSerial*: bool
      ## True when another discovered device carries the same serial.

  Observation* = object
    ## One normalised observation.
    name*: string
      ## The stable name of the observed quantity.
    status*: ObservationStatus
    value*: string
      ## The exact value, as a canonical decimal string.
      ## Empty when the observation carries no value.
    unit*: string
      ## The unit of `value`. Never empty for an observed value.
    source*: string
      ## The backend that produced the observation.
    sourceField*: string
      ## The field or derivation the value came from.
    collectedAt*: string
      ## RFC 3339 timestamp of the collection.
    reason*: string
      ## Why the value is unavailable, unsupported, invalid or conflicting.

  DeviceRecord* = object
    ## One discovered block device.
    kernelName*: string
    major*: string
    minor*: string
    sysfsPath*: string
    deviceClass*: DeviceClass
    transport*: Transport
    rotational*: bool
    rotationalKnown*: bool
    vendor*: string
    model*: string
    serial*: string
    firmware*: string
    wwn*: string
    capacityBytes*: string
      ## Capacity in bytes, as an exact canonical decimal string.
    logicalBlockSize*: int
    physicalBlockSize*: int
    paths*: seq[string]
      ## Current access paths, for example `/dev/sdb`.
    aliases*: seq[string]
      ## Persistent aliases, for example `/dev/disk/by-id/...`.
    identity*: Identity
    findings*: seq[string]
      ## Findings that explain the classification or the exclusions.

  Inventory* = object
    ## The result of one passive discovery pass.
    devices*: seq[DeviceRecord]
    findings*: seq[string]
    root*: string
      ## The discovery root that was read.
    complete*: bool
      ## False when the enumeration itself failed. An enumeration failure is
      ## never reported as a successful empty inventory.

proc className*(c: DeviceClass): string =
  ## The stable wire name of a device class.
  case c
  of dcPhysical: "physical"
  of dcPartition: "partition"
  of dcMapper: "device_mapper"
  of dcRaid: "raid"
  of dcLoop: "loop"
  of dcRam: "ram"
  of dcOptical: "optical"
  of dcVirtual: "virtual"
  of dcUnknown: "unknown"

proc transportName*(t: Transport): string =
  ## The stable wire name of a transport.
  case t
  of trSas: "sas"
  of trSata: "sata"
  of trNvme: "nvme"
  of trScsi: "scsi"
  of trUnknown: "unknown"

proc statusName*(s: ObservationStatus): string =
  ## The stable wire name of an observation status.
  case s
  of osObserved: "observed"
  of osDerived: "derived"
  of osUnavailable: "unavailable"
  of osUnsupported: "unsupported"
  of osInvalid: "invalid"
  of osConflicting: "conflicting"

proc confidenceName*(c: IdentityConfidence): string =
  ## The stable wire name of an identity confidence.
  case c
  of icAuthoritative: "authoritative"
  of icProbable: "probable"
  of icAmbiguous: "ambiguous"
  of icUnresolved: "unresolved"

proc outcomeName*(o: ExecOutcome): string =
  ## The stable wire name of an execution outcome.
  case o
  of eoSucceeded: "succeeded"
  of eoNonZeroExit: "non_zero_exit"
  of eoTimedOut: "timed_out"
  of eoLaunchFailed: "launch_failed"
  of eoOutputLimit: "output_limit_exceeded"
  of eoSignalled: "signalled"

proc identifierKindName*(k: IdentifierKind): string =
  ## The stable wire name of an identifier kind.
  case k
  of ikScsiWwn: "scsi_wwn"
  of ikAtaWwn: "ata_wwn"
  of ikNguid: "nguid"
  of ikEui64: "eui64"
  of ikNvmeUuid: "nvme_uuid"
  of ikSerial: "serial"
  of ikDiskSeq: "disk_sequence_number"

proc identifierNamespaceName*(n: IdentifierNamespace): string =
  ## The stable wire name of an identifier namespace.
  case n
  of inLogicalUnit: "logical_unit"
  of inNamespace: "namespace"
  of inController: "controller"
