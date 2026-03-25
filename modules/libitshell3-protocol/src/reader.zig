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
    if (hdr.payload_len > payload_buf.len)
        return error.PayloadTooLarge;
    const payload = payload_buf[0..hdr.payload_len];
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

// --- Tests ---

const writer_mod = @import("writer.zig");

test "readFrame/writeFrame round-trip (JSON message)" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const hdr = header_mod.Header{
        .msg_type = 0x0100,
        .flags = .{},
        .payload_len = 5,
        .sequence = 1,
    };
    try writer_mod.writeFrame(fbs.writer(), hdr, "hello");

    var read_stream = std.io.fixedBufferStream(fbs.getWritten());
    var payload_buf: [1024]u8 = undefined;
    const frame = try readFrame(read_stream.reader(), &payload_buf);
    try std.testing.expectEqual(@as(u16, 0x0100), frame.header.msg_type);
    try std.testing.expectEqual(@as(u32, 5), frame.header.payload_len);
    try std.testing.expectEqualSlices(u8, "hello", frame.payload);
}

test "readFrame/writeFrame round-trip (empty payload)" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const hdr = header_mod.Header{
        .msg_type = 0x0300,
        .flags = .{ .encoding = .binary },
        .payload_len = 0,
        .sequence = 42,
    };
    try writer_mod.writeFrame(fbs.writer(), hdr, "");

    var read_stream = std.io.fixedBufferStream(fbs.getWritten());
    var payload_buf: [1024]u8 = undefined;
    const frame = try readFrame(read_stream.reader(), &payload_buf);
    try std.testing.expectEqual(@as(u16, 0x0300), frame.header.msg_type);
    try std.testing.expectEqual(@as(u32, 0), frame.header.payload_len);
    try std.testing.expectEqual(@as(usize, 0), frame.payload.len);
}

test "Multiple frames written and read back-to-back" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();

    for (0..3) |i| {
        const hdr = header_mod.Header{
            .msg_type = 0x0100,
            .flags = .{},
            .payload_len = 1,
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

test "Read from stream with bad magic" {
    var buf = [_]u8{ 0xFF, 0xFF } ++ ([_]u8{0} ** 14);
    var fbs = std.io.fixedBufferStream(&buf);
    var payload_buf: [1024]u8 = undefined;
    const result = readFrame(fbs.reader(), &payload_buf);
    try std.testing.expectError(error.BadMagic, result);
}

test "Read from stream that ends mid-header" {
    // Only 4 bytes, header needs 16
    var buf = [_]u8{ 0x49, 0x54, 0x01, 0x00 };
    var fbs = std.io.fixedBufferStream(&buf);
    var payload_buf: [1024]u8 = undefined;
    const result = readFrame(fbs.reader(), &payload_buf);
    try std.testing.expectError(error.EndOfStream, result);
}

test "Read from stream that ends mid-payload" {
    // Write a valid header claiming 100 bytes, but only 2 bytes of payload follow
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const hdr = header_mod.Header{
        .msg_type = 0x0100,
        .flags = .{},
        .payload_len = 100,
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

test "SequenceTracker starts at 1" {
    var tracker = SequenceTracker{};
    try std.testing.expectEqual(@as(u32, 1), tracker.advance());
    try std.testing.expectEqual(@as(u32, 2), tracker.advance());
}

test "SequenceTracker wraps from max to 1" {
    var tracker = SequenceTracker{ .next = 0xFFFFFFFF };
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), tracker.advance());
    try std.testing.expectEqual(@as(u32, 1), tracker.advance());
}

test "SequenceTracker never produces 0" {
    var tracker = SequenceTracker{ .next = 0xFFFFFFFE };
    _ = tracker.advance(); // 0xFFFFFFFE
    const at_max = tracker.advance(); // 0xFFFFFFFF
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), at_max);
    const wrapped = tracker.advance(); // should be 1, not 0
    try std.testing.expectEqual(@as(u32, 1), wrapped);
}
