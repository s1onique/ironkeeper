# ACT-IRONKEEPER-M0-CLOSURE-01 — closure evidence

This bundle records the closure ACT for milestone M0. It is deliberately
compact: the foundation history stays in the predecessor bundles and is
not repeated here.

| File | Content |
|---|---|
| `exit-receipt.yaml` | The exit receipt: the exact heads, the remote authority, the observed results, the acceptance gates, the open findings and the verdict. |
| `reconciliation.md` | The reconciliation of the entry commit with the remote authority, and the classification of the intervening changes. |
| `local-gates.md` | The repository-owned gates that were executed locally on the executable subject, with their observed output. |
| `qualification.md` | The validator qualification: the pinned inputs, the witnesses, the two measurements and the product verdict. |
| `open-findings.md` | What remains unmet, and the exact operator action that closes it. |

The verdict is `PARTIAL_FOUNDATION`. M0 is closed only by a
`GO_FOUNDATION` verdict, and the native CI run of the subject has not been
observed because the sandbox cannot push to the remote.
