# ACT-IRONKEEPER-FOUNDATION-01 — evidence bundle

This directory holds the evidence for the Ironkeeper foundations ACT. Every
file records an observed result. Where a result could not be observed, the
entry says so explicitly rather than claiming a success.

## Contents

| File | Contents |
|---|---|
| `entry-identity.md` | Repository identity and entry authority |
| `toolchain.md` | Toolchain identity and the bootstrap procedure |
| `validator-qualification.md` | Validator candidate evaluation and conformance |
| `build-and-test.md` | Build, unit, contract and integration test results |
| `negative-witnesses.md` | The mandatory negative witnesses and their results |
| `non-vacuity.md` | Proof that the safety and contract tests can fail |
| `linux-native.md` | The Linux-native build and execution path |
| `ci-status.md` | CI workflow status and its honest classification |
| `secret-scan.md` | Secret scanning status |
| `dependencies.md` | Dependency decisions and licences |
| `acceptance.md` | The acceptance gates and the final verdict |

## Conventions

* A command is quoted exactly as it was run.
* A result is quoted exactly as it was observed.
* A result that was **not** observed is marked `NOT OBSERVED` with the
  reason.
* No compiler log, binary artefact or cache is committed here. The
  evidence is the summary, not the megabytes.
