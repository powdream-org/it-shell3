//! Dispatches session and pane management messages (0x01xx range) with a
//! second-level split: session (0x0100-0x013F), pane (0x0140-0x017F),
//! notification (0x0180-0x019F).
//!
//! Per ADR 00064 (second-level split via (raw & 0xC0) >> 6) and
//! protocol 01-protocol-overview (Session & Pane Management range 0x0100-0x01FF).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const server = @import("itshell3_server");
const session_handler = server.handlers.session_handler;
const pane_handler = server.handlers.pane_handler;
const core = @import("itshell3_core");
const message_dispatcher = @import("message_dispatcher.zig");
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;
const DispatcherContext = message_dispatcher.DispatcherContext;
const handler_utils = @import("handler_utils.zig");
const envelope = @import("protocol_envelope.zig");
const resize_handler = @import("resize_handler.zig");

/// Dispatches a session/pane-category message using a second-level split.
pub fn dispatch(params: CategoryDispatchParams) void {
    const raw = @intFromEnum(params.msg_type);
    const sub = (raw & 0xC0) >> 6;
    switch (sub) {
        0 => dispatchSession(params),
        1 => dispatchPane(params),
        2 => {
            // S->C notifications (0x0180-0x0185) need no receive handler on
            // the server side. WindowResize (0x0190+) is C->S.
            dispatchNotificationRange(params);
        },
        else => {},
    }
}

fn dispatchSession(params: CategoryDispatchParams) void {
    const ctx = params.context;
    const client = params.client;
    const client_slot = params.client_slot;
    const sequence = params.header.sequence;
    const payload = params.payload;

    switch (params.msg_type) {
        .create_session_request => {
            const parsed = std.json.parseFromSlice(struct {
                name: []const u8 = "",
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var session_ctx = makeSessionHandlerContext(ctx);
            session_handler.handleCreateSession(&session_ctx, client, client_slot, sequence, parsed.value.name);
        },
        .list_sessions_request => {
            var session_ctx = makeSessionHandlerContext(ctx);
            session_handler.handleListSessions(&session_ctx, client, client_slot, sequence);
        },
        .rename_session_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
                name: []const u8,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var session_ctx = makeSessionHandlerContext(ctx);
            session_handler.handleRenameSession(&session_ctx, client, client_slot, sequence, parsed.value.session_id, parsed.value.name);
        },
        .attach_session_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32 = 0,
                session_name: []const u8 = "",
                create_if_missing: bool = false,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var session_ctx = makeSessionHandlerContext(ctx);
            session_handler.handleAttachSession(&session_ctx, client, client_slot, sequence, parsed.value.session_id, parsed.value.session_name, parsed.value.create_if_missing);
        },
        .detach_session_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var session_ctx = makeSessionHandlerContext(ctx);
            session_handler.handleDetachSession(&session_ctx, client, client_slot, sequence, parsed.value.session_id);
        },
        .destroy_session_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
                force: bool = false,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var session_ctx = makeSessionHandlerContext(ctx);
            session_handler.handleDestroySession(&session_ctx, client, client_slot, sequence, parsed.value.session_id, parsed.value.force);
        },
        else => {},
    }
}

fn dispatchPane(params: CategoryDispatchParams) void {
    const ctx = params.context;
    const client = params.client;
    const client_slot = params.client_slot;
    const sequence = params.header.sequence;
    const payload = params.payload;

    switch (params.msg_type) {
        .create_pane_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var pane_ctx = makePaneHandlerContext(ctx);
            pane_handler.handleCreatePane(&pane_ctx, client, client_slot, sequence, parsed.value.session_id);
        },
        .split_pane_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
                pane_id: u32,
                direction: u8,
                ratio: u32 = 5000,
                focus_new: bool = true,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            const direction = std.meta.intToEnum(core.types.Direction, parsed.value.direction) catch return;
            var pane_ctx = makePaneHandlerContext(ctx);
            pane_handler.handleSplitPane(&pane_ctx, client, client_slot, sequence, parsed.value.session_id, parsed.value.pane_id, direction, parsed.value.ratio, parsed.value.focus_new);
        },
        .close_pane_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
                pane_id: u32,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var pane_ctx = makePaneHandlerContext(ctx);
            pane_handler.handleClosePane(&pane_ctx, client, client_slot, sequence, parsed.value.session_id, parsed.value.pane_id);
        },
        .focus_pane_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
                pane_id: u32,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var pane_ctx = makePaneHandlerContext(ctx);
            pane_handler.handleFocusPane(&pane_ctx, client, client_slot, sequence, parsed.value.session_id, parsed.value.pane_id);
        },
        .navigate_pane_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
                direction: u8,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            const direction = std.meta.intToEnum(core.types.Direction, parsed.value.direction) catch return;
            var pane_ctx = makePaneHandlerContext(ctx);
            pane_handler.handleNavigatePane(&pane_ctx, client, client_slot, sequence, parsed.value.session_id, direction);
        },
        .resize_pane_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
                pane_id: u32,
                orientation: u8,
                delta_ratio: i32,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            const orientation_enum = std.meta.intToEnum(core.types.Orientation, parsed.value.orientation) catch return;
            var pane_ctx = makePaneHandlerContext(ctx);
            pane_handler.handleResizePane(&pane_ctx, client, client_slot, sequence, parsed.value.session_id, parsed.value.pane_id, orientation_enum, parsed.value.delta_ratio);
        },
        .equalize_splits_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var pane_ctx = makePaneHandlerContext(ctx);
            pane_handler.handleEqualizeSplits(&pane_ctx, client, client_slot, sequence, parsed.value.session_id);
        },
        .zoom_pane_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
                pane_id: u32,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var pane_ctx = makePaneHandlerContext(ctx);
            pane_handler.handleZoomPane(&pane_ctx, client, client_slot, sequence, parsed.value.session_id, parsed.value.pane_id);
        },
        .swap_panes_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
                pane_a: u32,
                pane_b: u32,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var pane_ctx = makePaneHandlerContext(ctx);
            pane_handler.handleSwapPanes(&pane_ctx, client, client_slot, sequence, parsed.value.session_id, parsed.value.pane_a, parsed.value.pane_b);
        },
        .layout_get_request => {
            const parsed = std.json.parseFromSlice(struct {
                session_id: u32,
            }, ctx.allocator, payload, .{ .ignore_unknown_fields = true }) catch return;
            defer parsed.deinit();
            var pane_ctx = makePaneHandlerContext(ctx);
            pane_handler.handleLayoutGet(&pane_ctx, client, client_slot, sequence, parsed.value.session_id);
        },
        else => {},
    }
}

fn dispatchNotificationRange(params: CategoryDispatchParams) void {
    switch (params.msg_type) {
        .window_resize => handleWindowResize(params),
        else => {
            // Other notification-range messages (S->C only) need no handler.
        },
    }
}

/// Handles WindowResize (C->S). Per daemon-behavior spec resize policy:
/// Updates client display dimensions, updates latest_client_id,
/// triggers resize debounce computation.
fn handleWindowResize(params: CategoryDispatchParams) void {
    const client = params.client;
    const payload = params.payload;
    const sequence = params.header.sequence;

    const cols = handler_utils.extractU16Field(payload, "\"cols\":") orelse return;
    const rows = handler_utils.extractU16Field(payload, "\"rows\":") orelse return;

    // Record as application-level message (updates latest_client_id)
    client.recordApplicationMessage();

    // Update latest_client_id on session and apply dimension change guard.
    // Per daemon-behavior spec resize policy: only update effective dimensions
    // if the size actually changed.
    if (client.attached_session) |entry| {
        entry.latest_client_id = client.getClientId();
        if (resize_handler.dimensionsChanged(entry, cols, rows)) {
            entry.setEffectiveDimensions(cols, rows);
        }
    }

    // Send WindowResizeAck to requesting client (always, regardless of change)
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    var json_buffer: [128]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buffer, "{{\"status\":0,\"cols\":{d},\"rows\":{d}}}", .{
        cols,
        rows,
    }) catch return;
    const response = envelope.wrapResponse(
        &response_buffer,
        @intFromEnum(MessageType.window_resize_ack),
        sequence,
        json,
    ) orelse return;
    client.enqueueDirect(response) catch {};
}

fn makeSessionHandlerContext(ctx: *DispatcherContext) session_handler.SessionHandlerContext {
    return .{
        .session_manager = ctx.session_manager,
        .client_manager = ctx.client_manager,
        .disconnect_fn = ctx.disconnect_fn,
        .default_ime_engine = ctx.default_ime_engine,
    };
}

fn makePaneHandlerContext(ctx: *DispatcherContext) pane_handler.PaneHandlerContext {
    return .{
        .session_manager = ctx.session_manager,
        .client_manager = ctx.client_manager,
    };
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "dispatch: second-level split routes session range correctly" {
    // Verify that message types in 0x0100-0x013F route to the session sub-dispatcher.
    // create_session_request (0x0100) has sub-category bits (0x00 & 0xC0) >> 6 = 0.
    const raw = @intFromEnum(MessageType.create_session_request);
    const sub = (raw & 0xC0) >> 6;
    try std.testing.expectEqual(@as(u8, 0), sub);
}

test "dispatch: second-level split routes pane range correctly" {
    // Verify that message types in 0x0140-0x017F route to the pane sub-dispatcher.
    // create_pane_request (0x0140) has sub-category bits (0x40 & 0xC0) >> 6 = 1.
    const raw = @intFromEnum(MessageType.create_pane_request);
    const sub = (raw & 0xC0) >> 6;
    try std.testing.expectEqual(@as(u8, 1), sub);
}

test "dispatch: second-level split routes notification range correctly" {
    // Verify that 0x0180+ maps to sub-category 2 (notification).
    // layout_changed (0x0180) has sub-category bits (0x80 & 0xC0) >> 6 = 2.
    const raw = @intFromEnum(MessageType.layout_changed);
    const sub = (raw & 0xC0) >> 6;
    try std.testing.expectEqual(@as(u8, 2), sub);
}

test "dispatch: direction integer conversion for valid values" {
    // Verify that all four direction integers (0-3) convert to the Direction enum.
    const Direction = core.types.Direction;
    try std.testing.expectEqual(Direction.right, std.meta.intToEnum(Direction, 0) catch unreachable);
    try std.testing.expectEqual(Direction.down, std.meta.intToEnum(Direction, 1) catch unreachable);
    try std.testing.expectEqual(Direction.left, std.meta.intToEnum(Direction, 2) catch unreachable);
    try std.testing.expectEqual(Direction.up, std.meta.intToEnum(Direction, 3) catch unreachable);
}

test "dispatch: direction integer conversion rejects invalid value" {
    // Verify that an out-of-range direction integer (4+) produces an error.
    // Use a runtime value to avoid comptime enum validation.
    const Direction = core.types.Direction;
    var invalid_direction: u8 = 4;
    _ = &invalid_direction;
    const result = std.meta.intToEnum(Direction, invalid_direction);
    try std.testing.expectError(error.InvalidEnumTag, result);
}
