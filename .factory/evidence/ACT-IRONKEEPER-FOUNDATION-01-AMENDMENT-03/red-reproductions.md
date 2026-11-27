# RED reproductions

Every finding of this amendment was reproduced against the **production
path**, at the entry commit `fb9c5f6d5ec602b272c108a9d23a7342cbadcd35`,
before the corresponding repair.

## F1 — The conformance harness compared nothing

**Production path.** `tools/validator_conformance.nim` (entry revision),
driven by `tools/qualify_validator.sh`.

**The defect.** The harness loaded `TestCase.expectedValid` and never
compared it with the observed verdict. Its classification enum had four
values — `ckPass`, `ckFail`, `ckWrong`, `ckError` — and the counting
logic accepted `ckPass` **or** `ckFail` as a successful conformance case:

```nim
if outcome.kind == ckPass or outcome.kind == ckFail:
  inc mandatoryPassed
```

`ckPass` meant "the validator accepted" and `ckFail` meant "the validator
rejected". Both counted as a pass, so a validator that accepted every
document and one that rejected every document scored identically.

**The observed consequence.** The entry receipt reported
`mandatory_passed=1337`, `mandatory_failed=0`, `optional_passed=1031`,
`optional_failed=6`. Those counts were produced by the harness, and they
are retained as a historical observation. They establish nothing about
conformance, because no comparison was ever made.

**Reproduced by inspection and by the corrected harness.** The corrected
harness (`src/ironkeeper/qualification/verdict.nim`) classifies a case by
comparing the observed verdict with the expected one, and the witnesses
in `tools/validator_conformance_witnesses.nim` drive it with controlled
providers. See `green-witnesses.md`.

## F2 — The secret-scan gate validated its report with grep

**Production path.** `tools/gate_secret_scan.sh` (entry revision).

**The defect.** The report was validated with

```sh
elif ! grep -q '^\s*\[' "$GITLEAKS_REPORT"; then
```

and the finding count was

```sh
FINDINGS=$(grep -c '"RuleID"' "$GITLEAKS_REPORT" || true)
```

A grep cannot distinguish a complete JSON document from a truncated one,
an empty array from an array with one member, or a JSON array from an
arbitrary line that happens to begin with `[`.

**Observed consequence.** A controlled scanner that exited zero and
produced each of the following reports was run against the **entry**
revision of the gate (`git show fb9c5f6:tools/gate_secret_scan.sh`):

| Report | Expected | Observed at entry | Observed after the repair |
|---|---|---|---|
| `[{}]` | fail (nonempty array) | **exit 0 — passed** | exit 1 |
| `[] trailing garbage` | fail (not a complete document) | **exit 0 — passed** | exit 1 |
| `[` (truncated) | fail (not a complete document) | **exit 0 — passed** | exit 1 |
| `{"findings": []}` | fail (root is not an array) | exit 1 | exit 1 |

The first three passed the gate at the entry revision. The fourth already
failed, because the grep required a leading `[`.

The counterexamples are reproduced by `tools/gate_fault_injection.sh` in
the section "secret-scan gate: controlled scanner fixtures"; see
`green-witnesses.md`.

## F3 — The public output was not bounded by its own contracts

**Production path.** `src/ironkeeper/contracts/report.nim` and
`src/ironkeeper/cli/app.nim` (entry revision).

**The defect.** `schemas/v1/report.schema.json` limits a finding message
to 4096 characters, a location to 1024 characters and the findings array
to 1024 entries. `schemas/v1/validation.schema.json` limits an issue
message to 4096 characters, a location to 1024 characters and the issue
array to 1024 entries. Nothing in the producer enforced those limits:
the messages, the locations and the collections were emitted verbatim.

**Observed consequence.** The oversized-document tests established only
that the *schema* rejects invalid output. They did not establish that
production output always conforms. An oversized numeric lexeme, an
oversized validation location, an oversized diagnostic message and more
issues than the schema allows all reached stdout unbounded.

## F4 — The bounded reader trusted the pathname

**Production path.** `readDocument` in `src/ironkeeper/cli/app.nim` (entry
revision).

**The defect.** The reader opened the path with a **blocking** `open`,
and only afterwards checked that the handle referred to a regular file:

```nim
if not open(f, path, fmRead): ...
let info = getFileInfo(f)
if info.kind != pcFile: ...
```

A regular file can be replaced by a FIFO between the two operations. The
blocking `open` of a FIFO with no writer blocks forever, and the process
hangs before the check ever runs.

**Observed consequence.** The substitution is reproduced deterministically
in `tests/unit/boundedread_tests.nim` through the repository's own open
observer. The non-vacuity probe — replacing the descriptor check with a
pathname pre-check — makes the substitution slip through; see
`green-witnesses.md`.

## F5 — The schema policy and the reference collector disagreed

**Production path.** `src/ironkeeper/contracts/schemapolicy.nim` and
`collectExternalRefs` in `src/ironkeeper/contracts/validator.nim` (entry
revision).

**The defect.** The two traversed the document differently. The policy
walked schema-bearing positions; the reference collector walked *every*
member of *every* object. A `$ref` inside a literal `const` object or an
`examples` array was therefore treated as a reference, and a schema that
carried such a value was refused for a construct it does not contain.

**Observed consequence.** The witnesses in
`tests/unit/schemapolicy_tests.nim` pin the position-aware behaviour.

## F6 — The qualification removed the caller's directory

**Production path.** `tools/qualify_validator.sh` (entry revision).

**The defect.** The cleanup handler removed `IRK_QUALIFY_WORK` itself,
recursively:

```sh
cleanup() {
  if [ "$KEEP" != "1" ]; then
    rm -rf "$WORK"
  fi
}
```

A caller who pointed `IRK_QUALIFY_WORK` at a directory with other content
lost that content.

**Observed consequence.** The repair is witnessed with an isolated
temporary parent containing a sentinel file; see `green-witnesses.md`.
