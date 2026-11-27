# The post-qualification diff

The executable subject was qualified **once**, by GitHub Actions run
**45912585631** at commit `b6f8142e6d17910de3ac92cb8523a9338057b33b`.
The evidence bundle and the documentation were committed **afterwards**.

This file is the proof that the post-qualification diff is restricted to
non-executable files, so that the qualification of the subject remains
valid for the final head.

## The diff

```
$ git --no-pager diff --stat b6f8142..HEAD
 .../README.md                                      |  32 +++
 .../acceptance.md                                  | 103 ++++++++
 .../ci-qualification.md                            | 211 +++++++++++++++
 .../entry-identity.md                              |  61 ++++++
 .../green-witnesses.md                             | 283 ++++++++++++++++++++
 .../non-vacuity.md                                 | 151 ++++++++++++++
 .../red-reproductions.md                           | 284 ++++++++++++++++++++
 .../remaining-limitations.md                       |  67 +++++
 .../repairs.md                                     | 265 ++++++++++++++++++++
 .../ACT-IRONKEEPER-FOUNDATION-01/acceptance.md     |  30 ++-
 .../ACT-IRONKEEPER-FOUNDATION-01/ci-status.md      |  66 ++++--
 .../ACT-IRONKEEPER-FOUNDATION-01/dependencies.md   |   7 +
 .../ACT-IRONKEEPER-FOUNDATION-01/linux-native.md   |  56 ++++-
 .../ACT-IRONKEEPER-FOUNDATION-01/toolchain.md      |  44 +++-
 .../validator-qualification.md                     |  52 ++++-
 EPICS.md                                           |  40 ++-
 16 files changed, 1698 insertions(+), 54 deletions(-)
```

## The check that matters

```
$ git --no-pager diff --name-only b6f8142..HEAD \
    | grep -E '\.(nim|nimble|json|sh|yml|yaml)$|^\.github/'
NONE: no source, test, schema, dependency, gate script or CI configuration changed
```

Every changed file is Markdown: the new evidence bundle, the corrected
predecessor evidence, and the epic board. **No source file, no test, no
schema, no dependency declaration, no gate script and no CI
configuration changed after the qualification.**

## The consequence

The qualification of `b6f8142e` therefore remains valid for the final
head, because the final head contains exactly the same executable
content. The qualification is **not** re-triggered for the
evidence-only commit, because re-triggering it would produce a run at a
different commit and would not add evidence about the executable
content.

This is the discipline the review asked for: *"Qualify the executable
subject once, preserve terminal results, and commit the evidence
afterward."*

## For the record

The evidence bundle also records the one run that **did** qualify a
later commit, for a different reason: run **45912607978** at `2bb64bdd`
on the temporary `act/tmp-ci-negative-witness` branch. That branch is
not part of this ACT's history — it was created only to observe the
workflow's conclusion on a deliberately failing test, and it was deleted
afterwards. Its run ID identifies that commit and no other.
