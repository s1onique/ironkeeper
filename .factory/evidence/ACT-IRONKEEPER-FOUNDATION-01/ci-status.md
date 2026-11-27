# CI status

## Authorisation

Pushing the ACT development branch to `https://github.com/s1onique/ironkeeper`
was authorised solely to run GitHub Actions and to publish the reviewed
foundation changes on that branch. No push to `main`, no merge, no
release, no force-push and no infrastructure was created.

## Execution environment

| Item | Value |
|---|---|
| Repository | `s1onique/ironkeeper` |
| Branch | `act/ironkeeper-foundation-01` |
| Workflow | `ci` (`.github/workflows/ci.yml`) |
| Runners | `ubuntu-24.04` (amd64), `ubuntu-24.04-arm` (arm64) |
| Emulation | none; both runners execute natively |

## The qualifying run

| Field | Value |
|---|---|
| Run ID | **45907055629** |
| Attempt | 1 |
| Workflow name | `ci` |
| Head SHA | `886a7d20a33e3f8a4c666b550a74872cf0b1a800` |
| Branch | `act/ironkeeper-foundation-01` |
| Status | `completed` |
| **Conclusion** | **`success`** |
| Created | 2026-11-26T22:48:05Z |
| Updated | 2026-11-26T22:49:09Z |
| URL | https://github.com/s1onique/ironkeeper/actions/runs/45907055629 |

### Job conclusions

| Job | Runner | Conclusion |
|---|---|---|
| `build and test (amd64)` | GitHub Actions 1000018921 | **success** |
| `build and test (arm64)` | GitHub Actions 1000018920 | **success** |
| `secret scan` | GitHub Actions 1000018919 | **success** |

`CI_HEAD` equals `SUBJECT_HEAD`: the run executed
`886a7d20a33e3f8a4c666b550a74872cf0b1a800`, which is exactly the
qualified subject.

### What the run exercised

Both build jobs ran, natively and on the exact subject commit:

* the pinned, digest-verified Nim 2.4.2 distribution, selected by the
  runner's own architecture;
* the PCRE runtime dependency, with its presence asserted;
* the pinned dependency, fetched at an exact commit with its tree
  digest verified;
* the type-check of every module;
* the debug build of the application and of the three test binaries;
* the unit, contract and compiled CLI integration test suites;
* the embedded-schema drift check;
* independent schema validation with `check-jsonschema`, including the
  metaschema check of every repository schema and the cross-check of the
  machine-readable output the binary produces;
* the release-mode compilation;
* the recording of the exact architecture, OS, compiler version, memory
  manager and executable identity.

The secret-scan job ran the pinned gitleaks binary over the whole
history.

## The runs on the evidence-only commits

Each evidence-only commit was independently qualified, and each run
identifies exactly one commit. The order is chronological.

### The run on `a8372fa8`

| Field | Value |
|---|---|
| Run ID | **45907640271** |
| Attempt | 1 |
| Head SHA | `a8372fa8005063c9c880d8f0323ef0e36a88e61f` |
| Branch | `act/ironkeeper-foundation-01` |
| Conclusion | **success** |

| Job | Runner | Conclusion |
|---|---|---|
| `build and test (amd64)` | GitHub Actions 1000018924 | success |
| `build and test (arm64)` | GitHub Actions 1000018922 | success |
| `secret scan` | GitHub Actions 1000018923 | success |

The difference between the qualified subject `886a7d20` and `a8372fa8`
is confined to the evidence bundle, the epic board and the README. No
code, test, schema, dependency, build configuration or workflow
definition changes.

### The run on `ccd814f5`

| Field | Value |
|---|---|
| Run ID | **45907844182** |
| Attempt | 1 |
| Head SHA | `ccd814f5` |
| Branch | `act/ironkeeper-foundation-01` |
| Conclusion | **success** |

### The run on `70d74877`

| Field | Value |
|---|---|
| Run ID | **45908229091** |
| Attempt | 1 |
| Head SHA | `70d74877cb8f20431dcf57029e03aa59e686aab8` |
| Branch | `act/ironkeeper-foundation-01` |
| Conclusion | **success** |

| Job | Runner | Conclusion |
|---|---|---|
| `build and test (amd64)` | GitHub Actions 1000018928 | success |
| `build and test (arm64)` | GitHub Actions 1000018930 | success |
| `secret scan` | GitHub Actions 1000018929 | success |

The difference between the qualified subject `886a7d20` and the final
head `70d74877` is confined to the evidence bundle, the epic board, the
README and the `.gitignore`. No code, test, schema, dependency, build
configuration or workflow definition changes, so the qualification of the
subject remains valid, and the final head is independently qualified as
well.

### The run on `aeb10ae`, the entry head of the amendment ACT

| Field | Value |
|---|---|
| Run ID | **45908776155** |
| Attempt | 1 |
| Head SHA | `aeb10ae594e695dda163a4053bdb6944b2c89ca7` |
| Branch | `act/ironkeeper-foundation-01` |
| Conclusion | **success** |

### The run on `main`

| Field | Value |
|---|---|
| Run ID | **45909128457** |
| Attempt | 1 |
| Head SHA | `aeb10ae594e695dda163a4053bdb6944b2c89ca7` |
| Branch | `main` |
| Conclusion | **success** |

### A note on the "final head"

This file previously carried two sections with the same heading, "The
run on the final head", for two different commits. The commits are now
listed separately, each with its own run ID. The distinction matters: a
successful run at a different commit is not evidence for the current
subject.

## The run history, and what each failure taught

The first **eight** runs failed. Every failure was a real defect in the
workflow or the manifest, and every one was corrected and re-qualified.
The full history is recorded because it is evidence.

| Run | Head SHA | Conclusion | What was wrong |
|---|---|---|---|
| 45902483261 | `0f469d13` | failure | The Nimble manifest declared `0.1.0-dev`, which Nimble rejects. The pinned gitleaks action revision did not exist. Dependency resolution depended on Nimble's task runner. |
| 45903257833 | `0d371696` | failure | The type-check step's include paths omitted the shared test harness. |
| 45903641662 | `536476de` | failure | A diagnostic edit put `if: failure()` on the type-check step itself, so the step never ran and the workflow reported failure with no jobs. |
| 45903855725 | `60b988f7` | failure | The step output was not readable without repository admin rights. The diagnostic capture was added. |
| 45904573697 | `00bcb648` | failure | `std/re` loads PCRE dynamically at run time and the Nim distribution does not bundle it, so the build failed on both architectures while the type-check passed. The gitleaks action also required a commercial licence. |
| 45905287218 | `057979b1` | failure | The independent schema validation validated every schema against itself, which can never succeed. The correct check is `--check-metaschema`. |
| 45905789860 | `b0a59295` | failure | The toolchain was not on PATH within the step that installed it, and the independent validator was installed to a location that was not on PATH. |
| 45906225914 | `6b92ad96` | failure | The pinned Nim distribution was the x86-64 one on an arm64 runner, so it could not be executed. |
| **45907055629** | **`886a7d20`** | **success** | — |
| 45907640271 | `a8372fa8` | success | The evidence commit; no executable change |
| **45908229091** | **`70d74877`** | **success** | The final head |

Each fix was verified locally before it was pushed. The independent
schema validation was verified with `check-jsonschema` 0.31.2 against the
real repository, and the arm64 Nim distribution was verified to contain
an ARM aarch64 binary before the architecture selection was pushed.

### The one defect this found in the product

The report identifier mixed a signed random value with a nanosecond
counter through a cast between signed and unsigned types. The result
was implementation defined and its width could differ between
architectures. It is now derived with explicit masking and always has
the same shape. The independent validator caught it on arm64, which is
precisely the value of running on the real architecture.

## Secret scanning

The gitleaks **binary** is used, not the gitleaks action. The action
requires a commercial licence for an organisation-owned repository; the
binary is MIT licensed and needs no licence key, no token and no
organisation-level entitlement.

| Item | Value |
|---|---|
| Version | 8.30.1 |
| Archive | `gitleaks_8.30.1_linux_x64.tar.gz` |
| sha256 | `551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb` |

The checksum is the one published in the release's `checksums.txt`, and
it is verified before the binary is used.

The scan was also run locally against the repository, with the same
invocation the workflow uses:

```
$ gitleaks git --redact --no-banner --report-format json \
    --report-path gitleaks-report.json --exit-code 1
INF 11 commits scanned.
INF scanned ~610766 bytes (610.77 KB) in 562ms
INF no leaks found
```

The report was `[]`.

## Classification

The CI status is reported **per run, at the exact commit it executed**.
A successful run at a different commit is not evidence for the current
subject.

The amd64 and arm64 results are classified independently. Both are
**native executions**: no cross-architecture emulation is used, and a
cross-compiled artefact is never reported as "executed".

The workflow is also triggered on a push to `main` and on every pull
request, so an ordinary pull request runs the same gates without any
extra configuration.
