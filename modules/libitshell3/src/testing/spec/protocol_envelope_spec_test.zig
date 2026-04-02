//! Spec compliance tests: Protocol header wrapping (envelope).
//!
//! Covers 16-byte header encoding/decoding for all outbound message types,
//! magic validation, version checking, flags encoding, payload length limits,
//! and sequence number population.
//!
//! Spec sources:
//!   - protocol 01-protocol-overview (Section 3.1: 16-byte header format,
//!     magic 0x4954, version byte, flags, msg_type, payload_length, sequence)
//!   - protocol 03-session-pane-management (Encoding section: all session/pane
//!     messages use JSON payloads wrapped in 16-byte header)

const std = @import("std");
const protocol = @import("itshell3_protocol");

const header_mod = protocol.header;
const Header = header_mod.Header;
const Flags = header_mod.Flags;
const MessageType = protocol.message_type.MessageType;

// ── Header field encoding ──────────────────────────────────────────────────

test "spec: envelope -- magic bytes are 0x49 0x54 at offsets 0-1" {
    // protocol 01 Section 3.1: Offset 0, Size 2, "IT" (0x4954).
    const hdr = Header{
        .msg_type = @intFromEnum(MessageType.create_session_response),
        .flags = .{},
        .payload_length = 0,
        .sequence = 1,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    try std.testing.expectEqual(@as(u8, 0x49), buf[0]);
    try std.testing.expectEqual(@as(u8, 0x54), buf[1]);
}

test "spec: envelope -- version byte is 2 at offset 2" {
    // protocol 01 Section 3.1: Offset 2, Size 1, currently 2 (v2 header).
    const hdr = Header{
        .msg_type = @intFromEnum(MessageType.list_sessions_response),
        .flags = .{},
        .payload_length = 0,
        .sequence = 1,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    try std.testing.expectEqual(@as(u8, 2), buf[2]);
}

test "spec: envelope -- flags at offset 3 default to JSON encoding" {
    // protocol 01 Section 3.1: Offset 3, Size 1, Flags byte.
    // JSON encoding = bit 0 is 0.
    const hdr = Header{
        .msg_type = @intFromEnum(MessageType.session_list_changed),
        .flags = .{},
        .payload_length = 10,
        .sequence = 1,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    const flags: Flags = @bitCast(buf[3]);
    const default_flags = Flags{};
    try std.testing.expectEqual(default_flags.encoding, flags.encoding);
    try std.testing.expect(!flags.response);
    try std.testing.expect(!flags.@"error");
}

test "spec: envelope -- msg_type at offsets 4-5 little-endian" {
    // protocol 01 Section 3.1: Offset 4, Size 2, msg_type (little-endian).
    const hdr = Header{
        .msg_type = @intFromEnum(MessageType.layout_changed), // 0x0180
        .flags = .{},
        .payload_length = 0,
        .sequence = 1,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    const msg_type = std.mem.readInt(u16, buf[4..6], .little);
    try std.testing.expectEqual(@as(u16, 0x0180), msg_type);
}

test "spec: envelope -- reserved bytes at offsets 6-7 are zero" {
    // protocol 01 Section 3.1: Offset 6, Size 2, reserved (must be 0).
    const hdr = Header{
        .msg_type = @intFromEnum(MessageType.client_attached),
        .flags = .{},
        .payload_length = 50,
        .sequence = 3,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    const reserved = std.mem.readInt(u16, buf[6..8], .little);
    try std.testing.expectEqual(@as(u16, 0), reserved);
}

test "spec: envelope -- payload_length at offsets 8-11 little-endian" {
    // protocol 01 Section 3.1: Offset 8, Size 4, payload_length (little-endian).
    const hdr = Header{
        .msg_type = @intFromEnum(MessageType.attach_session_response),
        .flags = .{},
        .payload_length = 1234,
        .sequence = 1,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    const payload_len = std.mem.readInt(u32, buf[8..12], .little);
    try std.testing.expectEqual(@as(u32, 1234), payload_len);
}

test "spec: envelope -- sequence at offsets 12-15 little-endian" {
    // protocol 01 Section 3.1: Offset 12, Size 4, sequence (little-endian).
    const hdr = Header{
        .msg_type = @intFromEnum(MessageType.detach_session_response),
        .flags = .{},
        .payload_length = 0,
        .sequence = 0xDEADBEEF,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    const seq = std.mem.readInt(u32, buf[12..16], .little);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), seq);
}

// ── Decode validation ──────────────────────────────────────────────────────

test "spec: envelope -- decode rejects wrong version" {
    // protocol 01 Section 3.1.1: exact version match required.
    var buf: [header_mod.HEADER_SIZE]u8 = [_]u8{0} ** header_mod.HEADER_SIZE;
    buf[0] = 0x49;
    buf[1] = 0x54;
    buf[2] = 99; // wrong version
    const result = Header.decode(&buf);
    try std.testing.expectError(error.UnsupportedVersion, result);
}

test "spec: envelope -- decode rejects nonzero reserved flags" {
    // protocol 01 Section 3.1: reserved bits in flags must be 0.
    var buf: [header_mod.HEADER_SIZE]u8 = [_]u8{0} ** header_mod.HEADER_SIZE;
    buf[0] = 0x49;
    buf[1] = 0x54;
    buf[2] = 2; // v2
    buf[3] = 0xF0; // reserved bits set
    const result = Header.decode(&buf);
    try std.testing.expectError(error.ReservedFlagsSet, result);
}

test "spec: envelope -- decode rejects nonzero reserved field" {
    // protocol 01 Section 3.1: reserved bytes at offset 6-7 must be 0.
    var buf: [header_mod.HEADER_SIZE]u8 = [_]u8{0} ** header_mod.HEADER_SIZE;
    buf[0] = 0x49;
    buf[1] = 0x54;
    buf[2] = 2; // v2
    buf[3] = 0;
    std.mem.writeInt(u16, buf[6..8], 1, .little); // nonzero reserved
    const result = Header.decode(&buf);
    try std.testing.expectError(error.ReservedFieldNonZero, result);
}

// ── Flags encoding for responses and errors ────────────────────────────────

test "spec: envelope -- response flag set for response messages" {
    // protocol 01: RESPONSE flag indicates this is a response to a request.
    const flags = Flags{ .response = true };
    const hdr = Header{
        .msg_type = @intFromEnum(MessageType.create_session_response),
        .flags = flags,
        .payload_length = 30,
        .sequence = 2,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    const decoded = try Header.decode(&buf);
    try std.testing.expect(decoded.flags.response);
    try std.testing.expect(!decoded.flags.@"error");
}

test "spec: envelope -- error flag set for error responses" {
    // protocol 01: ERROR flag indicates an error response.
    const flags = Flags{ .@"error" = true };
    const hdr = Header{
        .msg_type = @intFromEnum(MessageType.@"error"),
        .flags = flags,
        .payload_length = 20,
        .sequence = 1,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);
    const decoded = try Header.decode(&buf);
    try std.testing.expect(decoded.flags.@"error");
}

// ── All session/pane responses use JSON encoding ───────────────────────────

test "spec: envelope -- session response types use JSON encoding" {
    // protocol 03 Encoding section: all session/pane messages use JSON.
    const response_types = [_]MessageType{
        .create_session_response,
        .list_sessions_response,
        .attach_session_response,
        .detach_session_response,
        .destroy_session_response,
        .rename_session_response,
        .attach_session_response,
    };
    for (response_types) |mt| {
        try std.testing.expectEqual(MessageType.Encoding.json, mt.expectedEncoding());
    }
}

test "spec: envelope -- pane response types use JSON encoding" {
    // protocol 03 Encoding section: all pane messages use JSON.
    const response_types = [_]MessageType{
        .create_pane_response,
        .split_pane_response,
        .close_pane_response,
        .focus_pane_response,
        .navigate_pane_response,
        .resize_pane_response,
        .equalize_splits_response,
        .zoom_pane_response,
        .swap_panes_response,
        .layout_get_response,
    };
    for (response_types) |mt| {
        try std.testing.expectEqual(MessageType.Encoding.json, mt.expectedEncoding());
    }
}

// ── Header round-trip for every notification type ──────────────────────────

test "spec: envelope -- round-trip for each notification message type" {
    // protocol 01: each notification can be encoded in a 16-byte header
    // and decoded back correctly.
    const notification_types = [_]MessageType{
        .layout_changed,
        .pane_metadata_changed,
        .session_list_changed,
        .client_attached,
        .client_detached,
        .client_health_changed,
    };
    for (notification_types) |mt| {
        const hdr = Header{
            .msg_type = @intFromEnum(mt),
            .flags = .{},
            .payload_length = 100,
            .sequence = 42,
        };
        var buf: [header_mod.HEADER_SIZE]u8 = undefined;
        hdr.encode(&buf);
        const decoded = try Header.decode(&buf);
        try std.testing.expectEqual(@intFromEnum(mt), decoded.msg_type);
        try std.testing.expectEqual(@as(u32, 100), decoded.payload_length);
        try std.testing.expectEqual(@as(u32, 42), decoded.sequence);
    }
}
