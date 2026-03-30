## Example 1: Spec ↔ Code Conflict

### What

The `broadcastSessionEvent` function excludes the requesting client from
receiving layout-change notifications, but the protocol spec says the event is
"sent to ALL clients attached to the session."

### Why

After the user splits a pane, their own terminal window still shows the old
layout. They have to detach and re-attach to see the new pane they just created.
Every other terminal window connected to the same session updates immediately —
only the window that performed the action is stale. This affects all
user-initiated session events (split, close, resize, focus change) because every
call site except session-restore excludes the requester.

### Who

The protocol spec (`server-client-protocols v1.0-r12`) vs. the session handler
implementation (`modules/libitshell3/src/server/handlers/session_handler.zig`).

### When

Introduced during Plan 4 implementation. Not caught in Plan 4 verification
because the test suite only asserted that OTHER clients received the broadcast,
never that the requester also received it.

### Where

**The broadcast flow:**

```
Client sends SplitPane
  → handler processes split
  → broadcastSessionEvent(session, event, exclude=requester)
                                                  ↑ PROBLEM: spec says no exclusion

Inside broadcastSessionEvent:
  for each attached client:
    if client == excluded → SKIP          ← requester never gets the event
    else                  → send event
```

The spec sentence that matters (`server-client-protocols.md`, Section 6.3.2):

> When a session-level event occurs, the daemon MUST broadcast a SessionEvent
> message to ALL clients currently attached to the affected session. The
> broadcast is unconditional — no client filtering is applied.

**Call-site inventory** — every place `broadcastSessionEvent` is called:

| # | Handler file          | Line | Event type       | `exclude_client`    |
| - | --------------------- | ---- | ---------------- | ------------------- |
| 1 | `layout_handler.zig`  | 112  | layout_change    | `request.client_id` |
| 2 | `layout_handler.zig`  | 178  | layout_change    | `request.client_id` |
| 3 | `pane_handler.zig`    | 89   | pane_created     | `request.client_id` |
| 4 | `pane_handler.zig`    | 134  | pane_destroyed   | `request.client_id` |
| 5 | `focus_handler.zig`   | 67   | focus_changed    | `request.client_id` |
| 6 | `focus_handler.zig`   | 103  | focus_changed    | `request.client_id` |
| 7 | `resize_handler.zig`  | 91   | layout_change    | `request.client_id` |
| 8 | `session_handler.zig` | 305  | session_restored | `null`              |

Call sites 1-7 all exclude the requester. Only call site 8 (session restore,
which has no "requester") passes `null`. This means for all user-initiated
actions, the requesting client never receives layout updates and its UI stays
stale until the next full sync.

### How

The owner needs to decide how broadcast semantics should work. Options include
but are not limited to: remove the `exclude_client` parameter entirely (match
the spec literally), keep the exclusion but update the spec to document it as
intentional, or add a separate "acknowledgment" message for the requester while
keeping the broadcast exclusion for the event stream.
