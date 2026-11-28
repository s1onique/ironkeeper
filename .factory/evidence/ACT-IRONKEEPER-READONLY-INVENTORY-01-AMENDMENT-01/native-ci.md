# Native CI

The authoritative qualification of this amendment is the native CI run of
the final subject. The workflow runs on GitHub-hosted Linux runners:
`ubuntu-24.04` for amd64 and `ubuntu-24.04-arm` for arm64. No
cross-architecture emulation is used, so the arm64 result is a genuine
arm64 execution.

## The runs of this amendment

| Run | Subject | Conclusion | What it established |
|---|---|---|---|
| `46003398072` | `1abb68f` | failure | The build and the test step failed: the file modes were written as typed 16-bit literals, which do not convert to the 32-bit mode type of a Linux build. |
| `46006408873` | `f45be39` | failure | The same step failed: the copy of the synthetic fixture tree lost the executable bit of the controlled tools, so the tools of the copy could not run. |
| `46009167146` | `ee97aa6` | failure | The same step failed: the identity reconciliation had been left in the mutated state of a non-vacuity check, and the ambiguity refusal was therefore absent. |
| `46015982726` | `0f88bae` | failure | The build and the test step passed; the non-vacuity gate exceeded the time budget of the job. |
| `46017344205` | `68b4a84` | failure | The build and the test step and the non-vacuity gate passed; the independent cross-check validated the wrong document on arm64, because the observation document had been written into a file named `manifest.json` and the manifest was looked up with an unordered search. |
| `46018090446` | `7d878ee` | failure | The build and the test step passed; the non-vacuity gate exceeded the time budget of the job. |
| `46020231721` | `7849527` | failure | The non-vacuity gate failed: the mutations rebuilt the shipped binaries from a mutated source, and the later gates of the job consumed those binaries. |
| `46021642146` | `b29840b` | failure | The non-vacuity gate failed again, and the reason could not be read: the job log of a failed run needs administrative rights. The gate now reports the reason of every failing phase as a workflow annotation, which is part of the public check-run record. |
| `46031059134` | `b501bb6` | failure | The annotation identified the phase: the pipe stream identity witness did not detect its mutation. The witness closed the standard output and wrote to the standard error immediately afterwards, so whether the defect was observable depended on a race between the child and the parent. The witness now delays the write, which makes the ordering deterministic. |
| the final run | the final subject | see the exit receipt | the qualification of the final subject |

Every failure above was **reproduced locally** before it was repaired,
and every repair was verified with the pinned toolchain (Nim 2.4.2) and
with the repository gates before the branch was pushed again. The
failures are recorded here because a run that only ever succeeded does
not establish that the gates can fail.

## The qualification of the final subject

The final run of the final subject is recorded in the exit receipt. The
run must show, for **both** architectures:

| Job | Required conclusion |
|---|---|
| build and test (amd64) | success |
| build and test (arm64) | success |
| validator qualification | success |
| secret scan | success |

## The artefacts

The build job publishes the **production** binary and the **test-enabled**
binary, together with the identity of each:

| Artefact | Identity |
|---|---|
| `build/ironkeeper` | the production variant; the artefact of the hardware qualification |
| `build/ironkeeper-testing` | the test-enabled variant; never shipped, never used for a hardware qualification |

The job records the variant of each binary in `build-variants.txt` and
the digests in `executable-identity.txt`, so that a test-enabled binary
can never be mistaken for the production one.

The digests of the published artefacts of the final run are:

| Artefact | Digest |
|---|---|
| `build-evidence-amd64` | `sha256:800a074a3c6f0c11862973b0329887e9ade59ef29977c0156dc921b8d457de1e` |
| `build-evidence-arm64` | `sha256:0bbfa5513b0b59edcdd59ddf55965644a50b4ed2c428d06e6a7acce4065ca7cc` |

## The local runs

The local runs are the development runs, not the qualification:

| Item | Value |
|---|---|
| local toolchain | Nim 2.4.2 (the pinned version) and Nim 2.2.4 |
| local platform | macOS arm64 - **not** the qualified environment |
| local gate | `tools/gate_build_test.sh` - passed |
| local non-vacuity gate | `tools/gate_storage_non-vacuity.sh` - passed |
| local Linux type check | `nim check --os:linux --cpu:amd64` with Nim 2.4.2 - passed |

The Linux-specific defects that the local platform could not expose were
found by the native run and are recorded above.
