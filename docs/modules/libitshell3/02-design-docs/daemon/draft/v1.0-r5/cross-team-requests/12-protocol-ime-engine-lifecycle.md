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
6. **InputMethodSwitch server behavior (from Doc 05 §3.1)**: Document the
   server-internal processing of InputMethodSwitch (0x0404): the server calls
   `setActiveInputMethod()` on the per-session IME engine; for
   `commit_current=false`, the server first calls `reset()` then
   `setActiveInputMethod()`, holding the per-session lock across both calls to
   ensure atomicity; the switch applies to the entire session (all panes), not
   per-pane.
7. **Per-session engine state (from Doc 05 §3.3)**: Document the server's
   per-session IME state: the active `input_method` identifier, the
   `keyboard_layout`, and the single IME engine instance — all maintained at
   session level and shared by all panes. New panes inherit the session's
   current `active_input_method`; no per-pane override is supported. Default for
   new sessions: `input_method: "direct"`, `keyboard_layout: "qwerty"`.
8. **Engine initialization on session restore (from Doc 05 §8.2)**: Document
   that when a session is restored after daemon restart, the server creates one
   `HangulImeEngine` per session with the saved `input_method`; all panes share
   this engine; no per-pane IME state is restored; reconnecting clients receive
   the session's input method via `AttachSessionResponse` and LayoutChanged leaf
   nodes.

## Summary Table

| Target Doc            | Section/Message                   | Change Type | Source Resolution             |
| --------------------- | --------------------------------- | ----------- | ----------------------------- |
| Internal architecture | Per-session IME engine            | Add         | Protocol v1.0-r12 Doc 01 §5.5 |
| Internal architecture | Preedit exclusivity invariant     | Add         | Protocol v1.0-r12 Doc 01 §5.5 |
| Internal architecture | Per-session IME locking           | Add         | Protocol v1.0-r12 Doc 01 §5.5 |
| Runtime policies      | Server IME text derivation        | Add         | Protocol v1.0-r12 Doc 04 §2.1 |
| Internal architecture | InputMethodSwitch server behavior | Add         | Protocol v1.0-r12 Doc 05 §3.1 |
| Internal architecture | Per-session engine state          | Add         | Protocol v1.0-r12 Doc 05 §3.3 |
| Runtime policies      | Engine init on session restore    | Add         | Protocol v1.0-r12 Doc 05 §8.2 |

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

## Reference: Original Protocol Text (from Doc 05 §§3.1, 3.3, 8.2)

The following is the original text from Doc 05 (CJK Preedit Sync and IME
Protocol) describing server-internal IME engine behavior. Provided as reference
for the daemon team — adapt as needed.

### From Doc 05 §3.1 — InputMethodSwitch Server Behavior

**Server implementation**:

- `commit_current=true`: Server calls `setActiveInputMethod(new_method)`. The
  IME flushes (commits) pending composition and switches. This is the standard
  behavior.
- `commit_current=false`: Server calls `reset()` to discard the current
  composition, then `setActiveInputMethod(new_method)` to switch. The server
  MUST hold the per-session lock across both calls to ensure atomicity. The
  PreeditEnd reason is `"cancelled"`.

> The server identifies the session from `pane_id`, then applies the input
> method switch to the entire session (all panes). The switch is not limited to
> the identified pane.

### From Doc 05 §3.3 — Per-Session Input Method State

All panes in a session share the same active input method and keyboard layout.
The server maintains one IME engine instance per session (see IME Interface
Contract, Sections 3.5–3.7 for the per-session engine architecture). When the
user switches input methods on any pane, the change applies to all panes in the
session.

> The new pane inherits the session's current `active_input_method`. No per-pane
> override is supported. To change the input method, send an InputMethodSwitch
> message (0x0404) after the pane is created.

**Default for new sessions**: `input_method: "direct"`,
`keyboard_layout: "qwerty"`. This is a normative requirement — servers MUST
initialize new sessions with these defaults. New panes inherit the session's
current values.

**Input method identifiers**: The protocol uses a single canonical string
identifier for input methods (e.g., `"direct"`, `"korean_2set"`,
`"korean_3set_390"`). This string is the ONLY representation that crosses
component boundaries — it flows unchanged from client to server to IME engine
constructor. The `keyboard_layout` field (e.g., `"qwerty"`, `"azerty"`) is a
separate, orthogonal per-session property and is NOT encoded in the
`input_method` string. Both `input_method` and `keyboard_layout` are stored at
session level in session snapshots (not per pane). See IME Interface Contract,
Section 9 for the session snapshot schema.

### From Doc 05 §8.2 — Restore Behavior (Input Method State)

2. **Input method state**: The session's `input_method` and `keyboard_layout`
   are restored at session level. The server creates one `HangulImeEngine` per
   session with the saved `input_method`. All panes in the session share this
   engine. No per-pane IME state is restored — panes carry no IME fields in the
   session snapshot. When a client reconnects, it receives the session's input
   method via `AttachSessionResponse` and LayoutChanged leaf nodes.
