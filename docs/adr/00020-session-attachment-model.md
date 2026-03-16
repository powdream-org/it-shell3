# 00020. Session Attachment Model

- Date: 2026-03-16
- Status: Accepted

## Context

A client app may have multiple tabs, each attached to a different session. The
protocol must define how connections map to sessions — whether a single
connection can multiplex multiple sessions, and how multi-client access to the
same session is governed (input ordering, readonly observers, exclusive access).

## Decision

**Single-session-per-connection:** Each client connection is attached to at most
one session at a time. To switch sessions, the client must first detach
(`DetachSessionRequest`) then attach to the new session. Sending
`AttachSessionRequest` while already attached returns
`ERR_SESSION_ALREADY_ATTACHED`. A multi-tab client opens one connection per tab.
This matches tmux behavior — each `tmux attach` opens its own Unix socket
connection. The difference is that tmux clients are separate processes while
it-shell3 manages multiple connections within a single GUI app process; from the
daemon's perspective, the pattern is the same.

**Multi-client access modes:** When multiple clients attach to the same session:

- **Input ordering:** Arrival order at the server — no client-side coordination.
- **Readonly attach:** A client can attach in readonly mode (observer, no input
  forwarded to PTY).
- **Exclusive attach:** A client can set `detach_others` to forcibly detach all
  other clients from the session.

Details of readonly and exclusive attach are specified in the handshake spec
(Doc 02, `AttachSessionRequest`/`AttachSessionResponse`).

## Consequences

- One connection per tab — simple state machine (each connection has exactly one
  session context or none).
- Session switching requires a detach/attach round-trip, not an in-place swap.
  Acceptable latency over Unix socket.
- Multi-client scenarios (pair programming, monitoring) are supported via
  readonly and exclusive modes without protocol-level locking.
