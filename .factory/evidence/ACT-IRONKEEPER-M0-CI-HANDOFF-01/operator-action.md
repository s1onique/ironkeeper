# The operator action

The subject `ea1d5d110e65a21e130daf6d3c9b3c156a986902` is committed
locally. One authenticated push preflight was performed:

```sh
git push --dry-run origin act/ironkeeper-foundation-01-amendment-03
```

and it was denied (`fatal: Could not read from remote repository.`). No
credential reconnaissance was performed, and no further attempt was
made.

The operator action is exactly:

```sh
git push origin act/ironkeeper-foundation-01-amendment-03
```

The push triggers three jobs. M0 is closed only when all of them reach a
terminal success:

* **build and test (amd64)** on `ubuntu-24.04` — the native amd64 build
  and the three test suites;
* **build and test (arm64)** on `ubuntu-24.04-arm` — the native arm64
  build and the three test suites;
* **secret scan** over the whole history;
* **validator qualification** — the qualification step executes
  unconditionally, the gate requires an authoritative qualification, and
  the run must print
  `qualification_authoritative=true`,
  `qualification_classification=pinned-verified`,
  `inputs_digest_verified=true` and a terminal product verdict.

A green job whose qualification step was skipped does not close M0.
The run id and its conclusion must be recorded against the subject head.
