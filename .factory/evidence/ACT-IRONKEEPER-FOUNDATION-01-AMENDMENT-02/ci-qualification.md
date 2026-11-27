# CI qualification

## Authorisation

The ACT development branch `act/ironkeeper-foundation-01-amendment-02` was
pushed to `https://github.com/s1onique/ironkeeper` solely to run GitHub
Actions and to publish the reviewed changes on that branch. No push to
`main`, no merge, no release, no force-push and no infrastructure was
created.

## The qualifying run

| Field | Value |
|---|---|
| Run ID | **45912585631** |
| Attempt | 1 |
| Workflow name | `ci` |
| Head SHA | `b6f8142e6d17910de3ac92cb8523a9338057b33b` |
| Branch | `act/ironkeeper-foundation-01-amendment-02` |
| Status | `completed` |
| **Conclusion** | **`success`** |
| Created | 2026-11-26T23:43:17Z |
| Updated | 2026-11-26T23:44:22Z |
| URL | https://github.com/s1onique/ironkeeper/actions/runs/45912585631 |

### Job conclusions

| Job | Runner | Started | Completed | Conclusion |
|---|---|---|---|---|
| `secret scan` | GitHub Actions 1000018959 | 23:43:19Z | 23:43:25Z | **success** |
| `build and test (arm64)` | GitHub Actions 1000018960 | 23:43:21Z | 23:44:10Z | **success** |
| `build and test (amd64)` | GitHub Actions 1000018961 | 23:43:20Z | 23:44:22Z | **success** |

`CI_HEAD` equals `SUBJECT_HEAD`: the run executed
`b6f8142e6d17910de3ac92cb8523a9338057b33b`, which is exactly the
qualified subject.

Both build jobs ran **natively** on `ubuntu-24.04` (amd64) and
`ubuntu-24.04-arm` (arm64). No cross-architecture emulation was used, so
the arm64 result is a genuine arm64 execution.

### What the run exercised

* the pinned, digest-verified Nim 2.4.2 distribution, selected by the
  runner's own architecture;
* the PCRE runtime dependency, with its presence asserted;
* the pinned dependency, fetched at an exact commit with its tree digest
  verified;
* the type-check of every module;
* the debug build of the application and of the three test binaries;
* the unit, contract and compiled CLI integration test suites;
* the embedded-schema drift check;
* independent schema validation with `check-jsonschema`, including the
  metaschema check of every repository schema and the cross-check of the
  machine-readable output the binary produces;
* the release-mode compilation;
* the recording of the exact architecture, OS, compiler version and
  executable identity.

The secret-scan job ran the pinned gitleaks binary over the whole
history.

## The negative witness

A deliberately failing test assertion was pushed to the temporary branch
`act/tmp-ci-negative-witness`, to establish that a failing mandatory test
makes the workflow conclusion `failure`.

| Field | Value |
|---|---|
| Run ID | **45912607978** |
| Head SHA | `2bb64bdd8233757873fbf0a5d2d5e53449725895` |
| Branch | `act/tmp-ci-negative-witness` |
| Status | `completed` |
| **Conclusion** | **`failure`** |
| URL | https://github.com/s1onique/ironkeeper/actions/runs/45912607978 |

### Job and step conclusions

| Job | Conclusion |
|---|---|
| `build and test (amd64)` | **failure** |
| `build and test (arm64)` | **failure** |
| `secret scan` | success |

The `amd64` job's steps:

| Step | Conclusion |
|---|---|
| Check out the repository | success |
| Install the pinned Nim toolchain | success |
| Install the PCRE runtime dependency | success |
| Record the exact execution environment | success |
| Resolve pinned dependencies | success |
| **Type-check, build and test** | **failure** |
| Verify the embedded schemas match the repository | skipped |
| Install the independent schema validator | skipped |
| Independent schema validation and cross-check | skipped |
| Release-mode compilation | skipped |
| Record the executable identity | skipped |
| Collect diagnostics | success |
| Upload the build evidence | success |

This is the decisive observation for the gate authority: the mandatory
step **failed**, the workflow concluded **failure**, and the two steps
that ran afterwards — the diagnostic collection and the artifact upload —
**succeeded** without changing the conclusion. A successful artifact
upload and a successful log rendering did **not** mask the failure.

The temporary branch was deleted after the run was observed. No
deliberately broken implementation remains on the ACT branch.

## The first run, and the defect it found

The first run of the branch, **45912205110** at `afa6dd7`, concluded
**failure**. The gate was right and the workflow was wrong.

| Job | Conclusion |
|---|---|
| `build and test (amd64)` | **failure** |
| `build and test (arm64)` | **failure** |
| `secret scan` | success |

The failing step was `Type-check, build and test`; every later step was
skipped. The cause was reproduced locally by running the gate with the
dependency path unset:

```
$ env -u IRK_DEPS_PATH ... tools/gate_build_test.sh
src/ironkeeper/contracts/validator.nim(39, 8) Error: cannot open file: jschema
src/ironkeeper/contracts/validator.nim(67, 15) Error: undeclared identifier: 'SchemaRegistry'
...
```

The gate script took the dependency path from `IRK_DEPS_PATH`, but the
workflow only exported that variable in the release-mode step, so the
type-check, build and test steps resolved the dependency against nothing.

The fix is commit `b6f8142`: the gate and the build derive the default
Nimble location themselves when the variable is not set, and the
dependency-resolution step exports it for every later step. The
qualification run above is the run of the fixed subject.

This is recorded because it is the strongest available evidence that the
gate is authoritative: **the gate failed a run that the predecessor's
workflow would have reported as a success**, because the defect was a
missing dependency path rather than a failing test.

## The secret-scan negative witness

A second temporary branch, `act/tmp-secret-scan-witness`, was created
with a synthetic token fixture, to establish that a detected secret
fails the secret-scan gate.

The push was **refused by GitHub's own push protection**, which
independently confirmed that the fixture matched a real secret pattern:

```
remote: error: GH013: Repository rule violations found for refs/heads/act/tmp-secret-scan-witness.
remote:
remote: - GITHUB PUSH PROTECTION
remote:
remote:     - Push cannot contain secrets
remote:
remote:       —— Stripe API Key ————————————————————————————————————
remote:        locations:
remote:          - commit: 922e47f370adfc40b0048d8b518347bb34c7233b
remote:            path: tmp-secret-probe/fixture.txt:1
```

The secret therefore could not reach the CI runner through a push, which
is a *stronger* result than a CI failure: the platform refused to admit
it. The gate's own behaviour on a finding was then established against a
**temporary local repository**, so that no secret-like material entered
the public repository history:

```
$ cd /tmp/secret-witness-repo
$ gitleaks git --redact --no-banner --report-format json \
    --report-path /tmp/sw-report.json --exit-code 1
INF 1 commits scanned.
WRN leaks found: 1
```

and the gate's verdict logic on that result:

```
report_error=none findings=1 scan_status=1
gate: FAIL secret-scan: the scanner reported 1 finding(s)
exit 1
```

The gate fails on a detected finding. The temporary branch was deleted.

## Run identity ledger

Every run ID in this evidence bundle identifies exactly one observed
commit. No run is identified at a commit it did not execute.

| Run ID | Head SHA | Conclusion | Subject |
|---|---|---|---|
| 45912205110 | `afa6dd76` | failure | the gate script before the dependency-path fix |
| **45912585631** | **`b6f8142e`** | **success** | **the qualified executable subject** |
| **45912607978** | **`2bb64bdd`** | **failure** | the CI negative witness |
| **45915464716** | **`c4fee46d`** | **success** | the final head, evidence-only diff |
| **45915748084** | **`bc3d425a`** | **success** | the final head, after the last evidence commit |

### The run on the final head

The evidence bundle was committed after the qualification, so the final
head was run once as well. Its executable content is identical to the
qualified subject, and the run is recorded here for completeness:

| Field | Value |
|---|---|
| Run ID | **45915464716** |
| Head SHA | `c4fee46dbdba89f1e872dba79ccfcd628684e59f` |
| Branch | `act/ironkeeper-foundation-01-amendment-02` |
| Status | `completed` |
| **Conclusion** | **`success`** |
| URL | https://github.com/s1onique/ironkeeper/actions/runs/45915464716 |

| Job | Runner | Conclusion |
|---|---|---|
| `build and test (amd64)` | GitHub Actions 1000018970 | **success** |
| `build and test (arm64)` | GitHub Actions 1000018969 | **success** |
| `secret scan` | GitHub Actions 1000018971 | **success** |

The **qualified executable subject** remains `b6f8142e`, qualified by
run 45912585631. The run at the final head is an additional
confirmation, not a replacement: `post-qualification-diff.md` proves
that the executable content is identical between the two commits.

## The evidence-only commit

The evidence bundle and the documentation are committed **after** the
qualification. The qualification run above therefore identifies the
*executable* subject, and the post-qualification diff is confined to
non-executable files. `post-qualification-diff.md` records the proof.
