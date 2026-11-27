# Entry identity

## The repository

| Property | Value |
|---|---|
| Remote | `git@github.com:s1onique/ironkeeper.git` (push), `https://github.com/s1onique/ironkeeper.git` (read) |
| Expected entry HEAD | `fb9c5f6d5ec602b272c108a9d23a7342cbadcd35` |
| Observed entry HEAD | `fb9c5f6d5ec602b272c108a9d23a7342cbadcd35` — **as expected** |
| Working tree at entry | clean |
| Stashes at entry | none |
| Worktrees at entry | none |

The entry HEAD was verified against the assignment before any change was
made. The branch `act/ironkeeper-foundation-01-amendment-03` was created
from it; the predecessor branches
`act/ironkeeper-foundation-01` and
`act/ironkeeper-foundation-01-amendment-02` were left untouched.

## The state of `main` at entry

`main` was at `fb9c5f6d5ec602b272c108a9d23a7342cbadcd35`, and
`origin/main` was at the same commit. The remote was read directly:

```
$ git ls-remote https://github.com/s1onique/ironkeeper.git
fb9c5f6d5ec602b272c108a9d23a7342cbadcd35	HEAD
aeb10ae594e695dda163a4053bdb6944b2c89ca7	refs/heads/act/ironkeeper-foundation-01
fb9c5f6d5ec602b272c108a9d23a7342cbadcd35	refs/heads/act/ironkeeper-foundation-01-amendment-02
fb9c5f6d5ec602b272c108a9d23a7342cbadcd35	refs/heads/main
fb9c5f6d5ec602b272c108a9d23a7342cbadcd35	refs/pull/1/head
```

**This is the observed state. How `main` reached it is not recorded here,
because it was not observed.** The amendment did not modify `main` and
did not merge to it; merging to `main` was not authorised.

## The intervening changes

There were none to classify. The working tree was clean at entry, the
stash list was empty and no worktree carried uncommitted work. Every
change in this amendment is the amendment's own.

## The environment failure

**The branch could not be pushed, and no GitHub Actions run could be
triggered.** The sandbox has no usable GitHub credential:

```
$ git push -u origin act/ironkeeper-foundation-01-amendment-03
git@github.com: Permission denied (publickey).

$ ssh -o BatchMode=yes -T git@github.com
Load key "/…/.ssh/id_rsa": Operation not permitted
Load key "/…/.ssh/id_ed25519": Operation not permitted
git@github.com: Permission denied (publickey).

$ git push -u https://github.com/s1onique/ironkeeper.git …
fatal: could not read Username for 'https://github.com': Device not configured

$ gh auth status
X Failed to log in to github.com account alexclear (default)
  - The token in default is invalid.
```

The private keys cannot be read by the sandbox, the `gh` token is
invalid, the keychain holds no GitHub entry, and no `GITHUB_TOKEN` is
present in the environment. Anonymous HTTPS *reads* work; writes do not.

This is an **environment failure**, not a defect in the implementation.
It is recorded as such, and the acceptance gate it prevents (A13, the
native Linux amd64 and arm64 qualification) is left **unmet**. The
requirement it was meant to satisfy is not weakened: the workflow that
performs it is committed, and the gate is reported as unmet rather than
as satisfied by a local run.

No local virtualisation was attempted. There is no container runtime
available, and the ACT forbids QEMU and new infrastructure. The
**orphaned QEMU process** from the predecessor's abandoned local
virtualisation approach remains an **environment-cleanup item for the
operator**; it was not touched, and it is not a product defect.

## The protected work

| Item | State at entry | State now |
|---|---|---|
| `main` | `fb9c5f6` | `fb9c5f6` — unchanged |
| `origin/main` | `fb9c5f6` | `fb9c5f6` — unchanged |
| `act/ironkeeper-foundation-01` | `aeb10ae` | unchanged |
| `act/ironkeeper-foundation-01-amendment-02` | `fb9c5f6` | unchanged |
| `LICENSE` | `307c6257…` | `307c6257…` — unchanged |
