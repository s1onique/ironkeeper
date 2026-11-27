# Entry identity and repository authority

## Expected values

| Item | Expected | Observed | Match |
|---|---|---|---|
| Remote | `s1onique/ironkeeper` | `origin git@github.com:s1onique/ironkeeper.git` | yes |
| Entry HEAD | `aeb10ae594e695dda163a4053bdb6944b2c89ca7` | `aeb10ae594e695dda163a4053bdb6944b2c89ca7` | yes |
| Branch | `act/ironkeeper-foundation-01` | present, at `aeb10ae` | yes |

## Commands and results

```
$ git --no-pager remote -v
origin  git@github.com:s1onique/ironkeeper.git (fetch)
origin  git@github.com:s1onique/ironkeeper.git (push)

$ git rev-parse HEAD
aeb10ae594e695dda163a4053bdb6944b2c89ca7

$ git --no-pager branch -vv
  act/ironkeeper-foundation-01 aeb10ae [origin/act/ironkeeper-foundation-01] docs: record the final-head CI run
* main                         aeb10ae [origin/main] docs: record the final-head CI run

$ git status --porcelain=v1
(empty)

$ git stash list
(empty)

$ git worktree list
<checkout-path> aeb10ae [main]
```

## Interpretation

* The working tree was **clean** at the entry point.
* There were **no stashes** and **no additional worktrees**.
* `origin/main` and `origin/act/ironkeeper-foundation-01` both pointed at
  the entry commit, so the local branch and the authenticated remote
  agreed.
* The only commits beyond the initial one were the predecessor ACT's
  commits. There were no intervening changes to classify: the entry HEAD
  is the predecessor's final head.

## Licence

The `LICENSE` file is the MIT licence and was **not modified**:

```
$ shasum -a 256 LICENSE
307c6257a17d9d9c7f0a0d5d321fc1606fa53ef1e9da305b0d3012218f63393c  LICENSE
```

The same digest is present in the final tree.

## Work branch

The work was carried out on `act/ironkeeper-foundation-01-amendment-02`,
which was created from the entry commit. `main` was not modified, and no
merge, release, deployment or destructive operation was performed.
