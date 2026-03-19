# Move Server-Side IME Engine Lifecycle from Protocol to Daemon

- **Date**: 2026-03-16
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), Doc 01 §5.5 was identified
as containing a server-internal implementation detail: the "Independent IME
state" bullet describes how the daemon manages IME engine instances (per-session
allocation, libhangul memory cost, preedit exclusivity invariant, per-session
locking). These are daemon architecture concerns, not wire-observable protocol
behavior.

The wire-observable aspects of the per-connection-per-session model (independent
FrameUpdate streams, independent sequence counters, independent flow control)
remain in the protocol spec.

## Required Changes

1. **Per-session IME engine allocation**: Document that each session has one IME
   engine instance shared by all panes in the session, and that creating a new
   connection to a new session creates a new IME engine instance.
2. **libhangul memory cost**: Note that per-session libhangul instances are
   trivially cheap (~few KB each).
3. **Preedit exclusivity invariant**: Document that at most one pane in a
   session can have active preedit at any time.
4. **Per-session locking**: Document that when multiple connections attach to
   the same session, they share the same per-session IME state with per-session
   locking for preedit ownership.
5. **Server-side IME text derivation**: Document that the server derives text
   through the native IME engine (libitshell3-ime) from raw HID keycodes and
   modifiers — the client never sends composed text for key input. The client
   does not track IME composition state; the server determines composition state
   internally from the IME engine.

## Summary Table

| Target Doc            | Section/Message               | Change Type | Source Resolution             |
| --------------------- | ----------------------------- | ----------- | ----------------------------- |
| Internal architecture | Per-session IME engine        | Add         | Protocol v1.0-r12 Doc 01 §5.5 |
| Internal architecture | Preedit exclusivity invariant | Add         | Protocol v1.0-r12 Doc 01 §5.5 |
| Internal architecture | Per-session IME locking       | Add         | Protocol v1.0-r12 Doc 01 §5.5 |
| Runtime policies      | Server IME text derivation    | Add         | Protocol v1.0-r12 Doc 04 §2.1 |

## Reference: Original Protocol Text (removed from Doc 01 §5.5)

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the daemon team — adapt as needed. Only the
"Independent IME state" bullet is included — the rest of §5.5 is wire-observable
and remains in the protocol spec.

### From §5.5 — Independent IME state

- **Independent IME state**: IME engine instances are per-session (not
  per-connection or per-pane). Each session has one IME engine shared by all
  panes in the session. Creating a new connection to a new session creates a new
  IME engine instance, providing natural preedit isolation between sessions.
  Per-session libhangul instances are trivially cheap (~few KB each). When
  multiple connections attach to the same session, they share the same
  per-session IME state (with per-session locking for preedit ownership). At
  most one pane in a session can have active preedit at any time (preedit
  exclusivity invariant).

## Reference: Original Protocol Text (removed from Doc 04 §2.1)

The following is the original text from Doc 04 §2.1 (KeyEvent) that describes
server-side IME processing — a daemon implementation detail, not a wire-protocol
concern. Provided as reference for the daemon team — adapt as needed.

### From Doc 04 §2.1 — KeyEvent: Server IME Processing

The primary input message. The client sends raw HID keycodes and modifiers. The
server derives text through the native IME engine (libitshell3-ime) — the client
never sends composed text for key input. The client does not track IME
composition state; the server determines composition state internally from the
IME engine.
