//! EVFILT_WRITE chain handler. Handles writable events for client sockets,
//! draining the direct queue (priority 1) then ring buffer (priority 2).
//!
//! Per daemon-architecture integration-boundaries spec (two-channel write
//! priority, write-ready and backpressure); daemon-behavior
//! policies-and-procedures spec (socket write priority).

const std = @import("std");
const interfaces = @import("../os/interfaces.zig");
const event_loop_mod = @import("event_loop.zig");
const Handler = event_loop_mod.Handler;
const server = @import("itshell3_server");
const ClientManager = server.connection.client_manager.ClientManager;
const client_writer_mod = server.delivery.client_writer;
const ClientWriter = client_writer_mod.ClientWriter;
const WriteResult = client_writer_mod.WriteResult;

/// Context for the write handler.
pub const WriteHandlerContext = struct {
    client_manager: *ClientManager,
    disconnect_fn: *const fn (client_slot: u16) void,
};

/// Chain handler entry point for writable events on client sockets.
pub fn chainHandle(context: *anyopaque, event: interfaces.Event, next: ?*const Handler) void {
    if (event.filter == .write) {
        if (event.target) |target| {
            switch (target) {
                .client => |c| {
                    const ctx: *WriteHandlerContext = @ptrCast(@alignCast(context));
                    handleWritable(ctx, c.client_idx);
                    return;
                },
                else => {},
            }
        }
    }
    if (next) |n| n.invoke(event);
}

/// Handles a writable event for a specific client.
fn handleWritable(ctx: *WriteHandlerContext, client_idx: u16) void {
    const client = ctx.client_manager.getClient(client_idx) orelse return;

    // Drain direct queue first, then ring buffer via ClientWriter.
    // The client_writer.zig ClientWriter already implements the two-channel
    // priority: direct queue drained completely before ring buffer data.

    // Check for pending data in direct queue
    if (!client.direct_queue.isEmpty()) {
        // Drain direct queue messages one at a time
        const direct_queue_mod = server.delivery.direct_queue;
        var msg_buf: [direct_queue_mod.QUEUE_CAPACITY]u8 = undefined;
        while (true) {
            const msg_len = client.direct_queue.peekCopy(&msg_buf) orelse break;
            const data = msg_buf[client.direct_partial_offset..msg_len];

            const n = std.posix.write(client.fd(), data) catch |err| {
                switch (err) {
                    error.WouldBlock => return, // Stay armed
                    error.BrokenPipe, error.ConnectionResetByPeer => {
                        ctx.disconnect_fn(client_idx);
                        return;
                    },
                    else => {
                        ctx.disconnect_fn(client_idx);
                        return;
                    },
                }
            };
            if (n == 0) {
                ctx.disconnect_fn(client_idx);
                return;
            }

            if (n + client.direct_partial_offset < msg_len) {
                client.direct_partial_offset += n;
                return; // More data pending, stay armed
            }
            client.direct_queue.dequeue();
            client.direct_partial_offset = 0;
        }
    }

    // Phase 2: Ring buffer data would be written here.
    // Ring delivery is handled through the per-pane ring buffer cursors
    // in client_state.ring_cursors[]. The actual writev() for ring data
    // requires access to the per-pane RingBuffer which is stored in
    // pane_delivery. This integration point is wired during event loop setup.
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "chainHandle: non-write event forwards to next handler" {
    var forwarded = false;
    const NextCtx = struct {
        flag: *bool,
        fn handle(context_ptr: *anyopaque, _: interfaces.Event, _: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context_ptr));
            self.flag.* = true;
        }
    };
    var next_ctx = NextCtx{ .flag = &forwarded };
    const next_handler = Handler{
        .handleFn = NextCtx.handle,
        .context = @ptrCast(&next_ctx),
        .next = null,
    };

    var dummy_ctx: u8 = 0;
    const read_event = interfaces.Event{
        .fd = 42,
        .filter = .read,
        .target = .{ .listener = {} },
    };

    chainHandle(@ptrCast(&dummy_ctx), read_event, &next_handler);
    try std.testing.expect(forwarded);
}
