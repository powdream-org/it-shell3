const std = @import("std");
const json_mod = @import("json.zig");

// Direction: 0=right, 1=down, 2=left, 3=up
pub const Direction = enum(u8) { right = 0, down = 1, left = 2, up = 3 };

/// CreatePaneRequest (0x0140, C->S)
pub const CreatePaneRequest = struct {
    session_id: u32,
    shell: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
};

/// CreatePaneResponse (0x0141, S->C)
pub const CreatePaneResponse = struct {
    status: u32 = 0,
    pane_id: u32 = 0,
    @"error": ?[]const u8 = null,
};

/// SplitPaneRequest (0x0142, C->S)
pub const SplitPaneRequest = struct {
    session_id: u32,
    pane_id: u32,
    direction: u8 = 0,
    ratio: f32 = 0.5,
    shell: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    focus_new: bool = true,
};

/// SplitPaneResponse (0x0143, S->C)
pub const SplitPaneResponse = struct {
    status: u32 = 0,
    new_pane_id: u32 = 0,
    @"error": ?[]const u8 = null,
};

/// ClosePaneRequest (0x0144, C->S)
pub const ClosePaneRequest = struct {
    session_id: u32,
    pane_id: u32,
    force: bool = false,
};

/// ClosePaneResponse (0x0145, S->C)
pub const ClosePaneResponse = struct {
    status: u32 = 0,
    side_effect: u32 = 0,
    new_focus_pane_id: u32 = 0,
    @"error": ?[]const u8 = null,
};

/// FocusPaneRequest (0x0146, C->S)
pub const FocusPaneRequest = struct {
    session_id: u32,
    pane_id: u32,
};

/// FocusPaneResponse (0x0147, S->C)
pub const FocusPaneResponse = struct {
    status: u32 = 0,
    previous_pane_id: u32 = 0,
};

/// NavigatePaneRequest (0x0148, C->S)
pub const NavigatePaneRequest = struct {
    session_id: u32,
    direction: u8 = 0,
};

/// NavigatePaneResponse (0x0149, S->C)
pub const NavigatePaneResponse = struct {
    status: u32 = 0,
    focused_pane_id: u32 = 0,
};

/// ResizePaneRequest (0x014A, C->S)
pub const ResizePaneRequest = struct {
    session_id: u32,
    pane_id: u32,
    direction: u8 = 0,
    delta: i16 = 0,
};

/// ResizePaneResponse (0x014B, S->C)
pub const ResizePaneResponse = struct {
    status: u32 = 0,
    @"error": ?[]const u8 = null,
};

/// EqualizeSplitsRequest (0x014C, C->S)
pub const EqualizeSplitsRequest = struct {
    session_id: u32,
};

/// EqualizeSplitsResponse (0x014D, S->C)
pub const EqualizeSplitsResponse = struct {
    status: u32 = 0,
};

/// ZoomPaneRequest (0x014E, C->S)
pub const ZoomPaneRequest = struct {
    session_id: u32,
    pane_id: u32,
};

/// ZoomPaneResponse (0x014F, S->C)
pub const ZoomPaneResponse = struct {
    status: u32 = 0,
    zoomed: bool = false,
};

/// SwapPanesRequest (0x0150, C->S)
pub const SwapPanesRequest = struct {
    session_id: u32,
    pane_a: u32,
    pane_b: u32,
};

/// SwapPanesResponse (0x0151, S->C)
pub const SwapPanesResponse = struct {
    status: u32 = 0,
    @"error": ?[]const u8 = null,
};

/// LayoutGetRequest (0x0152, C->S)
pub const LayoutGetRequest = struct {
    session_id: u32,
};

/// Layout tree node — recursive JSON structure
pub const LayoutNode = struct {
    type: NodeType,
    pane_id: ?u32 = null,
    cols: ?u16 = null,
    rows: ?u16 = null,
    x_off: ?u16 = null,
    y_off: ?u16 = null,
    preedit_active: ?bool = null,
    active_input_method: ?[]const u8 = null,
    active_keyboard_layout: ?[]const u8 = null,
    orientation: ?[]const u8 = null,
    ratio: ?f32 = null,
    first: ?*const LayoutNode = null,
    second: ?*const LayoutNode = null,

    pub const NodeType = enum { leaf, split };
};

/// LayoutGetResponse (0x0153, S->C)
pub const LayoutGetResponse = struct {
    session_id: u32,
    active_pane_id: u32,
    zoomed_pane_present: bool = false,
    zoomed_pane_id: u32 = 0,
    layout_tree: ?std.json.Value = null,
};

// ---- Notifications ----

/// LayoutChanged (0x0180, S->C)
pub const LayoutChanged = struct {
    session_id: u32,
    active_pane_id: u32,
    zoomed_pane_present: bool = false,
    zoomed_pane_id: u32 = 0,
    layout_tree: ?std.json.Value = null,
};

/// PaneMetadataChanged (0x0181, S->C)
pub const PaneMetadataChanged = struct {
    session_id: u32,
    pane_id: u32,
    title: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    process_name: ?[]const u8 = null,
    exit_status: ?i32 = null,
    pid: ?u32 = null,
    is_running: ?bool = null,
};

/// SessionListChanged (0x0182, S->C)
pub const SessionListChanged = struct {
    event: []const u8,
    session_id: u32,
    name: []const u8 = "",
};

/// ClientAttached (0x0183, S->C)
pub const ClientAttached = struct {
    session_id: u32,
    client_id: u32,
    client_name: []const u8 = "",
    attached_clients: u32 = 0,
};

/// ClientDetached (0x0184, S->C)
pub const ClientDetached = struct {
    session_id: u32,
    client_id: u32,
    client_name: []const u8 = "",
    reason: []const u8 = "client_requested",
    attached_clients: u32 = 0,
};

/// ClientHealthChanged (0x0185, S->C)
pub const ClientHealthChanged = struct {
    session_id: u32,
    client_id: u32,
    client_name: []const u8 = "",
    health: []const u8 = "healthy",
    previous_health: []const u8 = "healthy",
    reason: []const u8 = "",
    excluded_from_resize: bool = false,
};

/// WindowResize (0x0190, C->S)
pub const WindowResize = struct {
    session_id: u32,
    cols: u16,
    rows: u16,
    pixel_width: ?u16 = null,
    pixel_height: ?u16 = null,
};

/// WindowResizeAck (0x0191, S->C)
pub const WindowResizeAck = struct {
    session_id: u32,
    cols: u16,
    rows: u16,
};

test "SplitPaneRequest: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = SplitPaneRequest{ .session_id = 1, .pane_id = 1, .direction = 1, .ratio = 0.5 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(SplitPaneRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.session_id);
    try std.testing.expectEqual(@as(u8, 1), parsed.value.direction);
}

test "ClosePaneResponse: side_effect field" {
    const allocator = std.testing.allocator;
    const original = ClosePaneResponse{ .status = 0, .side_effect = 1, .new_focus_pane_id = 0 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(ClosePaneResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.side_effect);
}

test "ZoomPaneResponse: zoomed field" {
    const allocator = std.testing.allocator;
    const original = ZoomPaneResponse{ .status = 0, .zoomed = true };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(ZoomPaneResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.zoomed);
}

test "SessionListChanged: event field" {
    const allocator = std.testing.allocator;
    const original = SessionListChanged{ .event = "created", .session_id = 1, .name = "main" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(SessionListChanged, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("created", parsed.value.event);
}

test "WindowResize: optional pixel fields omitted" {
    const allocator = std.testing.allocator;
    const original = WindowResize{ .session_id = 1, .cols = 120, .rows = 40 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    try std.testing.expect(std.mem.indexOf(u8, j, "pixel_width") == null);
}

test "ClientHealthChanged: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = ClientHealthChanged{
        .session_id = 1,
        .client_id = 5,
        .health = "stale",
        .previous_health = "healthy",
        .reason = "pause_timeout",
        .excluded_from_resize = true,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(ClientHealthChanged, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("stale", parsed.value.health);
    try std.testing.expect(parsed.value.excluded_from_resize);
}
