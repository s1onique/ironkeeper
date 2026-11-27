# ACT-IRONKEEPER-M0-CI-HANDOFF-01 — handoff evidence

A narrow correction of the CI toolchain verification, and the handoff
that makes native acceptance reachable.

| File | Content |
|---|---|
| `exit-receipt.yaml` | The exit receipt: the heads, the red and green of the step-file lifecycle, the regression result, the non-vacuity proof, the CI state and the verdict. |
| `remote-evidence.md` | The two terminal remote runs, what they establish and the exact failing step. |
| `operator-action.md` | The exact push command and what the run must show. |

The verdict is `PARTIAL_FOUNDATION`: the defect is corrected and the
witness is non-vacuous, but the subject has no native CI run, because
the one authenticated push preflight was denied.
