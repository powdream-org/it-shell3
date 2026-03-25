const std = @import("std");
const direct_queue_mod = @import("direct_queue.zig");
const ring_buffer_mod = @import("ring_buffer.zig");
const frame_serializer_mod = @import("frame_serializer.zig");
const DirectQueue = direct_queue_mod.DirectQueue;
const RingBuffer = ring_buffer_mod.RingBuffer;
const RingCursor = ring_buffer_mod.RingCursor;

pub const WriteResult = enum {
    fully_caught_up,
    more_pending,
    would_block,
    peer_closed,
    write_error,
};

/// Per-client two-channel writer: drains direct (priority 1) queue first,
/// then delivers ring buffer frames (priority 2).
///
/// **Partial frame handling**: When a ring frame write is partial, the cursor
/// is NOT advanced. Instead, `ring_frame_sent` tracks how many bytes of the
/// current frame have been sent. The frame is re-peeked (re-read from the
/// ring) on the next write attempt, starting from `ring_frame_sent`. This
/// avoids buffering a full frame copy (up to MAX_FRAME_SIZE bytes) per client.
pub const ClientWriter = struct {
    direct_queue: DirectQueue,
    ring_cursor: RingCursor,
    /// Partial send state for direct queue messages.
    direct_partial_offset: usize,
    /// How many bytes of the current ring frame have already been sent.
    /// Non-zero means a partial ring frame is in progress.
    /// Cursor is NOT advanced until the full frame is sent.
    ring_frame_sent: usize,

    pub fn init() ClientWriter {
        return .{
            .direct_queue = DirectQueue.init(),
            .ring_cursor = RingCursor.init(),
            .direct_partial_offset = 0,
            .ring_frame_sent = 0,
        };
    }

    pub fn deinit(self: *ClientWriter) void {
        self.direct_queue.deinit();
    }

    pub fn enqueueDirect(self: *ClientWriter, data: []const u8) !void {
        try self.direct_queue.enqueue(data);
    }

    pub fn hasPending(self: *const ClientWriter, ring: *const RingBuffer) bool {
        if (self.ring_frame_sent > 0) return true;
        return !self.direct_queue.isEmpty() or ring.available(&self.ring_cursor) > 0;
    }

    /// Attempt to write pending data to socket.
    /// Priority: direct queue (priority 1) → ring buffer (priority 2).
    ///
    pub fn writePending(
        self: *ClientWriter,
        fd: std.posix.socket_t,
        ring: *const RingBuffer,
    ) WriteResult {
        // Phase 1: Drain direct queue (priority 1)
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

        // Phase 2: Deliver ring buffer frames
        if (ring.isCursorOverwritten(&self.ring_cursor)) {
            ring.seekToLatestIFrame(&self.ring_cursor);
            self.ring_frame_sent = 0;
        }

        var frame_buf: [frame_serializer_mod.SCRATCH_SIZE]u8 = undefined;

        while (ring.available(&self.ring_cursor) > 0 or self.ring_frame_sent > 0) {
            const frame_len = ring.peekFrame(&self.ring_cursor, &frame_buf) orelse break;

            const remaining = frame_buf[self.ring_frame_sent..frame_len];
            if (remaining.len == 0) {
                ring.advancePastFrame(&self.ring_cursor, frame_len);
                self.ring_frame_sent = 0;
                continue;
            }

            const n = std.posix.write(fd, remaining) catch |err| return writeErrorToResult(err);
            if (n == 0) return .peer_closed;

            if (n < remaining.len) {
                self.ring_frame_sent += n;
                return .more_pending;
            }

            ring.advancePastFrame(&self.ring_cursor, frame_len);
            self.ring_frame_sent = 0;
        }

        if (self.hasPending(ring)) return .more_pending;
        return .fully_caught_up;
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

test "init: clean state" {
    const cw = ClientWriter.init();
    try std.testing.expect(cw.direct_queue.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), cw.ring_frame_sent);
    try std.testing.expectEqual(@as(usize, 0), cw.direct_partial_offset);
}

test "enqueueDirect adds to direct queue" {
    var cw = ClientWriter.init();
    defer cw.deinit();
    try cw.enqueueDirect("control-msg");
    try std.testing.expect(!cw.direct_queue.isEmpty());
}

test "hasPending: false when all channels empty" {
    var cw = ClientWriter.init();
    var backing: [1024]u8 = @splat(0);
    const ring = RingBuffer.init(&backing);
    try std.testing.expect(!cw.hasPending(&ring));
}

test "hasPending: true with direct queue" {
    var cw = ClientWriter.init();
    defer cw.deinit();
    var backing: [1024]u8 = @splat(0);
    const ring = RingBuffer.init(&backing);
    try cw.enqueueDirect("msg");
    try std.testing.expect(cw.hasPending(&ring));
}

test "hasPending: true with ring data" {
    var cw = ClientWriter.init();
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    try ring.writeFrame("frame", false, 1);
    try std.testing.expect(cw.hasPending(&ring));
}

test "hasPending: true with partial ring frame in progress" {
    var cw = ClientWriter.init();
    var backing: [1024]u8 = @splat(0);
    const ring = RingBuffer.init(&backing);
    // Simulate partial frame state
    cw.ring_frame_sent = 5;
    try std.testing.expect(cw.hasPending(&ring));
}

test "hasPending: false with ring data but cursor caught up" {
    var cw = ClientWriter.init();
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    try ring.writeFrame("frame", false, 1);
    var out: [256]u8 = undefined;
    const n = ring.peekFrame(&cw.ring_cursor, &out).?;
    ring.advancePastFrame(&cw.ring_cursor, n);
    try std.testing.expect(!cw.hasPending(&ring));
}

test "enqueueDirect error propagation from QueueFull" {
    var cw = ClientWriter.init();
    defer cw.deinit();
    // Fill up to near capacity
    const big = [_]u8{'A'} ** (direct_queue_mod.QUEUE_CAPACITY - 8);
    try cw.enqueueDirect(&big);
    try std.testing.expectError(error.QueueFull, cw.enqueueDirect("overflow"));
}

test "ring_cursor starts at zero" {
    const cw = ClientWriter.init();
    try std.testing.expectEqual(@as(usize, 0), cw.ring_cursor.total_read);
}
