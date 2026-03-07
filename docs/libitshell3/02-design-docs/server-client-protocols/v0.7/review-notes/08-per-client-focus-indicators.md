# Per-Client Focus Indicators

**Date**: 2026-03-07
**Raised by**: owner (carried forward from v0.5)
**Severity**: ENHANCEMENT (v1 nice-to-have)
**Affected docs**: Doc 03 (Session/Pane Management)
**Status**: open
**Original source**: `v0.5/review-notes-01-per-client-focus-indicators.md`, Issue 1 (lines 1–186)

---

## Problem

When multiple clients are attached to the same session, there is no way to show which clients are focused on which tabs and panes. The protocol has multi-client awareness infrastructure (`client_id`, `client_name`, `ClientAttached`/`ClientDetached`, `ClientHealthChanged`) but no per-client focus tracking.

## What Exists

| Element | Location | Purpose |
|---------|----------|---------|
| `client_id` (u32) | ServerHello (doc 02) | Unique per-connection identifier |
| `client_name` (string) | ClientHello (doc 02) | Human-readable name |
| `ClientAttached` (0x0183) | Doc 03, Section 4 | Join notification |
| `ClientDetached` (0x0184) | Doc 03, Section 4 | Leave notification |
| `ClientHealthChanged` (0x0185) | Doc 03, Section 4 | Health transition notification |

## What Is Missing

- **Per-client focus tracking**: Server does not track which pane each client is viewing. v1 uses shared focus — all clients share one `active_pane_id` per session (tmux model).
- **`ClientFocusChanged` notification**: No message to broadcast when a client changes their focused pane.
- **`ListAttachedClients` query**: No way to query attached clients and their focus state on demand (e.g., on reconnect).
- **Per-client cursor broadcasting**: No mechanism for showing other clients' cursor positions within shared panes ("fake cursors").

## Design Decisions Needed

1. **Display-only focus vs independent input routing**: Each client tracks what they are *looking at* (display-only), or each client's input goes to their own focused pane (zellij independent mode). Independent mode requires per-client PTY size negotiation.
2. **Message ID allocation**: 0x0185 is now occupied by `ClientHealthChanged`. New message IDs needed.
3. **Client-side rendering approach**: Our RenderState architecture means the client renders focus indicators locally from protocol messages (tab bar markers, pane frame indicators, optional fake cursors).

## Zellij Reference

The v0.5 source document (Section 3) contains detailed zellij reference material: two modes (mirrored/independent), color assignment (`client_id % 10`), server-side `other_focused_clients` computation, tab bar and pane frame rendering patterns. Still valid for design work.

## Proposed Change

{To be designed. See original source for sketches.}

## Resolution

{To be resolved in v0.8 or later.}
