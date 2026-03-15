# Move KeyEvent pane_id Routing Logic from Protocol to Daemon

- **Date**: 2026-03-16
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), the `pane_id` routing
paragraph in Doc 04 (Input Forwarding and RenderState) §2.1 KeyEvent was
identified as daemon implementation detail. The wire spec only needs to define
the field semantics (optional u32, 0 = focused pane). How the server routes,
validates, and handles race conditions is daemon-internal.

## Required Changes

1. **pane_id routing logic**: Add a section describing how the server routes
   KeyEvents based on `pane_id` — omitted/0 routes to focused pane, non-zero
   routes directly after validation.
2. **IME composition race prevention**: Document the SHOULD recommendation for
   clients to specify `pane_id` during IME composition to prevent focus-change
   races.

## Summary Table

| Target Doc       | Section/Message   | Change Type | Source Resolution             |
| ---------------- | ----------------- | ----------- | ----------------------------- |
| Runtime policies | KeyEvent routing  | Add         | Protocol v1.0-r12 Doc 04 §2.1 |
| Runtime policies | IME race handling | Add         | Protocol v1.0-r12 Doc 04 §2.1 |

## Reference: Original Protocol Text (removed from Doc 04 §2.1)

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the daemon team — adapt as needed.

### `pane_id` routing

When `pane_id` is omitted or 0, the server routes the KeyEvent to the session's
currently focused pane. When present and non-zero, the server validates that the
pane exists in the client's attached session and routes directly. During IME
composition, the client SHOULD specify `pane_id` to prevent focus-change races —
if another client changes focus mid-composition, explicitly routed KeyEvents
continue to reach the correct pane.
