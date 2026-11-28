# Coverage and receipt reconciliation (W10)

## The exact subject

| Item | Value |
|---|---|
| Executable subject | `build/ironkeeper` (production variant) and `build/ironkeeper-testing` (test-enabled variant) |
| Source revision of the subject | `0f88baefbba610bb492ad4fe9fa7cef701941ab2` (the last commit that changed the production code) |
| Qualified head | `11824b7701cc9104944be8ec49f66132f54c2a4c` (the head of the green native run `46141549489`) |
| Build toolchain | Nim 2.4.2 (the pinned version), `--mm:orc`, release mode (`-d:release --opt:speed`) |
| Local execution environment | macOS arm64 - **not** the qualified native environment |
| Authoritative executable | the native CI artefact `build/ironkeeper` of the qualified head; see `native-ci.md` |
| Authoritative digest | the digest that the native run recorded in `executable-identity.txt`; the digests of the published artefacts are in `native-ci.md` |

The local build is **not** the qualified artefact: the qualified artefact
is produced by the native CI run, which records the digest of each
variant in `executable-identity.txt`. The development agent did not
retrieve the artefact, because the retrieval needs administrative rights
on the repository that this agent does not have.

## The reconciled identities

| Item | Value |
|---|---|
| Entry HEAD | `965940647a123bedb25dd609019208b4c84a967e` |
| Subject HEAD (the last commit that changed the production code) | `0f88baefbba610bb492ad4fe9fa7cef701941ab2` |
| Final HEAD (the last commit of the branch) | the branch head that carries this receipt; every commit after the CI-qualified head alters only the evidence documents of this directory |
| CI head | `11824b7701cc9104944be8ec49f66132f54c2a4c` |
| CI run | `46141549489` |
| Live-tested source revision | **none**: no live execution by the development agent was authorised |
| Build and runtime dependencies on the storage host | **unchanged**: the amendment adds no dependency and installs nothing. The `libpcre3` runtime dependency of the binary is pre-existing and is now recorded as a host prerequisite of the operator procedure |
| Authority for a host modification | **none**: no host modification was made |

The production executable source is the source of the CI-qualified head
`11824b7701cc9104944be8ec49f66132f54c2a4c`: the commits that follow that
head on the branch change only the evidence documents of this directory
and the documentation of the receipt, so the production code that the run
compiled is byte-for-byte the production code of that head. The commit
that carries this reconciliation is such a commit; its own native run is
the final confirmation of the branch, not a new subject. Every run of
every head of the branch is listed in `native-ci.md`.

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
