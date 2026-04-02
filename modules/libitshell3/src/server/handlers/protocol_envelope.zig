//! Wraps JSON payloads with the 20-byte protocol header for outbound messages.
//! Used by all handler modules to produce correctly framed wire messages.
//!
//! Per protocol 01-protocol-overview (20-byte header: magic 0x4954 + version +
//! flags + msg_type + reserved + payload_length + sequence).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const Header = protocol.header.Header;
const Flags = protocol.header.Flags;
const HEADER_SIZE = protocol.header.HEADER_SIZE;

/// Maximum size of a JSON payload that can be wrapped. Sized to fit the largest
/// notification (LayoutChanged with a full 16-pane tree).
pub const MAX_ENVELOPE_PAYLOAD: usize = 8192;

/// Total buffer size: header + max payload.
pub const MAX_ENVELOPE_SIZE: usize = HEADER_SIZE + MAX_ENVELOPE_PAYLOAD;

/// Scratch buffer type for message building. Shared by all builder modules.
pub const ScratchBuf = [MAX_ENVELOPE_SIZE]u8;

/// Wraps a JSON payload with a 20-byte protocol header. Returns the total
/// number of bytes written (header + payload) into `out_buf`, or null if the
/// payload exceeds MAX_ENVELOPE_PAYLOAD.
pub fn wrap(
    out_buf: []u8,
    msg_type: u16,
    flags: Flags,
    sequence: u64,
    payload: []const u8,
) ?[]const u8 {
    const total = HEADER_SIZE + payload.len;
    if (payload.len > MAX_ENVELOPE_PAYLOAD) return null;
    if (out_buf.len < total) return null;

    const header = Header{
        .msg_type = msg_type,
        .flags = flags,
        .payload_length = @intCast(payload.len),
        .sequence = sequence,
    };
    header.encode(out_buf[0..HEADER_SIZE]);
    @memcpy(out_buf[HEADER_SIZE..total], payload);
    return out_buf[0..total];
}

/// Wraps a JSON payload as a response (RESPONSE flag set). Convenience for
/// request/response patterns where the sequence number echoes the request.
pub fn wrapResponse(
    out_buf: []u8,
    msg_type: u16,
    sequence: u64,
    payload: []const u8,
) ?[]const u8 {
    return wrap(out_buf, msg_type, .{ .response = true }, sequence, payload);
}

/// Wraps a JSON payload as a notification (no RESPONSE flag, server sequence).
pub fn wrapNotification(
    out_buf: []u8,
    msg_type: u16,
    sequence: u64,
    payload: []const u8,
) ?[]const u8 {
    return wrap(out_buf, msg_type, .{}, sequence, payload);
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "wrap: produces correct header and payload" {
    var buf: [MAX_ENVELOPE_SIZE]u8 = undefined;
    const payload = "{\"status\":0}";
    const result = wrap(&buf, 0x0101, .{ .response = true }, 42, payload);
    try std.testing.expect(result != null);
    const data = result.?;
    try std.testing.expectEqual(HEADER_SIZE + payload.len, data.len);

    // Decode the header to verify.
    const decoded = try Header.decode(data[0..HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, 0x0101), decoded.msg_type);
    try std.testing.expect(decoded.flags.response);
    try std.testing.expectEqual(@as(u32, @intCast(payload.len)), decoded.payload_length);
    try std.testing.expectEqual(@as(u64, 42), decoded.sequence);

    // Verify payload bytes.
    try std.testing.expectEqualSlices(u8, payload, data[HEADER_SIZE..]);
}

test "wrap: returns null for oversized payload" {
    var buf: [MAX_ENVELOPE_SIZE]u8 = undefined;
    const big = [_]u8{0} ** (MAX_ENVELOPE_PAYLOAD + 1);
    const result = wrap(&buf, 0x0101, .{}, 1, &big);
    try std.testing.expect(result == null);
}

test "wrap: returns null for undersized output buffer" {
    var buf: [10]u8 = undefined;
    const result = wrap(&buf, 0x0101, .{}, 1, "hello");
    try std.testing.expect(result == null);
}

test "wrapResponse: sets RESPONSE flag" {
    var buf: [MAX_ENVELOPE_SIZE]u8 = undefined;
    const result = wrapResponse(&buf, 0x0101, 5, "{}");
    try std.testing.expect(result != null);
    const decoded = try Header.decode(result.?[0..HEADER_SIZE]);
    try std.testing.expect(decoded.flags.response);
}

test "wrapNotification: does not set RESPONSE flag" {
    var buf: [MAX_ENVELOPE_SIZE]u8 = undefined;
    const result = wrapNotification(&buf, 0x0180, 10, "{}");
    try std.testing.expect(result != null);
    const decoded = try Header.decode(result.?[0..HEADER_SIZE]);
    try std.testing.expect(!decoded.flags.response);
}

test "wrap: empty payload produces header-only message" {
    var buf: [HEADER_SIZE]u8 = undefined;
    const result = wrap(&buf, 0x0003, .{}, 1, "");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(HEADER_SIZE, result.?.len);
    const decoded = try Header.decode(result.?[0..HEADER_SIZE]);
    try std.testing.expectEqual(@as(u32, 0), decoded.payload_length);
}
