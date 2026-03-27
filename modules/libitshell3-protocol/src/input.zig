const std = @import("std");
const json_mod = @import("json.zig");

/// Modifier bitflags (u8)
pub const Modifiers = struct {
    pub const shift: u8 = 1 << 0;
    pub const ctrl: u8 = 1 << 1;
    pub const alt: u8 = 1 << 2;
    pub const super: u8 = 1 << 3;
    pub const caps_lock: u8 = 1 << 4;
    pub const num_lock: u8 = 1 << 5;
};

/// Key action values
pub const Action = struct {
    pub const press: u8 = 0;
    pub const release: u8 = 1;
    pub const repeat: u8 = 2;
};

/// KeyEvent (0x0200, C->S)
pub const KeyEvent = struct {
    keycode: u16,
    action: u8, // 0=press, 1=release, 2=repeat
    modifiers: u8, // bitflags
    input_method: []const u8 = "direct",
    pane_id: ?u32 = null,
};

/// TextInput (0x0201, C->S)
pub const TextInput = struct {
    pane_id: u32,
    text: []const u8,
};

/// MouseButton (0x0202, C->S)
pub const MouseButton = struct {
    pane_id: u32,
    button: u8, // 0=left, 1=middle, 2=right, 3-7=extra
    action: u8, // 0=press, 1=release
    modifiers: u8,
    click_count: u8 = 1,
    x: f32 = 0.0,
    y: f32 = 0.0,
};

/// MouseMove (0x0203, C->S)
pub const MouseMove = struct {
    pane_id: u32,
    modifiers: u8,
    buttons_held: u8, // bitflags: bit 0=left, 1=middle, 2=right
    x: f32 = 0.0,
    y: f32 = 0.0,
};

/// MouseScroll (0x0204, C->S)
pub const MouseScroll = struct {
    pane_id: u32,
    modifiers: u8,
    dx: f32 = 0.0,
    dy: f32 = 0.0,
    precise: bool = false,
};

/// PasteData (0x0205, C->S)
pub const PasteData = struct {
    pane_id: u32,
    bracketed_paste: bool = true,
    first_chunk: bool = true,
    final_chunk: bool = true,
    data: []const u8,
};

/// FocusEvent (0x0206, C->S)
pub const FocusEvent = struct {
    pane_id: u32,
    focused: bool,
};

/// ScrollRequest (0x0301, C->S)
pub const ScrollRequest = struct {
    pane_id: u32,
    direction: u8 = 0, // 0=up, 1=down, 2=top, 3=bottom
    lines: u32 = 0,
};

/// ScrollPosition (0x0302, S->C)
pub const ScrollPosition = struct {
    pane_id: u32,
    viewport_top: u32 = 0,
    total_lines: u32 = 0,
    viewport_rows: u32 = 0,
};

/// SearchRequest (0x0303, C->S)
pub const SearchRequest = struct {
    pane_id: u32,
    direction: u8 = 0, // 0=forward, 1=backward
    case_sensitive: bool = false,
    regex: bool = false,
    wrap_around: bool = true,
    query: []const u8,
};

/// SearchResult (0x0304, S->C)
pub const SearchResult = struct {
    pane_id: u32,
    total_matches: u32 = 0,
    current_match: u32 = 0,
    match_row: u16 = 0,
    match_start_col: u16 = 0,
    match_end_col: u16 = 0,
};

/// SearchCancel (0x0305, C->S)
pub const SearchCancel = struct {
    pane_id: u32,
};

test "KeyEvent: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = KeyEvent{
        .keycode = 0x04,
        .action = Action.press,
        .modifiers = Modifiers.ctrl | Modifiers.shift,
        .input_method = "direct",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(KeyEvent, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u16, 0x04), parsed.value.keycode);
    try std.testing.expectEqual(Modifiers.ctrl | Modifiers.shift, parsed.value.modifiers);
    try std.testing.expectEqualStrings("direct", parsed.value.input_method);
}

test "KeyEvent: optional pane_id omitted when null" {
    const allocator = std.testing.allocator;
    const original = KeyEvent{ .keycode = 0x28, .action = 0, .modifiers = 0 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    try std.testing.expect(std.mem.indexOf(u8, j, "pane_id") == null);
}

test "MouseButton: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = MouseButton{ .pane_id = 1, .button = 0, .action = 0, .modifiers = 0, .x = 5.0, .y = 10.0 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(MouseButton, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(f32, 5.0), parsed.value.x);
    try std.testing.expectEqual(@as(f32, 10.0), parsed.value.y);
}

test "PasteData: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = PasteData{ .pane_id = 1, .data = "hello world" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(PasteData, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("hello world", parsed.value.data);
}

test "SearchRequest: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = SearchRequest{ .pane_id = 1, .query = "foo", .regex = true };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(SearchRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("foo", parsed.value.query);
    try std.testing.expect(parsed.value.regex);
}

test "Modifiers: constants" {
    try std.testing.expectEqual(@as(u8, 0x01), Modifiers.shift);
    try std.testing.expectEqual(@as(u8, 0x02), Modifiers.ctrl);
    try std.testing.expectEqual(@as(u8, 0x04), Modifiers.alt);
    try std.testing.expectEqual(@as(u8, 0x08), Modifiers.super);
    try std.testing.expectEqual(@as(u8, 0x10), Modifiers.caps_lock);
    try std.testing.expectEqual(@as(u8, 0x20), Modifiers.num_lock);
}
