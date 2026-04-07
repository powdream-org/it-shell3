//! EVFILT_WRITE chain handler. Handles writable events for client sockets,
//! delegating two-channel write (direct queue priority 1, ring buffer
//! priority 2) to ControlChannelWriter.
//!
//! Per daemon-architecture integration-boundaries spec (two-channel write
//! priority, write-ready and backpressure); daemon-behavior
//! policies-and-procedures spec (socket write priority).

const std = @import("std");
const interfaces = @import("../os/interfaces.zig");
const event_loop_mod = @import("event_loop.zig");
const Handler = event_loop_mod.Handler;
const server = @import("itshell3_server");
const core = @import("itshell3_core");
const ClientManager = server.connection.client_manager.ClientManager;
const frame_delivery = server.delivery.frame_delivery;
const ring_buffer_mod = server.delivery.ring_buffer;

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

/// Handles a writable event for a specific client. Drains direct queue
/// first, then delivers ring buffer data per pane.
fn handleWritable(ctx: *WriteHandlerContext, client_idx: u16) void {
    const client = ctx.client_manager.getClient(client_idx) orelse return;
    const conn = client.connection.socket;

    // Phase 1: Drain direct queue (priority 1).
    switch (client.control_channel.flush(conn)) {
        .flushed => {},
        .would_block => return,
        .peer_closed, .write_error => {
            ctx.disconnect_fn(client_idx);
            return;
        },
    }

    // Phase 2: Frame delivery (priority 2).
    const session_entry = client.attached_session orelse return;
    const delivery_state = session_entry.delivery_state orelse return;

    switch (frame_delivery.deliverPendingFrames(conn, delivery_state, &client.ring_cursors)) {
        .fully_caught_up => {},
        .would_block => return,
        .peer_closed, .write_error => {
            ctx.disconnect_fn(client_idx);
            return;
        },
    }
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

test "chainHandle: write event with non-client target forwards to next handler" {
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
    const write_event = interfaces.Event{
        .fd = 42,
        .filter = .write,
        .target = .{ .pty = .{ .session_idx = 0, .pane_slot = 0 } },
    };

    chainHandle(@ptrCast(&dummy_ctx), write_event, &next_handler);
    try std.testing.expect(forwarded);
}

test "chainHandle: write event with null target forwards to next handler" {
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
    const write_event = interfaces.Event{
        .fd = 42,
        .filter = .write,
        .target = null,
    };

    chainHandle(@ptrCast(&dummy_ctx), write_event, &next_handler);
    try std.testing.expect(forwarded);
}

test "chainHandle: write event with null next and non-client target does not crash" {
    var dummy_ctx: u8 = 0;
    const write_event = interfaces.Event{
        .fd = 42,
        .filter = .write,
        .target = .{ .pty = .{ .session_idx = 0, .pane_slot = 0 } },
    };
    chainHandle(@ptrCast(&dummy_ctx), write_event, null);
}

test "handleWritable: invalid client_idx returns early without crash" {
    const helpers = @import("itshell3_testing").helpers;
    var disconnect_called = false;
    const S = struct {
        var flag: *bool = undefined;
        fn disconnect(_: u16) void {
            flag.* = true;
        }
    };
    S.flag = &disconnect_called;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    var ctx = WriteHandlerContext{
        .client_manager = &client_manager,
        .disconnect_fn = S.disconnect,
    };

    const write_event = interfaces.Event{
        .fd = 42,
        .filter = .write,
        .target = .{ .client = .{ .client_idx = 99 } }, // Invalid slot
    };

    chainHandle(@ptrCast(&ctx), write_event, null);
    // Should not crash and should not call disconnect
    try std.testing.expect(!disconnect_called);
}

test "handleWritable: empty direct queue and no attached session returns early" {
    const helpers = @import("itshell3_testing").helpers;
    var disconnect_called = false;
    const S = struct {
        var flag: *bool = undefined;
        fn disconnect(_: u16) void {
            flag.* = true;
        }
    };
    S.flag = &disconnect_called;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = 42 });

    var ctx = WriteHandlerContext{
        .client_manager = &client_manager,
        .disconnect_fn = S.disconnect,
    };

    const write_event = interfaces.Event{
        .fd = 42,
        .filter = .write,
        .target = .{ .client = .{ .client_idx = slot } },
    };

    chainHandle(@ptrCast(&ctx), write_event, null);
    // Empty queue, no session — should return early without disconnect.
    try std.testing.expect(!disconnect_called);
    client_manager.getClient(slot).?.deinit();
}

test "handleWritable: drains direct queue through pipe fd" {
    const helpers = @import("itshell3_testing").helpers;
    const pipe_fds = try helpers.createPipe();
    defer std.posix.close(pipe_fds[0]); // read end
    defer std.posix.close(pipe_fds[1]); // write end

    var disconnect_called = false;
    const S = struct {
        var flag: *bool = undefined;
        fn disconnect(_: u16) void {
            flag.* = true;
        }
    };
    S.flag = &disconnect_called;

    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    // Use the write end of the pipe as the client fd.
    const slot = try client_manager.addClient(.{ .fd = pipe_fds[1] });
    const client = client_manager.getClient(slot).?;

    // Enqueue a message into the direct queue.
    try client.enqueueDirect("hello-direct");
    try std.testing.expect(!client.control_channel.direct_queue.isEmpty());

    var ctx = WriteHandlerContext{
        .client_manager = &client_manager,
        .disconnect_fn = S.disconnect,
    };

    const write_event = interfaces.Event{
        .fd = pipe_fds[1],
        .filter = .write,
        .target = .{ .client = .{ .client_idx = slot } },
    };

    chainHandle(@ptrCast(&ctx), write_event, null);

    // Direct queue should be drained.
    try std.testing.expect(client.control_channel.direct_queue.isEmpty());
    try std.testing.expect(!disconnect_called);

    // Read the data from the pipe read end to verify it was written.
    var read_buf: [256]u8 = undefined;
    const n = try std.posix.read(pipe_fds[0], &read_buf);
    try std.testing.expect(n > 0);
    // The written data should contain "hello-direct".
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "hello-direct") != null);
    client.deinit();
}

test "handleWritable: write returns 0 triggers disconnect" {
    const helpers = @import("itshell3_testing").helpers;
    // Create a pipe and immediately close the read end — writes to the write
    // end will get EPIPE / BrokenPipe, which triggers disconnect.
    const pipe_fds = try helpers.createPipe();
    std.posix.close(pipe_fds[0]); // close read end
    defer std.posix.close(pipe_fds[1]);

    var disconnected_slot: ?u16 = null;
    const S = struct {
        var slot_ptr: *?u16 = undefined;
        fn disconnect(client_slot: u16) void {
            slot_ptr.* = client_slot;
        }
    };
    S.slot_ptr = &disconnected_slot;

    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = pipe_fds[1] });
    const client = client_manager.getClient(slot).?;

    try client.enqueueDirect("will-fail");

    var ctx = WriteHandlerContext{
        .client_manager = &client_manager,
        .disconnect_fn = S.disconnect,
    };

    const write_event = interfaces.Event{
        .fd = pipe_fds[1],
        .filter = .write,
        .target = .{ .client = .{ .client_idx = slot } },
    };

    chainHandle(@ptrCast(&ctx), write_event, null);

    // BrokenPipe should trigger disconnect.
    try std.testing.expect(disconnected_slot != null);
    try std.testing.expectEqual(slot, disconnected_slot.?);
    client.deinit();
}

test "handleWritable: multiple direct queue messages drained in order" {
    const helpers = @import("itshell3_testing").helpers;
    const pipe_fds = try helpers.createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    var disconnect_called = false;
    const S = struct {
        var flag: *bool = undefined;
        fn disconnect(_: u16) void {
            flag.* = true;
        }
    };
    S.flag = &disconnect_called;

    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = pipe_fds[1] });
    const client = client_manager.getClient(slot).?;

    try client.enqueueDirect("msg1");
    try client.enqueueDirect("msg2");
    try client.enqueueDirect("msg3");

    var ctx = WriteHandlerContext{
        .client_manager = &client_manager,
        .disconnect_fn = S.disconnect,
    };

    const write_event = interfaces.Event{
        .fd = pipe_fds[1],
        .filter = .write,
        .target = .{ .client = .{ .client_idx = slot } },
    };

    chainHandle(@ptrCast(&ctx), write_event, null);

    try std.testing.expect(client.control_channel.direct_queue.isEmpty());
    try std.testing.expect(!disconnect_called);

    // Read all data from the pipe.
    var read_buf: [1024]u8 = undefined;
    const n = try std.posix.read(pipe_fds[0], &read_buf);
    const output = read_buf[0..n];
    // All messages should appear in the output.
    try std.testing.expect(std.mem.indexOf(u8, output, "msg1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "msg2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "msg3") != null);
    client.deinit();
}

test "handleWritable: with attached session and ring buffer delivers ring data" {
    const helpers = @import("itshell3_testing").helpers;
    const pipe_fds = try helpers.createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    var disconnected_slot: ?u16 = null;
    const S = struct {
        var slot_ptr: *?u16 = undefined;
        fn disconnect(client_slot: u16) void {
            slot_ptr.* = client_slot;
        }
    };
    S.slot_ptr = &disconnected_slot;

    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = pipe_fds[1] });
    const client = client_manager.getClient(slot).?;

    // Create a SessionDeliveryState with a ring buffer on slot 0.
    const pane_delivery = server.delivery.pane_delivery;
    var delivery_state = pane_delivery.SessionDeliveryState.init();
    try delivery_state.initPaneRing(0);
    defer delivery_state.deinit();

    // Write frame data to the ring.
    const ring = delivery_state.getRingBuffer(0).?;
    try ring.writeFrame("ring-frame", false, 1);

    // Create session entry and attach delivery state.
    const session_mod = core.session;
    const s = session_mod.Session.init(1, "test", 0, helpers.testImeEngine(), 0);
    var entry = server.state.session_entry.SessionEntry.init(s);
    entry.delivery_state = &delivery_state;

    // Attach session to client and initialize ring cursor for slot 0.
    client.attached_session = &entry;
    client.ring_cursors[0] = ring_buffer_mod.RingCursor.init();

    var ctx = WriteHandlerContext{
        .client_manager = &client_manager,
        .disconnect_fn = S.disconnect,
    };

    const write_event = interfaces.Event{
        .fd = pipe_fds[1],
        .filter = .write,
        .target = .{ .client = .{ .client_idx = slot } },
    };

    chainHandle(@ptrCast(&ctx), write_event, null);

    // Ring data should have been delivered.
    try std.testing.expect(disconnected_slot == null);

    var read_buf: [256]u8 = undefined;
    const n = try std.posix.read(pipe_fds[0], &read_buf);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "ring-frame") != null);
    client.deinit();
}

test "handleWritable: ring peer_closed triggers disconnect" {
    const helpers = @import("itshell3_testing").helpers;
    const pipe_fds = try helpers.createPipe();
    std.posix.close(pipe_fds[0]); // close read end to trigger BrokenPipe
    defer std.posix.close(pipe_fds[1]);

    var disconnected_slot: ?u16 = null;
    const S = struct {
        var slot_ptr: *?u16 = undefined;
        fn disconnect(client_slot: u16) void {
            slot_ptr.* = client_slot;
        }
    };
    S.slot_ptr = &disconnected_slot;

    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = pipe_fds[1] });
    const client = client_manager.getClient(slot).?;

    // Create delivery state with ring data.
    const pane_delivery = server.delivery.pane_delivery;
    var delivery_state = pane_delivery.SessionDeliveryState.init();
    try delivery_state.initPaneRing(0);
    defer delivery_state.deinit();

    const ring = delivery_state.getRingBuffer(0).?;
    try ring.writeFrame("will-fail", false, 1);

    const session_mod = core.session;
    const s = session_mod.Session.init(1, "test", 0, helpers.testImeEngine(), 0);
    var entry = server.state.session_entry.SessionEntry.init(s);
    entry.delivery_state = &delivery_state;

    client.attached_session = &entry;
    client.ring_cursors[0] = ring_buffer_mod.RingCursor.init();

    var ctx = WriteHandlerContext{
        .client_manager = &client_manager,
        .disconnect_fn = S.disconnect,
    };

    const write_event = interfaces.Event{
        .fd = pipe_fds[1],
        .filter = .write,
        .target = .{ .client = .{ .client_idx = slot } },
    };

    chainHandle(@ptrCast(&ctx), write_event, null);

    // BrokenPipe should trigger disconnect.
    try std.testing.expect(disconnected_slot != null);
    try std.testing.expectEqual(slot, disconnected_slot.?);
    client.deinit();
}

test "handleWritable: direct queue drained before ring delivery" {
    const helpers = @import("itshell3_testing").helpers;
    const pipe_fds = try helpers.createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    var disconnect_called = false;
    const S = struct {
        var flag: *bool = undefined;
        fn disconnect(_: u16) void {
            flag.* = true;
        }
    };
    S.flag = &disconnect_called;

    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = pipe_fds[1] });
    const client = client_manager.getClient(slot).?;

    // Set up delivery state with ring data.
    const pane_delivery = server.delivery.pane_delivery;
    var delivery_state = pane_delivery.SessionDeliveryState.init();
    try delivery_state.initPaneRing(0);
    defer delivery_state.deinit();

    const ring = delivery_state.getRingBuffer(0).?;
    try ring.writeFrame("ring-data", false, 1);

    const session_mod = core.session;
    const s = session_mod.Session.init(1, "test", 0, helpers.testImeEngine(), 0);
    var entry = server.state.session_entry.SessionEntry.init(s);
    entry.delivery_state = &delivery_state;

    client.attached_session = &entry;
    client.ring_cursors[0] = ring_buffer_mod.RingCursor.init();

    // Also enqueue direct message.
    try client.enqueueDirect("direct-first");

    var ctx = WriteHandlerContext{
        .client_manager = &client_manager,
        .disconnect_fn = S.disconnect,
    };

    const write_event = interfaces.Event{
        .fd = pipe_fds[1],
        .filter = .write,
        .target = .{ .client = .{ .client_idx = slot } },
    };

    chainHandle(@ptrCast(&ctx), write_event, null);

    try std.testing.expect(client.control_channel.direct_queue.isEmpty());
    try std.testing.expect(!disconnect_called);

    // Read all output: direct message should come before ring data.
    var read_buf: [512]u8 = undefined;
    var total: usize = 0;
    while (total < "direct-first".len + "ring-data".len) {
        const n = std.posix.read(pipe_fds[0], read_buf[total..]) catch break;
        if (n == 0) break;
        total += n;
    }
    const output = read_buf[0..total];
    const direct_pos = std.mem.indexOf(u8, output, "direct-first");
    const ring_pos = std.mem.indexOf(u8, output, "ring-data");
    try std.testing.expect(direct_pos != null);
    try std.testing.expect(ring_pos != null);
    try std.testing.expect(direct_pos.? < ring_pos.?);
    client.deinit();
}

test "handleWritable: no-session direct queue drain peer_closed disconnects" {
    const helpers = @import("itshell3_testing").helpers;
    const pipe_fds = try helpers.createPipe();
    std.posix.close(pipe_fds[0]); // close read end
    defer std.posix.close(pipe_fds[1]);

    var disconnected_slot: ?u16 = null;
    const S = struct {
        var slot_ptr: *?u16 = undefined;
        fn disconnect(client_slot: u16) void {
            slot_ptr.* = client_slot;
        }
    };
    S.slot_ptr = &disconnected_slot;

    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = pipe_fds[1] });
    const client = client_manager.getClient(slot).?;

    // No attached session, but has direct queue data.
    try client.enqueueDirect("no-session-fail");

    var ctx = WriteHandlerContext{
        .client_manager = &client_manager,
        .disconnect_fn = S.disconnect,
    };

    const write_event = interfaces.Event{
        .fd = pipe_fds[1],
        .filter = .write,
        .target = .{ .client = .{ .client_idx = slot } },
    };

    chainHandle(@ptrCast(&ctx), write_event, null);

    // Should disconnect because pipe is broken.
    try std.testing.expect(disconnected_slot != null);
    try std.testing.expectEqual(slot, disconnected_slot.?);
    client.deinit();
}

test "handleWritable: fully_caught_up on no-session direct drain returns early" {
    const helpers = @import("itshell3_testing").helpers;
    const pipe_fds = try helpers.createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    var disconnect_called = false;
    const S = struct {
        var flag: *bool = undefined;
        fn disconnect(_: u16) void {
            flag.* = true;
        }
    };
    S.flag = &disconnect_called;

    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = pipe_fds[1] });
    const client = client_manager.getClient(slot).?;

    // No attached session, but has direct queue data that will succeed.
    try client.enqueueDirect("success-msg");

    var ctx = WriteHandlerContext{
        .client_manager = &client_manager,
        .disconnect_fn = S.disconnect,
    };

    const write_event = interfaces.Event{
        .fd = pipe_fds[1],
        .filter = .write,
        .target = .{ .client = .{ .client_idx = slot } },
    };

    chainHandle(@ptrCast(&ctx), write_event, null);

    // Direct queue should be drained successfully.
    try std.testing.expect(client.control_channel.direct_queue.isEmpty());
    try std.testing.expect(!disconnect_called);

    // Verify data.
    var read_buf: [256]u8 = undefined;
    const n = try std.posix.read(pipe_fds[0], &read_buf);
    try std.testing.expect(std.mem.indexOf(u8, read_buf[0..n], "success-msg") != null);
    client.deinit();
}
