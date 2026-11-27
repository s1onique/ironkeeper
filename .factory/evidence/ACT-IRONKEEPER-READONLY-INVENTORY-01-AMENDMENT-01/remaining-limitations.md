# Remaining limitations

These are the limits that this amendment does **not** lift. They are
stated here so that they are not mistaken for completed work.

1. **No handle-bound authority.** The tools are executed by pathname.
   The pre/post identity checks narrow the window between the selection
   and the execution; they do not close it. Handle-bound authority for
   intrusive operations remains a mandatory future gate (IRK-05 /
   IRK-07).
2. **No multipath management.** The identity model detects an ambiguous
   target and refuses it. It does not enrol a multipath device, does not
   probe a device through every alias and does not persist an enrolment.
   The durable identity registry remains IRK-03 / IRK-05.
3. **No full-surface read scanner.** The individual self-test history
   records and the individual ATA attribute records are preserved but
   **not** interpreted. An ATA attribute carries a vendor-specific
   meaning, and a universal meaning must not be inferred from it. The
   scanner remains IRK-07.
4. **No live execution by the development agent.** No live execution was
   authorised for this amendment, so the amended production path has
   been exercised against synthetic fixtures and the compiled CLI only.
   The live requalification is the operator's procedure.
5. **The public history still carries the predecessor's identifiers.**
   The status is established in `privacy-history.md`; the remediation is
   a separate, operator-authorised act.
6. **`sg_readcap` support is version-dependent.** The decoder accepts
   the member names and the field names of the supported versions. A
   version that names its members differently is refused rather than
   parsed with heuristics.
