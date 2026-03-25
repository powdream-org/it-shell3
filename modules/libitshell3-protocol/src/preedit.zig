const std = @import("std");
const json_mod = @import("json.zig");

/// PreeditStart (0x0400, S->C)
pub const PreeditStart = struct {
    pane_id: u32,
    client_id: u32,
    active_input_method: []const u8,
    preedit_session_id: u32,
};

/// PreeditUpdate (0x0401, S->C)
pub const PreeditUpdate = struct {
    pane_id: u32,
    preedit_session_id: u32,
    text: []const u8,
};

/// PreeditEnd (0x0402, S->C)
pub const PreeditEnd = struct {
    pane_id: u32,
    preedit_session_id: u32,
    reason: []const u8, // "committed", "cancelled", "pane_closed", etc.
    committed_text: []const u8 = "",
};

/// PreeditSync (0x0403, S->C) — full state snapshot for late-joining client
pub const PreeditSync = struct {
    pane_id: u32,
    preedit_session_id: u32,
    preedit_owner: u32,
    active_input_method: []const u8,
    text: []const u8,
};

/// InputMethodSwitch (0x0404, C->S)
pub const InputMethodSwitch = struct {
    pane_id: u32,
    input_method: []const u8,
    keyboard_layout: ?[]const u8 = null,
    commit_current: bool = true,
};

/// InputMethodAck (0x0405, S->C) — broadcast to all attached clients
pub const InputMethodAck = struct {
    pane_id: u32,
    active_input_method: []const u8,
    previous_input_method: []const u8,
    active_keyboard_layout: []const u8,
};

/// AmbiguousWidthConfig (0x0406, C->S or S->C)
pub const AmbiguousWidthConfig = struct {
    pane_id: u32,
    ambiguous_width: u8 = 1, // 1=single-width, 2=double-width
    scope: []const u8 = "per_pane", // "per_pane", "per_session", "global"
};

/// IMEError (0x04FF, S->C)
pub const IMEError = struct {
    pane_id: u32,
    error_code: u32,
    detail: []const u8 = "",
};

test "PreeditStart JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = PreeditStart{
        .pane_id = 1,
        .client_id = 7,
        .active_input_method = "korean_2set",
        .preedit_session_id = 42,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(PreeditStart, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("korean_2set", parsed.value.active_input_method);
    try std.testing.expectEqual(@as(u32, 42), parsed.value.preedit_session_id);
}

test "PreeditEnd committed_text round-trip" {
    const allocator = std.testing.allocator;
    const original = PreeditEnd{ .pane_id = 1, .preedit_session_id = 42, .reason = "committed", .committed_text = "\xed\x95\x9c" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(PreeditEnd, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("committed", parsed.value.reason);
    try std.testing.expectEqualStrings("\xed\x95\x9c", parsed.value.committed_text);
}

test "PreeditEnd committed_text empty when cancelled" {
    const allocator = std.testing.allocator;
    const original = PreeditEnd{ .pane_id = 1, .preedit_session_id = 1, .reason = "cancelled" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    // committed_text is always present (empty string for cancelled)
    try std.testing.expect(std.mem.indexOf(u8, j, "committed_text") != null);
    const parsed = try json_mod.decode(PreeditEnd, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("", parsed.value.committed_text);
}

test "InputMethodSwitch optional keyboard_layout" {
    const allocator = std.testing.allocator;
    const original = InputMethodSwitch{ .pane_id = 1, .input_method = "korean_2set" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    try std.testing.expect(std.mem.indexOf(u8, j, "keyboard_layout") == null);
}

test "InputMethodAck JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = InputMethodAck{
        .pane_id = 1,
        .active_input_method = "korean_2set",
        .previous_input_method = "direct",
        .active_keyboard_layout = "qwerty",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(InputMethodAck, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("direct", parsed.value.previous_input_method);
}
