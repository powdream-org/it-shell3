//! Handles pane management requests: Create, Split, Close, Focus, Navigate,
//! Resize, Equalize, Zoom, Swap, and LayoutGet. Each handler validates state,
//! mutates SessionEntry/SplitTree, sends a response, and broadcasts
//! LayoutChanged to session peers.
//!
//! Per protocol 03-session-pane-management (0x0140-0x0153).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const core = @import("itshell3_core");
const types = core.types;
const split_tree = core.split_tree;
const navigation = core.navigation;
const server = @import("itshell3_server");
const SessionManager = server.state.session_manager.SessionManager;
const SessionEntry = server.state.session_entry.SessionEntry;
const Pane = server.state.pane.Pane;
const ClientState = server.connection.client_state.ClientState;
const ClientManager = server.connection.client_manager.ClientManager;
const broadcast_mod = server.connection.broadcast;
const envelope = @import("protocol_envelope.zig");
const notification_builder = @import("notification_builder.zig");

/// Context for pane handler operations.
pub const PaneHandlerContext = struct {
    session_manager: *SessionManager,
    client_manager: *ClientManager,
};

// ── CreatePaneRequest (0x0140) ─────────────────────────────────────────────

/// Handles CreatePaneRequest. Creates a standalone pane replacing the layout
/// root. Per protocol 03-session-pane-management (standalone pane creation).
pub fn handleCreatePane(
    ctx: *PaneHandlerContext,
    client: *ClientState,
    _: u16,
    sequence: u64,
    session_id: types.SessionId,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err = "{\"status\":1,\"error\":\"session not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.create_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // Allocate a new pane slot.
    const new_slot = entry.allocPaneSlot() catch {
        const err = "{\"status\":8,\"error\":\"PANE_LIMIT_EXCEEDED\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.create_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // Assign a PaneId and create stub Pane (PTY not yet spawned).
    const new_pane_id = ctx.session_manager.allocPaneId();
    // TODO(Plan 9+): Spawn shell via forkpty with optional shell/cwd args.
    entry.setPaneAtSlot(new_slot, Pane.init(new_pane_id, new_slot, -1, 0, 0, 0));

    // Replace the layout root with this single leaf.
    entry.session.tree_nodes = split_tree.initSingleLeaf(new_slot);
    entry.session.focused_pane = new_slot;

    // Response to requester.
    var json_buffer: [128]u8 = undefined;
    const response_json = std.fmt.bufPrint(&json_buffer, "{{\"status\":0,\"pane_id\":{d}}}", .{new_pane_id}) catch return;
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.create_pane_response), sequence, response_json) orelse return;
    client.enqueueDirect(response) catch {};

    // Broadcast LayoutChanged.
    broadcastLayoutChanged(ctx, client, entry);
}

// ── SplitPaneRequest (0x0142) ───────────────────────────────────────────────

/// Handles SplitPaneRequest. Validates pane limit, allocates new pane,
/// splits the tree, sends response + LayoutChanged.
pub fn handleSplitPane(
    ctx: *PaneHandlerContext,
    client: *ClientState,
    _: u16,
    sequence: u64,
    session_id: types.SessionId,
    target_pane_id: types.PaneId,
    direction: types.Direction,
    ratio: u32,
    focus_new: bool,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err = "{\"status\":1,\"error\":\"session not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.split_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // Find the target pane's slot.
    const target_slot = entry.findPaneSlotByPaneId(target_pane_id) orelse {
        const err = "{\"status\":1,\"error\":\"pane not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.split_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // Allocate a new pane slot.
    const new_slot = entry.allocPaneSlot() catch {
        const err = "{\"status\":8,\"error\":\"PANE_LIMIT_EXCEEDED\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.split_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // Unzoom if zoomed.
    entry.unzoom();

    // Map direction to orientation and determine child placement.
    const orientation: types.Orientation = switch (direction) {
        .right, .left => .horizontal,
        .down, .up => .vertical,
    };

    // Find the leaf in the tree.
    const leaf_index = split_tree.findLeafBySlot(&entry.session.tree_nodes, target_slot) orelse {
        entry.freePaneSlot(new_slot);
        const err = "{\"status\":7,\"error\":\"internal error\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.split_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // For left/up splits, the new pane is the left child and original is right.
    // splitLeaf always puts original on left, new on right.
    // For left/up, we swap after splitting.
    split_tree.splitLeaf(&entry.session.tree_nodes, leaf_index, orientation, ratio, new_slot) catch {
        entry.freePaneSlot(new_slot);
        const err = "{\"status\":3,\"error\":\"TOO_SMALL\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.split_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // For left/up directions, swap so the new pane is on the correct side.
    if (direction == .left or direction == .up) {
        _ = split_tree.swapLeaves(&entry.session.tree_nodes, target_slot, new_slot);
    }

    // Assign a PaneId and create stub Pane (PTY not yet spawned).
    const new_pane_id = ctx.session_manager.allocPaneId();
    // TODO(Plan 9+): Spawn shell via forkpty, init Terminal + RenderState.
    entry.setPaneAtSlot(new_slot, Pane.init(new_pane_id, new_slot, -1, 0, 0, 0));

    // Update focus if requested.
    if (focus_new) {
        entry.session.focused_pane = new_slot;
    }

    // Response to requester.
    var json_buffer: [128]u8 = undefined;
    const response_json = std.fmt.bufPrint(&json_buffer, "{{\"status\":0,\"new_pane_id\":{d}}}", .{new_pane_id}) catch return;
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.split_pane_response), sequence, response_json) orelse return;
    client.enqueueDirect(response) catch {};

    // Broadcast LayoutChanged.
    broadcastLayoutChanged(ctx, client, entry);
}

// ── ClosePaneRequest (0x0144) ───────────────────────────────────────────────

/// Handles ClosePaneRequest. Removes leaf from tree, frees pane slot.
/// When last pane is closed, triggers session auto-destroy.
pub fn handleClosePane(
    ctx: *PaneHandlerContext,
    client: *ClientState,
    _: u16,
    sequence: u64,
    session_id: types.SessionId,
    target_pane_id: types.PaneId,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err = "{\"status\":1,\"error\":\"pane not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.close_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    const target_slot = entry.findPaneSlotByPaneId(target_pane_id) orelse {
        const err = "{\"status\":1,\"error\":\"pane not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.close_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // Find the leaf in the tree.
    const leaf_index = split_tree.findLeafBySlot(&entry.session.tree_nodes, target_slot) orelse return;

    // Determine sibling for focus transfer.
    var new_focus_pane_id: types.PaneId = 0;
    var side_effect: u8 = 0;

    split_tree.removeLeaf(&entry.session.tree_nodes, leaf_index) catch {
        // CannotRemoveRoot = last pane in session. Session auto-destroy.
        side_effect = 1;
        entry.freePaneSlot(target_slot);

        var json_buffer: [128]u8 = undefined;
        const response_json = std.fmt.bufPrint(&json_buffer, "{{\"status\":0,\"side_effect\":1,\"new_focus_pane_id\":0}}", .{}) catch return;
        const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.close_pane_response), sequence, response_json) orelse return;
        client.enqueueDirect(response) catch {};

        // Session auto-destroy: broadcast SessionListChanged.
        var notification_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
        const name = entry.session.getName();
        const notification_sequence = client.connection.advanceSendSequence();
        const notification = notification_builder.buildSessionListChanged("destroyed", session_id, name, notification_sequence, &notification_buffer) orelse return;
        _ = broadcast_mod.broadcastToActive(ctx.client_manager, notification, null);

        _ = ctx.session_manager.destroySession(session_id);
        return;
    };

    // Free the pane slot.
    entry.freePaneSlot(target_slot);
    entry.unzoom();

    // Transfer focus to sibling if the closed pane was focused.
    if (entry.session.focused_pane) |fp| {
        if (fp == target_slot) {
            // Find any remaining leaf.
            var i: u32 = 0;
            while (i < types.MAX_PANES) : (i += 1) {
                const slot: types.PaneSlot = @intCast(i);
                if (entry.pane_slots[slot]) |pane| {
                    entry.session.focused_pane = slot;
                    new_focus_pane_id = pane.pane_id;
                    break;
                }
            }
        }
    }

    var json_buffer: [128]u8 = undefined;
    const response_json = std.fmt.bufPrint(&json_buffer, "{{\"status\":0,\"side_effect\":{d},\"new_focus_pane_id\":{d}}}", .{ side_effect, new_focus_pane_id }) catch return;
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.close_pane_response), sequence, response_json) orelse return;
    client.enqueueDirect(response) catch {};

    broadcastLayoutChanged(ctx, client, entry);
}

// ── FocusPaneRequest (0x0146) ───────────────────────────────────────────────

/// Handles FocusPaneRequest.
pub fn handleFocusPane(
    ctx: *PaneHandlerContext,
    client: *ClientState,
    _: u16,
    sequence: u64,
    session_id: types.SessionId,
    target_pane_id: types.PaneId,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err = "{\"status\":1,\"error\":\"pane not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.focus_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    const target_slot = entry.findPaneSlotByPaneId(target_pane_id) orelse {
        const err = "{\"status\":1,\"error\":\"pane not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.focus_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    const previous_pane_id = entry.getPaneIdOrNone(entry.session.focused_pane);

    const focus_changed = entry.session.focused_pane != target_slot;
    entry.session.focused_pane = target_slot;

    // Response.
    var json_buffer: [128]u8 = undefined;
    const response_json = std.fmt.bufPrint(&json_buffer, "{{\"status\":0,\"previous_pane_id\":{d}}}", .{previous_pane_id}) catch return;
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.focus_pane_response), sequence, response_json) orelse return;
    client.enqueueDirect(response) catch {};

    // Broadcast LayoutChanged only if focus actually changed.
    if (focus_changed) {
        broadcastLayoutChanged(ctx, client, entry);
    }
}

// ── NavigatePaneRequest (0x0148) ────────────────────────────────────────────

/// Handles NavigatePaneRequest.
pub fn handleNavigatePane(
    ctx: *PaneHandlerContext,
    client: *ClientState,
    _: u16,
    sequence: u64,
    session_id: types.SessionId,
    direction: types.Direction,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err = "{\"status\":1,\"error\":\"session not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.navigate_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    const current_slot = entry.session.focused_pane orelse {
        const err = "{\"status\":7,\"error\":\"no focused pane\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.navigate_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // Use actual session effective dimensions from the latest client.
    const total_cols: u16 = entry.effective_cols;
    const total_rows: u16 = entry.effective_rows;

    const new_slot = navigation.findPaneInDirection(
        &entry.session.tree_nodes,
        total_cols,
        total_rows,
        current_slot,
        direction,
    );

    var focused_pane_id: types.PaneId = 0;
    const focus_changed = if (new_slot) |ns| blk: {
        entry.session.focused_pane = ns;
        if (entry.getPaneAtSlot(ns)) |pane| {
            focused_pane_id = pane.pane_id;
        }
        break :blk ns != current_slot;
    } else blk: {
        // No navigation target; focus stays.
        if (entry.getPaneAtSlot(current_slot)) |pane| {
            focused_pane_id = pane.pane_id;
        }
        break :blk false;
    };

    // Response.
    var json_buffer: [128]u8 = undefined;
    const response_json = std.fmt.bufPrint(&json_buffer, "{{\"status\":0,\"focused_pane_id\":{d}}}", .{focused_pane_id}) catch return;
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.navigate_pane_response), sequence, response_json) orelse return;
    client.enqueueDirect(response) catch {};

    if (focus_changed) {
        broadcastLayoutChanged(ctx, client, entry);
    }
}

// ── ResizePaneRequest (0x014A) ──────────────────────────────────────────────

/// Handles ResizePaneRequest. Per ADR 00062, uses orientation (not direction)
/// and delta_ratio in fixed-point x10^4 units. Finds nearest ancestor split
/// matching orientation and applies new_ratio = old_ratio + delta_ratio,
/// clamped to [MIN_RATIO, RATIO_SCALE - MIN_RATIO].
pub fn handleResizePane(
    ctx: *PaneHandlerContext,
    client: *ClientState,
    _: u16,
    sequence: u64,
    session_id: types.SessionId,
    target_pane_id: types.PaneId,
    orientation: types.Orientation,
    delta_ratio: i32,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err = "{\"status\":1,\"error\":\"pane not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.resize_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    const target_slot = entry.findPaneSlotByPaneId(target_pane_id) orelse {
        const err = "{\"status\":1,\"error\":\"pane not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.resize_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // Find nearest ancestor split matching orientation.
    // Use a direction-based lookup mapped from orientation.
    const probe_direction: types.Direction = switch (orientation) {
        .horizontal => .right,
        .vertical => .down,
    };
    const split_index = split_tree.findAdjacentSplit(&entry.session.tree_nodes, target_slot, probe_direction) orelse {
        const err = "{\"status\":2,\"error\":\"no split in that orientation\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.resize_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // Apply delta_ratio with integer arithmetic. Clamp to [MIN_RATIO, RATIO_SCALE - MIN_RATIO].
    if (entry.session.tree_nodes[split_index]) |*node| {
        switch (node.*) {
            .split => |*s| {
                const old: i32 = @intCast(s.ratio);
                const new_ratio = old + delta_ratio;
                const min: i32 = @intCast(types.MIN_RATIO);
                const max: i32 = @intCast(types.RATIO_SCALE - types.MIN_RATIO);
                s.ratio = @intCast(std.math.clamp(new_ratio, min, max));
            },
            .leaf => {},
        }
    }

    // Response.
    const ok_json = "{\"status\":0}";
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.resize_pane_response), sequence, ok_json) orelse return;
    client.enqueueDirect(response) catch {};

    broadcastLayoutChanged(ctx, client, entry);
}

// ── EqualizeSplitsRequest (0x014C) ──────────────────────────────────────────

/// Handles EqualizeSplitsRequest.
pub fn handleEqualizeSplits(
    ctx: *PaneHandlerContext,
    client: *ClientState,
    _: u16,
    sequence: u64,
    session_id: types.SessionId,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err = "{\"status\":1,\"error\":\"session not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.equalize_splits_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    split_tree.equalizeRatios(&entry.session.tree_nodes);

    const ok_json = "{\"status\":0}";
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.equalize_splits_response), sequence, ok_json) orelse return;
    client.enqueueDirect(response) catch {};

    broadcastLayoutChanged(ctx, client, entry);
}

// ── ZoomPaneRequest (0x014E) ────────────────────────────────────────────────

/// Handles ZoomPaneRequest. Toggles zoom state.
pub fn handleZoomPane(
    ctx: *PaneHandlerContext,
    client: *ClientState,
    _: u16,
    sequence: u64,
    session_id: types.SessionId,
    target_pane_id: types.PaneId,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err = "{\"status\":1,\"error\":\"pane not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.zoom_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    const target_slot = entry.findPaneSlotByPaneId(target_pane_id) orelse {
        const err = "{\"status\":1,\"error\":\"pane not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.zoom_pane_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    entry.toggleZoom(target_slot);

    var json_buffer: [64]u8 = undefined;
    const response_json = std.fmt.bufPrint(&json_buffer, "{{\"status\":0,\"zoomed\":{}}}", .{entry.isZoomed()}) catch return;
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.zoom_pane_response), sequence, response_json) orelse return;
    client.enqueueDirect(response) catch {};

    broadcastLayoutChanged(ctx, client, entry);
}

// ── SwapPanesRequest (0x0150) ───────────────────────────────────────────────

/// Handles SwapPanesRequest.
pub fn handleSwapPanes(
    ctx: *PaneHandlerContext,
    client: *ClientState,
    _: u16,
    sequence: u64,
    session_id: types.SessionId,
    pane_a_id: types.PaneId,
    pane_b_id: types.PaneId,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err = "{\"status\":1,\"error\":\"pane not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.swap_panes_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    const slot_a = entry.findPaneSlotByPaneId(pane_a_id) orelse {
        const err = "{\"status\":1,\"error\":\"pane_a not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.swap_panes_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    const slot_b = entry.findPaneSlotByPaneId(pane_b_id) orelse {
        const err = "{\"status\":2,\"error\":\"pane_b not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.swap_panes_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    _ = split_tree.swapLeaves(&entry.session.tree_nodes, slot_a, slot_b);

    const ok_json = "{\"status\":0}";
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.swap_panes_response), sequence, ok_json) orelse return;
    client.enqueueDirect(response) catch {};

    broadcastLayoutChanged(ctx, client, entry);
}

// ── LayoutGetRequest (0x0152) ───────────────────────────────────────────────

/// Handles LayoutGetRequest. Builds the same payload as LayoutChanged but
/// sends as a response with RESPONSE flag.
pub fn handleLayoutGet(
    ctx: *PaneHandlerContext,
    client: *ClientState,
    _: u16,
    sequence: u64,
    session_id: types.SessionId,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err = "{\"status\":1,\"error\":\"session not found\"}";
        const r = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.layout_get_response), sequence, err) orelse return;
        client.enqueueDirect(r) catch {};
        return;
    };

    // Build the layout tree JSON, then assemble the full response payload.
    var tree_buffer: [4096]u8 = @splat(0);
    const tree_json = buildLayoutPayload(entry, &tree_buffer) orelse return;

    var json_buffer: [6144]u8 = @splat(0);
    const layout_json = std.fmt.bufPrint(&json_buffer, "{{\"session_id\":{d},\"active_pane_id\":{d},\"zoomed_pane_present\":{},\"zoomed_pane_id\":{d},\"layout_tree\":{s}}}", .{
        entry.session.session_id,
        entry.getPaneIdOrNone(entry.session.focused_pane),
        entry.isZoomed(),
        entry.getPaneIdOrNone(entry.zoomed_pane),
        tree_json,
    }) catch return;
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.layout_get_response), sequence, layout_json) orelse return;
    client.enqueueDirect(response) catch {};
}

// ── Shared helpers ──────────────────────────────────────────────────────────

fn broadcastLayoutChanged(
    ctx: *PaneHandlerContext,
    client: *ClientState,
    entry: *SessionEntry,
) void {
    var tree_buffer: [4096]u8 = @splat(0);
    const tree_json = buildLayoutPayload(entry, &tree_buffer) orelse return;

    var notification_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notification_sequence = client.connection.advanceSendSequence();

    const notification = notification_builder.buildLayoutChanged(
        entry.session.session_id,
        entry.getPaneIdOrNone(entry.session.focused_pane),
        entry.isZoomed(),
        entry.getPaneIdOrNone(entry.zoomed_pane),
        tree_json,
        notification_sequence,
        &notification_buffer,
    ) orelse return;

    _ = broadcast_mod.broadcastToSession(
        ctx.client_manager,
        entry.session.session_id,
        notification,
        null,
    );
}

/// Serializes the layout tree of a session entry into JSON. Returns only
/// the tree node JSON (leaf/split), not the full LayoutChanged wrapper.
/// Callers use notification_builder.buildLayoutChanged to assemble the
/// complete notification payload.
pub fn buildLayoutPayload(entry: *SessionEntry, out_buffer: []u8) ?[]const u8 {
    return notification_builder.serializeLayoutTree(
        entry,
        entry.effective_cols,
        entry.effective_rows,
        entry.session.getActiveInputMethod(),
        entry.session.getActiveKeyboardLayout(),
        out_buffer,
    );
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "handleEqualizeSplits: equalizes split ratios" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot_index = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot_index).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    const S = struct {
        var session_manager = SessionManager.init();
    };
    S.session_manager.reset();
    _ = S.session_manager.createSession("test", helpers.testImeEngine(), 0) catch unreachable;
    const entry = S.session_manager.getSession(1).?;

    // Set up a split with non-equal ratio.
    const slot0: types.PaneSlot = 0;
    entry.setPaneAtSlot(slot0, Pane.init(1, slot0, -1, 0, 80, 24));
    const slot1 = entry.allocPaneSlot() catch unreachable;
    entry.setPaneAtSlot(slot1, Pane.init(2, slot1, -1, 0, 80, 24));
    split_tree.splitLeaf(&entry.session.tree_nodes, 0, .horizontal, 3000, slot1) catch unreachable;

    var context = PaneHandlerContext{
        .session_manager = &S.session_manager,
        .client_manager = &client_manager,
    };

    handleEqualizeSplits(&context, client, slot_index, 1, 1);

    // Verify ratio is now EQUAL_RATIO (5000).
    if (entry.session.tree_nodes[0]) |node| {
        switch (node) {
            .split => |s| try std.testing.expectEqual(types.EQUAL_RATIO, s.ratio),
            .leaf => unreachable,
        }
    }

    client.deinit();
}

test "buildLayoutPayload: returns only layout tree JSON without wrapper fields" {
    const helpers = @import("itshell3_testing").helpers;
    const S = struct {
        var session_manager = SessionManager.init();
    };
    S.session_manager.reset();
    _ = S.session_manager.createSession("test", helpers.testImeEngine(), 0) catch unreachable;
    const entry = S.session_manager.getSession(1).?;
    const slot0: types.PaneSlot = 0;
    entry.setPaneAtSlot(slot0, Pane.init(1, slot0, -1, 0, 80, 24));

    var tree_buffer: [4096]u8 = @splat(0);
    const payload = buildLayoutPayload(entry, &tree_buffer);
    try std.testing.expect(payload != null);
    const json = payload.?;

    // The payload should be ONLY the layout tree (a leaf/split node), NOT a
    // wrapper object containing session_id, active_pane_id, etc.
    // If it contains "session_id", the payload is double-nested.
    try std.testing.expect(std.mem.indexOf(u8, json, "\"session_id\"") == null);
    // It should contain tree node content.
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"leaf\"") != null);
}

test "handleZoomPane: toggles zoom state" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot_index = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot_index).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    const S = struct {
        var session_manager = SessionManager.init();
    };
    S.session_manager.reset();
    _ = S.session_manager.createSession("test", helpers.testImeEngine(), 0) catch unreachable;
    const entry = S.session_manager.getSession(1).?;
    const slot0: types.PaneSlot = 0;
    entry.setPaneAtSlot(slot0, Pane.init(1, slot0, -1, 0, 80, 24));

    var context = PaneHandlerContext{
        .session_manager = &S.session_manager,
        .client_manager = &client_manager,
    };

    try std.testing.expect(!entry.isZoomed());
    handleZoomPane(&context, client, slot_index, 1, 1, 1);
    try std.testing.expect(entry.isZoomed());

    client.deinit();
}
