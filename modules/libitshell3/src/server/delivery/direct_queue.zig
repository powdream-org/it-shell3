//! FIFO byte-buffer queue for direct (priority 1) control messages.
//! Lazily heap-allocated to avoid inlining 32 KB per client slot on the stack.

const std = @import("std");

/// Total byte budget per client for queued control messages.
/// 32 KB handles typical bursts of LayoutChanged, PreeditSync, etc.
pub const QUEUE_CAPACITY: usize = 32 * 1024;

/// Messages are stored contiguously as [4-byte LE length][data] in a
/// circular buffer.
pub const DirectQueue = struct {
    /// Heap-allocated backing buffer (null until first enqueue).
    buf_storage: ?[]u8,
    read_pos: usize,
    write_pos: usize,
    count: usize,

    pub fn init() DirectQueue {
        return .{
            .buf_storage = null,
            .read_pos = 0,
            .write_pos = 0,
            .count = 0,
        };
    }

    pub fn deinit(self: *DirectQueue) void {
        if (self.buf_storage) |buf| {
            std.heap.page_allocator.free(buf);
            self.buf_storage = null;
        }
    }

    /// Enqueue a pre-serialized message.
    pub fn enqueue(self: *DirectQueue, data: []const u8) error{ QueueFull, OutOfMemory }!void {
        if (self.buf_storage == null) {
            const buf = try std.heap.page_allocator.alloc(u8, QUEUE_CAPACITY);
            self.buf_storage = buf;
        }

        const entry_len = 4 + data.len;
        if (self.usedBytes() + entry_len > QUEUE_CAPACITY) return error.QueueFull;

        var len_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &len_buf, @intCast(data.len), .little);
        self.writeBytesInternal(&len_buf);
        self.writeBytesInternal(data);
        self.count += 1;
    }

    /// Peek at the front message data without removing it.
    /// Returns the message bytes as a direct slice only when the message
    /// does not wrap around. For wrapped messages, use peekCopy().
    pub fn peek(self: *const DirectQueue) ?[]const u8 {
        if (self.count == 0) return null;
        const buf = self.buf_storage orelse return null;

        var len_buf: [4]u8 = undefined;
        readBytesAtBuf(buf, self.read_pos, &len_buf);
        const msg_len = std.mem.readInt(u32, &len_buf, .little);
        const data_start = (self.read_pos + 4) % QUEUE_CAPACITY;

        if (data_start + msg_len <= QUEUE_CAPACITY) {
            return buf[data_start..][0..msg_len];
        }
        return null;
    }

    /// Copy front message data into caller buffer. Always works (handles wrap).
    pub fn peekCopy(self: *const DirectQueue, out: []u8) ?usize {
        if (self.count == 0) return null;
        const buf = self.buf_storage orelse return null;

        var len_buf: [4]u8 = undefined;
        readBytesAtBuf(buf, self.read_pos, &len_buf);
        const msg_len = std.mem.readInt(u32, &len_buf, .little);
        if (msg_len > out.len) return null;

        const data_start = (self.read_pos + 4) % QUEUE_CAPACITY;
        readBytesAtBuf(buf, data_start, out[0..msg_len]);
        return msg_len;
    }

    /// Remove the front message.
    pub fn dequeue(self: *DirectQueue) void {
        if (self.count == 0) return;
        const buf = self.buf_storage orelse return;

        var len_buf: [4]u8 = undefined;
        readBytesAtBuf(buf, self.read_pos, &len_buf);
        const msg_len = std.mem.readInt(u32, &len_buf, .little);
        self.read_pos = (self.read_pos + 4 + msg_len) % QUEUE_CAPACITY;
        self.count -= 1;
    }

    pub fn isEmpty(self: *const DirectQueue) bool {
        return self.count == 0;
    }

    fn usedBytes(self: *const DirectQueue) usize {
        if (self.write_pos >= self.read_pos) {
            return self.write_pos - self.read_pos;
        }
        return QUEUE_CAPACITY - self.read_pos + self.write_pos;
    }

    fn writeBytesInternal(self: *DirectQueue, data: []const u8) void {
        const buf = self.buf_storage.?; // guaranteed non-null after enqueue checks
        const first_len = @min(data.len, QUEUE_CAPACITY - self.write_pos);
        @memcpy(buf[self.write_pos..][0..first_len], data[0..first_len]);
        if (first_len < data.len) {
            @memcpy(buf[0 .. data.len - first_len], data[first_len..]);
        }
        self.write_pos = (self.write_pos + data.len) % QUEUE_CAPACITY;
    }

    fn readBytesAtBuf(buf: []const u8, pos: usize, out: []u8) void {
        const first_len = @min(out.len, QUEUE_CAPACITY - pos);
        @memcpy(out[0..first_len], buf[pos..][0..first_len]);
        if (first_len < out.len) {
            @memcpy(out[first_len..], buf[0 .. out.len - first_len]);
        }
    }
};

// --- Tests ---

test "DirectQueue.init: empty queue, no allocation" {
    const q = DirectQueue.init();
    try std.testing.expect(q.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), q.count);
    try std.testing.expect(q.peek() == null);
    try std.testing.expect(q.buf_storage == null);
}

test "DirectQueue.enqueue: allocates buffer on first use" {
    var q = DirectQueue.init();
    defer q.deinit();
    try q.enqueue("hello world");
    try std.testing.expect(q.buf_storage != null);
}

test "DirectQueue: enqueue peek dequeue data integrity" {
    var q = DirectQueue.init();
    defer q.deinit();
    try q.enqueue("hello world");

    const data = q.peek().?;
    try std.testing.expectEqualSlices(u8, "hello world", data);

    q.dequeue();
    try std.testing.expect(q.isEmpty());
}

test "DirectQueue: FIFO ordering across multiple messages" {
    var q = DirectQueue.init();
    defer q.deinit();
    try q.enqueue("first");
    try q.enqueue("second");
    try q.enqueue("third");

    try std.testing.expectEqualSlices(u8, "first", q.peek().?);
    q.dequeue();
    try std.testing.expectEqualSlices(u8, "second", q.peek().?);
    q.dequeue();
    try std.testing.expectEqualSlices(u8, "third", q.peek().?);
    q.dequeue();
    try std.testing.expect(q.isEmpty());
}

test "DirectQueue.peek: does not consume" {
    var q = DirectQueue.init();
    defer q.deinit();
    try q.enqueue("stable");

    _ = q.peek();
    _ = q.peek(); // peek twice
    try std.testing.expectEqual(@as(usize, 1), q.count);

    q.dequeue();
    try std.testing.expect(q.isEmpty());
}

test "DirectQueue.peekCopy: handles wrapped messages" {
    var q = DirectQueue.init();
    defer q.deinit();

    // Fill most of the buffer, then drain, then write a message that wraps
    const fill = [_]u8{'X'} ** (QUEUE_CAPACITY - 100);
    try q.enqueue(&fill);
    q.dequeue();

    // Now write_pos near end, next message wraps
    const msg = "wrap-around-message";
    try q.enqueue(msg);

    var out: [256]u8 = @splat(0);
    const n = q.peekCopy(&out).?;
    try std.testing.expectEqualSlices(u8, msg, out[0..n]);
}

test "DirectQueue.enqueue: QueueFull when capacity exceeded" {
    var q = DirectQueue.init();
    defer q.deinit();
    // Fill with a large message (leaves no room for another entry)
    const big = [_]u8{'Z'} ** (QUEUE_CAPACITY - 8);
    try q.enqueue(&big);

    // Even a tiny message should fail
    try std.testing.expectError(error.QueueFull, q.enqueue("x"));
}

test "DirectQueue: interleaved enqueue dequeue preserves ordering" {
    var q = DirectQueue.init();
    defer q.deinit();

    try q.enqueue("A");
    try q.enqueue("B");
    try std.testing.expectEqualSlices(u8, "A", q.peek().?);
    q.dequeue();

    try q.enqueue("C");
    try std.testing.expectEqualSlices(u8, "B", q.peek().?);
    q.dequeue();
    try std.testing.expectEqualSlices(u8, "C", q.peek().?);
    q.dequeue();
    try std.testing.expect(q.isEmpty());
}

test "DirectQueue: many small messages fill and drain" {
    var q = DirectQueue.init();
    defer q.deinit();

    // Enqueue many small messages until full
    var enqueued: usize = 0;
    while (true) {
        q.enqueue("msg") catch break;
        enqueued += 1;
    }
    try std.testing.expect(enqueued > 0);

    // Drain all and verify count
    var drained: usize = 0;
    while (!q.isEmpty()) {
        q.dequeue();
        drained += 1;
    }
    try std.testing.expectEqual(enqueued, drained);
}

test "DirectQueue.peekCopy: returns null when out buffer too small" {
    var q = DirectQueue.init();
    defer q.deinit();
    try q.enqueue("a long message that wont fit");

    var tiny: [4]u8 = @splat(0);
    try std.testing.expect(q.peekCopy(&tiny) == null);
}

test "DirectQueue.dequeue: on empty queue is a no-op" {
    var q = DirectQueue.init();
    defer q.deinit();
    q.dequeue(); // should not crash
    try std.testing.expect(q.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), q.count);
}

test "DirectQueue.deinit: frees buffer and can be called multiple times" {
    var q = DirectQueue.init();
    try q.enqueue("data");
    q.deinit();
    try std.testing.expect(q.buf_storage == null);
    q.deinit(); // second call is safe
}
