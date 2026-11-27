# ACT-IRONKEEPER-M0-CLOSURE-01-AMENDMENT-01 — closure evidence

A surgical correction of the three remaining closure defects, plus the
evidence corrections. The foundation history stays in the predecessor
bundles.

| File | Content |
|---|---|
| `exit-receipt.yaml` | The exit receipt: the heads, the three corrections, the observed results, the acceptance gates, the open finding and the verdict. |
| `local-gates.md` | The repository-owned gates executed on the executable subject, with their observed output. |
| `defect-repairs.md` | The three defects, their reproduction, the correction and the witness of each. |

The verdict is `PARTIAL_FOUNDATION`. The three defects are corrected and
every repository-owned gate passes locally, but the subject has no
native CI run: one bounded authentication preflight was denied.
