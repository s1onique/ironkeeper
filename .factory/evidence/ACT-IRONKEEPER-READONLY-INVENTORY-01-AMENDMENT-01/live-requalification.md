# Operator live requalification procedure

The amendment changes the production acquisition, the identity and the
evidence behaviour. The predecessor's live capture therefore does not
requalify the amended implementation, and the operator executes the
procedure below.

## The artefact

The artefact is the **production** binary of the final subject:

* either the native CI artefact of the final subject (the recommended
  choice: it is the artefact that the gates were run against), or
* a binary that the operator builds on the storage host with the
  repository-owned `tools/build.sh`.

The **test-enabled** binary is never used for a live check: it honours
the fixture seams and it is not the qualified artefact.

The digest of the chosen artefact is recorded in the operator's own
run log. The digest of the CI artefact is the one recorded in
`native-ci.md`.

## The host prerequisite: the PCRE runtime library

The binary loads `libpcre.so.3` **dynamically at start-up**, because the
schema validator uses `std/re`. The check for the prerequisite is one
command, and it is the first step of the procedure:

```sh
# 0. the host must provide the PCRE1 runtime library
ldconfig -p | grep -q 'libpcre\.so\.3' || echo "PCRE1 runtime missing"
```

A host that does not provide it cannot run the binary at all: every
command fails immediately with

```
could not load: libpcre.so(.3|.1|)
```

This is not a defect of the artefact and it is not discovered by the
operator during the check: it is a **prerequisite of the host**, and
the operator resolves it before the procedure starts.

The known case is a distribution that has moved to PCRE2 only. Debian 13
(trixie) is one: it ships no `libpcre.so.3`, and no `libpcre3` package
exists for it. On such a host the operator provides a PCRE1 build of
the library, or runs the check on a host that still ships PCRE1. The
library is placed where the dynamic loader finds it; the procedure
itself installs nothing.

## The procedure

The procedure runs **only** passive discovery and the explicitly
selected read-only SMART and capacity observations. No self-test is
started, no surface is scanned and no other intrusive operation is
performed.

```sh
# 1. the passive inventory of the storage host
ironkeeper inventory list --json > inventory.json

# 2. the read-only observations of the one device the operator selects
ironkeeper device inspect --wwn "$EXPECTED_WWN" \
    --smart --capacity --allow-wake --json > observation.json

# 3. the evidence bundle of that inspection
ironkeeper device inspect --wwn "$EXPECTED_WWN" \
    --smart --capacity --allow-wake --evidence-dir ./evidence --json
```

The operator supplies `EXPECTED_WWN` locally. It is **not** committed.

## What the check must establish

| Item | Expected |
|---|---|
| the capacity | the exact byte count, with every digit; the value of `capacity.total_bytes` must equal the capacity that the host reports, and the comparison observation must not be `conflicting` |
| the protection format | the protection type must be one of `type_0`, `type_1`, `type_2`, `type_3`; a `missing` or `reserved_unsupported` value means that the tool did not report the protection information, and it is reported as such - it is never silently a `type_0` |
| the attribution | `attribution.status` must be `bound`; a `refused` status means that the device changed, that the rediscovery did not complete, or that the tool reported a contradictory identity |
| the device counters | the counters of the observation document must equal the counters that the tool reported, digit for digit, including the counters beyond 64 bits |
| the manifest completeness | `completeness.status` must be `complete`; a `partial` status names the observation that is missing in its `reason` |
| the evidence hashes | every `sha256` of the manifest must equal the SHA-256 of the preserved file, and the stored `observation.json` must agree with the emitted document |
| the previously unopenable device | if the operator inspects it, the result must be reported honestly: a launch failure, a timeout or a refused attribution is a *report*, not a defect of the operator's procedure |

## The exit status

The exit status of the inspection follows the completeness: `0` when
every requested observation was obtained, `3` when it was not. A `3` is
**not** a crash: the document on stdout is still the machine-readable
result, and it names the reason in `completeness.reason`.

## No host modification

The procedure installs nothing on the storage host and modifies nothing
on it. The only artefact that the procedure writes is the evidence
bundle that the operator asked for.
