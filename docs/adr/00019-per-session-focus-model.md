# 00019. Per-Session Focus Model (v1)

- Date: 2026-03-22
- Status: Accepted

## Context

In a multi-client multiplexer, each session has a "focused pane" that receives
keyboard input. Two models exist:

1. **Per-session focus** (tmux model): all attached clients share the same
   active pane. Focus is a property of the session, not the client.
2. **Per-client focus**: each client independently selects which pane is active.
   Focus is a property of the client-session binding.

Per-client focus requires tracking independent focus state per attachment,
splitting input routing, and introducing ambiguity about which pane receives
server-initiated events. Per-session focus keeps the protocol simpler and
matches the mental model users already have from tmux.

## Decision

v1 uses **per-session focus**: the session owns a single `focused_pane_id`, and
all attached clients share it. This matches the tmux model.

Per-client focus may be added in a future version as an opt-in capability
negotiated at handshake. The v1 wire format does not preclude this extension:
the existing message types (`FocusPaneRequest`, `NavigatePaneRequest`,
`LayoutChanged`) can be reused, requiring only server-side tracking changes.

## Consequences

- `FocusPaneRequest` and `NavigatePaneRequest` change the session-level active
  pane, affecting all attached clients immediately.
- The server broadcasts `LayoutChanged` to all attached clients when focus
  changes, so every client stays in sync.
- Focus changes flush any active preedit before processing (commit-by-default
  per ADR 00026).
- Future per-client focus additions are backward-compatible: the existing
  message types suffice, so only a new capability flag and server-side tracking
  are needed.
