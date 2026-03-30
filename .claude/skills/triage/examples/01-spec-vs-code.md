## Example 1: Spec ↔ Code Conflict

### What

The `broadcastSessionEvent` function excludes the requesting client from
receiving layout-change notifications, but the protocol spec says the event is
"sent to ALL clients attached to the session."

### Why

The protocol spec defines broadcast semantics for session events to ensure every
attached client stays synchronized with the current layout state. If one client
is excluded, its UI becomes stale — it shows the old pane layout until the user
performs an action that triggers a full re-sync. This creates a class of bugs
where the user sees different layouts on different terminal windows connected to
the same session. The implementer likely added the exclusion to avoid "echo" —
sending the requester a notification about their own action — but the spec makes
no exception for the requester.

### Who

The protocol spec (`server-client-protocols v1.0-r12`) vs. the session handler
implementation (`modules/libitshell3/src/server/handlers/session_handler.zig`).

### When

Introduced during Plan 4 implementation. Not caught in Plan 4 verification
because the test suite only asserted that OTHER clients received the broadcast,
never that the requester also received it.

### Where

**Spec quote** (`docs/modules/libitshell3-protocol/server-client-protocols.md`,
lines 847-855):

```
## 6.3.2 Session Event Broadcasting

When a session-level event occurs (layout change, pane creation, pane
destruction, focus change), the daemon MUST broadcast a SessionEvent
message to ALL clients currently attached to the affected session.
The broadcast is unconditional — no client filtering is applied.
Each client independently decides whether to act on or ignore the
event based on its local state.
```

**Function code**
(`modules/libitshell3/src/server/handlers/session_handler.zig`, lines 214-241):

```zig
fn broadcastSessionEvent(
    self: *SessionHandler,
    session: *Session,
    event: SessionEvent,
    exclude_client: ?ClientId,
) !void {
    const attached_clients = session.getAttachedClients();
    var message = protocol.Message.init(.session_event, .{
        .session_id = session.id,
        .event_type = event.event_type,
        .payload = event.payload,
    });

    for (attached_clients) |client| {
        if (exclude_client) |excluded| {
            if (client.id == excluded) continue;  // ← the conflict
        }
        try self.transport.sendMessage(client.connection, message);
    }

    self.metrics.recordBroadcast(session.id, attached_clients.len);
}
```

**Called function's signature** showing what `exclude_client` enables
(`modules/libitshell3/src/server/transport.zig`, line 87):

```zig
/// Sends a message to a specific client connection.
/// The caller is responsible for client filtering — this function
/// performs no filtering of its own.
pub fn sendMessage(self: *Transport, connection: *Connection, message: Message) !void
```

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

