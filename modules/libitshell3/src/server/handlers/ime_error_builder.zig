//! Builds JSON payloads for IME error responses (0x04FF), wrapped with
//! protocol headers. All builders use fixed-size scratch buffers.
//!
//! Per protocol 05-cjk-preedit-protocol (IMEError).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const envelope = @import("protocol_envelope.zig");
const core = @import("itshell3_core");
const types = core.types;

/// Scratch buffer type alias for message building.
pub const ScratchBuf = envelope.ScratchBuf;

/// Maximum size for IME error JSON payloads.
const MAX_IME_ERROR_JSON: usize = 512;

/// Error codes per protocol 05-cjk-preedit-protocol.
pub const ErrorCode = enum(u16) {
    unknown_input_method = 0x0001,
    pane_not_found = 0x0002,
    invalid_composition_state = 0x0003,
    preedit_session_id_mismatch = 0x0004,
    utf8_encoding_error = 0x0005,
    input_method_not_supported = 0x0006,
};

// ── IMEError (0x04FF) ──────────────────────────────────────────────────────

/// Builds an IMEError response (S->C). Accepts a typed ErrorCode and
/// converts to the wire u16 internally.
pub fn buildIMEError(
    pane_id: types.PaneId,
    error_code: ErrorCode,
    detail: []const u8,
    sequence: u64,
    out_buf: *ScratchBuf,
) ?[]const u8 {
    var json_buf: [MAX_IME_ERROR_JSON]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"pane_id\":{d},\"error_code\":{d},\"detail\":\"{s}\"}}", .{
        pane_id,
        @intFromEnum(error_code),
        detail,
    }) catch return null;

    return envelope.wrapResponse(
        out_buf,
        @intFromEnum(MessageType.ime_error),
        sequence,
        json,
    );
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "buildIMEError: unknown input method error" {
    var buf: ScratchBuf = undefined;
    const result = buildIMEError(1, .unknown_input_method, "Unknown input method: foobar", 5, &buf);
    try std.testing.expect(result != null);
    const data = result.?;
    const header = try protocol.header.Header.decode(data[0..protocol.header.HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, @intFromEnum(MessageType.ime_error)), header.msg_type);
    try std.testing.expect(header.flags.response);
    const payload = data[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"pane_id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"error_code\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "Unknown input method") != null);
}

test "buildIMEError: pane not found error" {
    var buf: ScratchBuf = undefined;
    const result = buildIMEError(99, .pane_not_found, "Pane does not exist", 6, &buf);
    try std.testing.expect(result != null);
    const data = result.?;
    const header = try protocol.header.Header.decode(data[0..protocol.header.HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, @intFromEnum(MessageType.ime_error)), header.msg_type);
    const payload = data[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"pane_id\":99") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"error_code\":2") != null);
}
