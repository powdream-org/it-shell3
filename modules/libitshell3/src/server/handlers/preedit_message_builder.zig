//! Builds JSON payloads for preedit lifecycle messages (0x0400-0x0403),
//! wrapped with protocol headers. All builders use fixed-size scratch buffers.
//!
//! Per protocol 05-cjk-preedit-protocol (PreeditStart, PreeditUpdate,
//! PreeditEnd, PreeditSync).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const envelope = @import("protocol_envelope.zig");
const core = @import("itshell3_core");
const types = core.types;

/// Scratch buffer type alias for preedit message building.
pub const ScratchBuf = envelope.ScratchBuf;

/// Maximum size for preedit JSON payloads.
const MAX_PREEDIT_JSON: usize = 1024;

// ── PreeditStart (0x0400) ──────────────────────────────────────────────────

/// Builds a PreeditStart notification (S->C, broadcast).
pub fn buildPreeditStart(
    pane_id: types.PaneId,
    client_id: types.ClientId,
    active_input_method: []const u8,
    preedit_session_id: u32,
    sequence: u64,
    out_buf: *ScratchBuf,
) ?[]const u8 {
    var json_buf: [MAX_PREEDIT_JSON]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"pane_id\":{d},\"client_id\":{d},\"active_input_method\":\"{s}\",\"preedit_session_id\":{d}}}", .{
        pane_id,
        client_id,
        active_input_method,
        preedit_session_id,
    }) catch return null;

    return envelope.wrapNotification(
        out_buf,
        @intFromEnum(MessageType.preedit_start),
        sequence,
        json,
    );
}

// ── PreeditUpdate (0x0401) ─────────────────────────────────────────────────

/// Builds a PreeditUpdate notification (S->C, broadcast).
pub fn buildPreeditUpdate(
    pane_id: types.PaneId,
    preedit_session_id: u32,
    text: []const u8,
    sequence: u64,
    out_buf: *ScratchBuf,
) ?[]const u8 {
    var json_buf: [MAX_PREEDIT_JSON]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"pane_id\":{d},\"preedit_session_id\":{d},\"text\":\"{s}\"}}", .{
        pane_id,
        preedit_session_id,
        text,
    }) catch return null;

    return envelope.wrapNotification(
        out_buf,
        @intFromEnum(MessageType.preedit_update),
        sequence,
        json,
    );
}

// ── PreeditEnd (0x0402) ────────────────────────────────────────────────────

/// Builds a PreeditEnd notification (S->C, broadcast).
pub fn buildPreeditEnd(
    pane_id: types.PaneId,
    preedit_session_id: u32,
    reason: []const u8,
    committed_text: []const u8,
    sequence: u64,
    out_buf: *ScratchBuf,
) ?[]const u8 {
    var json_buf: [MAX_PREEDIT_JSON]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"pane_id\":{d},\"preedit_session_id\":{d},\"reason\":\"{s}\",\"committed_text\":\"{s}\"}}", .{
        pane_id,
        preedit_session_id,
        reason,
        committed_text,
    }) catch return null;

    return envelope.wrapNotification(
        out_buf,
        @intFromEnum(MessageType.preedit_end),
        sequence,
        json,
    );
}

// ── PreeditSync (0x0403) ───────────────────────────────────────────────────

/// Builds a PreeditSync notification (S->C, unicast to late-joining client).
pub fn buildPreeditSync(
    pane_id: types.PaneId,
    preedit_session_id: u32,
    preedit_owner: types.ClientId,
    active_input_method: []const u8,
    text: []const u8,
    sequence: u64,
    out_buf: *ScratchBuf,
) ?[]const u8 {
    var json_buf: [MAX_PREEDIT_JSON]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"pane_id\":{d},\"preedit_session_id\":{d},\"preedit_owner\":{d},\"active_input_method\":\"{s}\",\"text\":\"{s}\"}}", .{
        pane_id,
        preedit_session_id,
        preedit_owner,
        active_input_method,
        text,
    }) catch return null;

    return envelope.wrapNotification(
        out_buf,
        @intFromEnum(MessageType.preedit_sync),
        sequence,
        json,
    );
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "buildPreeditStart: produces valid envelope with correct fields" {
    var buf: ScratchBuf = undefined;
    const result = buildPreeditStart(1, 7, "korean_2set", 42, 5, &buf);
    try std.testing.expect(result != null);
    const data = result.?;
    const header = try protocol.header.Header.decode(data[0..protocol.header.HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, @intFromEnum(MessageType.preedit_start)), header.msg_type);
    try std.testing.expect(!header.flags.response);
    const payload = data[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"pane_id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"client_id\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"active_input_method\":\"korean_2set\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"preedit_session_id\":42") != null);
}

test "buildPreeditUpdate: produces valid envelope with text field" {
    var buf: ScratchBuf = undefined;
    const result = buildPreeditUpdate(1, 42, "\xed\x95\x9c", 6, &buf);
    try std.testing.expect(result != null);
    const data = result.?;
    const header = try protocol.header.Header.decode(data[0..protocol.header.HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, @intFromEnum(MessageType.preedit_update)), header.msg_type);
    const payload = data[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"pane_id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"preedit_session_id\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"text\":\"") != null);
}

test "buildPreeditEnd: produces valid envelope with reason and committed_text" {
    var buf: ScratchBuf = undefined;
    const result = buildPreeditEnd(1, 42, "committed", "\xed\x95\x9c", 7, &buf);
    try std.testing.expect(result != null);
    const data = result.?;
    const header = try protocol.header.Header.decode(data[0..protocol.header.HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, @intFromEnum(MessageType.preedit_end)), header.msg_type);
    const payload = data[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"reason\":\"committed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"committed_text\":\"") != null);
}

test "buildPreeditEnd: cancelled reason with empty committed_text" {
    var buf: ScratchBuf = undefined;
    const result = buildPreeditEnd(2, 10, "cancelled", "", 8, &buf);
    try std.testing.expect(result != null);
    const payload = result.?[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"reason\":\"cancelled\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"committed_text\":\"\"") != null);
}

test "buildPreeditSync: produces valid envelope with all fields" {
    var buf: ScratchBuf = undefined;
    const result = buildPreeditSync(1, 42, 7, "korean_2set", "\xed\x95\x9c", 9, &buf);
    try std.testing.expect(result != null);
    const data = result.?;
    const header = try protocol.header.Header.decode(data[0..protocol.header.HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, @intFromEnum(MessageType.preedit_sync)), header.msg_type);
    const payload = data[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"pane_id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"preedit_session_id\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"preedit_owner\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"active_input_method\":\"korean_2set\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"text\":\"") != null);
}
