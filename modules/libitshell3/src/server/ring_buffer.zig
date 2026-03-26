const std = @import("std");

pub const DEFAULT_RING_SIZE: usize = 2 * 1024 * 1024; // 2 MB
pub const MAX_FRAME_INDEX: usize = 256; // Track last 256 frames for seeking

/// Metadata for one frame stored in the ring.
pub const FrameMeta = struct {
    /// Monotonic byte offset where this frame starts.
    total_offset: usize = 0,
    /// Total bytes in ring: frame data bytes.
    len: usize = 0,
    /// true = I-frame (keyframe), false = P-frame (delta).
    is_i_frame: bool = false,
    /// Protocol-level frame sequence number.
    frame_sequence: u64 = 0,
};

/// Per-client read cursor into the ring buffer.
/// Spec §4.5: cursor tracks read position + last I-frame position.
pub const RingCursor = struct {
    /// Monotonic byte offset. Ring position = total_read % capacity.
    total_read: usize = 0,
    /// Monotonic byte offset of the last I-frame delivered to this client.
    ///
    /// The daemon uses this for recovery decisions: if the ring has overwritten
    /// this I-frame (total_written - last_i_frame > capacity), the client's
    /// P-frames are no longer decodable and recovery (seekToLatestIFrame) is
    /// required.
    ///
    /// The CLIENT independently tracks its own I-frame reference via the
    /// wire-level `frame_sequence` + `frame_type` fields in each FrameUpdate
    /// header (protocol spec doc 04: "the client MUST track the frame_sequence
    /// of the most recently received I-frame as local state"). P-frames are
    /// cumulative deltas against the last I-frame — no sequential chain.
    ///
    /// Updated only on seekToLatestIFrame(). During normal sequential delivery
    /// the daemon does not parse frame boundaries (delivery is byte-granular
    /// per spec §5.4), so it cannot detect I-frame passage. This is correct:
    /// the client handles I-frame tracking from the wire format, and the daemon
    /// only needs this field for its own "is recovery needed?" check.
    last_i_frame: usize = 0,

    pub fn init() RingCursor {
        return .{};
    }
};

/// Two iovecs covering all pending bytes from cursor to write_pos.
/// When pending range does not wrap: iov[0] is valid, iov[1].len == 0.
/// When pending range wraps the ring: both iov[0] and iov[1] are valid.
/// Spec §4.6 / §5.4: caller passes these directly to writev() — zero copy.
pub const PendingIovecs = struct {
    iov: [2]std.posix.iovec_const,
    count: usize, // 1 or 2

    pub fn totalLen(self: *const PendingIovecs) usize {
        var n: usize = 0;
        for (self.iov[0..self.count]) |v| n += v.len;
        return n;
    }
};

pub const RingBuffer = struct {
    buf: []u8,
    capacity: usize,
    write_pos: usize,
    total_written: usize,

    frame_index: [MAX_FRAME_INDEX]FrameMeta,
    frame_count: usize,
    latest_i_frame_idx: usize,
    has_i_frame: bool,

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

    /// Write a pre-serialized frame (protocol Header + FrameUpdate payload)
    /// into the ring as raw wire-format bytes. The delivery path
    /// (pendingIovecs + writev) sends these bytes directly to the client
    /// socket, so the ring content is identical to what the client receives.
    ///
    /// Frame boundaries within the ring are tracked by frame_index
    /// (FrameMeta.total_offset + FrameMeta.len) for seekToLatestIFrame.
    ///
    /// Rejects frames larger than capacity/2 to guarantee at least two
    /// frames can coexist in the ring.
    pub fn writeFrame(
        self: *RingBuffer,
        frame_data: []const u8,
        is_i_frame: bool,
        frame_sequence: u64,
    ) error{FrameTooLarge}!void {
        if (frame_data.len > self.capacity / 2) return error.FrameTooLarge;

        const frame_total_offset = self.total_written;

        self.writeBytes(frame_data);

        const idx = self.frame_count % MAX_FRAME_INDEX;
        self.frame_index[idx] = .{
            .total_offset = frame_total_offset,
            .len = frame_data.len,
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

    /// Returns true if the ring has wrapped past the cursor's position,
    /// meaning the data the cursor points to has been overwritten by newer
    /// frames. When this returns true, the cursor's iovecs would point to
    /// corrupted data — the caller MUST call seekToLatestIFrame before
    /// attempting delivery.
    ///
    /// The `total_read > total_written` guard catches impossible states
    /// (cursor ahead of writer), which can only happen via direct struct
    /// mutation — defensive, not expected in production.
    pub fn isCursorOverwritten(self: *const RingBuffer, cursor: *const RingCursor) bool {
        if (cursor.total_read > self.total_written) return true;
        return (self.total_written - cursor.total_read) > self.capacity;
    }

    pub fn available(self: *const RingBuffer, cursor: *const RingCursor) usize {
        if (self.isCursorOverwritten(cursor)) return 0;
        if (cursor.total_read >= self.total_written) return 0;
        return self.total_written - cursor.total_read;
    }

    /// Return iovecs covering ALL pending bytes from cursor to write_pos.
    /// Spec §4.6 / §5.4: iovecs point DIRECTLY into self.buf — zero copy.
    /// When range does not wrap: count=1, iov[0] covers the full range.
    /// When range wraps the ring: count=2, iov[0] = tail segment, iov[1] = head segment.
    /// Returns null when no pending bytes (available == 0 or cursor overwritten).
    pub fn pendingIovecs(self: *const RingBuffer, cursor: *const RingCursor) ?PendingIovecs {
        const avail = self.available(cursor);
        if (avail == 0) return null;

        const read_pos = cursor.total_read % self.capacity;
        const tail_len = self.capacity - read_pos; // bytes from read_pos to end of buf

        if (avail <= tail_len) {
            return .{
                .iov = .{
                    .{ .base = self.buf.ptr + read_pos, .len = avail },
                    .{ .base = self.buf.ptr, .len = 0 },
                },
                .count = 1,
            };
        } else {
            const head_len = avail - tail_len;
            return .{
                .iov = .{
                    .{ .base = self.buf.ptr + read_pos, .len = tail_len },
                    .{ .base = self.buf.ptr, .len = head_len },
                },
                .count = 2,
            };
        }
    }

    /// Advance cursor by exactly n bytes.
    /// Spec §5.4: "advance client cursor by n bytes".
    /// n must not exceed available(cursor). Asserts in debug builds.
    pub fn advanceCursor(self: *const RingBuffer, cursor: *RingCursor, n: usize) void {
        std.debug.assert(n <= self.available(cursor));
        cursor.total_read += n;
    }

    /// Advance cursor to the latest I-frame position in the ring.
    ///
    /// This is the universal recovery operation — all recovery scenarios
    /// collapse into this single call (spec §4.8, §5.5):
    ///   - Slow client: cursor overwritten by ring wrap → seek to I-frame
    ///   - ContinuePane after PausePane → seek to I-frame
    ///   - Stale client recovery → seek to I-frame
    ///   - Client attach/reattach → seek to I-frame
    ///
    /// After seeking, the client receives a complete terminal state
    /// (I-frame) as its next delivery, then resumes incremental P-frames.
    /// No special recovery codepath — the I-frame IS the resync.
    ///
    /// Also updates cursor.last_i_frame so the daemon can later check
    /// whether this I-frame is still valid in the ring.
    ///
    /// No-op if no I-frame has ever been written to the ring, or if the
    /// latest I-frame has itself been overwritten (ring too small for the
    /// write rate). In the latter case the caller should produce a fresh
    /// I-frame before retrying.
    pub fn seekToLatestIFrame(self: *const RingBuffer, cursor: *RingCursor) void {
        if (!self.has_i_frame) return;
        const meta = self.frame_index[self.latest_i_frame_idx];
        if (self.total_written - meta.total_offset <= self.capacity) {
            cursor.total_read = meta.total_offset;
            cursor.last_i_frame = meta.total_offset;
        }
    }

    /// Returns true if the ring contains at least one I-frame that hasn't
    /// been overwritten. Used to check the ring invariant (spec §4.1:
    /// "ring MUST always contain at least one complete I-frame").
    ///
    /// When this returns false and the ring is actively being written to,
    /// the frame export logic (Plan 6) must force-produce an I-frame
    /// before any more P-frames — otherwise seekToLatestIFrame will be a
    /// no-op and slow clients cannot recover.
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

test "RingCursor: last_i_frame field present and zero-initialized (spec §4.5)" {
    const cursor = RingCursor.init();
    try std.testing.expectEqual(@as(usize, 0), cursor.total_read);
    try std.testing.expectEqual(@as(usize, 0), cursor.last_i_frame);
}

test "pendingIovecs: null when ring is empty" {
    var backing: [1024]u8 = @splat(0);
    const rb = RingBuffer.init(&backing);
    const cursor = RingCursor.init();
    try std.testing.expect(rb.pendingIovecs(&cursor) == null);
}

test "pendingIovecs: single iovec, no wrap (spec §4.6 zero-copy)" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    const cursor = RingCursor.init();

    const payload = "hello, ring buffer!";
    try rb.writeFrame(payload, false, 42);

    const p = rb.pendingIovecs(&cursor).?;
    try std.testing.expectEqual(@as(usize, 1), p.count);
    // Zero-copy proof: iovec base must be inside self.buf address range
    const buf_start = @intFromPtr(rb.buf.ptr);
    const buf_end = buf_start + rb.capacity;
    const iov_base = @intFromPtr(p.iov[0].base);
    try std.testing.expect(iov_base >= buf_start and iov_base < buf_end);
    // Length must equal available bytes
    try std.testing.expectEqual(rb.available(&cursor), p.totalLen());
}

test "pendingIovecs: two iovecs when pending range wraps ring (spec §4.6)" {
    // 32-byte ring. Write 3 frames of 10 bytes each (entry = 10).
    // After reading 2 frames (20 bytes), write_pos = 20.
    // Third frame at 20..30 fits, but let's use 12-byte frames to force wrap.
    // Use 11-byte frames: 2 * 11 = 22 bytes, third at 22..33 wraps: 10 tail + 1 head.
    var backing: [32]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    const f = [_]u8{'A'} ** 11; // 11 bytes per entry
    try rb.writeFrame(&f, false, 1);
    try rb.writeFrame(&f, false, 2);
    // Advance cursor past first two entries (22 bytes)
    rb.advanceCursor(&cursor, 11);
    rb.advanceCursor(&cursor, 11);
    // Now write the third frame — it wraps at position 22 (22+11=33 > 32)
    try rb.writeFrame(&f, true, 3);

    const avail = rb.available(&cursor);
    try std.testing.expectEqual(@as(usize, 11), avail);

    const p = rb.pendingIovecs(&cursor).?;
    try std.testing.expectEqual(@as(usize, 2), p.count);

    // Both iovecs must point into rb.buf
    const buf_start = @intFromPtr(rb.buf.ptr);
    const buf_end = buf_start + rb.capacity;
    try std.testing.expect(@intFromPtr(p.iov[0].base) >= buf_start and @intFromPtr(p.iov[0].base) < buf_end);
    try std.testing.expect(@intFromPtr(p.iov[1].base) >= buf_start and @intFromPtr(p.iov[1].base) < buf_end);

    // Total length must equal available bytes
    try std.testing.expectEqual(avail, p.totalLen());

    // Concatenated content must equal the original frame bytes ('A' repeated)
    var combined: [32]u8 = @splat(0);
    @memcpy(combined[0..p.iov[0].len], p.iov[0].base[0..p.iov[0].len]);
    @memcpy(combined[p.iov[0].len..][0..p.iov[1].len], p.iov[1].base[0..p.iov[1].len]);
    // All bytes should be 'A'
    try std.testing.expectEqualSlices(u8, &f, combined[0..11]);
}

test "advanceCursor: byte-granular advancement (spec §5.4)" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try rb.writeFrame("hello", false, 1); // 5 bytes
    try rb.writeFrame("world", false, 2); // 5 bytes
    try std.testing.expectEqual(@as(usize, 10), rb.available(&cursor));

    // Partial advance: 5 bytes
    rb.advanceCursor(&cursor, 5);
    try std.testing.expectEqual(@as(usize, 5), cursor.total_read);
    try std.testing.expectEqual(@as(usize, 5), rb.available(&cursor));

    // Advance remaining
    rb.advanceCursor(&cursor, 5);
    try std.testing.expectEqual(@as(usize, 10), cursor.total_read);
    try std.testing.expectEqual(@as(usize, 0), rb.available(&cursor));
    try std.testing.expect(rb.pendingIovecs(&cursor) == null);
}

test "advanceCursor: zero advance is no-op" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try rb.writeFrame("data", false, 1);
    const before = cursor.total_read;
    rb.advanceCursor(&cursor, 0);
    try std.testing.expectEqual(before, cursor.total_read);
}

test "pendingIovecs: iovec total equals available() (spec §5.4)" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try rb.writeFrame("hello", false, 1);
    try rb.writeFrame("world!", false, 2);

    const avail = rb.available(&cursor);
    const p = rb.pendingIovecs(&cursor).?;
    try std.testing.expectEqual(avail, p.totalLen());
}

test "independent cursors: advancing A does not affect B (spec §4.5)" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var c1 = RingCursor.init();
    var c2 = RingCursor.init();

    try rb.writeFrame("frame-A", false, 1);
    try rb.writeFrame("frame-B", false, 2);

    const avail_before = rb.available(&c2);
    rb.advanceCursor(&c1, rb.available(&c1));
    // c2 unaffected
    try std.testing.expectEqual(avail_before, rb.available(&c2));
    try std.testing.expectEqual(@as(usize, 0), rb.available(&c1));
}

test "monotonic counters advance correctly" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);

    try rb.writeFrame("test", false, 1);
    try std.testing.expectEqual(@as(usize, 4), rb.total_written); // 4 bytes ("test")
    try std.testing.expectEqual(@as(usize, 1), rb.frame_count);

    try rb.writeFrame("test", false, 2);
    try std.testing.expectEqual(@as(usize, 8), rb.total_written);
}

test "rejects frame larger than half capacity" {
    var backing: [64]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    const big = [_]u8{0} ** 33; // 33 > 32 (capacity/2)
    try std.testing.expectError(error.FrameTooLarge, rb.writeFrame(&big, false, 1));
}

test "isCursorOverwritten: detects when cursor data is gone" {
    var backing: [32]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    const frame = [_]u8{'X'} ** 8; // 8 bytes each
    try rb.writeFrame(&frame, true, 1);
    try rb.writeFrame(&frame, true, 2); // 16 bytes total
    try std.testing.expect(!rb.isCursorOverwritten(&cursor));

    try rb.writeFrame(&frame, true, 3); // 24 bytes total
    try rb.writeFrame(&frame, true, 4); // 32 bytes total (at capacity edge)
    try rb.writeFrame(&frame, true, 5); // 40 > 32: overwrite
    try std.testing.expect(rb.isCursorOverwritten(&cursor));
}

test "isCursorOverwritten: caught-up cursor is never overwritten" {
    var backing: [64]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try rb.writeFrame("abc", false, 1);
    const n = rb.available(&cursor);
    rb.advanceCursor(&cursor, n);
    try std.testing.expect(!rb.isCursorOverwritten(&cursor));
}

test "available: exact pending bytes" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try std.testing.expectEqual(@as(usize, 0), rb.available(&cursor));
    try rb.writeFrame("hello", false, 1); // 5 bytes
    try std.testing.expectEqual(@as(usize, 5), rb.available(&cursor));

    try rb.writeFrame("world!", false, 2); // 6 bytes
    try std.testing.expectEqual(@as(usize, 11), rb.available(&cursor));
}

test "available: returns 0 for overwritten cursor" {
    var backing: [32]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();
    const frame = [_]u8{'Y'} ** 10;
    try rb.writeFrame(&frame, true, 1);
    try rb.writeFrame(&frame, true, 2);
    try rb.writeFrame(&frame, true, 3); // 30 bytes total — not yet overwritten (30 < 32), write one more
    try rb.writeFrame(&frame, true, 4); // 40 > 32: overwritten
    try std.testing.expectEqual(@as(usize, 0), rb.available(&cursor));
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

test "seekToLatestIFrame: cursor reads I-frame then subsequent frames via iovecs" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    // Write: P P I P P
    // lengths: "p-frame-1"=13, "THE-I-FRAME"=15, "p-frame-2"=13, "p-frame-3"=13
    try rb.writeFrame("p-frame-1", false, 1);
    try rb.writeFrame("THE-I-FRAME", true, 2);
    try rb.writeFrame("p-frame-2", false, 3);
    try rb.writeFrame("p-frame-3", false, 4);

    rb.seekToLatestIFrame(&cursor);
    // cursor.last_i_frame should be updated
    try std.testing.expect(cursor.last_i_frame > 0 or cursor.total_read == 0);

    // Verify iovecs start from I-frame: the first bytes read via iovec
    // are the I-frame data itself ("THE-I-FRAME").
    const p = rb.pendingIovecs(&cursor).?;
    var combined: [512]u8 = @splat(0);
    var off: usize = 0;
    for (p.iov[0..p.count]) |v| {
        @memcpy(combined[off..][0..v.len], v.base[0..v.len]);
        off += v.len;
    }
    // First 11 bytes = the I-frame payload "THE-I-FRAME"
    try std.testing.expectEqualSlices(u8, "THE-I-FRAME", combined[0..11]);
}

test "seekToLatestIFrame: recovers overwritten cursor" {
    var backing: [96]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    // 8-byte frames, no prefix. Need > 96 bytes to overwrite a 96-byte ring.
    // 13 frames * 8 bytes = 104 > 96.
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
    try rb.writeFrame(&frame, false, 10);
    try rb.writeFrame(&frame, true, 11);
    try rb.writeFrame(&frame, false, 12);
    try rb.writeFrame(&frame, true, 13);

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

test "multiple independent cursors: iovecs span same ring memory (spec §4.1 §4.11)" {
    var backing: [1024]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var c1 = RingCursor.init();
    var c2 = RingCursor.init();

    try rb.writeFrame("frame-A", false, 1);
    try rb.writeFrame("frame-B", false, 2);
    try rb.writeFrame("frame-C", false, 3);

    // Both cursors get iovecs from the same ring backing memory
    const p1 = rb.pendingIovecs(&c1).?;
    const p2 = rb.pendingIovecs(&c2).?;

    const buf_start = @intFromPtr(rb.buf.ptr);
    const buf_end = buf_start + rb.capacity;

    for (p1.iov[0..p1.count]) |v| {
        try std.testing.expect(@intFromPtr(v.base) >= buf_start and @intFromPtr(v.base) < buf_end);
    }
    for (p2.iov[0..p2.count]) |v| {
        try std.testing.expect(@intFromPtr(v.base) >= buf_start and @intFromPtr(v.base) < buf_end);
    }

    // Both cursors see identical total bytes
    try std.testing.expectEqual(p1.totalLen(), p2.totalLen());

    // Advance c1 entirely; c2 stays put
    rb.advanceCursor(&c1, p1.totalLen());
    try std.testing.expectEqual(@as(usize, 0), rb.available(&c1));
    try std.testing.expectEqual(p2.totalLen(), rb.available(&c2));
}

test "wrap-around: data integrity via iovecs across ring boundary" {
    var backing: [64]u8 = @splat(0);
    var rb = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    const frame_a = "AAAAAAAAAA"; // 10 bytes per entry
    const frame_b = "BBBBBBBBBB";
    const frame_c = "CCCCCCCCCC";
    const frame_d = "DDDDDDDDDD";

    try rb.writeFrame(frame_a, true, 1);
    try rb.writeFrame(frame_b, false, 2);
    try rb.writeFrame(frame_c, false, 3);
    try rb.writeFrame(frame_d, false, 4); // 40 bytes total

    // Advance cursor to read all 4 frames byte-by-byte via iovecs
    var read_buf: [256]u8 = @splat(0);
    var off: usize = 0;
    const p = rb.pendingIovecs(&cursor).?;
    for (p.iov[0..p.count]) |v| {
        @memcpy(read_buf[off..][0..v.len], v.base[0..v.len]);
        off += v.len;
    }
    try std.testing.expectEqual(@as(usize, 40), off);
    rb.advanceCursor(&cursor, 40);

    // Write a wrapping frame (starts at position 40 % 64 = 40, extends to 50; no wrap yet)
    // Write another to force wrap: position 50, extends to 60; still no wrap
    // Write one more: position 60, extends to 70 — wraps!
    const frame_e = "EEEEEEEEEE";
    try rb.writeFrame(frame_e, false, 5); // pos 40..50
    try rb.writeFrame(frame_e, false, 6); // pos 50..60
    try rb.writeFrame(frame_e, true, 7);  // pos 60..70 — wraps at 64
    const avail = rb.available(&cursor);
    try std.testing.expectEqual(@as(usize, 30), avail); // 3 * 10

    const p2 = rb.pendingIovecs(&cursor).?;
    var combined: [64]u8 = @splat(0);
    var off2: usize = 0;
    for (p2.iov[0..p2.count]) |v| {
        @memcpy(combined[off2..][0..v.len], v.base[0..v.len]);
        off2 += v.len;
    }
    // All bytes should be 'E' (frame_e repeated 3 times)
    try std.testing.expectEqual(@as(usize, 30), off2);
    for (combined[0..30]) |b| {
        try std.testing.expectEqual(@as(u8, 'E'), b);
    }
}
