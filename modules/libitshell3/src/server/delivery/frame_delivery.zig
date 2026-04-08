//! Frame delivery (priority 2). Delivers pending frame data from per-pane
//! ring buffers to a client SocketConnection.

const std = @import("std");
const transport = @import("itshell3_transport");
const SocketConnection = transport.transport.SocketConnection;
const ring_buffer_mod = @import("ring_buffer.zig");
const RingBuffer = ring_buffer_mod.RingBuffer;
const RingCursor = ring_buffer_mod.RingCursor;
const core = @import("itshell3_core");
const PaneSlot = core.types.PaneSlot;
const MAX_PANES = core.types.MAX_PANES;
const server = @import("itshell3_server");
const SessionDeliveryState = server.delivery.pane_delivery.SessionDeliveryState;

/// Outcome of delivering frame data for a client.
pub const DeliveryResult = enum {
    fully_caught_up,
    would_block,
    peer_closed,
    write_error,
};

/// Delivers pending frame data for all panes in a session.
/// Call only after the control channel is flushed to maintain two-channel
/// priority.
pub fn deliverPendingFrames(
    conn: SocketConnection,
    delivery_state: *SessionDeliveryState,
    ring_cursors: *[MAX_PANES]?RingCursor,
) DeliveryResult {
    for (0..MAX_PANES) |slot_idx| {
        const slot: PaneSlot = @intCast(slot_idx);
        const ring = delivery_state.getRingBuffer(slot) orelse continue;
        const cursor = &(ring_cursors[slot] orelse continue);

        const result = deliverPaneFrames(conn, ring, cursor);
        switch (result) {
            .fully_caught_up => continue,
            .would_block => return .would_block,
            .peer_closed => return .peer_closed,
            .write_error => return .write_error,
        }
    }
    return .fully_caught_up;
}

/// Delivers pending frame data for a single pane until caught up or blocked.
fn deliverPaneFrames(
    conn: SocketConnection,
    ring: *const RingBuffer,
    cursor: *RingCursor,
) DeliveryResult {
    if (ring.isCursorOverwritten(cursor)) {
        ring.seekToLatestIFrame(cursor);
    }

    while (true) {
        const pending = ring.pendingIovecs(cursor) orelse return .fully_caught_up;

        switch (conn.sendv(pending.iov[0..pending.count])) {
            .bytes_written => |n| ring.advanceCursor(cursor, n),
            .would_block => return .would_block,
            .peer_closed => return .peer_closed,
            .err => return .write_error,
        }
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "deliverPendingFrames: no active panes returns fully_caught_up" {
    const pipe_fds = try std.posix.pipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);
    const conn = SocketConnection{ .fd = pipe_fds[1] };

    var delivery_state = SessionDeliveryState.init();
    defer delivery_state.deinit();
    var ring_cursors: [MAX_PANES]?RingCursor = [_]?RingCursor{null} ** MAX_PANES;

    const result = deliverPendingFrames(conn, &delivery_state, &ring_cursors);
    try std.testing.expectEqual(DeliveryResult.fully_caught_up, result);
}

test "deliverPendingFrames: single pane with data delivers and catches up" {
    const pipe_fds = try std.posix.pipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);
    const conn = SocketConnection{ .fd = pipe_fds[1] };

    var delivery_state = SessionDeliveryState.init();
    defer delivery_state.deinit();
    try delivery_state.initPaneRing(0);
    const ring = delivery_state.getRingBuffer(0).?;
    try ring.writeFrame("test-frame-data", false, 1);

    var ring_cursors: [MAX_PANES]?RingCursor = [_]?RingCursor{null} ** MAX_PANES;
    ring_cursors[0] = RingCursor.init();

    const result = deliverPendingFrames(conn, &delivery_state, &ring_cursors);
    try std.testing.expectEqual(DeliveryResult.fully_caught_up, result);

    // Verify data was written to the pipe.
    var read_buf: [256]u8 = undefined;
    const n = try std.posix.read(pipe_fds[0], &read_buf);
    try std.testing.expect(n > 0);
}

test "deliverPendingFrames: multiple panes deliver in slot order" {
    const pipe_fds = try std.posix.pipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);
    const conn = SocketConnection{ .fd = pipe_fds[1] };

    var delivery_state = SessionDeliveryState.init();
    defer delivery_state.deinit();
    try delivery_state.initPaneRing(0);
    try delivery_state.initPaneRing(2);
    try delivery_state.getRingBuffer(0).?.writeFrame("pane0", false, 1);
    try delivery_state.getRingBuffer(2).?.writeFrame("pane2", false, 2);

    var ring_cursors: [MAX_PANES]?RingCursor = [_]?RingCursor{null} ** MAX_PANES;
    ring_cursors[0] = RingCursor.init();
    ring_cursors[2] = RingCursor.init();

    const result = deliverPendingFrames(conn, &delivery_state, &ring_cursors);
    try std.testing.expectEqual(DeliveryResult.fully_caught_up, result);

    // Both cursors should be caught up.
    try std.testing.expectEqual(
        @as(usize, 0),
        delivery_state.getRingBuffer(0).?.available(&ring_cursors[0].?),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        delivery_state.getRingBuffer(2).?.available(&ring_cursors[2].?),
    );
}

test "deliverPendingFrames: peer_closed on broken pipe" {
    const pipe_fds = try std.posix.pipe();
    std.posix.close(pipe_fds[0]); // Close read end.
    defer std.posix.close(pipe_fds[1]);
    const conn = SocketConnection{ .fd = pipe_fds[1] };

    var delivery_state = SessionDeliveryState.init();
    defer delivery_state.deinit();
    try delivery_state.initPaneRing(0);
    try delivery_state.getRingBuffer(0).?.writeFrame("will-fail", false, 1);

    var ring_cursors: [MAX_PANES]?RingCursor = [_]?RingCursor{null} ** MAX_PANES;
    ring_cursors[0] = RingCursor.init();

    const result = deliverPendingFrames(conn, &delivery_state, &ring_cursors);
    try std.testing.expectEqual(DeliveryResult.peer_closed, result);
}

test "deliverPendingFrames: pane with ring but no cursor is skipped" {
    const pipe_fds = try std.posix.pipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);
    const conn = SocketConnection{ .fd = pipe_fds[1] };

    var delivery_state = SessionDeliveryState.init();
    defer delivery_state.deinit();
    try delivery_state.initPaneRing(0);
    try delivery_state.getRingBuffer(0).?.writeFrame("data", false, 1);

    // No cursor for slot 0 — should be skipped.
    var ring_cursors: [MAX_PANES]?RingCursor = [_]?RingCursor{null} ** MAX_PANES;

    const result = deliverPendingFrames(conn, &delivery_state, &ring_cursors);
    try std.testing.expectEqual(DeliveryResult.fully_caught_up, result);
}

test "deliverPendingFrames: empty ring returns fully_caught_up" {
    const pipe_fds = try std.posix.pipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);
    const conn = SocketConnection{ .fd = pipe_fds[1] };

    var delivery_state = SessionDeliveryState.init();
    defer delivery_state.deinit();
    try delivery_state.initPaneRing(0);

    var ring_cursors: [MAX_PANES]?RingCursor = [_]?RingCursor{null} ** MAX_PANES;
    ring_cursors[0] = RingCursor.init();

    // Ring allocated but no data written.
    const result = deliverPendingFrames(conn, &delivery_state, &ring_cursors);
    try std.testing.expectEqual(DeliveryResult.fully_caught_up, result);
}
