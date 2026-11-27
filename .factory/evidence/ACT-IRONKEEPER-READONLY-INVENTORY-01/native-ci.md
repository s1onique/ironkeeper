# Native Linux execution

The authoritative suite runs natively on Linux. No emulation is used, so
the arm64 result is a genuine arm64 execution.

## The CI workflow

The existing qualified workflow is reused. The ACT extends it with the
storage gates; it does not redesign it, and it does not modify the
toolchain pins or the validator dependency.

| Job | Runner | Purpose |
|---|---|---|
| `build and test (amd64)` | `ubuntu-24.04` | type-check, build, unit, contract and integration suites, schema drift, the non-vacuity gate, the independent cross-check |
| `build and test (arm64)` | `ubuntu-24.04-arm` | the same |
| `validator qualification` | `ubuntu-24.04` | the authoritative validator qualification against the pinned inputs |
| `secret scan` | `ubuntu-24.04` | the history-wide secret scan |

The storage gates that were added:

* the **storage fixture check**, which asserts that the synthetic sysfs
  tree and the controlled backend executables are present;
* the **non-vacuity gate**, `tools/gate_storage_non_vacuity.sh`, which
  reverses each critical check and shows that the corresponding witness
  fails;
* the **independent cross-check** of the generated inventory and
  observation documents, which the existing
  `tools/gate_independent_check.sh` now performs.

## The observed CI runs

| Run | Subject | Conclusion | Jobs |
|---|---|---|---|
| `45969499328` | `68ee056` | **success** | secret scan, build and test (amd64), build and test (arm64), validator qualification |
| `45970216843` | `400360e3a0c0ebb91199c35a0c16850f05578f68` | **success** | secret scan, build and test (amd64), build and test (arm64), validator qualification |
| `45971329094` | `6e00e91` | **success** | secret scan, build and test (amd64), build and test (arm64), validator qualification |
| `45972040790` | `95a8030` | **success** | secret scan, build and test (amd64), build and test (arm64), validator qualification (the evidence commit) |

The run `45971329094` executed the **implementation subject** `6e00e91`,
which is the commit that carries the whole implementation, the contracts,
the tests, the gates and the documentation. The commits that follow it
change only the evidence documents; the implementation is unchanged, and
the CI run of such a commit is reported in the receipt as a
documentation-only follow-up.

The final run is the authoritative one for the subject. The job
conclusions were read from the run itself:

```text
run conclusion: success head: 400360e3a0c0ebb91199c35a0c16850f05578f68
  secret scan -> success
  build and test (arm64) -> success
  validator qualification -> success
  build and test (amd64) -> success
```

The individual step logs are not readable with the credentials of this
environment (the API refuses them without repository admin rights), so
the step-level evidence is the **local** execution of the same
repository-owned gate scripts, recorded above and in
`contract-validation.md` and `non-vacuity.md`.

## The native run on the storage host

The complete authoritative suite was also executed natively on the Linux
storage host, with the pinned toolchain (Nim 2.4.2) and the pinned
validator dependency, on the amd64 architecture:

```text
=== unit
ok   boundedread (23 checks, 0 ms)
ok   cli-args (15 checks, 0 ms)
ok   config-semantics (16 checks, 0 ms)
ok   outputbounds (35 checks, 25 ms)
ok   qualification (27 checks, 0 ms)
ok   schemapolicy (24 checks, 0 ms)
ok   storage (74 checks, 636 ms)
ok   strictjson (82 checks, 98 ms)
ok   validator-adapter (51 checks, 41 ms)
ok   unit-suites
=== contract
ok   contracts (80 checks, 632 ms)
ok   version-contract (6 checks, 0 ms)
ok   contract-suites
=== integration
ok   integration (102 checks, 243 ms)
ok   storage-integration (53 checks, 148 ms)
ok   integration-suites
```

The run needs no root, no physical storage device and no access to the
runner's real block devices.

## The runtime dependency

The binary links the PCRE runtime dynamically, because the JSON Schema
validator uses the `pattern` keyword. The CI job installs `libpcre3`
explicitly. The storage host of the lab does not provide the PCRE 1
runtime, so the qualification build there used a locally built PCRE 1 in
`/opt/pcre1` and the loader path pointed at it. This is an **environment**
property of that host, not a product defect: the CI runners install the
dependency the way the workflow documents.
