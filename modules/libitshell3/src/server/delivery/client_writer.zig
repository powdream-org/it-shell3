//! Per-client two-channel writer. Drains the direct queue (priority 1) before
//! delivering ring buffer frames (priority 2) via zero-copy writev().

const std = @import("std");
const direct_queue_mod = @import("direct_queue.zig");
const ring_buffer_mod = @import("ring_buffer.zig");
const DirectQueue = direct_queue_mod.DirectQueue;
const RingBuffer = ring_buffer_mod.RingBuffer;
const RingCursor = ring_buffer_mod.RingCursor;

/// Outcome of a writePending call, per daemon-behavior policies spec
/// three-branch model.
pub const WriteResult = enum {
    fully_caught_up,
    more_pending,
    would_block,
    peer_closed,
    write_error,
};

pub const ClientWriter = struct {
    direct_queue: DirectQueue,
    ring_cursor: RingCursor,
    /// Partial send state for direct queue messages.
    direct_partial_offset: usize,

    pub fn init() ClientWriter {
        return .{
            .direct_queue = DirectQueue.init(),
            .ring_cursor = RingCursor.init(),
            .direct_partial_offset = 0,
        };
    }

    pub fn deinit(self: *ClientWriter) void {
        self.direct_queue.deinit();
    }

    pub fn enqueueDirect(self: *ClientWriter, data: []const u8) !void {
        try self.direct_queue.enqueue(data);
    }

    pub fn hasPending(self: *const ClientWriter, ring: *const RingBuffer) bool {
        return !self.direct_queue.isEmpty() or ring.available(&self.ring_cursor) > 0;
    }

    /// Writes pending data to `fd`. Drains direct queue first, then ring buffer.
    pub fn writePending(
        self: *ClientWriter,
        fd: std.posix.socket_t,
        ring: *const RingBuffer,
    ) WriteResult {
        // Phase 1: Drain direct queue (priority 1).
        if (!self.direct_queue.isEmpty()) {
            var msg_buf: [direct_queue_mod.QUEUE_CAPACITY]u8 = undefined;
            while (true) {
                const msg_len = self.direct_queue.peekCopy(&msg_buf) orelse break;
                const data = msg_buf[self.direct_partial_offset..msg_len];

                const n = std.posix.write(fd, data) catch |err| return writeErrorToResult(err);
                if (n == 0) return .peer_closed;

                if (n + self.direct_partial_offset < msg_len) {
                    self.direct_partial_offset += n;
                    return .more_pending;
                }
                self.direct_queue.dequeue();
                self.direct_partial_offset = 0;
            }
        }

        // Phase 2: Zero-copy ring buffer delivery (priority 2).
        if (ring.isCursorOverwritten(&self.ring_cursor)) {
            ring.seekToLatestIFrame(&self.ring_cursor);
        }

        const pending = ring.pendingIovecs(&self.ring_cursor) orelse {
            return .fully_caught_up;
        };

        const n = std.posix.writev(fd, pending.iov[0..pending.count]) catch |err| return writeErrorToResult(err);

        if (n == 0) return .peer_closed;

        ring.advanceCursor(&self.ring_cursor, n);

        if (ring.available(&self.ring_cursor) == 0 and self.direct_queue.isEmpty()) {
            return .fully_caught_up;
        }
        return .more_pending;
    }

    fn writeErrorToResult(err: anyerror) WriteResult {
        return switch (err) {
            error.WouldBlock => .would_block,
            error.BrokenPipe, error.ConnectionResetByPeer => .peer_closed,
            else => .write_error,
        };
    }
};

// --- Tests ---

test "ClientWriter.init: clean state" {
    const cw = ClientWriter.init();
    try std.testing.expect(cw.direct_queue.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), cw.direct_partial_offset);
    try std.testing.expectEqual(@as(usize, 0), cw.ring_cursor.position);
}

test "ClientWriter.enqueueDirect: adds to direct queue" {
    var cw = ClientWriter.init();
    defer cw.deinit();
    try cw.enqueueDirect("control-msg");
    try std.testing.expect(!cw.direct_queue.isEmpty());
}

test "ClientWriter.hasPending: false when all channels empty" {
    var cw = ClientWriter.init();
    var backing: [1024]u8 = @splat(0);
    const ring = RingBuffer.init(&backing);
    try std.testing.expect(!cw.hasPending(&ring));
}

test "ClientWriter.hasPending: true with direct queue" {
    var cw = ClientWriter.init();
    defer cw.deinit();
    var backing: [1024]u8 = @splat(0);
    const ring = RingBuffer.init(&backing);
    try cw.enqueueDirect("msg");
    try std.testing.expect(cw.hasPending(&ring));
}

test "ClientWriter.hasPending: true with ring data" {
    var cw = ClientWriter.init();
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    try ring.writeFrame("frame", false, 1);
    try std.testing.expect(cw.hasPending(&ring));
}

test "ClientWriter.hasPending: false when ring cursor caught up" {
    var cw = ClientWriter.init();
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    try ring.writeFrame("frame", false, 1);
    const n = ring.available(&cw.ring_cursor);
    ring.advanceCursor(&cw.ring_cursor, n);
    try std.testing.expect(!cw.hasPending(&ring));
}

test "ClientWriter.hasPending: reflects both channels independently" {
    var cw = ClientWriter.init();
    defer cw.deinit();
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    // Direct only
    try cw.enqueueDirect("msg");
    try std.testing.expect(cw.hasPending(&ring));
    cw.direct_queue.dequeue();
    try std.testing.expect(!cw.hasPending(&ring));

    // Ring only
    try ring.writeFrame("frame", false, 1);
    try std.testing.expect(cw.hasPending(&ring));
    ring.advanceCursor(&cw.ring_cursor, ring.available(&cw.ring_cursor));
    try std.testing.expect(!cw.hasPending(&ring));
}

test "ClientWriter.enqueueDirect: error propagation from QueueFull" {
    var cw = ClientWriter.init();
    defer cw.deinit();
    const big = [_]u8{'A'} ** (direct_queue_mod.QUEUE_CAPACITY - 8);
    try cw.enqueueDirect(&big);
    try std.testing.expectError(error.QueueFull, cw.enqueueDirect("overflow"));
}

test "ClientWriter.init: ring_cursor starts at zero" {
    const cw = ClientWriter.init();
    try std.testing.expectEqual(@as(usize, 0), cw.ring_cursor.position);
}

test "WriteResult: enum has three-branch variants" {
    // Verify all three daemon-behavior policies spec outcomes + write_error are present
    _ = WriteResult.fully_caught_up;
    _ = WriteResult.more_pending;
    _ = WriteResult.would_block;
    _ = WriteResult.peer_closed;
    _ = WriteResult.write_error;
}
