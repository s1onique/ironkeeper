# ACT-IRONKEEPER-FOUNDATION-01-AMENDMENT-02 — evidence

This bundle records the correction of the acceptance authority that
independent review found defective.

## The files

| File | Contents |
|---|---|
| `entry-identity.md` | The entry HEAD, the remote, the branch and the working-tree state |
| `red-reproductions.md` | Every counterexample, reproduced against the production path at the entry commit, with the input, the observed result and the intended invariant |
| `repairs.md` | Each repair, the production path it changed and the invariant it restores |
| `green-witnesses.md` | The observed output of every witness, after the repairs |
| `non-vacuity.md` | Each repair reverted or disabled, the failure observed, and the implementation restored |
| `ci-qualification.md` | The qualifying run, the negative witnesses, the first run's defect, and the run identity ledger |
| `acceptance.md` | The twenty acceptance gates, the identities, the verdict and the outstanding findings |
| `remaining-limitations.md` | Every outstanding observation, classified |
| `post-qualification-diff.md` | The proof that the post-qualification diff is confined to non-executable files |

## The one-line summary

The predecessor's CI gates could report success after a mandatory
command had failed, and its secret-scan gate discarded a detected
secret. Its strict reader rounded numbers into the accepted range and
terminated the process on the signed minimum. Its validator accepted
misspelled schema keywords, and its report validator accepted impossible
timestamps and a `PASS` verdict on a failed execution.

All of that was reproduced, repaired and witnessed. The CI gates are now
authoritative: a real GitHub Actions run at the exact subject concluded
`success`, and a real run with a deliberately failing mandatory test
concluded `failure`.
