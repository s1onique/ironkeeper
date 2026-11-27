# Reconciliation of the entry commit with the remote authority

## The entry commit

The entry commit is `c3c4b5881bdbc2fdfa2103fc1da36097180da4cb` on the
branch `act/ironkeeper-foundation-01-amendment-03`. The working tree at
the entry was clean and matched that commit.

## The remote authority

The predecessor ACT reported that its sandbox could not authenticate to
GitHub, so it could not observe a CI run. That observation is
**historical**. The remote state was retrieved from the GitHub Actions
API and it is unambiguous:

| Run | Head | Conclusion | Jobs |
|---|---|---|---|
| 45926174624 | `c3c4b5881bdb` | failure | build and test (amd64) success; build and test (arm64) success; secret scan success; validator qualification failure |
| 45926147466 | `c3c4b5881bdb` | failure | build and test (amd64) success; build and test (arm64) success; secret scan success; validator qualification failure |

Both runs executed the entry commit, both reached a terminal conclusion,
and both failed in the same place: step 3 of the `validator
qualification` job, "Install the pinned Nim toolchain". The qualification
step itself (step 7) was never reached in either run.

## The classification of the intervening changes

The changes of this ACT are narrow corrections and targeted regression
witnesses. They are:

* the CI toolchain bootstrap, moved into one repository-owned script and
  corrected (the toolchain directory was appended to `PATH` as if `PATH`
  were a file);
* the requalification decision, made fail-closed, and the qualification
  step, made unconditional;
* the qualification accounting, separated into a raw upstream measurement
  and an adapter measurement, with the counting invariants established;
* the qualification input identity, extended to the remote schema tree;
* the output bounds, made UTF-8 safe, with the dropped-item accounting
  corrected; and
* the documentation reconciliation of the numeric model and the
  milestone status.

No architecture decision was taken, no dependency was replaced, no
product functionality was added, and no hardware was touched.

The predecessor's own receipts are retained unchanged. They are not
rewritten: the authentication failure they record was true when it was
produced.
