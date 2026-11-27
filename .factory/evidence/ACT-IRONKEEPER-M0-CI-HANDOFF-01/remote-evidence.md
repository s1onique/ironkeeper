# The existing remote evidence

Two terminal GitHub Actions runs executed the entry commit
`9e1d49ce1ac0fdc8d8171ab99f6f23eafa0fcf52` on the branch
`act/ironkeeper-foundation-01-amendment-03`:

| Run | Conclusion | Job | Conclusion | Failing step |
|---|---|---|---|---|
| 45934380741 | failure | build and test (amd64) | failure | Verify the pinned toolchain |
| | | build and test (arm64) | failure | Verify the pinned toolchain |
| | | secret scan | success | — |
| | | validator qualification | failure | Verify the pinned toolchain |
| 45934374904 | failure | build and test (amd64) | failure | Verify the pinned toolchain |
| | | build and test (arm64) | failure | Verify the pinned toolchain |
| | | secret scan | success | — |
| | | validator qualification | failure | Verify the pinned toolchain |

The two runs are the confirmation that the defect is real and that it
is where it was reported: the secret scan — the only job that needs no
toolchain — succeeded, and every job that installs and then verifies the
toolchain failed at the verification.

The preceding authentication limitation is historical. It is not
investigated again in this ACT.

## The run of the corrected production verifier

Run **45934831421** executed the commit
`25a60ebf2b71a82acd6aaac05f8a5cafa04d08da`:

| Job | Conclusion | Detail |
|---|---|---|
| secret scan | success | — |
| validator qualification | success | the authoritative native qualification executed and passed |
| build and test (amd64) | failure | at "Check the CI toolchain bootstrap" |
| build and test (arm64) | failure | at "Check the CI toolchain bootstrap" |

The production toolchain verification passed on both architectures and in
the validator job. The only remaining defect was in the regression
fixture itself, which is corrected by this ACT.
