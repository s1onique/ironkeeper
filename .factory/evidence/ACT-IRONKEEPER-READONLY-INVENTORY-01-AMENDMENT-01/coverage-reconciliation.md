# Coverage and receipt reconciliation (W10)

## The exact subject

| Item | Value |
|---|---|
| Executable subject | `build/ironkeeper` (production variant) and `build/ironkeeper-testing` (test-enabled variant) |
| Source revision of the subject | `3032d39fda9b2168681f028ae681b28344efc224` (the repair commit of this amendment) |
| Build toolchain | Nim 2.2.4, `--mm:orc`, release mode (`-d:release --opt:speed`) |
| Local execution environment | macOS arm64 - **not** the qualified native environment |
| Production digest (local build) | `f41d24225cf91bdc9976da337de92d373672980e4cb9817617917fbd517f10c9` |
| Test-enabled digest (local build) | `31ea021bf303679e0568af8f75223b5e5c3ae70177404fe9e174818bdb820f` |
| Authoritative executable | the native CI artefact of the final subject; see `native-ci.md` |
| Authoritative digest | the digest recorded by the native CI run of the final subject |

The digests above are the digests of the **local** build. They are
recorded so that the local subject is identifiable, and they are **not**
the digest of the qualified artefact: the qualified artefact is produced
by the native CI run, whose digest is recorded in `native-ci.md`.

## The reconciled identities

| Item | Value |
|---|---|
| Entry HEAD | `965940647a123bedb25dd609019208b4c84a967e` |
| Subject HEAD (the repair commit) | `3032d39fda9b2168681f028ae681b28344efc224` |
| Final HEAD (the last commit of the branch) | recorded in `exit-receipt.yaml` |
| CI head | the head of the native run recorded in `native-ci.md` |
| CI run | recorded in `native-ci.md` |
| Live-tested source revision | **none**: no live execution by the development agent was authorised |
| Build and runtime dependencies on the storage host | **unchanged**: the amendment adds no dependency and installs nothing |
| Authority for a host modification | **none**: no host modification was made |

## What was and was not tested

| Area | Status |
|---|---|
| Passive discovery | exercised against the synthetic tree and by the compiled-CLI suite |
| SMART acquisition and normalisation | exercised against the synthetic fixtures; the wire shapes are the upstream ones (`KEY_s`, `KEY_le`, the upstream exit bits) |
| Capacity acquisition and protection | exercised against the synthetic fixtures |
| Identity reconciliation and attribution | exercised against the synthetic fixtures, including the disappearance, the replacement, the failed rediscovery and the contradictory identity |
| Evidence bundle ownership | exercised against a real temporary directory |
| Live ATA / NVMe / SCSI interrogation | **not** exercised: no live execution by the development agent was authorised |
| Live passive discovery of the storage host | not exercised by the development agent |

The distinction between the live passive discovery of the predecessor and
the live SMART normalisation of the predecessor is preserved here: the
predecessor's live evidence established a passive inventory of the host
and a live SMART response for one device. The amendment changes the
acquisition, the identity and the evidence behaviour, so the predecessor's
live capture **does not** requalify the amended implementation.

## The bounded normalisation

The amendment normalises the individual self-test history records and the
ATA attribute records to the extent that M1 requires, and to no more:

* the **self-test log** is normalised to the **number of entries** that
  the document carries. The individual records are preserved verbatim in
  the evidence bundle and are **not** interpreted.
* the **ATA attribute table** is normalised to the presence of the table.
  The individual attributes are **not** interpreted: an ATA attribute
  carries a vendor-specific meaning, and a universal meaning must not
  be inferred from it. The raw table is preserved in the evidence bundle.

The gate that remains unmet for these two quantities is the one named in
`remaining-limitations.md`.

## The patch hygiene

The fixtures contain deliberate whitespace - a trailing space in a
synthetic vendor attribute, for example - and the fixtures are not
machine-read by the linter of the repository. The evidence files of this
ACT contain no such fixture whitespace, and no unrelated documentation
was expanded: the documentation changes are limited to the sections that
the repairs changed.
