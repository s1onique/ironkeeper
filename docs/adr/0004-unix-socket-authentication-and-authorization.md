# ADR-0004: Unix domain socket, authentication and authorisation

* **Status:** Accepted
* **Date:** 2026-11-26
* **Milestone:** M0 — Foundations (recorded for IRK-06 and IRK-09)
* **Deciders:** Ironkeeper maintainers

## Context

Ironkeeper will eventually run as a daemon and needs a control interface
that a local operator, and possibly a fleet controller, can use to ask
for work and to read results. The interface will carry privileged
requests: start a self-test, admit a device, read a report.

The host is a storage host. It may be reachable from other machines.
Anything that can reach the control interface may be able to influence
what happens to the data-bearing devices.

## Decision

The control interface is a **local Unix domain socket**
(`AF_UNIX`, `SOCK_STREAM`).

The proposed combination, for the milestone that implements it:

* **JSON-RPC 2.0** as the message format.
* **Explicit newline-delimited framing.** One JSON-RPC message per line.
  Framing is never inferred from a JSON parser's return value.
* **Bounded requests and responses.** A request and a response each have
  a maximum size. A larger message is refused, not truncated.
* **Linux `SO_PEERCRED`** to obtain the peer's credentials (uid, gid,
  pid) at connect time.
* **Filesystem access permissions** on the socket as the primary
  authorisation boundary: the socket is owned by a dedicated group, and
  membership of that group is what grants access.
* **systemd socket activation with `Accept=no`.** systemd owns the
  listening socket; Ironkeeper is activated per connection, or the
  socket is passed to the service. `Accept=no` means systemd does not
  fork a process per connection.

Authorisation is a **separate decision** from authentication:

* Authentication establishes *who* is asking, using `SO_PEERCRED` and the
  socket's filesystem permissions.
* Authorisation establishes *what they may ask for*, against an explicit
  policy. Read-only requests and state-changing requests are distinct.

## Rationale

**A Unix socket, not TCP.** A TCP port would need its own
authentication and encryption story and would expand the network surface
of a storage host. A Unix socket inherits the filesystem's permission
model, which operators already understand.

**`SO_PEERCRED` rather than an application-level token.** The kernel
supplies the credentials, so they cannot be forged by the client. An
application-level shared secret would have to be distributed, rotated and
protected, and would be weaker.

**Newline framing.** It keeps the framing separate from the payload
syntax, so that a message that is valid JSON but that arrives in the
wrong place is a framing error rather than a parse error. It also makes
the maximum message size enforceable without buffering an unbounded
amount.

**`Accept=no`.** Socket activation lets systemd own the socket's
lifetime and permissions, and it means Ironkeeper does not need to
implement its own re-binding and privilege-drop dance for the listener.

## Consequences

* The control interface is only reachable from the host. A remote fleet
  controller needs a separate, explicitly designed transport; that is a
  future decision, not an extension of this one.
* Permissions on the socket are load-bearing. The systemd unit must set
  them correctly, and packaging must create the group.
* Every request must be authorised individually. There is no blanket
  "connected clients may do anything".
* Bounded messages mean that a request cannot ask for an unbounded
  amount of work in one call; long operations are job handles.

## Status

Recorded and accepted. The control socket is **not** implemented in
milestone M0. `ironkeeper daemon` returns an explicit
unsupported-operation result rather than pretending to exist.
