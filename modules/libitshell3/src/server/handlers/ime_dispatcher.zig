//! Dispatcher for CJK and IME messages (0x04xx range).
//! Handles InputMethodSwitch (0x0404) and AmbiguousWidthConfig (0x0406).
//!
//! Per protocol 05-cjk-preedit-protocol.

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const message_dispatcher = @import("message_dispatcher.zig");
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;
const handler_utils = @import("handler_utils.zig");
const envelope = @import("protocol_envelope.zig");
const ime_error_builder = @import("ime_error_builder.zig");
const ErrorCode = ime_error_builder.ErrorCode;
const server = @import("itshell3_server");
const procedures = server.ime.procedures;
const BroadcastContext = procedures.BroadcastContext;
const core = @import("itshell3_core");
const types = core.types;
const interfaces = server.os.interfaces;

/// Dispatches an IME-category message.
pub fn dispatch(params: CategoryDispatchParams) void {
    switch (params.msg_type) {
        .input_method_switch => handleInputMethodSwitch(params),
        .ambiguous_width_config => handleAmbiguousWidthConfig(params),
        else => {},
    }
}

/// Handles InputMethodSwitch (0x0404, C->S).
fn handleInputMethodSwitch(params: CategoryDispatchParams) void {
    const client = params.client;
    const payload = params.payload;
    const sequence = params.header.sequence;

    // Parse fields from payload.
    const pane_id = extractU32Field(payload, "pane_id") orelse 0;
    const commit_current = extractBoolField(payload, "commit_current") orelse true;
    const input_method = extractStringField(payload, "input_method") orelse "direct";

    // Resolve session from pane_id.
    const entry = resolveSessionFromPaneId(params, pane_id) orelse {
        var buf: ime_error_builder.ScratchBuf = undefined;
        if (ime_error_builder.buildIMEError(pane_id, @intFromEnum(ErrorCode.pane_not_found), "Pane does not exist", sequence, &buf)) |msg| {
            client.enqueueDirect(msg) catch {};
        }
        return;
    };

    // Validate input method is supported.
    if (!isSupportedInputMethod(input_method)) {
        var buf: ime_error_builder.ScratchBuf = undefined;
        if (ime_error_builder.buildIMEError(pane_id, @intFromEnum(ErrorCode.unknown_input_method), "Unknown input method", sequence, &buf)) |msg| {
            client.enqueueDirect(msg) catch {};
        }
        return;
    }

    // Build broadcast context.
    var seq = sequence;
    var bc = BroadcastContext{
        .client_manager = params.context.client_manager,
        .session_id = entry.session.session_id,
        .pane_id = pane_id,
        .sequence = &seq,
    };

    // Resolve PTY fd and ops for the focused pane.
    const focused_pane = entry.focusedPane();
    const pty_fd: std.posix.fd_t = if (focused_pane) |p| p.pty_fd else -1;
    const pty_ops = params.context.pty_ops orelse {
        // No PTY ops available -- cannot write committed text.
        // Still perform the switch logic without PTY write.
        procedures.onInputMethodSwitchWithBroadcast(
            &entry.session,
            input_method,
            commit_current,
            pty_fd,
            // Use a minimal no-op pty ops. The procedure will try to write
            // but the write call will be skipped if no committed text.
            &no_op_pty_ops,
            &bc,
        );
        client.recordActivity();
        return;
    };

    procedures.onInputMethodSwitchWithBroadcast(
        &entry.session,
        input_method,
        commit_current,
        pty_fd,
        pty_ops,
        &bc,
    );

    client.recordActivity();
}

/// Handles AmbiguousWidthConfig (0x0406).
fn handleAmbiguousWidthConfig(params: CategoryDispatchParams) void {
    // AmbiguousWidthConfig pass-through to terminal instances.
    // TODO(Plan 9): Apply ambiguous_width to ghostty Terminal instances
    // once frame export pipeline is wired.
    params.client.recordActivity();
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Whether an input method identifier is supported in v1.
fn isSupportedInputMethod(method: []const u8) bool {
    return std.mem.eql(u8, method, "direct") or
        std.mem.eql(u8, method, "korean_2set");
}

/// Resolves a SessionEntry from a pane_id.
fn resolveSessionFromPaneId(
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

/// No-op PTY operations for when no real PTY ops are available.
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

/// Extracts a u32 field from JSON payload using simple string search.
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

/// Extracts a bool field from JSON payload using simple string search.
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

/// Extracts a string field value from JSON payload (no allocation).
fn extractStringField(payload: []const u8, field: []const u8) ?[]const u8 {
    var search_buf: [64]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\":\"", .{field}) catch return null;
    const pos = std.mem.indexOf(u8, payload, search) orelse return null;
    const after = payload[pos + search.len ..];
    const end = std.mem.indexOf(u8, after, "\"") orelse return null;
    return after[0..end];
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "isSupportedInputMethod: direct and korean_2set are supported" {
    try std.testing.expect(isSupportedInputMethod("direct"));
    try std.testing.expect(isSupportedInputMethod("korean_2set"));
    try std.testing.expect(!isSupportedInputMethod("japanese_romaji"));
    try std.testing.expect(!isSupportedInputMethod("foobar"));
}

test "extractU32Field: parses integer from JSON" {
    const payload = "{\"pane_id\":42,\"other\":1}";
    try std.testing.expectEqual(@as(?u32, 42), extractU32Field(payload, "pane_id"));
    try std.testing.expectEqual(@as(?u32, 1), extractU32Field(payload, "other"));
    try std.testing.expect(extractU32Field(payload, "missing") == null);
}

test "extractBoolField: parses boolean from JSON" {
    const payload = "{\"commit_current\":true,\"flag\":false}";
    try std.testing.expectEqual(@as(?bool, true), extractBoolField(payload, "commit_current"));
    try std.testing.expectEqual(@as(?bool, false), extractBoolField(payload, "flag"));
}

test "extractStringField: extracts string value from JSON" {
    const payload = "{\"input_method\":\"korean_2set\",\"layout\":\"qwerty\"}";
    const im = extractStringField(payload, "input_method");
    try std.testing.expect(im != null);
    try std.testing.expectEqualSlices(u8, "korean_2set", im.?);
}
