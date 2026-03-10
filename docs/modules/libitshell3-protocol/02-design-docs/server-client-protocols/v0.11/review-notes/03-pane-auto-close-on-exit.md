# Pane Auto-Close on Process Exit

**Date**: 2026-03-07
**Raised by**: owner
**Severity**: MEDIUM
**Affected docs**: Doc 03 (Session/Pane Management)
**Status**: open

---

## Problem

The spec does not define what happens to a pane when its shell process exits. `PaneMetadataChanged` (0x0181) provides `is_running: false` and `exit_status`, but the server's response to process termination is unspecified.

## Analysis

Two behaviors are possible:

**Auto-close**: Server automatically closes the pane on process exit. Triggers `LayoutChanged` and layout reflow. Simple, no dead panes accumulate.

**Remain-on-exit**: Pane stays visible showing exit status until user manually closes it. Useful for reviewing build output or error messages. tmux supports this as an option.

## Proposed Change

v1: auto-close. When a pane's process exits, the server MUST automatically close the pane. The server sends `PaneMetadataChanged` with `is_running: false` followed by the same sequence as `ClosePane` (layout reflow, `LayoutChanged` notification).

**Cascade with Q1 (last-pane-close)**: If the auto-closed pane was the last pane in the session, the session is auto-destroyed (`ClosePaneResponse` `side_effect = 1`). From all connected clients' UI perspective, this means the terminal tab closes when the last pane's process exits. This cascade is intentional — owner confirmed no issue with this behavior.

**libghostty integration**: ghostty has a `wait-after-command` config option (default `false` = auto-close). libghostty does not read config files — the embedder must explicitly pass `wait_after_command` via `Surface.Options` when creating each Surface. Our daemon (embedder) MUST pass `wait_after_command = false` to ensure auto-close behavior. See `v0.7/research/04-ghostty-wait-after-command.md` for full details.

Remain-on-exit is deferred to post-v1 (see `99-post-v1-features.md` Section 2).

## Owner Decision

Auto-close for v1. Remain-on-exit is post-v1.

## Resolution

{To be resolved in v0.9.}
