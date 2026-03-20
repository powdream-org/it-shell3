# Move Preedit Race Condition Server Behavior from Protocol to Daemon

- **Date**: 2026-03-20
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), Doc 05 §6.1–6.10 (Race
Condition Handling) and §10.1 (Invalid Composition State) were identified as
containing server implementation internals mixed into the protocol spec.

The protocol spec defines wire-observable behavior — which messages are sent, in
what order, and with what field values. However, the step-by-step server
procedures describing how the server processes each interrupt event internally
(lock ordering, API call sequences, internal state transitions) are daemon
implementation concerns, not wire-protocol concerns.

These server behavior sequences are being removed from Doc 05 and must be
defined in the daemon design docs.

## Required Changes

1. **§6.1 Pane close during composition**: Define the server's internal handling
   procedure: cancel the active composition (do NOT commit to PTY — the PTY is
   being closed), send PreeditEnd with `reason="pane_closed"` to all clients,
   then proceed with the pane close sequence.

2. **§6.2 Client disconnect during composition**: Define the server's internal
   handling procedure: detect disconnect (socket read returns 0 or error),
   commit current preedit text to PTY (best-effort: preserve the user's work),
   send PreeditEnd with `reason="client_disconnected"` to remaining clients,
   clear preedit ownership. Also define the T=300s stale timeout eviction path:
   commit preedit, evict the client, send PreeditEnd with
   `reason="client_evicted"` to remaining clients.

3. **§6.3 Concurrent preedit and resize**: Define the server's internal handling
   procedure: process the resize through libghostty-vt Terminal, recompute
   preedit cell positions internally (cursor row/column may change due to
   reflow), send FrameUpdate with `frame_type=1` (I-frame) containing preedit
   cells at the updated position.

4. **§6.5 Rapid keystroke bursts**: Define the server's internal handling
   procedure: process all pending KeyEvents in order, coalesce intermediate
   preedit states (do not send intermediate PreeditUpdate messages for states
   superseded within the same frame interval), write the final preedit text into
   frame cell data as a single frame, send one PreeditUpdate for the burst.

5. **§6.7 Focus change during composition**: Define the server's internal
   handling procedure: commit the active preedit text to PTY, send PreeditEnd
   with `reason="focus_changed"` to all clients, then send LayoutChanged with
   the new focused pane. (Decision: ADR 00026 — focus change always commits, not
   cancels.)

6. **§6.8 Session detach during composition**: Define the server's internal
   handling procedure: commit current preedit text to PTY (preserve the user's
   work), send PreeditEnd with `reason="client_disconnected"` to remaining
   clients, clear preedit ownership, then process the session detach normally.

7. **§6.9 InputMethodSwitch during active preedit**: Define the server's
   internal handling procedure: if `commit_current=true`, call
   `setActiveInputMethod(new_method)` (the IME flushes and switches); if
   `commit_current=false`, call `reset()` to discard current composition then
   call `setActiveInputMethod(new_method)`, holding the per-session lock across
   both calls to ensure atomicity. Send PreeditEnd with the appropriate reason
   to all clients, then send InputMethodAck broadcast.

8. **§6.10 Mouse click during composition**: Define the server's internal
   handling procedure: commit current preedit text to PTY, send PreeditEnd with
   `reason="committed"` and the committed text to all clients, then forward the
   mouse event to the terminal.

9. **§10.1 Invalid composition state**: Define the server's internal error
   recovery procedure: log the error with full state dump, commit whatever
   preedit text exists to PTY, reset composition state to `null` (no active
   composition), send PreeditEnd with `reason="cancelled"` to all clients,
   optionally send a diagnostic notification to the composing client.

## Summary Table

| Target Doc       | Section/Message                    | Change Type | Source Resolution              |
| ---------------- | ---------------------------------- | ----------- | ------------------------------ |
| Runtime policies | Pane close server behavior         | Add         | Protocol v1.0-r12 Doc 05 §6.1  |
| Runtime policies | Client disconnect server behavior  | Add         | Protocol v1.0-r12 Doc 05 §6.2  |
| Runtime policies | Resize server behavior             | Add         | Protocol v1.0-r12 Doc 05 §6.3  |
| Runtime policies | Rapid keystrokes server behavior   | Add         | Protocol v1.0-r12 Doc 05 §6.5  |
| Runtime policies | Focus change server behavior       | Add         | Protocol v1.0-r12 Doc 05 §6.7  |
| Runtime policies | Session detach server behavior     | Add         | Protocol v1.0-r12 Doc 05 §6.8  |
| Runtime policies | InputMethodSwitch server behavior  | Add         | Protocol v1.0-r12 Doc 05 §6.9  |
| Runtime policies | Mouse click server behavior        | Add         | Protocol v1.0-r12 Doc 05 §6.10 |
| Runtime policies | Invalid composition state recovery | Add         | Protocol v1.0-r12 Doc 05 §10.1 |

## Reference: Original Protocol Text (removed from Doc 05 §6.1–6.10 and §10.1)

The following is the original "Server behavior" text as it appeared in Doc 05.
The wire-observable properties (wire traces, reason values, message ordering)
remain in the protocol spec; the internal procedures below are what this CTR
asks the daemon team to define.

### §6.1 Pane Close During Composition — Server behavior

1. Cancel the active composition (do NOT commit to PTY — the PTY is being
   closed)
2. Send PreeditEnd with `reason="pane_closed"` to all clients
3. Proceed with pane close sequence

### §6.2 Client Disconnect During Composition — Server behavior

1. Detect disconnect (socket read returns 0 or error)
2. Commit current preedit text to PTY (best-effort: preserve the user's work)
3. Send PreeditEnd with `reason="client_disconnected"` to remaining clients
4. Clear preedit ownership

**Timeout**: If the server receives no input from the preedit owner for T=300s
(per doc 06 health escalation timeline), it commits the current preedit, evicts
the client, and sends `PreeditEnd` with `reason="client_evicted"` to remaining
clients. This handles cases where the client is frozen but the socket is still
open.

### §6.3 Concurrent Preedit and Resize — Server behavior

1. Process the resize through libghostty-vt Terminal
2. The server repositions preedit cells internally (cursor row/column may change
   due to reflow)
3. Send FrameUpdate with `frame_type=1` (I-frame) — preedit cells are included
   in the cell data at the updated position

### §6.5 Rapid Keystroke Bursts — Server behavior

1. Process all pending KeyEvents in order
2. Coalesce intermediate preedit states — only send the final PreeditUpdate for
   the burst
3. The server injects the final preedit text into frame cell data, and the
   resulting cell data is written to the ring buffer as a single frame

### §6.7 Focus Change During Composition — Wire behavior

The server sends `PreeditEnd` with `reason="focus_changed"` to all clients,
followed by `LayoutChanged` with the new focused pane. PTY commit details are
defined in daemon design docs.

### §6.8 Session Detach During Composition — Server behavior

1. Commit current preedit text to PTY (preserve the user's work)
2. Send PreeditEnd with `reason="client_disconnected"` to remaining clients
3. Clear preedit ownership
4. Process the session detach normally

### §6.9 InputMethodSwitch During Active Preedit — Server behavior

1. If `commit_current=true`: Commit current preedit text to PTY, send PreeditEnd
   with `reason="committed"` to all clients
2. If `commit_current=false`: Cancel current preedit, send PreeditEnd with
   `reason="cancelled"` to all clients
3. Switch the session's input method (applies to all panes)
4. Send InputMethodAck to all attached clients

**Server implementation**:

- `commit_current=true`: Server calls `setActiveInputMethod(new_method)`. The
  IME flushes (commits) pending composition and switches. This is the standard
  behavior.
- `commit_current=false`: Server calls `reset()` to discard the current
  composition, then `setActiveInputMethod(new_method)` to switch. The server
  MUST hold the per-session lock across both calls to ensure atomicity. The
  PreeditEnd reason is `"cancelled"`.

### §6.10 Mouse Event During Composition — Server behavior

1. Commit current preedit text to PTY
2. Send PreeditEnd with `reason="committed"` and the committed text to all
   clients
3. Forward the mouse event to the terminal

### §10.1 Invalid Composition State

If the server's IME engine reaches an invalid state (should not happen with
correctly implemented Korean algorithms):

1. Log the error with full state dump
2. Commit whatever preedit text exists to PTY
3. Reset composition state to `null` (no active composition)
4. Send PreeditEnd with `reason="cancelled"` to all clients
5. Send a diagnostic notification to the composing client (optional)
