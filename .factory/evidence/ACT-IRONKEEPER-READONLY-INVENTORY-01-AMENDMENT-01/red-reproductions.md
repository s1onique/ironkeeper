# RED — the defects, reproduced against the production path

Every defect below was reproduced **against the production path** before
it was repaired. The reproduction is a command and its observed output;
the witness that catches the defect is named in the last column.

## R1 — the production binary honours the test seams (W1)

The shipped binary read `IRONKEEPER_TEST_TOOL_DIR` and the three
discovery-root overrides. The reproduction supplied the synthetic
`tools-marker` directory and the synthetic sysfs root to the **production**
binary:

```text
$ IRONKEEPER_TEST_TOOL_DIR=tests/fixtures/storage/tools-marker \
  IRONKEEPER_MARKER_FILE=/tmp/marker \
  IRONKEEPER_SYSFS_ROOT=tests/fixtures/storage/sys \
  build/ironkeeper device inspect --wwn 5000c500a1b2c3d4 --smart --allow-wake --json
```

Before the repair the binary selected a device out of the **synthetic**
tree, which it must never do. After the repair the same command reports
`no device matches the selector` and the marker file is never created.

| Witness | `tests/integration/storage_cli_tests.nim`: "the production binary does not execute the marker" |

## R2 — the poll descriptor array loses the stream identity (W2)

The poll array was indexed as though stdout were always the first
element. When stdout reached end of file, stderr took its place and the
captured bytes were attributed to the wrong stream. The reproduction is
a child that closes stdout and keeps writing to stderr:

```text
/bin/sh -c "exec 1>&-; printf 'late-stderr-data' >&2; sleep 0.2"
```

Before the repair the standard error data ended up in the standard
output capture.

| Witness | `tests/unit/storage_witness_tests.nim`: "the standard error keeps its own data" |

## R3 — a failed launch is indistinguishable from exit 127 (W2)

The child exited with status 127 when `execve` failed, so a failed
launch and a program that legitimately returns 127 produced the same
result. The reproduction is an invocation of a path that does not exist
and a child that exits with 127.

| Witness | `tests/unit/storage_witness_tests.nim`: "a program that exits with 127 is not a launch failure" |

## R4 — the deadline stops applying after the pipes reach end of file (W2)

The capture loop ended when both streams were closed, and the child was
then awaited outside the deadline. A child that closes both streams and
keeps running was not terminated at the deadline.

| Witness | `tests/unit/storage_witness_tests.nim`: "a child that closes both streams is still bound by the deadline" |

## R5 — the SMART exit bits are misnamed (W5)

The implementation decoded bit 5 as an old error record, bit 6 as a
self-test log and bit 7 as an other error. The upstream definitions
(`smartmontools/smartctl.h`) are `FAILAGE` for bit 5, `FAILERR` for bit
6 and `FAILLOG` for bit 7. The reproduction is the decoding of every
bit and of several combinations.

| Witness | `tests/unit/storage_witness_tests.nim`: "the bit N is decoded independently" |

## R6 — a status that no process produced was decoded as a bitmask (W5)

The synthetic status `-1` of a launch failure and of a timeout was
decoded like a real status, so a failed acquisition produced eight
`false` bits that read like a healthy device.

| Witness | `tests/unit/storage_witness_tests.nim`: "a synthetic status yields no bit observations" |

## R7 — the numeric companions were invented (W5)

The implementation read `_raw` and `_hex` companions, which `smartctl`
does not emit. The real companions are `KEY_s` (the exact decimal value
as a string) and `KEY_le` (the raw bytes as a little-endian byte array).

| Witness | `tests/unit/storage_witness_tests.nim`: "an agreeing decimal companion is accepted" |

## R8 — the capacity arithmetic dropped the trailing zeros (W6)

The multiplication trimmed the decimal string at **both** ends, so the
capacity of the last logical block address 999 with a block length of
512 became `512` instead of `512000`.

| Witness | `tests/unit/storage_witness_tests.nim`: "the capacity conserves every digit" |

## R9 — an unavailable protection field was an observed zero (W6)

`decodeCapacity` defaulted `PROT_EN` and `P_TYPE` to zero, so a
response that carried no protection field produced `protection.type =
type_0` - a claim about the protection information that the tool never
made.

| Witness | `tests/unit/storage_witness_tests.nim`: "a missing protection field is never Type 0" |

## R10 — the completeness followed the presence of an execution record (W4)

The manifest completeness was `complete` when any execution record
existed. A tool that timed out, produced truncated output, produced
malformed JSON or omitted a mandatory field still leaves an execution
record behind.

| Witness | `tests/unit/storage_witness_tests.nim`: "a missing mandatory observation makes the acquisition incomplete" and the compiled-CLI exit-status witnesses |

## R11 — the post-collection lookup defaulted to the original device (W3)

The lookup after the collection initialised the replacement record with
the original device, so a device that had **disappeared** compared
equal and the attribution stayed bound.

| Witness | `tests/integration/storage_cli_tests.nim`: "a disappearing device refuses the attribution" |

## R12 — a replaced device kept the attribution (W3)

A device that was replaced by another device with the same kernel name,
the same device numbers and the same world-wide name compared equal,
because the disk sequence number was not part of the comparison.

| Witness | `tests/integration/storage_cli_tests.nim`: "a replaced device refuses the attribution" |

## R13 — a contradictory tool identity kept the attribution (W3)

The serial number that `smartctl` reported was never reconciled with the
serial number of the selected device.

| Witness | `tests/integration/storage_cli_tests.nim`: "a contradicting tool identity refuses the attribution" |

## R14 — the identity model discarded a source by precedence (W7)

The udev world-wide name was used only when the sysfs one was absent, so
a contradiction between the two sources was invisible, and an arbitrary
nonempty world-wide name earned authoritative confidence.

| Witness | `tests/unit/storage_witness_tests.nim`: "a conflicting world-wide name is ambiguous" and "an all-zero identifier is not usable" |

## R15 — the NVMe controller serial was a namespace identity (W7)

The serial number of an NVMe device was the serial number of the
**controller**. Two namespaces behind one controller carried the same
serial, so both of them were reported as ambiguous.

| Witness | `tests/unit/storage_witness_tests.nim`: "a shared controller serial is not a contradiction" |

## R16 — the evidence directory was not owned atomically (W8)

The bundle directory was created with `createDir` and then chmodded, and
the artefacts were written with `writeFile`, which follows a symlink and
overwrites an existing file.

| Witness | `tests/integration/storage_cli_tests.nim`: "a caller-owned file is preserved", together with the exclusive creation of the bundle directory and of every artefact |
