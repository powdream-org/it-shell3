# 00026. Preedit Interrupt Policy: Commit Unless Impossible

- Date: 2026-03-20
- Status: Accepted

## Context

The server-side IME engine owns all composition state. When an external event
interrupts an active preedit — pane close, client disconnect, resize, focus
change, IME switch, daemon restart, or others — the server must apply a
consistent policy.

Without an explicit policy, implementations diverge. Some events destroy the
editing context (PTY going away), making commit impossible. Others are purely
viewport operations that do not touch the editing context at all. Still others
are cases where the client explicitly controls the outcome. Mixing these up
either loses user work unnecessarily or produces corrupted terminal output.

## Decision

The default policy is **commit**: preserve the user's in-progress composition by
writing it to the PTY.

There are exactly three classes of exception:

1. **Cancel** — when the PTY target is gone (e.g., pane close). Commit is
   impossible because there is nowhere to write. Cancel is the only correct
   action.

2. **Preserve** — when the editing context is unchanged (e.g., resize, mouse
   scroll). These are viewport-only operations; the cursor position and PTY are
   unaffected. There is no reason to interrupt composition at all.

3. **Client delegation** — the `commit_current` flag on `InputMethodSwitch`.
   This is the only event where the client explicitly controls whether the
   in-progress composition is committed or discarded. Clients SHOULD default to
   `commit_current=true`; the cancel path exists for language-switch scenarios
   where discard may be appropriate.

All other interrupting events — client disconnect, screen switch, focus change,
session detach, mouse click, daemon restart restore — fall under the default
commit policy. They are not individually enumerated here; the principle covers
them.

For daemon restart restore specifically: v1 commits on restore.
Resume-on-restore (delivering a `PreeditSync` to the reconnecting client) is not
in scope for v1.

## Consequences

- Commit-by-default minimizes data loss; cancel is restricted to the single case
  where the PTY target no longer exists.
- Resize and mouse scroll do not interrupt composition. This is a normative
  requirement — any implementation that commits on resize or scroll is
  incorrect.
- The `commit_current` flag on `InputMethodSwitch` is the only case where the
  commit-vs-cancel decision is delegated to the client. All other events have a
  fixed server-side policy.
- v1 commits on daemon restart restore; resume-on-restore is not in scope for
  v1.
