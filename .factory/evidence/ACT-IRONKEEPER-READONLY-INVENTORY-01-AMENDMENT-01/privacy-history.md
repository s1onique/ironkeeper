# Public history privacy status (W9)

## The question

The predecessor replaced real host identifiers that had been committed.
The question is whether the **original** identifiers remain in the
commits that are reachable from the pushed branch.

## The inspection

The inspection was performed with `git rev-list` and `git grep` over
the reachable history. The identifiers themselves are **not** reproduced
here, in the logs, or in any new evidence file: the inspection reports
the *locations* only.

| Item | Result |
|---|---|
| Commits reachable from `act/ironkeeper-readonly-inventory-01` | 54 |
| Commits that contain a private identifier | 6 |
| Files that carry a private identifier in those commits | `docs/architecture/storage-observation.md`, `src/ironkeeper/storage/identity.nim`, `tests/fixtures/storage/sys/class/block/nvme0n1/device/serial`, `tests/fixtures/storage/sys/class/block/nvme0n2/device/serial`, `tests/fixtures/storage/tools/smartctl` |
| The commits that introduced them | the two implementation commits of the predecessor and the three documentation commits that followed them |
| Are the affected commits reachable from the pushed branch | **yes** |
| Do private identifiers remain in the reachable history | **yes** |
| Is only local, unreachable history affected | **no** |
| Is operator-authorised remediation required | **yes** |

The identifiers are the SCSI world-wide name of a live disk and the
serial number of a live NVMe controller. Both are properties of the
operator's own hardware, and both were replaced in the working tree by
the predecessor - but replacing a value in a later commit does not
remove it from the earlier ones.

## Why a successful secret scan is not sufficient

The secret scan is a **credential** scan. It looks for tokens, keys and
passwords. A world-wide name and a controller serial are not
credentials: the scan passes, and the identifiers are still there. The
privacy invariant of this section is therefore established by the
reachability inspection above and by nothing else.

## The remediation recommendation

The only way to remove the identifiers from the reachable history is to
rewrite it: a filter over the affected commits, followed by a force
push of the rewritten branch. The rewriting tool is not in the
repository, the rewrite touches commits that other branches descend
from, and a force push is **not** authorised by this ACT. The
recommendation is therefore a separate, operator-authorised action:

1. Decide whether the public repository is the right place for the
   history at all. A repository that is created after the fact has no
   such history.
2. If the history must be rewritten, do it in one dedicated act, with
   the filter, the rewrite and the force push reviewed by the operator,
   and with the credential rotation that the exposure of a
   hardware identifier may warrant.
3. Until then, treat the identifiers as **public**, and do not use the
   affected values in any new evidence.

This amendment does **not** rewrite history, does not force-push, and
does not delete a remote branch. It reports the status and stops the
publication of the affected material: no release and no deployment is
produced from the branch until the operator has decided.
