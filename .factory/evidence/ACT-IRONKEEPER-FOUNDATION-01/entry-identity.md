# Entry identity and repository authority

Recorded at the start of ACT-IRONKEEPER-FOUNDATION-01.

## Repository root

The checkout path on the development workstation is a private path and is
not reproduced here. The repository identity is established by the remote
and the commit graph, which are reproduced below.

## Expected values

| Item | Expected | Observed | Match |
|---|---|---|---|
| Remote | `s1onique/ironkeeper` | `origin git@github.com:s1onique/ironkeeper.git` | yes |
| Default branch | `main` | `main` | yes |
| Entry HEAD | `c649d1aef3b80f37475c49f67efc3a4be72fadf1` | `c649d1a` | yes |

## Commands and results

```
$ git --no-pager remote -v
origin  git@github.com:s1onique/ironkeeper.git (fetch)
origin  git@github.com:s1onique/ironkeeper.git (push)

$ git --no-pager branch -avv
* main                c649d1a [origin/main] Initial commit
  remotes/origin/HEAD -> origin/main
  remotes/origin/main c649d1a Initial commit

$ git --no-pager log --oneline -20
c649d1a Initial commit

$ git --no-pager status --porcelain=v1 -uall
(empty)

$ git --no-pager stash list
(empty)

$ git --no-pager worktree list
<checkout-path> c649d1a [main]
```

## Interpretation

* The working tree was **clean** at the entry point: no modified, staged
  or untracked files.
* There were **no stashes** and **no additional worktrees**, so no
  existing work could be lost by the branch that was created.
* The only commit was `c649d1a Initial commit`, which contains the
  repository's `LICENSE` and nothing else. HEAD had **not** advanced
  beyond the expected entry, so there were no intervening commits to
  classify.
* `origin/main` pointed at the same commit as the local `main`, so the
  local branch and the authenticated remote agreed.

## Licence

The `LICENSE` file is the MIT licence and was **not modified** by this
ACT.

```
$ shasum -a 256 LICENSE
307c6257a17d9d9c7f0a0d5d321fc1606fa53ef1e9da305b0d3012218f63393c  LICENSE
```

The same digest is present in the final tree. `git diff --cached --
stat LICENSE` was empty at every commit that staged anything, and the
file appears in no commit other than `c649d1a`.

## Branch

A dedicated branch was created for the work:

```
$ git checkout -b act/ironkeeper-foundation-01
Switched to a new branch 'act/ironkeeper-foundation-01'
```

No history was rewritten. No push, merge, rebase, force-push, reset or
clean was performed. The `main` branch is untouched at `c649d1a`.
