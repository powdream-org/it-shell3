const std = @import("std");
const header_mod = @import("header.zig");

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

// ── Tests ────────────────────────────────────────────────────────────────────

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
