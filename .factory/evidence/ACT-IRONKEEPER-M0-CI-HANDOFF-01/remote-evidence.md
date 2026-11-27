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
