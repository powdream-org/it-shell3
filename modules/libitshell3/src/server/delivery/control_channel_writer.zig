//! Control channel writer (priority 1). Flushes the direct queue to a
//! SocketConnection before frame delivery proceeds.

const std = @import("std");
const transport = @import("itshell3_transport");
const SocketConnection = transport.transport.SocketConnection;
const direct_queue_mod = @import("direct_queue.zig");
const DirectQueue = direct_queue_mod.DirectQueue;

/// Outcome of flushing the direct queue to the connection.
pub const FlushResult = enum {
    flushed,
    would_block,
    peer_closed,
    write_error,
};

pub const ControlChannelWriter = struct {
    direct_queue: DirectQueue,
    /// Partial send state for direct queue messages.
    direct_partial_offset: usize,

    pub fn init() ControlChannelWriter {
        return .{
            .direct_queue = DirectQueue.init(),
            .direct_partial_offset = 0,
        };
    }

    pub fn deinit(self: *ControlChannelWriter) void {
        self.direct_queue.deinit();
    }

    /// Whether the direct queue has pending messages.
    pub fn hasPending(self: *const ControlChannelWriter) bool {
        return !self.direct_queue.isEmpty();
    }

    /// Enqueues a control message into the direct queue for priority delivery.
    pub fn enqueue(self: *ControlChannelWriter, data: []const u8) !void {
        try self.direct_queue.enqueue(data);
    }

    /// Flushes the direct queue to the connection. Must be called before
    /// frame delivery to maintain two-channel priority.
    pub fn flush(self: *ControlChannelWriter, conn: SocketConnection) FlushResult {
        if (self.direct_queue.isEmpty()) return .flushed;

        var msg_buf: [direct_queue_mod.QUEUE_CAPACITY]u8 = undefined;
        while (true) {
            const msg_len = self.direct_queue.peekCopy(&msg_buf) orelse break;
            const data = msg_buf[self.direct_partial_offset..msg_len];

            switch (conn.send(data)) {
                .bytes_written => |n| {
                    if (n + self.direct_partial_offset < msg_len) {
                        self.direct_partial_offset += n;
                        return .would_block;
                    }
                    self.direct_queue.dequeue();
                    self.direct_partial_offset = 0;
                },
                .would_block => return .would_block,
                .peer_closed => return .peer_closed,
                .err => return .write_error,
            }
        }
        return .flushed;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

test "ControlChannelWriter.init: clean state" {
    const cw = ControlChannelWriter.init();
    try std.testing.expect(cw.direct_queue.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), cw.direct_partial_offset);
}

test "ControlChannelWriter.enqueue: adds to direct queue" {
    var cw = ControlChannelWriter.init();
    defer cw.deinit();
    try cw.enqueue("control-msg");
    try std.testing.expect(!cw.direct_queue.isEmpty());
}

test "ControlChannelWriter.hasPending: false when empty" {
    const cw = ControlChannelWriter.init();
    try std.testing.expect(!cw.hasPending());
}

test "ControlChannelWriter.hasPending: true with enqueued data" {
    var cw = ControlChannelWriter.init();
    defer cw.deinit();
    try cw.enqueue("msg");
    try std.testing.expect(cw.hasPending());
}

test "ControlChannelWriter.enqueue: error propagation from QueueFull" {
    var cw = ControlChannelWriter.init();
    defer cw.deinit();
    const big = [_]u8{'A'} ** (direct_queue_mod.QUEUE_CAPACITY - 8);
    try cw.enqueue(&big);
    try std.testing.expectError(error.QueueFull, cw.enqueue("overflow"));
}
