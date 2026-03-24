# 00051. Eager Per-Session IME Deactivation

- Date: 2026-03-24
- Status: Accepted

## Context

The `ImeEngine` is a per-session shared resource. When clients attach to and
detach from a session, the daemon must decide when to call `deactivate()` on the
engine. Two dimensions:

**Scope — per-client vs per-session**: Should `deactivate()` fire when any
single client detaches, or only when the session's attached-client count drops
to zero?

- Per-client deactivation would discard in-progress composition belonging to
  remaining attached clients, violating the last-writer-wins preedit ownership
  model.
- Per-session deactivation preserves composition as long as any client is
  attached.

**Timing — eager vs lazy**: Should `deactivate()` fire immediately when the last
client departs, or defer until the engine is actually needed again?

- Lazy deactivation creates deferred routing bugs. Concrete scenario: user
  composes Korean text in Session A (solo client), switches to Session B, closes
  Session A's pane from B, then types in B. Lazy deactivation would attempt to
  flush committed text to a pane that no longer exists.
- Eager deactivation flushes committed text while the pane is still alive.

## Decision

**Eager, per-session deactivation.** The engine is deactivated immediately when
the session's attached-client count drops to zero. The engine is activated when
the first client attaches.

- `deactivate()` flushes any in-progress composition (committed text written to
  the focused pane's PTY) and resets the engine to idle state.
- `activate()` is a no-op for Korean (the engine is stateless between
  activate/deactivate cycles).
- Zero cost when not composing: `deactivate()` on an empty engine returns
  `ImeResult{}` (all null/false fields).
- The engine's `active_input_method` is NOT changed by deactivate/activate.
  Users expect that switching sessions and coming back preserves their input
  mode.

## Consequences

- No deferred routing bugs — composition is always flushed while the target pane
  exists and its PTY fd is open.
- Multi-client sessions are safe — `deactivate()` only fires when ALL clients
  have left, so no client's in-progress composition is discarded prematurely.
- Language mode is preserved across session switches — only composition state is
  cleared, not the active input method.
- Negligible performance cost — deactivate/activate are trivial operations when
  no composition is active.
