const std = @import("std");
const header_mod = @import("header.zig");

pub const Frame = struct {
    header: header_mod.Header,
    payload: []const u8,
};

pub const ReadError = header_mod.HeaderError || error{
    EndOfStream,
};

/// Read one complete frame from a stream.
/// `payload_buf` must be large enough for the payload (up to 16 MiB).
/// Returns the frame with payload slice into `payload_buf`.
pub fn readFrame(reader: anytype, payload_buf: []u8) (ReadError || @TypeOf(reader).NoEofError)!Frame {
    var hdr_buf: [header_mod.HEADER_SIZE]u8 = undefined;
    try reader.readNoEof(&hdr_buf);
    const hdr = try header_mod.Header.decode(&hdr_buf);
    if (hdr.payload_length > payload_buf.len)
        return error.PayloadTooLarge;
    const payload = payload_buf[0..hdr.payload_length];
    if (payload.len > 0) {
        try reader.readNoEof(payload);
    }
    return .{ .header = hdr, .payload = payload };
}

/// Monotonically increasing sequence counter per direction.
/// Starts at 1. Wraps from 0xFFFFFFFF back to 1 (skipping 0).
pub const SequenceTracker = struct {
    next: u32 = 1,

    pub fn advance(self: *SequenceTracker) u32 {
        const seq = self.next;
        self.next = if (self.next == 0xFFFFFFFF) 1 else self.next + 1;
        return seq;
    }
};

/// Accumulates partial protocol frames across recv() calls.
///
/// Per daemon-architecture integration-boundaries spec: per-connection framing
/// state that accumulates partial messages across recv() calls. TCP does not
/// guarantee message boundaries, so incomplete trailing bytes from one recv()
/// must be preserved for the next.
pub const MessageReader = struct {
    buffer: [BUFFER_SIZE]u8 = [_]u8{0} ** BUFFER_SIZE,
    length: u16 = 0,

    /// Buffer size for partial frame accumulation. Large enough to hold one
    /// max-size header plus some payload spillover.
    pub const BUFFER_SIZE: u16 = 4096;

    /// Feed received bytes into the reader.
    /// Returns a slice of all accumulated data (old partial + new bytes)
    /// that the caller should pass to `nextMessage` in a loop.
    /// If the combined data exceeds the buffer capacity, excess is silently
    /// dropped (protocol error -- the frame is too large for partial buffering).
    pub fn feed(self: *MessageReader, data: []const u8) []const u8 {
        const available = BUFFER_SIZE - self.length;
        const copy_length: u16 = @intCast(@min(data.len, available));
        @memcpy(self.buffer[self.length..][0..copy_length], data[0..copy_length]);
        self.length += copy_length;
        return self.buffer[0..self.length];
    }

    /// A decoded message: header plus payload slice into the reader's buffer.
    /// The caller must consume the payload before the next feed() or
    /// nextMessage() call, as the buffer contents shift on extraction.
    pub const Message = struct {
        header: header_mod.Header,
        payload: []const u8,
    };

    /// Try to extract the next complete frame from accumulated data.
    /// Returns the header and payload slice, or null if incomplete.
    /// On success, the consumed bytes are removed from the internal buffer.
    pub fn nextMessage(self: *MessageReader) ?Message {
        if (self.length < header_mod.HEADER_SIZE) return null;

        const hdr = header_mod.Header.decode(self.buffer[0..header_mod.HEADER_SIZE]) catch return null;

        const frame_end = header_mod.HEADER_SIZE + hdr.payload_length;
        if (frame_end > self.length) return null;

        const payload_slice = self.buffer[header_mod.HEADER_SIZE..frame_end];
        const result = Message{
            .header = hdr,
            .payload = payload_slice,
        };

        // Shift remaining bytes to the front.
        const remaining = self.length - @as(u16, @intCast(frame_end));
        if (remaining > 0) {
            std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[frame_end..self.length]);
        }
        self.length = remaining;

        return result;
    }

    /// Discard all accumulated data.
    pub fn reset(self: *MessageReader) void {
        self.length = 0;
    }
};

// --- Tests ---

const writer_mod = @import("writer.zig");

test "readFrame: round-trip with JSON message" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const hdr = header_mod.Header{
        .msg_type = 0x0100,
        .flags = .{},
        .payload_length = 5,
        .sequence = 1,
    };
    try writer_mod.writeFrame(fbs.writer(), hdr, "hello");

    var read_stream = std.io.fixedBufferStream(fbs.getWritten());
    var payload_buf: [1024]u8 = undefined;
    const frame = try readFrame(read_stream.reader(), &payload_buf);
    try std.testing.expectEqual(@as(u16, 0x0100), frame.header.msg_type);
    try std.testing.expectEqual(@as(u32, 5), frame.header.payload_length);
    try std.testing.expectEqualSlices(u8, "hello", frame.payload);
}

test "readFrame: round-trip with empty payload" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const hdr = header_mod.Header{
        .msg_type = 0x0300,
        .flags = .{ .encoding = .binary },
        .payload_length = 0,
        .sequence = 42,
    };
    try writer_mod.writeFrame(fbs.writer(), hdr, "");

    var read_stream = std.io.fixedBufferStream(fbs.getWritten());
    var payload_buf: [1024]u8 = undefined;
    const frame = try readFrame(read_stream.reader(), &payload_buf);
    try std.testing.expectEqual(@as(u16, 0x0300), frame.header.msg_type);
    try std.testing.expectEqual(@as(u32, 0), frame.header.payload_length);
    try std.testing.expectEqual(@as(usize, 0), frame.payload.len);
}

test "readFrame: multiple frames read back-to-back" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();

    for (0..3) |i| {
        const hdr = header_mod.Header{
            .msg_type = 0x0100,
            .flags = .{},
            .payload_length = 1,
            .sequence = @intCast(i + 1),
        };
        const payload = [_]u8{@intCast('A' + i)};
        try writer_mod.writeFrame(w, hdr, &payload);
    }

    var read_stream = std.io.fixedBufferStream(fbs.getWritten());
    var payload_buf: [1024]u8 = undefined;
    const r = read_stream.reader();

    for (0..3) |i| {
        const frame = try readFrame(r, &payload_buf);
        try std.testing.expectEqual(@as(u32, @intCast(i + 1)), frame.header.sequence);
        try std.testing.expectEqual(@as(u8, @intCast('A' + i)), frame.payload[0]);
    }
}

test "readFrame: bad magic returns error" {
    var buf = [_]u8{ 0xFF, 0xFF } ++ ([_]u8{0} ** 14);
    var fbs = std.io.fixedBufferStream(&buf);
    var payload_buf: [1024]u8 = undefined;
    const result = readFrame(fbs.reader(), &payload_buf);
    try std.testing.expectError(error.BadMagic, result);
}

test "readFrame: stream ends mid-header" {
    // Only 4 bytes, header needs 16
    var buf = [_]u8{ 0x49, 0x54, 0x01, 0x00 };
    var fbs = std.io.fixedBufferStream(&buf);
    var payload_buf: [1024]u8 = undefined;
    const result = readFrame(fbs.reader(), &payload_buf);
    try std.testing.expectError(error.EndOfStream, result);
}

test "readFrame: stream ends mid-payload" {
    // Write a valid header claiming 100 bytes, but only 2 bytes of payload follow
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const hdr = header_mod.Header{
        .msg_type = 0x0100,
        .flags = .{},
        .payload_length = 100,
        .sequence = 1,
    };
    var hdr_buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&hdr_buf);
    fbs.writer().writeAll(&hdr_buf) catch unreachable;
    fbs.writer().writeAll("ab") catch unreachable; // Only 2 bytes, claimed 100

    var read_stream = std.io.fixedBufferStream(fbs.getWritten());
    var payload_buf: [1024]u8 = undefined;
    const result = readFrame(read_stream.reader(), &payload_buf);
    try std.testing.expectError(error.EndOfStream, result);
}

test "SequenceTracker: starts at 1" {
    var tracker = SequenceTracker{};
    try std.testing.expectEqual(@as(u32, 1), tracker.advance());
    try std.testing.expectEqual(@as(u32, 2), tracker.advance());
}

test "SequenceTracker: wraps from max to 1" {
    var tracker = SequenceTracker{ .next = 0xFFFFFFFF };
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), tracker.advance());
    try std.testing.expectEqual(@as(u32, 1), tracker.advance());
}

test "SequenceTracker: never produces 0" {
    var tracker = SequenceTracker{ .next = 0xFFFFFFFE };
    _ = tracker.advance(); // 0xFFFFFFFE
    const at_max = tracker.advance(); // 0xFFFFFFFF
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), at_max);
    const wrapped = tracker.advance(); // should be 1, not 0
    try std.testing.expectEqual(@as(u32, 1), wrapped);
}

test "MessageReader: starts empty" {
    var reader = MessageReader{};
    try std.testing.expectEqual(@as(u16, 0), reader.length);
    try std.testing.expect(reader.nextMessage() == null);
}

test "MessageReader: feed and extract complete frame" {
    var reader = MessageReader{};

    // Build a valid frame: header + payload.
    var frame_buf: [header_mod.HEADER_SIZE + 5]u8 = undefined;
    const hdr = header_mod.Header{
        .msg_type = 0x0100,
        .flags = .{},
        .payload_length = 5,
        .sequence = 1,
    };
    hdr.encode(frame_buf[0..header_mod.HEADER_SIZE]);
    @memcpy(frame_buf[header_mod.HEADER_SIZE..], "hello");

    _ = reader.feed(&frame_buf);
    const msg = reader.nextMessage();
    try std.testing.expect(msg != null);
    try std.testing.expectEqual(@as(u16, 0x0100), msg.?.header.msg_type);
    try std.testing.expectEqual(@as(u32, 5), msg.?.header.payload_length);
    // After extraction, buffer should be empty.
    try std.testing.expectEqual(@as(u16, 0), reader.length);
}

test "MessageReader: partial header returns null" {
    var reader = MessageReader{};
    // Feed only 8 bytes of a 16-byte header.
    const partial = [_]u8{ 0x49, 0x54, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00 };
    _ = reader.feed(&partial);
    try std.testing.expect(reader.nextMessage() == null);
    try std.testing.expectEqual(@as(u16, 8), reader.length);
}

test "MessageReader: partial payload returns null, completes on second feed" {
    var reader = MessageReader{};

    // Build a header claiming 10 bytes of payload.
    var hdr_buf: [header_mod.HEADER_SIZE]u8 = undefined;
    const hdr = header_mod.Header{
        .msg_type = 0x0200,
        .flags = .{},
        .payload_length = 10,
        .sequence = 1,
    };
    hdr.encode(&hdr_buf);

    // Feed header + only 5 bytes of payload.
    _ = reader.feed(&hdr_buf);
    _ = reader.feed("hello");
    try std.testing.expect(reader.nextMessage() == null);

    // Feed remaining 5 bytes.
    _ = reader.feed("world");
    const msg = reader.nextMessage();
    try std.testing.expect(msg != null);
    try std.testing.expectEqual(@as(u32, 10), msg.?.header.payload_length);
}

test "MessageReader: two frames in one feed" {
    var reader = MessageReader{};

    // Build two complete frames back-to-back.
    var buf: [2 * (header_mod.HEADER_SIZE + 3)]u8 = undefined;
    const hdr1 = header_mod.Header{
        .msg_type = 0x0100,
        .flags = .{},
        .payload_length = 3,
        .sequence = 1,
    };
    hdr1.encode(buf[0..header_mod.HEADER_SIZE]);
    @memcpy(buf[header_mod.HEADER_SIZE..][0..3], "abc");

    const offset2 = header_mod.HEADER_SIZE + 3;
    const hdr2 = header_mod.Header{
        .msg_type = 0x0200,
        .flags = .{},
        .payload_length = 3,
        .sequence = 2,
    };
    hdr2.encode(buf[offset2..][0..header_mod.HEADER_SIZE]);
    @memcpy(buf[offset2 + header_mod.HEADER_SIZE ..][0..3], "xyz");

    _ = reader.feed(&buf);

    const msg1 = reader.nextMessage();
    try std.testing.expect(msg1 != null);
    try std.testing.expectEqual(@as(u16, 0x0100), msg1.?.header.msg_type);

    const msg2 = reader.nextMessage();
    try std.testing.expect(msg2 != null);
    try std.testing.expectEqual(@as(u16, 0x0200), msg2.?.header.msg_type);

    // No more messages.
    try std.testing.expect(reader.nextMessage() == null);
}

test "MessageReader.reset: clears all accumulated data" {
    var reader = MessageReader{};
    _ = reader.feed("partial-data");
    reader.reset();
    try std.testing.expectEqual(@as(u16, 0), reader.length);
    try std.testing.expect(reader.nextMessage() == null);
}
