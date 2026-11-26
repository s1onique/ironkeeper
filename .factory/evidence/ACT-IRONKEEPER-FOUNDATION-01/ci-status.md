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

## Run history

### Run 1 — failed, and the failures were real

| Field | Value |
|---|---|
| Run ID | 45902483261 |
| Attempt | 1 |
| Head SHA | `0f469d135ada079535241c9f9afca54477f9ee57` |
| Branch | `act/ironkeeper-foundation-01` |
| Conclusion | `failure` |

| Job | Conclusion |
|---|---|
| `build and test (amd64)` | failure |
| `build and test (arm64)` | failure |
| `secret scan` | failure |

The failing step in both build jobs was **"Resolve pinned dependencies"**.

Two distinct defects were found and corrected:

**1. The Nimble manifest version was rejected by Nimble.**

```
packageparser.nim(89)    validateVersion
    Error:  Version may only consist of numbers and '.' character but found '-'.
```

`ironkeeper.nimble` declared `version = "0.1.0-dev"`. Nimble's parser
accepts only digits and dots. The manifest now carries `0.1.0`, the
numeric part of the application version; the `-dev` pre-release marker
stays in the authoritative constant in
`src/ironkeeper/core/version.nim`. The contract test asserts that the two
agree on the numeric part and that the manifest version is a bare dotted
number.

**2. The pinned action revision for gitleaks did not exist.**

```
X Unable to resolve action `gitleaks/gitleaks-action@b32c793809d7b5bb587b8d2412648bd8b4a1c8f5b`,
  unable to find version `b32c793809d7b5bb587b8d2412648bd8b4a1c8f5b`
```

The revision was corrected to `ff98106e4c7b2bc287b24eaf42907196329070c7`,
which is the `v2.3.9` tag of `gitleaks/gitleaks-action`, verified with
`git ls-remote`. The revisions of `actions/checkout` and
`actions/upload-artifact` were verified the same way and were already
correct.

**3. Dependency resolution was made independent of Nimble's task runner.**

Nimble's own `setup` and `develop` tasks were the source of the failure.
They are also observed to abort with a segmentation fault in the macOS
development sandbox, so the CI gate no longer depends on them. The
dependency is now fetched at an exact commit and its tree digest is
verified before use:

```sh
git clone --quiet https://github.com/Niminem/jschema.git "$RUNNER_TEMP/jschema"
git -C "$RUNNER_TEMP/jschema" checkout --quiet "${JSCHEMA_COMMIT}"
actual=$(git -C "$RUNNER_TEMP/jschema" archive HEAD | sha256sum | cut -d" " -f1)
test "${actual}" = "${JSCHEMA_TREE_SHA256}"
```

| Item | Value |
|---|---|
| Dependency | `jschema` 0.1.0 |
| Commit | `a936862556f24fde475059c560c1a13f00291457` |
| Tree sha256 | `323f47f85dba93a0f96bd3ffd6ec964abe2663e260c988596d7a49a0d68573a8` |

The tree digest pins every file, so a rewritten tag or a changed file is
detected. The same approach is used for the Nim toolchain, whose
published `sha256` is verified.

**4. The type-check step now names the shared test-harness path.**

The contract and integration suites import the harness from
`tests/unit/`, so their include paths must include it. The `nim check`
invocations were corrected in both the Nimble manifest and the workflow.

### Run 2

Recorded in `ci-status.md` below once it reaches a terminal conclusion.

## Classification

The status of the CI is reported **per run**, at the exact commit it
executed. A successful run at a different commit is not evidence for the
current subject.

The arm64 result is classified independently of the amd64 result. A
cross-compiled artefact is never reported as executed.
