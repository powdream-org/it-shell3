//! 20-byte fixed protocol header: magic (0x4954) + version + flags +
//! msg_type + reserved + payload_length + sequence. Precedes every message
//! on the wire.

const std = @import("std");

/// Wire size of the protocol header in bytes.
pub const HEADER_SIZE: usize = 20;
/// Two-byte magic identifying an it-shell3 protocol frame ("IT").
pub const MAGIC: [2]u8 = .{ 0x49, 0x54 }; // "IT"
/// Current protocol version.
pub const VERSION: u8 = 2;
/// Maximum allowed payload size (16 MiB).
pub const MAX_PAYLOAD_SIZE: u32 = 16 * 1024 * 1024; // 16 MiB

/// Per-message flag byte packed into the header at offset 3.
pub const Flags = packed struct(u8) {
    encoding: enum(u1) { json = 0, binary = 1 } = .json,
    response: bool = false,
    @"error": bool = false,
    more_fragments: bool = false,
    _reserved: u4 = 0,
};

/// Decoded protocol header. Use `encode`/`decode` for wire conversion.
pub const Header = struct {
    msg_type: u16,
    flags: Flags,
    payload_length: u32,
    sequence: u64,

    pub fn encode(self: Header, buf: *[HEADER_SIZE]u8) void {
        buf[0] = MAGIC[0];
        buf[1] = MAGIC[1];
        buf[2] = VERSION;
        buf[3] = @bitCast(self.flags);
        std.mem.writeInt(u16, buf[4..6], self.msg_type, .little);
        std.mem.writeInt(u16, buf[6..8], 0, .little); // reserved
        std.mem.writeInt(u32, buf[8..12], self.payload_length, .little);
        std.mem.writeInt(u64, buf[12..20], self.sequence, .little);
    }

    pub fn decode(buf: *const [HEADER_SIZE]u8) HeaderError!Header {
        if (buf[0] != MAGIC[0] or buf[1] != MAGIC[1])
            return error.BadMagic;
        if (buf[2] != VERSION)
            return error.UnsupportedVersion;
        const flags: Flags = @bitCast(buf[3]);
        if (flags._reserved != 0)
            return error.ReservedFlagsSet;
        const reserved = std.mem.readInt(u16, buf[6..8], .little);
        if (reserved != 0)
            return error.ReservedFieldNonZero;
        const payload_length = std.mem.readInt(u32, buf[8..12], .little);
        if (payload_length > MAX_PAYLOAD_SIZE)
            return error.PayloadTooLarge;
        return .{
            .msg_type = std.mem.readInt(u16, buf[4..6], .little),
            .flags = flags,
            .payload_length = payload_length,
            .sequence = std.mem.readInt(u64, buf[12..20], .little),
        };
    }
};

/// Errors returned by `Header.decode` when the wire bytes are malformed.
pub const HeaderError = error{
    BadMagic,
    UnsupportedVersion,
    ReservedFlagsSet,
    ReservedFieldNonZero,
    PayloadTooLarge,
};

test "Header: size is 20 bytes" {
    try std.testing.expectEqual(@as(usize, 20), HEADER_SIZE);
}

test "Flags: packed struct is exactly 1 byte" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(Flags));
}

test "Header.encode/Header.decode: round-trip" {
    const original = Header{
        .msg_type = 0x0001,
        .flags = .{ .encoding = .json, .response = false, .@"error" = false, .more_fragments = false },
        .payload_length = 42,
        .sequence = 7,
    };
    var buf: [HEADER_SIZE]u8 = undefined;
    original.encode(&buf);
    const decoded = try Header.decode(&buf);
    try std.testing.expectEqual(original.msg_type, decoded.msg_type);
    try std.testing.expectEqual(original.payload_length, decoded.payload_length);
    try std.testing.expectEqual(original.sequence, decoded.sequence);
    try std.testing.expectEqual(@as(u8, @bitCast(original.flags)), @as(u8, @bitCast(decoded.flags)));
}

test "Header.encode/Header.decode: all flag combinations" {
    const cases = [_]Flags{
        .{ .encoding = .binary },
        .{ .response = true },
        .{ .@"error" = true },
        .{ .more_fragments = true },
        .{ .encoding = .binary, .response = true, .@"error" = true, .more_fragments = true },
    };
    for (cases) |flags| {
        const hdr = Header{ .msg_type = 0x0002, .flags = flags, .payload_length = 0, .sequence = 1 };
        var buf: [HEADER_SIZE]u8 = undefined;
        hdr.encode(&buf);
        const decoded = try Header.decode(&buf);
        try std.testing.expectEqual(@as(u8, @bitCast(flags)), @as(u8, @bitCast(decoded.flags)));
    }
}

test "Header.decode: bad magic" {
    var buf: [HEADER_SIZE]u8 = std.mem.zeroes([HEADER_SIZE]u8);
    buf[0] = 0x00;
    buf[1] = 0x00;
    buf[2] = VERSION;
    try std.testing.expectError(error.BadMagic, Header.decode(&buf));
}

test "Header.decode: unsupported version" {
    var buf: [HEADER_SIZE]u8 = std.mem.zeroes([HEADER_SIZE]u8);
    buf[0] = MAGIC[0];
    buf[1] = MAGIC[1];
    buf[2] = 99; // wrong version
    try std.testing.expectError(error.UnsupportedVersion, Header.decode(&buf));
}

test "Header.decode: reserved flags set" {
    var buf: [HEADER_SIZE]u8 = std.mem.zeroes([HEADER_SIZE]u8);
    buf[0] = MAGIC[0];
    buf[1] = MAGIC[1];
    buf[2] = VERSION;
    buf[3] = 0xF0; // reserved bits 4-7 set
    try std.testing.expectError(error.ReservedFlagsSet, Header.decode(&buf));
}

test "Header.decode: reserved field non-zero" {
    const hdr = Header{ .msg_type = 0x0001, .flags = .{}, .payload_length = 0, .sequence = 1 };
    var buf: [HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    std.mem.writeInt(u16, buf[6..8], 1, .little); // set reserved field
    try std.testing.expectError(error.ReservedFieldNonZero, Header.decode(&buf));
}

test "Header.decode: payload too large" {
    const hdr = Header{ .msg_type = 0x0001, .flags = .{}, .payload_length = MAX_PAYLOAD_SIZE + 1, .sequence = 1 };
    var buf: [HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    // bypass encode's no-validation by writing directly
    std.mem.writeInt(u32, buf[8..12], MAX_PAYLOAD_SIZE + 1, .little);
    try std.testing.expectError(error.PayloadTooLarge, Header.decode(&buf));
}

test "Header.decode: payload exactly at limit" {
    const hdr = Header{ .msg_type = 0x0001, .flags = .{}, .payload_length = MAX_PAYLOAD_SIZE, .sequence = 1 };
    var buf: [HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    const decoded = try Header.decode(&buf);
    try std.testing.expectEqual(MAX_PAYLOAD_SIZE, decoded.payload_length);
}

test "Header.decode: sequence number 0 is valid" {
    const hdr = Header{ .msg_type = 0x0001, .flags = .{}, .payload_length = 0, .sequence = 0 };
    var buf: [HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    const decoded = try Header.decode(&buf);
    try std.testing.expectEqual(@as(u64, 0), decoded.sequence);
}

test "Header.encode/Header.decode: u64 sequence values beyond u32 max" {
    const large_seq: u64 = 0x1_0000_0001; // larger than u32 max
    const hdr = Header{ .msg_type = 0x0001, .flags = .{}, .payload_length = 0, .sequence = large_seq };
    var buf: [HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    const decoded = try Header.decode(&buf);
    try std.testing.expectEqual(large_seq, decoded.sequence);
}

test "Header.decode: version check uses VERSION=2" {
    var buf: [HEADER_SIZE]u8 = std.mem.zeroes([HEADER_SIZE]u8);
    buf[0] = MAGIC[0];
    buf[1] = MAGIC[1];
    buf[2] = 1; // old version
    try std.testing.expectError(error.UnsupportedVersion, Header.decode(&buf));
}
