# The three defects and their repairs

## 1. The bootstrap integration seam

**Reproduction.** `tools/install_nim_toolchain.sh` followed by
`nimble --version` fails with exit 127 when no unrelated Nimble is
installed. The bootstrap is *executed*, so its exported PATH belongs to
the child process. The sourced invocation the regression test used
succeeded, which is why the defect survived.

**Repair.** The bootstrap stays executable and keeps writing the
toolchain directory to `$GITHUB_PATH`, which the runner reads for every
following step. The verification moves into its own step,
`tools/verify_nim_toolchain.sh`, which resolves the intended directory
from the last entry of `$GITHUB_PATH` and requires both `nim` and
`nimble` to resolve to it. An unrelated preinstalled compiler or package
manager is therefore not accepted.

**Witness.** `tools/gate_ci_bootstrap.sh` drives the production
invocation boundary: the bootstrap is executed, and the verification runs
as the following workflow step does, through `$GITHUB_PATH`. 17 checks.

## 2. The exact version check

**Reproduction.** The review observed `expected: 9.9.9`,
`reported: 9.9.90`, `actual bootstrap exit: 0`. The comparison was a
shell glob, so any version that starts with the pinned one passed.

**Repair.** The version token is extracted from the compiler's own
output and compared as a whole, in the bootstrap and in the verification
step.

**Witness.** A correct pinned version succeeds; 9.9.90 against 9.9.9
fails and names the mismatch; a missing compiler fails; a missing
nimble fails the verification; the following step resolves the intended
toolchain.

## 3. The qualification authority

**Reproduction.** `IRK_QUALIFY_EXPECTED_INPUTS_DIGEST=...` together with
`IRK_QUALIFY_AUTHORITATIVE=1` produced an authoritative classification
for substituted corpus contents.

**Repair.** The authority is decided by the verification and by nothing
else. Only a successful comparison against the repository-pinned digest
produces `qualification_authoritative=true`. A caller-supplied digest
produces a development-only result; no environment variable can promote
it, and the script reads no authority assertion at all. The production
CI gate sets `IRK_QUALIFY_REQUIRE_AUTHORITATIVE=1` and refuses a
non-authoritative result.

**Witness.** `tools/gate_remote_schema_integrity.sh` exercises the
production rejection path: a modified input with the repository pin is
refused and is not classified as authoritative; a modified input with a
caller-supplied matching digest is non-authoritative; a caller cannot
promote it; and the production gate refuses it. 19 checks.

## 4. The report semantic discrepancy

**Reproduction.** The closure receipt claimed that an external report
pairing PASS with a truncated findings collection is rejected. The
production semantic validator held no such rule.

**Repair.** `src/ironkeeper/contracts/reportsemantics.nim` rejects a
report that carries the `findings.truncated` marker and claims a PASS
assessment. The producer-side downgrade and the truncation accounting
are preserved.

**Witness.** The actual compiled `report validate --json` command is
exercised with a structurally valid synthetic report: a truncated report
with PASS is rejected as a semantic failure (exit 6) and the reason is
named, and the same report with WARN is accepted. The witness was shown
to be non-vacuous: with the rule disabled the integration suite fails,
and with the rule restored it passes.
