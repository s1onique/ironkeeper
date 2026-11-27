# Supported backend capabilities

The observation tools are external, trusted and closed over. No CLI
option and no configuration file can make an ordinary invocation execute
an arbitrary program.

| Tool | Canonical path | Invocation | Qualified version |
|---|---|---|---|
| `smartctl` | `/usr/sbin/smartctl` | `smartctl -x --json=o DEVICE` | smartctl 7.2 - 7.5 |
| `sg_readcap` | `/usr/bin/sg_readcap` | `sg_readcap --readonly --long --json DEVICE` | sg3_utils 4.13 |

## smartctl

The `-jv` spelling of the `-j` option is ambiguous in smartctl 7.x: the
tool reads it as `-j` with the value `v` and refuses the device
argument. The explicit `--json=o` form is therefore the invocation.

The `-x` option requests every available page, and `--json=o` requests
the JSON output format. The tool writes its response to stdout and its
diagnostics to stderr; both streams are captured separately and are
bounded independently.

The exit status is a **bitmask**. All eight bits are decoded and the
original numeric status is preserved. The bit that reports a
device-reported failing condition is a *health observation*, not a
collection failure: an inspection of a failing disk exits successfully.

The tool version that produced a response is recorded from the response
itself, not from a separate invocation.

## sg_readcap

The JSON support is version-dependent, so the decoder accepts the member
and field names of the supported versions:

| Purpose | Accepted names |
|---|---|
| the response member | `read_capacity_16_parameter_data`, `read_capacity` |
| the last logical block address | `returned_logical_block_address`, `last_lba` |
| the logical block length | `logical_block_length_in_bytes`, `block_length` |

No arbitrary human-readable output is parsed with uncontrolled
heuristics. `sg_format` and every other modifying operation are never
invoked.

## The execution limits

| Limit | Value | Rationale |
|---|---|---|
| Per-command deadline | 30 s | A spinning-up SAS drive behind two expanders answers in seconds; 30 s is generous for a healthy path and short enough to bound a stuck path. |
| Maximum stdout | 4 MiB | The verbose JSON of one device is well under 1 MiB; 4 MiB leaves headroom for a device with a long self-test log. |
| Maximum stderr | 256 KiB | The diagnostics of one invocation are small; a larger stream indicates a misbehaving tool. |
| Active interrogation concurrency | 1 | The interrogation of one device must not compete with the traffic of the host it observes. |

These values are the defaults in `src/ironkeeper/storage/procexec.nim`.
They were not changed during the ACT: the observed invocations of the
live host completed well inside them.

## The test seam

The test harness injects a controlled executable through
`IRONKEEPER_TEST_TOOL_DIR`. The seam only takes effect when the
directory exists and the resolved file is an executable regular file. It
exists so that the tests exercise the production code path, and it does
not widen the set of supported operations.
