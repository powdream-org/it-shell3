# 00017. Pane Minimum Size

- Date: 2026-03-16
- Status: Accepted

## Context

When a pane is split, the resulting panes must have a minimum size below which
the split is rejected (SplitPaneResponse status 3, TOO_SMALL). The
libitshell3-protocol server-client-protocols draft/v1.0-r12 Doc 03 (Session and
Pane Management) listed this as an open question without a defined value.

A separate but related threshold exists in libitshell3-protocol
server-client-protocols draft/v1.0-r12 Doc 04 (Input Forwarding and
RenderState): the server suppresses FrameUpdate for already-existing panes that
fall below `cols < 2` or `rows < 1` via resize. The split rejection threshold
defined here prevents creating panes below that size in the first place.

## Decision

Pane minimum size is 2 columns x 1 row, matching tmux's minimum. Splits that
would result in either child being smaller than this are rejected.

## Consequences

- Consistent with tmux behavior — users familiar with tmux encounter the same
  limits.
- Using the same value (2x1) for both split rejection and rendering suppression
  ensures no pane can be created that is immediately unrenderable.
- Very aggressive splitting (e.g., 20+ panes in a small terminal) is naturally
  limited by this floor.
