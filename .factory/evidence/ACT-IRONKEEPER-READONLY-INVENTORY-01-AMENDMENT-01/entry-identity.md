# Entry identity

| Item | Value |
|---|---|
| Entry HEAD | `965940647a123bedb25dd609019208b4c84a967e` |
| Entry commit | `docs: bind the exit receipt to the qualified subject` |
| Branch at entry | `act/ironkeeper-readonly-inventory-01` |
| Remote branch at entry | `origin/act/ironkeeper-readonly-inventory-01` at `9659406` |
| Amendment branch | `act/ironkeeper-readonly-inventory-01-amendment-01` |
| Predecessor ACT | ACT-IRONKEEPER-READONLY-INVENTORY-01 |
| Independent review disposition | `PARTIAL_INVENTORY` |
| Native CI at entry | run `45973773902`, native amd64 and arm64 |

The entry commit was verified locally against the remote branch before
any change was made: `git rev-parse origin/act/ironkeeper-readonly-inventory-01`
returned `965940647a123bedb25dd609019208b4c84a967e`, which is the
expected entry HEAD.

The amendment branch is created **from** the entry commit, so the entry
commit stays reachable and the diff of the amendment is exactly the set
of repairs.
