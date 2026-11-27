# Open findings

## 1. The subject has no native CI run

The sandbox cannot push to the remote:

* the SSH agent authenticates as the account `kaktyz`, which has no write
  access to `s1onique/ironkeeper`
  (`ERROR: Permission to s1onique/ironkeeper.git denied to kaktyz`);
* the `gh` CLI token is invalid (`The token in default is invalid`); and
* no credential helper can supply a token
  (`could not read Username for 'https://github.com'`).

The subject is therefore committed locally but not on the remote, and no
CI run exists for it. The acceptance gates that depend on a native run —
C08 (native Linux amd64 build and tests), C09 (native Linux arm64 build
and tests), C10 (secret scan) and the native part of C11 — are unmet.

### The operator action

```sh
git push origin act/ironkeeper-foundation-01-amendment-03
```

The push triggers the `build-test` matrix on `ubuntu-24.04` (amd64) and
`ubuntu-24.04-arm` (arm64), the `secret-scan` job and the
`validator-qualification` job. The qualification step now always
executes, so the run cannot be green with the qualification skipped.

M0 is closed only when that run reaches a terminal conclusion with all
four jobs successful, and when the run id and its conclusion are recorded
against the subject head.

## 2. The executable subject and the closure documents are distinct

The subject head is the commit that carries the executable changes. The
closure documents are committed afterwards and carry their own commit
hash. A closure document therefore never contains the hash of the commit
that contains it, and the two identities are recorded separately.
