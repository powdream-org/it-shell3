## Example 4: Code <-> Code Conflict

### What

The session manager's `destroySession` function frees all pane slots
synchronously during session teardown, but the frame delivery subsystem's
`deliverPendingFrames` timer callback reads those same pane slots on a 16 ms
interval without checking whether the owning session is still alive. When a
session is destroyed between timer ticks, the next tick dereferences freed
memory.

### Why

Both modules have internally consistent logic. The session manager assumes that
once `destroySession` is called, no further reads will occur because all clients
have been disconnected. The frame delivery subsystem assumes pane slots remain
valid for the entire lifetime of the session, and that it will be explicitly
stopped before any teardown begins. Neither module coordinates with the other
about shutdown ordering. The result is a use-after-free that is timing-dependent
and only manifests under load (multiple panes, rapid session close).

### Who

The session manager (`modules/libitshell3/src/session/session_manager.zig`) vs.
the frame delivery subsystem
(`modules/libitshell3/src/server/frame_delivery.zig`).

### When

Both functions were introduced during Plan 3 (session lifecycle) and Plan 4
(frame delivery pipeline) respectively. The conflict was not caught because Plan
3 tests do not exercise concurrent frame delivery, and Plan 4 tests never
destroy a session mid-delivery.

### Where

**Session manager destruction sequence**
(`modules/libitshell3/src/session/session_manager.zig`, lines 187-213):

```zig
pub fn destroySession(self: *SessionManager, session_id: SessionId) !void {
    const session = self.sessions.get(session_id) orelse
        return error.SessionNotFound;

    // Step 1: Disconnect all attached clients
    for (session.attached_clients.items()) |client| {
        try self.transport.disconnectClient(client.id, .session_destroyed);
    }
    session.attached_clients.clear();

    // Step 2: Free all pane slots
    for (session.pane_tree.allPanes()) |pane| {
        pane.pty.close();
        pane.render_state.deinit();
        self.pane_allocator.free(pane);  // <-- pane memory returned to pool
    }
    session.pane_tree.clear();

    // Step 3: Remove session from registry
    self.sessions.remove(session_id);
    self.session_allocator.free(session);

    log.info("session destroyed: {}", .{session_id});
}
```

**Frame delivery timer callback**
(`modules/libitshell3/src/server/frame_delivery.zig`, lines 94-123):

```zig
fn deliverPendingFrames(self: *FrameDelivery) void {
    for (self.active_sessions.items()) |session_id| {
        const session = self.session_registry.get(session_id) orelse continue;

        for (session.pane_tree.allPanes()) |pane| {
            // Read the pane's render state to check for dirty cells
            if (!pane.render_state.isDirty()) continue;  // <-- reads freed memory

            const frame = pane.render_state.extractDirtyFrame() orelse continue;

            for (session.attached_clients.items()) |client| {
                const message = protocol.Message.init(.frame_data, .{
                    .session_id = session_id,
                    .pane_id = pane.id,
                    .frame = frame,
                });
                self.transport.sendMessage(client.connection, message) catch |err| {
                    log.warn("frame delivery failed for client {}: {}", .{ client.id, err });
                };
            }

            pane.render_state.clearDirty();
        }
    }
}
```

**Execution timeline showing the race:**

```
Time    Thread / Subsystem       Action
----    --------------------     -----------------------------------------
T+0     Frame delivery timer     deliverPendingFrames() starts iteration
T+0     Frame delivery timer     Reads session S1 from registry (valid)
T+1     Client request thread    destroySession(S1) called
T+1     Client request thread    Disconnects all clients for S1
T+2     Client request thread    Frees pane P1 slot (pane_allocator.free)
T+2     Client request thread    Frees pane P2 slot (pane_allocator.free)
T+3     Client request thread    Removes S1 from session registry
T+3     Client request thread    Frees session S1
T+4     Frame delivery timer     Iterates S1.pane_tree.allPanes()
T+4     Frame delivery timer     Calls pane.render_state.isDirty() on P1
        ^^^ USE-AFTER-FREE: P1 was freed at T+2 ^^^
```

The session pointer obtained at T+0 is still held by the frame delivery loop.
Even though the session is removed from the registry at T+3, the frame delivery
callback already has a direct pointer to the session struct from before
destruction began. The `pane_tree.allPanes()` call at T+4 follows pointers into
freed pane slots.

**Concrete impact:** The daemon crashes with a use-after-free (segfault or
corrupted allocator metadata) when a session is destroyed while the frame
delivery timer is active. In debug builds, the Zig general-purpose allocator
detects the violation and panics with "use of freed memory." In release builds,
the behavior is undefined and may silently corrupt other sessions' pane data.

### How

The owner needs to decide how destruction and frame delivery coordinate. Options
include but are not limited to: adding a shutdown handshake where
`destroySession` first removes the session from `active_sessions` and waits for
the current delivery tick to complete before freeing pane slots, using
generation counters on pane slots so the frame delivery callback can detect
stale references, or restructuring so that `destroySession` only marks the
session as "pending destruction" and the frame delivery loop performs the actual
cleanup after it finishes the current tick.

---
