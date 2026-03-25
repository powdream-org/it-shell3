const std = @import("std");

pub const DEFAULT_RING_SIZE: usize = 2 * 1024 * 1024; // 2 MB
pub const MAX_FRAME_INDEX: usize = 256; // Track last 256 frames for seeking

/// Metadata for one frame stored in the ring.
pub const FrameMeta = struct {
    /// Monotonic byte offset where this frame's length prefix starts.
    total_offset: usize = 0,
    /// Total bytes in ring: 4-byte length prefix + frame data.
    len: usize = 0,
    /// true = I-frame (keyframe), false = P-frame (delta).
    is_i_frame: bool = false,
    /// Protocol-level frame sequence number.
    frame_sequence: u64 = 0,
};

/// Per-client read cursor into the ring buffer.
pub const RingCursor = struct {
    /// Monotonic byte offset. Ring position = total_read % capacity.
    total_read: usize = 0,

    pub fn init() RingCursor {
        return .{};
    }
};

pub const RingBuffer = struct {
    buf: []u8,
    capacity: usize,
    write_pos: usize,
    total_written: usize,

    // Frame index — circular array, zero-initialized via FrameMeta defaults
    frame_index: [MAX_FRAME_INDEX]FrameMeta,
    frame_count: usize,
    latest_i_frame_idx: usize,
    has_i_frame: bool, // true once at least one I-frame has been written

    const inert_state: RingBuffer = .{
        .buf = &.{},
        .capacity = 0,
        .write_pos = 0,
        .total_written = 0,
        .frame_index = [_]FrameMeta{.{}} ** MAX_FRAME_INDEX,
        .frame_count = 0,
        .latest_i_frame_idx = 0,
        .has_i_frame = false,
    };

    /// Create a zero-capacity inert ring buffer (placeholder for unallocated pane slots).
    pub fn initInert() RingBuffer {
        return inert_state;
    }

    pub fn init(backing: []u8) RingBuffer {
        std.debug.assert(backing.len > 0);
        return .{
            .buf = backing,
            .capacity = backing.len,
            .write_pos = 0,
            .total_written = 0,
            .frame_index = [_]FrameMeta{.{}} ** MAX_FRAME_INDEX,
            .frame_count = 0,
            .latest_i_frame_idx = 0,
            .has_i_frame = false,
        };
    }

    /// Write a pre-serialized frame into the ring.
    /// Stored as: [4-byte LE length][frame_data].
    pub fn writeFrame(
        self: *RingBuffer,
        frame_data: []const u8,
        is_i_frame: bool,
        frame_sequence: u64,
    ) error{FrameTooLarge}!void {
        const entry_len = 4 + frame_data.len;
        if (entry_len > self.capacity / 2) return error.FrameTooLarge;

        const frame_total_offset = self.total_written;

        var len_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &len_buf, @intCast(frame_data.len), .little);
        self.writeBytes(&len_buf);
        self.writeBytes(frame_data);

        const idx = self.frame_count % MAX_FRAME_INDEX;
        self.frame_index[idx] = .{
            .total_offset = frame_total_offset,
            .len = entry_len,
            .is_i_frame = is_i_frame,
            .frame_sequence = frame_sequence,
        };
        if (is_i_frame) {
            self.latest_i_frame_idx = idx;
            self.has_i_frame = true;
        }
        self.frame_count += 1;
    }

    fn writeBytes(self: *RingBuffer, data: []const u8) void {
        const first_len = @min(data.len, self.capacity - self.write_pos);
        @memcpy(self.buf[self.write_pos..][0..first_len], data[0..first_len]);
        if (first_len < data.len) {
            const rest = data.len - first_len;
            @memcpy(self.buf[0..rest], data[first_len..]);
        }
        self.write_pos = (self.write_pos + data.len) % self.capacity;
        self.total_written += data.len;
    }

    pub fn isCursorOverwritten(self: *const RingBuffer, cursor: *const RingCursor) bool {
        if (cursor.total_read > self.total_written) return true;
        return (self.total_written - cursor.total_read) > self.capacity;
    }

    pub fn available(self: *const RingBuffer, cursor: *const RingCursor) usize {
        if (self.isCursorOverwritten(cursor)) return 0;
        if (cursor.total_read >= self.total_written) return 0;
        return self.total_written - cursor.total_read;
    }

    /// Peek at frame data without advancing cursor.
    /// Copies frame data (without length prefix) into `out`.
    /// Returns frame length, or null if no frame available.
    pub fn peekFrame(
        self: *const RingBuffer,
        cursor: *const RingCursor,
        out: []u8,
    ) ?usize {
        const avail = self.available(cursor);
        if (avail < 4) return null;

        var len_buf: [4]u8 = undefined;
        const read_pos = cursor.total_read % self.capacity;
        self.readBytesAt(read_pos, &len_buf);
        const frame_len = std.mem.readInt(u32, &len_buf, .little);

        if (frame_len > out.len) return null;
        if (avail < 4 + frame_len) return null;

        const data_pos = (cursor.total_read + 4) % self.capacity;
        self.readBytesAt(data_pos, out[0..frame_len]);
        return frame_len;
    }

    /// Advance cursor past a frame. `frame_len` is the value returned by
    /// peekFrame — passing it avoids re-reading the length prefix from the ring.
    pub fn advancePastFrame(self: *const RingBuffer, cursor: *RingCursor, frame_len: usize) void {
        _ = self;
        cursor.total_read += 4 + frame_len;
    }

    fn readBytesAt(self: *const RingBuffer, pos: usize, out: []u8) void {
        const first_len = @min(out.len, self.capacity - pos);
        @memcpy(out[0..first_len], self.buf[pos..][0..first_len]);
        if (first_len < out.len) {
            @memcpy(out[first_len..], self.buf[0 .. out.len - first_len]);
        }
    }

    /// Advance cursor to the latest I-frame position.
    pub fn seekToLatestIFrame(self: *const RingBuffer, cursor: *RingCursor) void {
        if (!self.has_i_frame) return;
        const meta = self.frame_index[self.latest_i_frame_idx];
        if (self.total_written - meta.total_offset <= self.capacity) {
            cursor.total_read = meta.total_offset;
        }
    }

    pub fn hasValidIFrame(self: *const RingBuffer) bool {
        if (!self.has_i_frame) return false;
        const meta = self.frame_index[self.latest_i_frame_idx];
        return (self.total_written - meta.total_offset <= self.capacity);
    }
};

// --- Tests ---

test "init: zero state with correct capacity" {
    var backing: [4096]u8 = @splat(0);
    const rb = RingBuffer.init(&backing);
    try std.testing.expectEqual(@as(usize, 4096), rb.capacity);
    try std.testing.expectEqual(@as(usize, 0), rb.total_written);
    try std.testing.expectEqual(@as(usize, 0), rb.frame_count);
    try std.testing.expect(!rb.has_i_frame);
    try std.testing.expect(!rb.hasValidIFrame());
}

test "writeFrame + peekFrame: data integrity round-trip" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    const payload = "hello, ring buffer!";
    try rb.writeFrame(payload, false, 42);

    var out: [256]u8 = @splat(0);
    const n = rb.peekFrame(&cursor, &out).?;
    try std.testing.expectEqualSlices(u8, payload, out[0..n]);
}

test "peekFrame does NOT advance cursor; advancePastFrame does" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try rb.writeFrame("data", false, 1);

    var out: [256]u8 = @splat(0);
    // Peek twice — same result, cursor unchanged
    const n1 = rb.peekFrame(&cursor, &out).?;
    const saved_read = cursor.total_read;
    const n2 = rb.peekFrame(&cursor, &out).?;
    try std.testing.expectEqual(n1, n2);
    try std.testing.expectEqual(saved_read, cursor.total_read);

    // Advance — cursor moves
    rb.advancePastFrame(&cursor, n1);
    try std.testing.expect(cursor.total_read > saved_read);

    // No more data
    try std.testing.expect(rb.peekFrame(&cursor, &out) == null);
}

test "monotonic counters advance correctly" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);

    try rb.writeFrame("test", false, 1);
    try std.testing.expectEqual(@as(usize, 8), rb.total_written); // 4 + 4
    try std.testing.expectEqual(@as(usize, 1), rb.frame_count);

    try rb.writeFrame("test", false, 2);
    try std.testing.expectEqual(@as(usize, 16), rb.total_written);
}

test "rejects frame larger than half capacity" {
    var backing: [64]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    const big = [_]u8{0} ** 29; // 4 + 29 = 33 > 32
    try std.testing.expectError(error.FrameTooLarge, rb.writeFrame(&big, false, 1));
}

test "wrap-around: data integrity across ring boundary" {
    var backing: [64]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    const frame_a = "AAAAAAAAAA"; // 14 bytes per entry (4 + 10)
    const frame_b = "BBBBBBBBBB";
    const frame_c = "CCCCCCCCCC";
    const frame_d = "DDDDDDDDDD";

    try rb.writeFrame(frame_a, true, 1);
    try rb.writeFrame(frame_b, false, 2);
    try rb.writeFrame(frame_c, false, 3);
    try rb.writeFrame(frame_d, false, 4); // 56 bytes total

    var out: [64]u8 = @splat(0);
    const na = rb.peekFrame(&cursor, &out).?;
    try std.testing.expectEqualSlices(u8, frame_a, out[0..na]);
    rb.advancePastFrame(&cursor, na);
    const nb = rb.peekFrame(&cursor, &out).?;
    try std.testing.expectEqualSlices(u8, frame_b, out[0..nb]);
    rb.advancePastFrame(&cursor, nb);
    const nc = rb.peekFrame(&cursor, &out).?;
    try std.testing.expectEqualSlices(u8, frame_c, out[0..nc]);
    rb.advancePastFrame(&cursor, nc);
    const nd = rb.peekFrame(&cursor, &out).?;
    try std.testing.expectEqualSlices(u8, frame_d, out[0..nd]);
    rb.advancePastFrame(&cursor, nd);

    // Write a wrapping frame
    const frame_e = "EEEEEEEEEE";
    try rb.writeFrame(frame_e, true, 5);
    const n = rb.peekFrame(&cursor, &out).?;
    try std.testing.expectEqualSlices(u8, frame_e, out[0..n]);
}

test "isCursorOverwritten: detects when cursor data is gone" {
    var backing: [32]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    const frame = [_]u8{'X'} ** 8; // 12 bytes each
    try rb.writeFrame(&frame, true, 1);
    try rb.writeFrame(&frame, true, 2); // 24 bytes total
    try std.testing.expect(!rb.isCursorOverwritten(&cursor));

    try rb.writeFrame(&frame, true, 3); // 36 > 32: overwrite
    try std.testing.expect(rb.isCursorOverwritten(&cursor));
}

test "isCursorOverwritten: caught-up cursor is never overwritten" {
    var backing: [64]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();
    var out: [64]u8 = @splat(0);

    try rb.writeFrame("abc", false, 1);
    const n = rb.peekFrame(&cursor, &out).?;
    rb.advancePastFrame(&cursor, n);
    try std.testing.expect(!rb.isCursorOverwritten(&cursor));
}

test "available: exact pending bytes" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try std.testing.expectEqual(@as(usize, 0), rb.available(&cursor));
    try rb.writeFrame("hello", false, 1); // 9 bytes
    try std.testing.expectEqual(@as(usize, 9), rb.available(&cursor));

    try rb.writeFrame("world!", false, 2); // 10 bytes
    try std.testing.expectEqual(@as(usize, 19), rb.available(&cursor));
}

test "available: returns 0 for overwritten cursor" {
    var backing: [32]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();
    const frame = [_]u8{'Y'} ** 10;
    try rb.writeFrame(&frame, true, 1);
    try rb.writeFrame(&frame, true, 2);
    try rb.writeFrame(&frame, true, 3); // 42 > 32
    try std.testing.expectEqual(@as(usize, 0), rb.available(&cursor));
}

test "peekFrame: returns null when buffer too small" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();
    const big = [_]u8{'Z'} ** 100;
    try rb.writeFrame(&big, false, 1);
    var small: [50]u8 = @splat(0);
    try std.testing.expect(rb.peekFrame(&cursor, &small) == null);
}

test "I-frame tracking: latest_i_frame_idx tracks most recent" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);

    try rb.writeFrame("p1", false, 1);
    try std.testing.expect(!rb.has_i_frame);

    try rb.writeFrame("iframe1", true, 2);
    try std.testing.expect(rb.has_i_frame);
    try std.testing.expectEqual(@as(u64, 2), rb.frame_index[rb.latest_i_frame_idx].frame_sequence);

    try rb.writeFrame("p2", false, 3);
    try std.testing.expectEqual(@as(u64, 2), rb.frame_index[rb.latest_i_frame_idx].frame_sequence);

    try rb.writeFrame("iframe2", true, 4);
    try std.testing.expectEqual(@as(u64, 4), rb.frame_index[rb.latest_i_frame_idx].frame_sequence);
}

test "seekToLatestIFrame: cursor reads I-frame then subsequent frames" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try rb.writeFrame("p-frame-1", false, 1);
    try rb.writeFrame("THE-I-FRAME", true, 2);
    try rb.writeFrame("p-frame-2", false, 3);
    try rb.writeFrame("p-frame-3", false, 4);

    rb.seekToLatestIFrame(&cursor);

    var out: [256]u8 = @splat(0);
    const n1 = rb.peekFrame(&cursor, &out).?;
    try std.testing.expectEqualSlices(u8, "THE-I-FRAME", out[0..n1]);
    rb.advancePastFrame(&cursor, n1);
    const n2 = rb.peekFrame(&cursor, &out).?;
    try std.testing.expectEqualSlices(u8, "p-frame-2", out[0..n2]);
    rb.advancePastFrame(&cursor, n2);
    const n3 = rb.peekFrame(&cursor, &out).?;
    try std.testing.expectEqualSlices(u8, "p-frame-3", out[0..n3]);
}

test "seekToLatestIFrame: recovers overwritten cursor" {
    // 96-byte ring, 8-byte payload frames (12 bytes per entry incl. prefix).
    // 9 entries = 108 bytes > 96 => cursor gets overwritten.
    var backing: [96]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    const frame = [_]u8{'Q'} ** 8;
    try rb.writeFrame(&frame, true, 1);
    try rb.writeFrame(&frame, false, 2);
    try rb.writeFrame(&frame, true, 3);
    try rb.writeFrame(&frame, false, 4);
    try rb.writeFrame(&frame, true, 5);
    try rb.writeFrame(&frame, false, 6);
    try rb.writeFrame(&frame, true, 7);
    try rb.writeFrame(&frame, false, 8);
    try rb.writeFrame(&frame, true, 9);

    try std.testing.expect(rb.isCursorOverwritten(&cursor));
    rb.seekToLatestIFrame(&cursor);
    try std.testing.expect(!rb.isCursorOverwritten(&cursor));
}

test "hasValidIFrame: false with no I-frames, true after I-frame" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);

    try std.testing.expect(!rb.hasValidIFrame());
    try rb.writeFrame("p", false, 1);
    try std.testing.expect(!rb.hasValidIFrame()); // only P-frames

    try rb.writeFrame("i", true, 2);
    try std.testing.expect(rb.hasValidIFrame());
}

test "multiple independent cursors read full sequence" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var c1 = RingCursor.init();
    var c2 = RingCursor.init();

    try rb.writeFrame("frame-A", false, 1);
    try rb.writeFrame("frame-B", false, 2);
    try rb.writeFrame("frame-C", false, 3);

    var out: [64]u8 = @splat(0);
    // Cursor 1
    const c1a = rb.peekFrame(&c1, &out).?;
    try std.testing.expectEqualSlices(u8, "frame-A", out[0..c1a]);
    rb.advancePastFrame(&c1, c1a);
    const c1b = rb.peekFrame(&c1, &out).?;
    try std.testing.expectEqualSlices(u8, "frame-B", out[0..c1b]);
    rb.advancePastFrame(&c1, c1b);
    const c1c = rb.peekFrame(&c1, &out).?;
    try std.testing.expectEqualSlices(u8, "frame-C", out[0..c1c]);
    rb.advancePastFrame(&c1, c1c);

    // Cursor 2 — same data
    const c2a = rb.peekFrame(&c2, &out).?;
    try std.testing.expectEqualSlices(u8, "frame-A", out[0..c2a]);
    rb.advancePastFrame(&c2, c2a);
    const c2b = rb.peekFrame(&c2, &out).?;
    try std.testing.expectEqualSlices(u8, "frame-B", out[0..c2b]);
    rb.advancePastFrame(&c2, c2b);
    const c2c = rb.peekFrame(&c2, &out).?;
    try std.testing.expectEqualSlices(u8, "frame-C", out[0..c2c]);
}
