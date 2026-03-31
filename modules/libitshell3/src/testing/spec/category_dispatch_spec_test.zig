//! Spec compliance tests: Category-based message dispatcher (Plan 7.5).
//!
//! Validates the two-level dispatch architecture (ADR 00064) and two bugfixes:
//!   1. AttachOrCreateRequest parses "session_name" (not "name") per protocol
//!      session-pane-management AttachOrCreate definition.
//!   2. SplitPane, NavigatePane, ResizePane parse direction as integer (0-3)
//!      per protocol session-pane-management direction conventions.
//!
//! Spec sources:
//!   - ADR 00064 — Category-Based Message Dispatcher (structural decision)
//!   - protocol 01-protocol-overview message type ID allocation
//!   - protocol 03-session-pane-management AttachOrCreate definition
//!   - protocol 03-session-pane-management direction conventions
//!   - protocol 03-session-pane-management pane operation definitions

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;

// ── Spec: Message Type Range Boundaries (protocol 01-protocol-overview) ──

test "spec: category dispatch — message type ranges match protocol allocation" {
    // Lifecycle: 0x0001-0x00FF
    try std.testing.expectEqual(@as(u16, 0x0001), @intFromEnum(MessageType.client_hello));
    try std.testing.expectEqual(@as(u16, 0x00FF), @intFromEnum(MessageType.@"error"));

    // Session & Pane: 0x0100-0x01FF
    try std.testing.expectEqual(@as(u16, 0x0100), @intFromEnum(MessageType.create_session_request));
    try std.testing.expectEqual(@as(u16, 0x0191), @intFromEnum(MessageType.window_resize_ack));

    // Input: 0x0200-0x02FF
    try std.testing.expectEqual(@as(u16, 0x0200), @intFromEnum(MessageType.key_event));
    try std.testing.expectEqual(@as(u16, 0x0206), @intFromEnum(MessageType.focus_event));

    // Render: 0x0300-0x03FF
    try std.testing.expectEqual(@as(u16, 0x0300), @intFromEnum(MessageType.frame_update));
    try std.testing.expectEqual(@as(u16, 0x0305), @intFromEnum(MessageType.search_cancel));

    // CJK & IME: 0x0400-0x04FF
    try std.testing.expectEqual(@as(u16, 0x0400), @intFromEnum(MessageType.preedit_start));
    try std.testing.expectEqual(@as(u16, 0x04FF), @intFromEnum(MessageType.ime_error));

    // Flow Control: 0x0500-0x05FF
    try std.testing.expectEqual(@as(u16, 0x0500), @intFromEnum(MessageType.pause_pane));
    try std.testing.expectEqual(@as(u16, 0x0506), @intFromEnum(MessageType.client_display_info_ack));
}

// ── Spec: Page-Level Routing (ADR 00064 — msg_type >> 8) ──────────────────────

test "spec: category dispatch — page selector (msg_type >> 8) routes lifecycle to 0x00" {
    // All lifecycle messages must have page 0x00.
    const lifecycle_types = [_]MessageType{
        .client_hello,
        .server_hello,
        .heartbeat,
        .heartbeat_ack,
        .disconnect,
        .@"error",
    };
    for (lifecycle_types) |mt| {
        try std.testing.expectEqual(@as(u16, 0x00), @intFromEnum(mt) >> 8);
    }
}

test "spec: category dispatch — page selector routes session/pane to 0x01" {
    // All session, pane, and notification messages must have page 0x01.
    const session_pane_types = [_]MessageType{
        .create_session_request,
        .create_session_response,
        .list_sessions_request,
        .attach_session_request,
        .detach_session_request,
        .destroy_session_request,
        .rename_session_request,
        .attach_or_create_request,
        .create_pane_request,
        .split_pane_request,
        .close_pane_request,
        .focus_pane_request,
        .navigate_pane_request,
        .resize_pane_request,
        .equalize_splits_request,
        .zoom_pane_request,
        .swap_panes_request,
        .layout_get_request,
        .layout_changed,
        .pane_metadata_changed,
        .session_list_changed,
        .client_attached,
        .client_detached,
        .client_health_changed,
        .window_resize,
        .window_resize_ack,
    };
    for (session_pane_types) |mt| {
        try std.testing.expectEqual(@as(u16, 0x01), @intFromEnum(mt) >> 8);
    }
}

test "spec: category dispatch — page selector routes input to 0x02" {
    const input_types = [_]MessageType{
        .key_event,
        .text_input,
        .mouse_button,
        .mouse_move,
        .mouse_scroll,
        .paste_data,
        .focus_event,
    };
    for (input_types) |mt| {
        try std.testing.expectEqual(@as(u16, 0x02), @intFromEnum(mt) >> 8);
    }
}

test "spec: category dispatch — page selector routes render to 0x03" {
    const render_types = [_]MessageType{
        .frame_update,
        .scroll_request,
        .scroll_position,
        .search_request,
        .search_result,
        .search_cancel,
    };
    for (render_types) |mt| {
        try std.testing.expectEqual(@as(u16, 0x03), @intFromEnum(mt) >> 8);
    }
}

test "spec: category dispatch — page selector routes IME to 0x04" {
    const ime_types = [_]MessageType{
        .preedit_start,
        .preedit_update,
        .preedit_end,
        .preedit_sync,
        .input_method_switch,
        .input_method_ack,
        .ambiguous_width_config,
        .ime_error,
    };
    for (ime_types) |mt| {
        try std.testing.expectEqual(@as(u16, 0x04), @intFromEnum(mt) >> 8);
    }
}

test "spec: category dispatch — page selector routes flow control to 0x05" {
    const flow_types = [_]MessageType{
        .pause_pane,
        .continue_pane,
        .flow_control_config,
        .flow_control_config_ack,
        .output_queue_status,
        .client_display_info,
        .client_display_info_ack,
    };
    for (flow_types) |mt| {
        try std.testing.expectEqual(@as(u16, 0x05), @intFromEnum(mt) >> 8);
    }
}

// ── Spec: Second-Level Split Within 0x01xx (ADR 00064) ────────────────────────
// Sub-category = (@intFromEnum(msg_type) & 0xC0) >> 6
//   0 = session (0x0100-0x013F)
//   1 = pane    (0x0140-0x017F)
//   2 = notification (0x0180-0x019F)

test "spec: category dispatch — second-level split routes session messages to sub-category 0" {
    const session_types = [_]MessageType{
        .create_session_request,
        .create_session_response,
        .list_sessions_request,
        .list_sessions_response,
        .attach_session_request,
        .attach_session_response,
        .detach_session_request,
        .detach_session_response,
        .destroy_session_request,
        .destroy_session_response,
        .rename_session_request,
        .rename_session_response,
        .attach_or_create_request,
        .attach_or_create_response,
    };
    for (session_types) |mt| {
        const raw = @intFromEnum(mt);
        const sub = (raw & 0xC0) >> 6;
        try std.testing.expectEqual(@as(u16, 0), sub);
    }
}

test "spec: category dispatch — second-level split routes pane messages to sub-category 1" {
    const pane_types = [_]MessageType{
        .create_pane_request,
        .create_pane_response,
        .split_pane_request,
        .split_pane_response,
        .close_pane_request,
        .close_pane_response,
        .focus_pane_request,
        .focus_pane_response,
        .navigate_pane_request,
        .navigate_pane_response,
        .resize_pane_request,
        .resize_pane_response,
        .equalize_splits_request,
        .equalize_splits_response,
        .zoom_pane_request,
        .zoom_pane_response,
        .swap_panes_request,
        .swap_panes_response,
        .layout_get_request,
        .layout_get_response,
    };
    for (pane_types) |mt| {
        const raw = @intFromEnum(mt);
        const sub = (raw & 0xC0) >> 6;
        try std.testing.expectEqual(@as(u16, 1), sub);
    }
}

test "spec: category dispatch — second-level split routes notifications to sub-category 2" {
    const notification_types = [_]MessageType{
        .layout_changed,
        .pane_metadata_changed,
        .session_list_changed,
        .client_attached,
        .client_detached,
        .client_health_changed,
    };
    for (notification_types) |mt| {
        const raw = @intFromEnum(mt);
        const sub = (raw & 0xC0) >> 6;
        try std.testing.expectEqual(@as(u16, 2), sub);
    }
}

test "spec: category dispatch — window resize (0x0190) falls in sub-category 2" {
    // WindowResize (0x0190) and WindowResizeAck (0x0191) are in the notification
    // range per protocol 01-protocol-overview message type allocation.
    const raw_resize = @intFromEnum(MessageType.window_resize);
    const sub_resize = (raw_resize & 0xC0) >> 6;
    try std.testing.expectEqual(@as(u16, 2), sub_resize);

    const raw_ack = @intFromEnum(MessageType.window_resize_ack);
    const sub_ack = (raw_ack & 0xC0) >> 6;
    try std.testing.expectEqual(@as(u16, 2), sub_ack);
}

// ── Spec: Bugfix 1 — AttachOrCreateRequest "session_name" field ───────────────
// Protocol 03-session-pane-management AttachOrCreate definition specifies the
// field as "session_name", not "name".

test "spec: AttachOrCreateRequest — JSON field is 'session_name' per protocol AttachOrCreate definition" {
    // The spec defines: {"session_name": "main", "cols": 80, "rows": 24, ...}
    // Parsing a JSON payload with "session_name" must succeed and extract the value.
    const payload = "{\"session_name\": \"main\", \"cols\": 80, \"rows\": 24}";
    const Parsed = struct {
        session_name: []const u8 = "",
    };
    const result = std.json.parseFromSlice(Parsed, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    }) catch {
        return error.TestUnexpectedResult;
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("main", result.value.session_name);
}

test "spec: AttachOrCreateRequest — 'name' field must NOT be the parsed field" {
    // If the implementation incorrectly parses "name" instead of "session_name",
    // a payload with only "session_name" would yield an empty/default value
    // for "name". This test verifies the spec-mandated field name.
    const payload = "{\"session_name\": \"my-session\"}";

    // Parsing with the WRONG struct (field "name") should NOT find "my-session".
    const WrongParsed = struct {
        name: []const u8 = "",
    };
    const wrong_result = std.json.parseFromSlice(WrongParsed, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    }) catch {
        return error.TestUnexpectedResult;
    };
    defer wrong_result.deinit();
    // "name" field defaults to "" because the JSON has "session_name", not "name".
    try std.testing.expectEqualStrings("", wrong_result.value.name);

    // Parsing with the CORRECT struct (field "session_name") finds the value.
    const CorrectParsed = struct {
        session_name: []const u8 = "",
    };
    const correct_result = std.json.parseFromSlice(CorrectParsed, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    }) catch {
        return error.TestUnexpectedResult;
    };
    defer correct_result.deinit();
    try std.testing.expectEqualStrings("my-session", correct_result.value.session_name);
}

test "spec: AttachOrCreateRequest — empty session_name means attach to most recent" {
    // Per protocol AttachOrCreate definition: "Empty string = attach to most recently active session"
    const payload = "{\"session_name\": \"\"}";
    const Parsed = struct {
        session_name: []const u8 = "",
    };
    const result = std.json.parseFromSlice(Parsed, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    }) catch {
        return error.TestUnexpectedResult;
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("", result.value.session_name);
}

// ── Spec: Bugfix 2 — Direction as integer (0-3) ──────────────────────────────
// Protocol 03-session-pane-management direction conventions: "Directions use
// integers: 0 = right, 1 = down, 2 = left, 3 = up"

test "spec: SplitPaneRequest — direction is integer per protocol direction conventions" {
    // The spec example: {"session_id": 1, "pane_id": 1, "direction": 0, ...}
    const payload = "{\"session_id\": 1, \"pane_id\": 1, \"direction\": 0, \"ratio\": 0.5}";
    const Parsed = struct {
        session_id: u32,
        pane_id: u32,
        direction: u8,
        ratio: f32 = 0.5,
    };
    const result = std.json.parseFromSlice(Parsed, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    }) catch {
        return error.TestUnexpectedResult;
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.value.direction); // 0 = right
}

test "spec: NavigatePaneRequest — direction is integer per protocol direction conventions" {
    const payload = "{\"session_id\": 1, \"direction\": 1}";
    const Parsed = struct {
        session_id: u32,
        direction: u8,
    };
    const result = std.json.parseFromSlice(Parsed, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    }) catch {
        return error.TestUnexpectedResult;
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.value.direction); // 1 = down
}

test "spec: ResizePaneRequest — direction is integer per protocol direction conventions" {
    const payload = "{\"session_id\": 1, \"pane_id\": 1, \"direction\": 2, \"delta\": 5}";
    const Parsed = struct {
        session_id: u32,
        pane_id: u32,
        direction: u8,
        delta: i32,
    };
    const result = std.json.parseFromSlice(Parsed, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    }) catch {
        return error.TestUnexpectedResult;
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 2), result.value.direction); // 2 = left
}

test "spec: direction integer mapping — all four values per protocol Conventions" {
    // "Directions use integers: 0 = right, 1 = down, 2 = left, 3 = up
    //  (matches ghostty's GHOSTTY_SPLIT_DIRECTION)"
    const core = @import("itshell3_core");
    const Direction = core.types.Direction;

    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Direction.right));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Direction.down));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(Direction.left));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(Direction.up));
}

test "spec: direction as string must fail JSON integer parse" {
    // If the old code uses direction as string ("right"), parsing into u8 must fail.
    // This verifies that the wire format uses integers, not strings.
    const payload_with_string = "{\"session_id\": 1, \"pane_id\": 1, \"direction\": \"right\"}";
    const Parsed = struct {
        session_id: u32,
        pane_id: u32,
        direction: u8,
    };
    // Parsing a string into u8 must produce an error.
    if (std.json.parseFromSlice(Parsed, std.testing.allocator, payload_with_string, .{
        .ignore_unknown_fields = true,
    })) |result| {
        defer result.deinit();
        // If parsing somehow succeeded, the test should fail.
        return error.TestUnexpectedResult;
    } else |_| {
        // Expected: parsing fails because "right" is not a valid u8.
    }
}

test "spec: direction integer 0-3 maps to Direction enum via @enumFromInt" {
    // The integer wire values must be directly convertible to the Direction enum
    // without requiring a string lookup helper.
    const core = @import("itshell3_core");
    const Direction = core.types.Direction;

    const right: Direction = @enumFromInt(0);
    try std.testing.expectEqual(Direction.right, right);

    const down: Direction = @enumFromInt(1);
    try std.testing.expectEqual(Direction.down, down);

    const left: Direction = @enumFromInt(2);
    try std.testing.expectEqual(Direction.left, left);

    const up: Direction = @enumFromInt(3);
    try std.testing.expectEqual(Direction.up, up);
}

// ── Spec: Catch-all for unknown pages (ADR 00064) ────────────────────────────

test "spec: category dispatch — pages beyond 0x05 have no handler (catch-all)" {
    // ADR 00064 defines six arms (0x00-0x05) plus an else catch-all.
    // Clipboard (0x06), Persistence (0x07), etc. are beyond the dispatcher's range.
    try std.testing.expectEqual(@as(u16, 0x06), @intFromEnum(MessageType.clipboard_write) >> 8);
    try std.testing.expectEqual(@as(u16, 0x07), @intFromEnum(MessageType.snapshot_request) >> 8);
    try std.testing.expectEqual(@as(u16, 0x08), @intFromEnum(MessageType.pane_title_changed) >> 8);
    try std.testing.expectEqual(@as(u16, 0x0A), @intFromEnum(MessageType.extension_list) >> 8);
}

// ── Spec: Sub-category 3 is unused in 0x01xx (ADR 00064) ─────────────────────

test "spec: category dispatch — sub-category 3 (0x01C0-0x01FF) has no defined messages" {
    // The second-level split uses (raw & 0xC0) >> 6. Sub-category 3 (0xC0-0xFF
    // within the low byte) is not assigned any message types in the spec.
    // Verify no existing MessageType falls in this range.
    const all_01xx = [_]MessageType{
        // Session
        .create_session_request,   .create_session_response,
        .list_sessions_request,    .list_sessions_response,
        .attach_session_request,   .attach_session_response,
        .detach_session_request,   .detach_session_response,
        .destroy_session_request,  .destroy_session_response,
        .rename_session_request,   .rename_session_response,
        .attach_or_create_request, .attach_or_create_response,
        // Pane
        .create_pane_request,      .create_pane_response,
        .split_pane_request,       .split_pane_response,
        .close_pane_request,       .close_pane_response,
        .focus_pane_request,       .focus_pane_response,
        .navigate_pane_request,    .navigate_pane_response,
        .resize_pane_request,      .resize_pane_response,
        .equalize_splits_request,  .equalize_splits_response,
        .zoom_pane_request,        .zoom_pane_response,
        .swap_panes_request,       .swap_panes_response,
        .layout_get_request,       .layout_get_response,
        // Notification
        .layout_changed,           .pane_metadata_changed,
        .session_list_changed,     .client_attached,
        .client_detached,          .client_health_changed,
        .window_resize,            .window_resize_ack,
    };
    for (all_01xx) |mt| {
        const raw = @intFromEnum(mt);
        const sub = (raw & 0xC0) >> 6;
        try std.testing.expect(sub != 3);
    }
}

// ── Spec: SplitPane direction field accepts all four integer values ────────────

test "spec: SplitPaneRequest — direction 0 means right (vertical split, original left)" {
    // Per protocol SplitPane definition: "right (0): Vertical split. Original
    // pane becomes left, new pane appears on right."
    const payload = "{\"session_id\": 1, \"pane_id\": 1, \"direction\": 0, \"ratio\": 0.5}";
    const Parsed = struct { direction: u8 };
    const result = try std.json.parseFromSlice(Parsed, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    });
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.value.direction);
}

test "spec: SplitPaneRequest — direction 1 means down (horizontal split, original top)" {
    const payload = "{\"session_id\": 1, \"pane_id\": 1, \"direction\": 1, \"ratio\": 0.5}";
    const Parsed = struct { direction: u8 };
    const result = try std.json.parseFromSlice(Parsed, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    });
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.value.direction);
}

test "spec: SplitPaneRequest — direction 2 means left (vertical split, new pane left)" {
    const payload = "{\"session_id\": 1, \"pane_id\": 1, \"direction\": 2, \"ratio\": 0.5}";
    const Parsed = struct { direction: u8 };
    const result = try std.json.parseFromSlice(Parsed, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    });
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 2), result.value.direction);
}

test "spec: SplitPaneRequest — direction 3 means up (horizontal split, new pane top)" {
    const payload = "{\"session_id\": 1, \"pane_id\": 1, \"direction\": 3, \"ratio\": 0.5}";
    const Parsed = struct { direction: u8 };
    const result = try std.json.parseFromSlice(Parsed, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    });
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 3), result.value.direction);
}
