//! Builds JSON payloads for input method messages, wrapped with protocol
//! headers. All builders use fixed-size scratch buffers.
//!
//! Per protocol 05-cjk-preedit-protocol (InputMethodAck 0x0405).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const envelope = @import("protocol_envelope.zig");
const core = @import("itshell3_core");
const types = core.types;

/// Scratch buffer type for message building.
pub const ScratchBuf = [envelope.MAX_ENVELOPE_SIZE]u8;

/// Maximum size for input method JSON payloads.
const MAX_INPUT_METHOD_JSON: usize = 512;

// ── InputMethodAck (0x0405) ────────────────────────────────────────────────

/// Builds an InputMethodAck notification (S->C, broadcast).
pub fn buildInputMethodAck(
    pane_id: types.PaneId,
    active_input_method: []const u8,
    previous_input_method: []const u8,
    active_keyboard_layout: []const u8,
    sequence: u64,
    out_buf: *ScratchBuf,
) ?[]const u8 {
    var json_buf: [MAX_INPUT_METHOD_JSON]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"pane_id\":{d},\"active_input_method\":\"{s}\",\"previous_input_method\":\"{s}\",\"active_keyboard_layout\":\"{s}\"}}", .{
        pane_id,
        active_input_method,
        previous_input_method,
        active_keyboard_layout,
    }) catch return null;

    return envelope.wrapNotification(
        out_buf,
        @intFromEnum(MessageType.input_method_ack),
        sequence,
        json,
    );
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "buildInputMethodAck: produces valid envelope with correct fields" {
    var buf: ScratchBuf = undefined;
    const result = buildInputMethodAck(1, "korean_2set", "direct", "qwerty", 10, &buf);
    try std.testing.expect(result != null);
    const data = result.?;
    const header = try protocol.header.Header.decode(data[0..protocol.header.HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, @intFromEnum(MessageType.input_method_ack)), header.msg_type);
    try std.testing.expect(!header.flags.response);
    const payload = data[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"pane_id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"active_input_method\":\"korean_2set\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"previous_input_method\":\"direct\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"active_keyboard_layout\":\"qwerty\"") != null);
}

test "buildInputMethodAck: switching from korean to direct" {
    var buf: ScratchBuf = undefined;
    const result = buildInputMethodAck(5, "direct", "korean_2set", "qwerty", 20, &buf);
    try std.testing.expect(result != null);
    const payload = result.?[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"active_input_method\":\"direct\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"previous_input_method\":\"korean_2set\"") != null);
}
