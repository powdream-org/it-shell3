//! Dispatcher for input forwarding messages (0x02xx range).
//! Handles KeyEvent (0x0200), TextInput (0x0201), PasteData (0x0205),
//! and FocusEvent (0x0206). Implements 5-tier input processing priority.
//!
//! Per protocol 04-input-and-renderstate and daemon-behavior policies-and-procedures.

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const message_dispatcher = @import("message_dispatcher.zig");
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;
const server = @import("itshell3_server");
const core = @import("itshell3_core");
const types = core.types;
const input = @import("itshell3_input");
const interfaces = server.os.interfaces;
const ime_consumer = server.ime.consumer;
const procedures = server.ime.procedures;
const BroadcastContext = procedures.BroadcastContext;
const preedit_builder = server.handlers.preedit_message_builder;
const broadcast_mod = server.connection.broadcast;

/// Dispatches an input-category message with priority ordering.
/// P1: KeyEvent (0x0200), TextInput (0x0201) — highest priority.
/// P2: MouseButton/Scroll — deferred to Plan 17+.
/// P3: MouseMove — deferred to Plan 17+.
/// P4: PasteData (0x0205).
/// P5: FocusEvent (0x0206) — lowest priority.
///
/// Within a single dispatch call, messages are processed individually.
/// Priority ordering is applied when multiple messages are batched
/// in the event loop (future Plan 9 event batching).
pub fn dispatch(params: CategoryDispatchParams) void {
    switch (params.msg_type) {
        .key_event => handleKeyEvent(params),
        .text_input => handleTextInput(params),
        .paste_data => handlePasteData(params),
        .focus_event => handleFocusEvent(params),
        else => {},
    }
}

/// Priority tier for input message ordering.
pub const InputPriority = enum(u8) {
    /// P1: KeyEvent, TextInput — interactive keystroke path.
    p1_key_text = 1,
    /// P2: MouseButton, MouseScroll — deferred to Plan 17+.
    p2_mouse_button = 2,
    /// P3: MouseMove — deferred to Plan 17+.
    p3_mouse_move = 3,
    /// P4: PasteData — bulk data, lower than interactive input.
    p4_paste = 4,
    /// P5: FocusEvent — state notification, lowest priority.
    p5_focus = 5,
};

/// Returns the priority tier for a message type.
pub fn priorityOf(msg_type: MessageType) InputPriority {
    return switch (msg_type) {
        .key_event, .text_input => .p1_key_text,
        .paste_data => .p4_paste,
        .focus_event => .p5_focus,
        else => .p5_focus,
    };
}

// ── KeyEvent (0x0200) ──────────────────────────────────────────────────────

fn handleKeyEvent(params: CategoryDispatchParams) void {
    const client = params.client;
    const payload = params.payload;

    // Parse wire fields from JSON payload.
    const keycode = extractU16Field(payload, "keycode") orelse return;
    const action_raw = extractU8Field(payload, "action") orelse 0;
    const modifiers = extractU8Field(payload, "modifiers") orelse 0;
    const pane_id = extractU32Field(payload, "pane_id") orelse 0;

    // Convert action to enum.
    const action: core.KeyEvent.Action = switch (action_raw) {
        0 => .press,
        1 => .release,
        2 => .repeat,
        else => .press,
    };

    // Decompose wire event to internal KeyEvent.
    const key = input.decomposeWireEvent(keycode, modifiers, action);

    // Resolve target session entry.
    const entry = resolveSessionEntry(params, pane_id) orelse return;

    // Update latest_client_id on the session entry.
    entry.latest_client_id = client.getClientId();

    // Preedit ownership transfer if a different client is composing.
    const session = &entry.session;
    if (session.preedit.owner) |owner| {
        if (owner != client.getClientId()) {
            var seq = params.header.sequence;
            const resolved_pane_id = if (pane_id == 0)
                entry.getPaneIdOrNone(session.focused_pane)
            else
                pane_id;
            var bc = BroadcastContext{
                .client_manager = params.context.client_manager,
                .session_id = session.session_id,
                .pane_id = resolved_pane_id,
                .sequence = &seq,
            };
            const focused = entry.focusedPane();
            const pty_fd: std.posix.fd_t = if (focused) |p| p.pty_fd else -1;
            const pty_ops = params.context.pty_ops orelse &no_op_pty_ops;
            procedures.ownershipTransferWithBroadcast(session, pty_fd, pty_ops, client.getClientId(), &bc);
        }
    }

    // Route through Phase 0 + Phase 1.
    const toggle_bindings = [_]input.ToggleBinding{
        .{ .hid_keycode = 0xE6, .toggle_method = "korean_2set" }, // Right Alt
    };
    const result = input.handleKeyEvent(session.ime_engine, key, &toggle_bindings);

    // Phase 2: consume the result.
    const focused = entry.focusedPane();
    const pty_fd: std.posix.fd_t = if (focused) |p| p.pty_fd else -1;
    const pty_ops = params.context.pty_ops orelse &no_op_pty_ops;

    switch (result) {
        .consumed => |ime_result| {
            _ = ime_consumer.consumeImeResult(ime_result, session, pty_fd, pty_ops, null);
        },
        .bypassed => |bypass_key| {
            // Encode via ghostty key_encode and write to PTY.
            _ = bypass_key;
            // TODO(Plan 9): Wire ghostty key_encode for bypassed keys.
        },
        .processed => |ime_result| {
            const preedit_dirty = ime_consumer.consumeImeResult(ime_result, session, pty_fd, pty_ops, null);

            // Broadcast preedit messages based on state transitions.
            if (preedit_dirty) {
                broadcastPreeditState(params, entry, session);
            }
        },
    }

    client.recordActivity();
}

/// Broadcasts preedit state changes (PreeditStart, PreeditUpdate, or PreeditEnd).
fn broadcastPreeditState(
    params: CategoryDispatchParams,
    entry: *server.state.session_entry.SessionEntry,
    session: *core.session.Session,
) void {
    const pane_id = entry.getPaneIdOrNone(session.focused_pane);
    var seq = params.header.sequence;

    if (session.current_preedit) |preedit_text| {
        // Active preedit -- send PreeditUpdate (or PreeditStart if new session).
        if (session.preedit.owner == null) {
            // New composition -- set owner and send PreeditStart.
            session.preedit.owner = params.client.getClientId();
            var start_buf: preedit_builder.ScratchBuf = undefined;
            seq += 1;
            if (preedit_builder.buildPreeditStart(
                pane_id,
                params.client.getClientId(),
                session.getActiveInputMethod(),
                session.preedit.session_id,
                seq,
                &start_buf,
            )) |msg| {
                _ = broadcast_mod.broadcastToSession(
                    params.context.client_manager,
                    session.session_id,
                    msg,
                    null,
                );
            }
        }
        // Send PreeditUpdate.
        var update_buf: preedit_builder.ScratchBuf = undefined;
        seq += 1;
        if (preedit_builder.buildPreeditUpdate(
            pane_id,
            session.preedit.session_id,
            preedit_text,
            seq,
            &update_buf,
        )) |msg| {
            _ = broadcast_mod.broadcastToSession(
                params.context.client_manager,
                session.session_id,
                msg,
                null,
            );
        }
    } else {
        // Preedit cleared -- send PreeditEnd if there was an owner.
        if (session.preedit.owner != null) {
            var end_buf: preedit_builder.ScratchBuf = undefined;
            seq += 1;
            if (preedit_builder.buildPreeditEnd(
                pane_id,
                session.preedit.session_id,
                "committed",
                "",
                seq,
                &end_buf,
            )) |msg| {
                _ = broadcast_mod.broadcastToSession(
                    params.context.client_manager,
                    session.session_id,
                    msg,
                    null,
                );
            }
        }
    }
}

// ── TextInput (0x0201) ─────────────────────────────────────────────────────

fn handleTextInput(params: CategoryDispatchParams) void {
    const payload = params.payload;

    const pane_id = extractU32Field(payload, "pane_id") orelse 0;
    const text = extractStringField(payload, "text") orelse return;

    // Validate text length.
    if (text.len > 65535) return;

    const entry = resolveSessionEntry(params, pane_id) orelse return;
    const pane = resolvePaneInEntry(entry, pane_id) orelse return;
    const pty_ops = params.context.pty_ops orelse &no_op_pty_ops;

    // Write directly to PTY (bypass IME).
    _ = pty_ops.write(pane.pty_fd, text) catch {};

    params.client.recordActivity();
}

// ── PasteData (0x0205) ─────────────────────────────────────────────────────

fn handlePasteData(params: CategoryDispatchParams) void {
    const payload = params.payload;

    const pane_id = extractU32Field(payload, "pane_id") orelse 0;
    const bracketed_paste = extractBoolField(payload, "bracketed_paste") orelse false;
    const first_chunk = extractBoolField(payload, "first_chunk") orelse true;
    const final_chunk = extractBoolField(payload, "final_chunk") orelse true;
    const data = extractStringField(payload, "data") orelse return;

    const entry = resolveSessionEntry(params, pane_id) orelse return;
    const pane = resolvePaneInEntry(entry, pane_id) orelse return;
    const pty_ops = params.context.pty_ops orelse &no_op_pty_ops;

    // Bracketed paste prefix.
    if (first_chunk and bracketed_paste) {
        _ = pty_ops.write(pane.pty_fd, "\x1b[200~") catch {};
    }

    // Write paste data.
    _ = pty_ops.write(pane.pty_fd, data) catch {};

    // Bracketed paste suffix.
    if (final_chunk and bracketed_paste) {
        _ = pty_ops.write(pane.pty_fd, "\x1b[201~") catch {};
    }

    params.client.recordActivity();
}

// ── FocusEvent (0x0206) ────────────────────────────────────────────────────

fn handleFocusEvent(params: CategoryDispatchParams) void {
    const payload = params.payload;

    const pane_id = extractU32Field(payload, "pane_id") orelse 0;
    const focused = extractBoolField(payload, "focused") orelse true;

    const entry = resolveSessionEntry(params, pane_id) orelse return;
    const pane = resolvePaneInEntry(entry, pane_id) orelse return;
    const pty_ops = params.context.pty_ops orelse &no_op_pty_ops;

    // Focus reporting (CSI ? 1004 h). The terminal's focus reporting mode
    // is tracked by ghostty. Since we don't have direct access to the mode
    // flag here, we write the escape sequence unconditionally. The terminal
    // application will ignore it if focus reporting is not enabled.
    // TODO(Plan 9): Check terminal focus_reporting mode flag before writing.
    if (focused) {
        _ = pty_ops.write(pane.pty_fd, "\x1b[I") catch {};
    } else {
        _ = pty_ops.write(pane.pty_fd, "\x1b[O") catch {};
    }

    params.client.recordActivity();
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn resolveSessionEntry(
    params: CategoryDispatchParams,
    pane_id: types.PaneId,
) ?*server.state.session_entry.SessionEntry {
    if (pane_id == 0) {
        return params.client.attached_session;
    }
    const session_manager = params.context.session_manager;
    var i: u32 = 0;
    while (i < types.MAX_SESSIONS) : (i += 1) {
        if (session_manager.findSessionBySlot(i)) |entry| {
            if (entry.findPaneSlotByPaneId(pane_id) != null) {
                return entry;
            }
        }
    }
    return null;
}

fn resolvePaneInEntry(
    entry: *server.state.session_entry.SessionEntry,
    pane_id: types.PaneId,
) ?*server.state.pane.Pane {
    if (pane_id == 0) {
        return entry.focusedPane();
    }
    if (entry.findPaneSlotByPaneId(pane_id)) |slot| {
        return entry.getPaneAtSlot(slot);
    }
    return null;
}

/// No-op PTY operations fallback.
fn noOpWrite(_: std.posix.fd_t, data: []const u8) interfaces.PtyOps.WriteError!usize {
    return data.len;
}

fn noOpRead(_: std.posix.fd_t, _: []u8) interfaces.PtyOps.ReadError!usize {
    return 0;
}

fn noOpFork(_: u16, _: u16) interfaces.PtyOps.ForkPtyError!interfaces.PtyOps.ForkPtyResult {
    return .{ .master_fd = -1, .child_pid = 0 };
}

fn noOpResize(_: std.posix.fd_t, _: u16, _: u16) interfaces.PtyOps.ResizeError!void {}

fn noOpClose(_: std.posix.fd_t) void {}

const no_op_pty_ops = interfaces.PtyOps{
    .forkPty = noOpFork,
    .resize = noOpResize,
    .close = noOpClose,
    .read = noOpRead,
    .write = noOpWrite,
};

fn extractU32Field(payload: []const u8, field: []const u8) ?u32 {
    var search_buf: [64]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{field}) catch return null;
    const pos = std.mem.indexOf(u8, payload, search) orelse return null;
    const after = payload[pos + search.len ..];
    var start: usize = 0;
    while (start < after.len and (after[start] == ' ' or after[start] == '\t')) : (start += 1) {}
    if (start >= after.len) return null;
    var end = start;
    while (end < after.len and after[end] >= '0' and after[end] <= '9') : (end += 1) {}
    if (end == start) return null;
    return std.fmt.parseInt(u32, after[start..end], 10) catch null;
}

fn extractU16Field(payload: []const u8, field: []const u8) ?u16 {
    const val = extractU32Field(payload, field) orelse return null;
    if (val > std.math.maxInt(u16)) return null;
    return @intCast(val);
}

fn extractU8Field(payload: []const u8, field: []const u8) ?u8 {
    const val = extractU32Field(payload, field) orelse return null;
    if (val > std.math.maxInt(u8)) return null;
    return @intCast(val);
}

fn extractBoolField(payload: []const u8, field: []const u8) ?bool {
    var search_buf: [64]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{field}) catch return null;
    const pos = std.mem.indexOf(u8, payload, search) orelse return null;
    const after = payload[pos + search.len ..];
    var start: usize = 0;
    while (start < after.len and (after[start] == ' ' or after[start] == '\t')) : (start += 1) {}
    if (start >= after.len) return null;
    if (after.len - start >= 4 and std.mem.eql(u8, after[start .. start + 4], "true")) return true;
    if (after.len - start >= 5 and std.mem.eql(u8, after[start .. start + 5], "false")) return false;
    return null;
}

fn extractStringField(payload: []const u8, field: []const u8) ?[]const u8 {
    var search_buf: [64]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\":\"", .{field}) catch return null;
    const pos = std.mem.indexOf(u8, payload, search) orelse return null;
    const after = payload[pos + search.len ..];
    const end = std.mem.indexOf(u8, after, "\"") orelse return null;
    return after[0..end];
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "priorityOf: correct priority tiers per spec" {
    try std.testing.expectEqual(InputPriority.p1_key_text, priorityOf(.key_event));
    try std.testing.expectEqual(InputPriority.p1_key_text, priorityOf(.text_input));
    try std.testing.expectEqual(InputPriority.p4_paste, priorityOf(.paste_data));
    try std.testing.expectEqual(InputPriority.p5_focus, priorityOf(.focus_event));
}

test "extractU32Field: parses integer from JSON" {
    const payload = "{\"pane_id\":42}";
    try std.testing.expectEqual(@as(?u32, 42), extractU32Field(payload, "pane_id"));
}

test "extractStringField: extracts string value" {
    const payload = "{\"text\":\"Hello\"}";
    const text = extractStringField(payload, "text");
    try std.testing.expect(text != null);
    try std.testing.expectEqualSlices(u8, "Hello", text.?);
}

test "extractBoolField: parses booleans" {
    try std.testing.expectEqual(@as(?bool, true), extractBoolField("{\"focused\":true}", "focused"));
    try std.testing.expectEqual(@as(?bool, false), extractBoolField("{\"focused\":false}", "focused"));
}
