# Secret scanning

## Tool

The gitleaks **binary** is used, not the gitleaks action.

The gitleaks action requires a commercial licence for an
organisation-owned repository. The gitleaks binary is MIT licensed and
needs no licence key, no token and no organisation-level entitlement,
which makes it the correct choice for this repository.

| Item | Value |
|---|---|
| Version | 8.30.1 |
| Archive | `gitleaks_8.30.1_linux_x64.tar.gz` |
| sha256 | `551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb` |
| Licence | MIT |

The digest is the one published in the release's `checksums.txt`. It was
verified by downloading the archive and comparing:

```
$ curl -fsSLO https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
$ sha256sum gitleaks_8.30.1_linux_x64.tar.gz
551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb  gitleaks_8.30.1_linux_x64.tar.gz
```

It is verified again in the workflow before the binary is used.

## Result

**CI:** the `secret scan` job of run 45907055629 concluded **success**.

**Local:** the same invocation was run against the repository with the
darwin arm64 build of the same version:

```
$ gitleaks git --redact --no-banner --report-format json \
    --report-path gitleaks-report.json --exit-code 1
INF 11 commits scanned.
INF scanned ~610766 bytes (610.77 KB) in 562ms
INF no leaks found

$ cat gitleaks-report.json
[]
```

The whole history is scanned, not only the tip, so a secret that was
later removed is still detected.

## Repository hygiene, beyond the scanner

The scanner is a backstop, not the primary control. The staged content
was also inspected manually before every commit, for:

* credentials, tokens and private keys;
* device identifiers: WWNs, serial numbers, hardware identifiers;
* private network addresses and private host names;
* the private checkout path of the development workstation.

One real occurrence was found and removed: the evidence bundle
recorded the absolute checkout path of the development workstation. It
now records the repository identity by remote and commit graph, with
the path elided.

The only matches in the staged content for the secret patterns were
the *documentation* of secret scanning itself, the reference to
`${{ secrets.GITHUB_TOKEN }}` in the workflow, and the numeric
literals in the precision-boundary tests. None of them is a secret.
