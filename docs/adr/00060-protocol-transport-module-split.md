# 00060. Protocol and Transport Module Split

- Date: 2026-03-29
- Status: Accepted

## Context

`libitshell3-protocol` was implemented in Plan 3 as a single library covering
four layers: codec (Layer 1), framing (Layer 2), connection state machine (Layer
3), and transport (Layer 4). During Plan 6 Step 1 (Requirements Intake), a
systematic audit revealed multiple problems with this bundling:

**Spec-code divergences in transport and connection types.** The daemon
architecture spec defined `transport.Connection` as a plain struct with
`recv()`/`send()`/`sendv()`/`close()` returning result unions. The code
implemented a vtable-based `Transport` interface (for test mocking) and a
`connection.Connection` that bundled transport + state machine + client_id +
capabilities + session_id + sequence tracking. These types did not match the
spec, and their responsibilities overlapped with the daemon's `ClientState`.

**Layering confusion between protocol and transport.** The protocol library's
`connection.Connection` contained application-level state (attached_session_id,
negotiated_caps) alongside transport-level I/O. This made it unclear which
module owned connection lifecycle — the protocol library or the daemon. The
`handshake_io.zig` module orchestrated handshake flow using both connection
state and transport I/O, mixing protocol rules with daemon behavior.

**The vtable was unnecessary.** The polymorphic `Transport` vtable was
introduced solely for test mocking (BufferTransport). Real integration tests
using socketpairs proved sufficient, making the vtable indirection pointless
overhead with no production benefit.

**Server-only and client-only code mixed in one module.** `Listener` (server),
`connect()` (client), `auth` (server), `handshake_io` (mixed server/client
functions) all lived in the same library with no separation.

**Connection state machine belongs in the daemon.** The state machine
(handshaking → ready → operating → disconnecting), sequence tracking, and
capability negotiation are protocol _rules_ that the daemon enforces, not wire
format concerns. The wire format library should only define message structures
and serialization — it should not own connection lifecycle.

## Decision

Split `libitshell3-protocol` into two modules:

**`libitshell3-protocol`** — Wire format only. Message type definitions, header
encode/decode, JSON/binary serialization for all message structs (handshake,
session, pane, input, preedit, auxiliary, cell, frame_update), frame
reader/writer. No transport, no connection state, no I/O. Both daemon and client
depend on this.

**`libitshell3-transport`** — Socket lifecycle and byte I/O. Contains:

- `SocketConnection` — plain struct with `fd` + `recv()`/`send()`/`sendv()`/
  `close()` returning result unions (`RecvResult`/`SendResult`). No vtable.
  Matches the daemon architecture spec's `transport.Connection` design.
- `Listener` — server-side: `listen()` with stale socket detection (reports to
  caller, does not auto-unlink), directory creation, `chmod`, `O_NONBLOCK`.
  `accept()` with UID verification and buffer tuning (TODO for Plan 6).
- `connect()` — client-side connection to a daemon socket.
- `socket_path` — path resolution stub (proper implementation deferred to Plan
  12, ADR 00054).

The connection state machine (`ConnectionState`), sequence tracking, capability
negotiation, and handshake orchestration move to the daemon library
(`libitshell3/server/connection/`), where the daemon owns connection lifecycle.
The layered ownership model:

```
transport.SocketConnection    — fd + recv/send/sendv/close (transport module)
    ↑
server.ConnectionState        — state + client_id + caps + session_id + seq (daemon)
    ↑
server.ClientState            — ring_cursors + display_info + message_reader + ... (daemon)
```

## Consequences

**What gets easier:**

- Clear module boundaries — wire format is separate from I/O, connection
  lifecycle is separate from transport.
- The daemon owns its own state machine — no more "does the protocol library or
  the daemon manage connection state?"
- `SocketConnection` matches the spec exactly — plain struct, result unions, no
  vtable indirection.
- Future `SshChannelConnection` can be added to the transport module as a
  separate concrete type without polymorphic abstraction.
- Server-only code (`Listener`, `auth`) and client-only code (`connect()`) are
  in separate files within the transport module.

**What gets harder:**

- Three modules to manage instead of one (protocol, transport, daemon library).
  Build dependency wiring is more complex.
- The old `protocol.connection.Connection` and `protocol.handshake_io` are
  deleted — all code that depended on them must be rewritten in Plan 6.
- CTRs are needed to update the daemon architecture spec: rename
  `transport.Connection` to `transport.SocketConnection` (CTR-03), remove
  `SendvResult` (CTR-04).

**New obligations:**

- Plan 6 Task 0 must execute the module migration (rename v2 modules, delete old
  protocol, wire dependencies) before any implementation work begins.
- The daemon's `server/connection/handshake_handler.zig` must be written fresh
  against the spec — the old `handshake_io.zig` had too many gaps (missing UID
  verification, missing render capability negotiation, missing timeout
  enforcement, wrong version negotiation algorithm).
