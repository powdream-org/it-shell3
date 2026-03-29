//! Builds JSON payloads for always-sent notifications, wrapped with protocol
//! headers. All builders use fixed-size scratch buffers (no heap allocation).
//!
//! Per protocol 03-session-pane-management (0x0180-0x0184 notifications).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const envelope = @import("protocol_envelope.zig");
const core = @import("itshell3_core");
const types = core.types;
const split_tree = core.split_tree;

/// Maximum size for notification JSON payloads.
const MAX_NOTIFICATION_JSON: usize = 6144;

/// Scratch buffer type for notification building.
const ScratchBuf = [envelope.MAX_ENVELOPE_SIZE]u8;

// ── SessionListChanged (0x0182) ─────────────────────────────────────────────

/// Builds a SessionListChanged notification.
pub fn buildSessionListChanged(
    event: []const u8,
    session_id: types.SessionId,
    session_name: []const u8,
    sequence: u32,
    out_buf: *ScratchBuf,
) ?[]const u8 {
    var json_buf: [MAX_NOTIFICATION_JSON]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"event\":\"{s}\",\"session_id\":{d},\"name\":\"{s}\"}}", .{
        event,
        session_id,
        session_name,
    }) catch return null;

    return envelope.wrapNotification(
        out_buf,
        @intFromEnum(MessageType.session_list_changed),
        sequence,
        json,
    );
}

// ── ClientAttached (0x0183) ─────────────────────────────────────────────────

/// Builds a ClientAttached notification.
pub fn buildClientAttached(
    session_id: types.SessionId,
    client_id: types.ClientId,
    client_name: []const u8,
    attached_clients: u32,
    sequence: u32,
    out_buf: *ScratchBuf,
) ?[]const u8 {
    var json_buf: [MAX_NOTIFICATION_JSON]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"session_id\":{d},\"client_id\":{d},\"client_name\":\"{s}\",\"attached_clients\":{d}}}", .{
        session_id,
        client_id,
        client_name,
        attached_clients,
    }) catch return null;

    return envelope.wrapNotification(
        out_buf,
        @intFromEnum(MessageType.client_attached),
        sequence,
        json,
    );
}

// ── ClientDetached (0x0184) ─────────────────────────────────────────────────

/// Builds a ClientDetached notification.
pub fn buildClientDetached(
    session_id: types.SessionId,
    client_id: types.ClientId,
    client_name: []const u8,
    reason: []const u8,
    attached_clients: u32,
    sequence: u32,
    out_buf: *ScratchBuf,
) ?[]const u8 {
    var json_buf: [MAX_NOTIFICATION_JSON]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"session_id\":{d},\"client_id\":{d},\"client_name\":\"{s}\",\"reason\":\"{s}\",\"attached_clients\":{d}}}", .{
        session_id,
        client_id,
        client_name,
        reason,
        attached_clients,
    }) catch return null;

    return envelope.wrapNotification(
        out_buf,
        @intFromEnum(MessageType.client_detached),
        sequence,
        json,
    );
}

// ── PaneMetadataChanged (0x0181) ────────────────────────────────────────────

/// Builds a PaneMetadataChanged notification with only the changed fields.
pub fn buildPaneMetadataChanged(
    session_id: types.SessionId,
    pane_id: types.PaneId,
    title: ?[]const u8,
    cwd: ?[]const u8,
    sequence: u32,
    out_buf: *ScratchBuf,
) ?[]const u8 {
    var json_buf: [MAX_NOTIFICATION_JSON]u8 = undefined;
    var stream = std.io.fixedBufferStream(&json_buf);
    const writer = stream.writer();

    writer.writeAll("{") catch return null;
    writer.print("\"session_id\":{d},\"pane_id\":{d}", .{ session_id, pane_id }) catch return null;

    if (title) |t| {
        writer.print(",\"title\":\"{s}\"", .{t}) catch return null;
    }
    if (cwd) |c| {
        writer.print(",\"cwd\":\"{s}\"", .{c}) catch return null;
    }

    writer.writeAll("}") catch return null;

    const json = stream.getWritten();
    return envelope.wrapNotification(
        out_buf,
        @intFromEnum(MessageType.pane_metadata_changed),
        sequence,
        json,
    );
}

// ── LayoutChanged (0x0180) ──────────────────────────────────────────────────

/// Builds a LayoutChanged notification with the full layout tree.
pub fn buildLayoutChanged(
    session_id: types.SessionId,
    active_pane_id: types.PaneId,
    zoomed_pane_present: bool,
    zoomed_pane_id: types.PaneId,
    layout_tree_json: []const u8,
    sequence: u32,
    out_buf: *ScratchBuf,
) ?[]const u8 {
    var json_buf: [MAX_NOTIFICATION_JSON]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"session_id\":{d},\"active_pane_id\":{d},\"zoomed_pane_present\":{},\"zoomed_pane_id\":{d},\"layout_tree\":{s}}}", .{
        session_id,
        active_pane_id,
        zoomed_pane_present,
        zoomed_pane_id,
        layout_tree_json,
    }) catch return null;

    return envelope.wrapNotification(
        out_buf,
        @intFromEnum(MessageType.layout_changed),
        sequence,
        json,
    );
}

/// Serializes a split tree into the wire layout tree JSON format.
/// Per protocol 03-session-pane-management (recursive layout tree).
pub fn serializeLayoutTree(
    tree: *const [types.MAX_TREE_NODES]?split_tree.SplitNodeData,
    total_cols: u16,
    total_rows: u16,
    active_input_method: []const u8,
    active_keyboard_layout: []const u8,
    pane_id_lookup: *const fn (slot: types.PaneSlot) types.PaneId,
    out_buf: []u8,
) ?[]const u8 {
    var stream = std.io.fixedBufferStream(out_buf);
    const writer = stream.writer();
    serializeNode(
        tree,
        0,
        0,
        0,
        @floatFromInt(total_cols),
        @floatFromInt(total_rows),
        active_input_method,
        active_keyboard_layout,
        pane_id_lookup,
        writer,
    ) catch return null;
    return stream.getWritten();
}

fn serializeNode(
    tree: *const [types.MAX_TREE_NODES]?split_tree.SplitNodeData,
    node_index: u8,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    active_input_method: []const u8,
    active_keyboard_layout: []const u8,
    pane_id_lookup: *const fn (slot: types.PaneSlot) types.PaneId,
    writer: anytype,
) !void {
    if (node_index >= types.MAX_TREE_NODES) return;
    const node = tree[node_index] orelse return;

    switch (node) {
        .leaf => |slot| {
            const pane_id = pane_id_lookup(slot);
            const cols: u16 = @intFromFloat(@round(width));
            const rows: u16 = @intFromFloat(@round(height));
            const x_off: u16 = @intFromFloat(@round(x));
            const y_off: u16 = @intFromFloat(@round(y));
            try writer.print("{{\"type\":\"leaf\",\"pane_id\":{d},\"cols\":{d},\"rows\":{d},\"x_off\":{d},\"y_off\":{d},\"preedit_active\":false,\"active_input_method\":\"{s}\",\"active_keyboard_layout\":\"{s}\"}}", .{
                pane_id,
                cols,
                rows,
                x_off,
                y_off,
                active_input_method,
                active_keyboard_layout,
            });
        },
        .split => |s| {
            const orientation_string: []const u8 = if (s.orientation == .horizontal) "horizontal" else "vertical";
            const cols: u16 = @intFromFloat(@round(width));
            const rows: u16 = @intFromFloat(@round(height));
            const x_off: u16 = @intFromFloat(@round(x));
            const y_off: u16 = @intFromFloat(@round(y));

            try writer.print("{{\"type\":\"split\",\"orientation\":\"{s}\",\"ratio\":{d:.6},\"cols\":{d},\"rows\":{d},\"x_off\":{d},\"y_off\":{d},\"first\":", .{
                orientation_string,
                s.ratio,
                cols,
                rows,
                x_off,
                y_off,
            });

            const left_index = split_tree.leftChild(node_index);
            const right_index = split_tree.rightChild(node_index);

            switch (s.orientation) {
                .horizontal => {
                    const left_width = width * s.ratio;
                    try serializeNode(tree, left_index, x, y, left_width, height, active_input_method, active_keyboard_layout, pane_id_lookup, writer);
                    try writer.writeAll(",\"second\":");
                    try serializeNode(tree, right_index, x + left_width, y, width - left_width, height, active_input_method, active_keyboard_layout, pane_id_lookup, writer);
                },
                .vertical => {
                    const top_height = height * s.ratio;
                    try serializeNode(tree, left_index, x, y, width, top_height, active_input_method, active_keyboard_layout, pane_id_lookup, writer);
                    try writer.writeAll(",\"second\":");
                    try serializeNode(tree, right_index, x, y + top_height, width, height - top_height, active_input_method, active_keyboard_layout, pane_id_lookup, writer);
                },
            }
            try writer.writeAll("}");
        },
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "buildSessionListChanged: produces valid envelope" {
    var buf: ScratchBuf = undefined;
    const result = buildSessionListChanged("created", 1, "test-session", 5, &buf);
    try std.testing.expect(result != null);
    const data = result.?;
    // Verify header.
    const hdr = try protocol.header.Header.decode(data[0..protocol.header.HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, @intFromEnum(MessageType.session_list_changed)), hdr.msg_type);
    try std.testing.expect(!hdr.flags.response);
    // Verify payload contains expected fields.
    const payload = data[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"created\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "test-session") != null);
}

test "buildClientAttached: produces valid envelope" {
    var buf: ScratchBuf = undefined;
    const result = buildClientAttached(1, 42, "iPad", 3, 10, &buf);
    try std.testing.expect(result != null);
    const data = result.?;
    const hdr = try protocol.header.Header.decode(data[0..protocol.header.HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, @intFromEnum(MessageType.client_attached)), hdr.msg_type);
}

test "buildClientDetached: produces valid envelope" {
    var buf: ScratchBuf = undefined;
    const result = buildClientDetached(1, 5, "Mac", "client_requested", 2, 7, &buf);
    try std.testing.expect(result != null);
    const payload = result.?[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "client_requested") != null);
}

test "buildPaneMetadataChanged: includes only changed fields" {
    var buf: ScratchBuf = undefined;

    // Title only.
    const result_title = buildPaneMetadataChanged(1, 10, "vim", null, 1, &buf);
    try std.testing.expect(result_title != null);
    const payload_title = result_title.?[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload_title, "\"title\":\"vim\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload_title, "\"cwd\"") == null);

    // Both title and cwd.
    const result_both = buildPaneMetadataChanged(1, 10, "vim", "/home", 2, &buf);
    try std.testing.expect(result_both != null);
    const payload_both = result_both.?[protocol.header.HEADER_SIZE..];
    try std.testing.expect(std.mem.indexOf(u8, payload_both, "\"title\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload_both, "\"cwd\"") != null);
}

fn testPaneIdLookup(slot: types.PaneSlot) types.PaneId {
    // Simple identity mapping for tests.
    return @as(types.PaneId, slot) + 1;
}

test "serializeLayoutTree: single leaf" {
    const tree = split_tree.initSingleLeaf(0);
    var tree_buf: [4096]u8 = undefined;
    const json = serializeLayoutTree(&tree, 80, 24, "direct", "qwerty", testPaneIdLookup, &tree_buf);
    try std.testing.expect(json != null);
    try std.testing.expect(std.mem.indexOf(u8, json.?, "\"leaf\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.?, "\"pane_id\":1") != null);
}

test "serializeLayoutTree: two panes" {
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    var tree_buf: [4096]u8 = undefined;
    const json = serializeLayoutTree(&tree, 80, 24, "direct", "qwerty", testPaneIdLookup, &tree_buf);
    try std.testing.expect(json != null);
    try std.testing.expect(std.mem.indexOf(u8, json.?, "\"split\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.?, "\"first\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.?, "\"second\"") != null);
}

test "buildLayoutChanged: produces valid envelope with layout tree" {
    var buf: ScratchBuf = undefined;
    const result = buildLayoutChanged(1, 5, false, 0, "{\"type\":\"leaf\"}", 3, &buf);
    try std.testing.expect(result != null);
    const hdr = try protocol.header.Header.decode(result.?[0..protocol.header.HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, @intFromEnum(MessageType.layout_changed)), hdr.msg_type);
}
