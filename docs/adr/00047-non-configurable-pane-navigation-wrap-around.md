# 00047. Non-Configurable Pane Navigation Wrap-Around

- Date: 2026-03-24
- Status: Accepted

## Context

Pane navigation wrap-around determines what happens when the user navigates "up"
from the topmost pane or "left" from the leftmost pane. Two options exist:

- **Wrap**: Navigation cycles to the opposite edge (topmost → bottommost).
- **No-wrap**: Navigation stops at the edge (no effect).

A configurability question arises: should wrap-around behavior be a user
setting? If so, what scope — per-session, global, client-settable?

Prior art:

- **tmux**: Always wraps. No configuration option.
- **zellij**: Always wraps. No configuration option.
- No major terminal multiplexer provides a "no wrap" option.

## Decision

Wrap-around is always enabled and non-configurable in v1. The
`findPaneInDirection()` algorithm unconditionally searches the opposite
direction when no candidate is found in the primary direction.

Adding configurability is deferred to post-v1 if user feedback requests it
(YAGNI).

## Consequences

- **Simpler algorithm**: No conditional branching for wrap vs. no-wrap.
  `findPaneInDirection()` always returns a non-null result in multi-pane
  sessions.
- **Matches user expectations**: tmux and zellij users expect wrap-around.
  Disabling it would be surprising.
- **No settings surface**: Avoids introducing a configuration option (scope
  question: per-session? global? client-settable?) for a feature with no known
  user demand for customization.
- **Potential future work**: If post-v1 users request no-wrap mode, the
  algorithm change is localized to `findPaneInDirection()` — skip the
  wrap-around step and return `null` instead. The protocol already supports
  `null` returns (no navigation occurred).
