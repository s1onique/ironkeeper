# LAB-IRK-SAS-INVENTORY-01 — live SAS inventory qualification

This runbook qualifies the M1 read-only inventory and observation
commands against the live SAS storage host.

The lab host is the existing Proxmox storage host with an HBA and two SAS
expanders. The **operator** executes the commands; the development agent
does not assume access to it.

## Before the run

1. Obtain the qualified Linux executable. The CI build publishes it as the
   artefact `build-evidence-<architecture>`, together with
   `executable-identity.txt`, which records the SHA-256 digest of the
   binary.

   ```sh
   # After downloading and unpacking the artefact:
   sha256sum build/ironkeeper
   # Compare with the digest in executable-identity.txt.
   ```

2. Verify the digest **before** running the binary. A digest that does not
   match means the artefact is not the qualified subject; stop.

3. Check the runtime dependency: the binary links the PCRE runtime
   dynamically (`libpcre.so.3` on Debian and Ubuntu).

   ```sh
   ldconfig -p | grep libpcre
   ```

4. Choose the evidence parent directory. It must already exist; the tool
   never creates the parent and never removes anything from it.

   ```sh
   export EVIDENCE_PARENT=/root/irk-evidence
   mkdir -p "$EVIDENCE_PARENT"
   ```

## Stage A — passive inventory

Run as an ordinary user where possible:

```sh
ironkeeper inventory list --json
```

Compare the observed inventory with the existing Linux tooling:

```sh
lsblk -o NAME,TYPE,SIZE,MODEL,SERIAL,WWN
ls -l /dev/disk/by-id/ | grep -E 'wwn|nvme-eui'
```

Check:

* every physical disk appears exactly once, despite its aliases;
* no partition, device-mapper, RAID, loop or ZFS device appears as a
  physical disk;
* the capacities agree with `lsblk` (both in bytes);
* the world-wide names agree with `/dev/disk/by-id/wwn-*`.

**No SMART or SCSI capacity command may be launched in this stage.** The
passive command opens no physical device and runs no observation tool.

## Stage B — one explicitly selected SAS drive

The operator identifies the expected stable WWN and verifies that the
intended device is safe to interrogate:

```sh
EXPECTED_WWN=0x5000cca0...        # supplied locally by the operator
```

Confirm the target before interrogating it:

```sh
ironkeeper inventory list --json | grep -A5 "$EXPECTED_WWN"
```

Then run the inspection:

```sh
sudo ironkeeper device inspect \
  --wwn "$EXPECTED_WWN" \
  --smart \
  --capacity \
  --allow-wake \
  --evidence-dir "$EVIDENCE_PARENT" \
  --json
```

`--allow-wake` is mandatory: a read-only SMART acquisition may wake a
sleeping device.

Cross-check against the tools directly:

```sh
smartctl -x --json=o "$DEVICE"
sg_readcap --readonly --long "$DEVICE"
```

Compare:

| Quantity | Ironkeeper | Cross-check |
|---|---|---|
| Device identity | `device.kernel_name`, `device.wwn`, `device.serial` | `lsblk`, `udevadm info` |
| Capacity | `capacity.total_bytes` | `sg_readcap --long` |
| Protection format | `protection.enabled`, `protection.raw_type`, `protection.type` | `sg_readcap --long` |
| SMART health | `device_reported_health` | `smart_status.passed` |
| Temperature | `scsi.temperature_current` | `smartctl -x` |
| Grown defects | `scsi.grown_defect_count` | `smartctl -x` |
| Corrected / uncorrected errors | `scsi.read_corrected`, `scsi.read_uncorrected` | `smartctl -x` |
| Non-medium errors | `scsi.non_medium_errors` | `smartctl -x` |
| Self-test history | `scsi.self_test_log_entries` | `smartctl -x` |
| SAS PHY observations | `sas.port_N.phy_M.*` | `smartctl -x`, `sg_ses` |

Check the evidence bundle:

```sh
ls -l "$EVIDENCE_PARENT"/*/
cat "$EVIDENCE_PARENT"/*/manifest.json
sha256sum "$EVIDENCE_PARENT"/*/smartctl.stdout
```

The digest in the manifest must match the preserved file.

## Stage C — the selected SAS fleet

Repeat Stage B **sequentially** for each explicitly selected SAS drive.
Never run two interrogations at once: the active interrogation
concurrency is one.

For each drive, compare the same quantities as in Stage B, and verify
that:

* the protection format is represented correctly, including Type 0 and
  any other format the fleet uses;
* the missing fields are classified honestly, as `unavailable` or
  `unsupported`, never as zero;
* the evidence bundles are internally consistent;
* every public JSON document validates:

  ```sh
  check-jsonschema --schemafile schemas/v1/observation.schema.json obs.json
  ```

## What must **not** happen

* No self-test may be started, aborted or modified.
* No surface read may be initiated.
* No disk may be qualified, admitted, retired or erased.
* No PHY counter may be reset.
* No Proxmox configuration may be changed.

## Live acceptance criteria

* The inventory agrees with the independently observed device identities.
* No accidental duplication from aliases.
* No unexpected active interrogation during the passive discovery.
* The explicit inspection produces the correct normalised observations.
* The protection formats are represented correctly.
* The missing fields are classified honestly.
* The evidence bundles are internally consistent.
* All public JSON documents validate.
* No unauthorised storage operation occurred.

## Recording the result

The observations stay **outside** the public repository. Only a sanitised
summary may be committed: the counts, the classifications and the
verdicts, never the serials, the WWNs, the host names or the raw
captures.
