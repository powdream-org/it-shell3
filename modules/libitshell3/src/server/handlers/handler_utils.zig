//! Shared utility functions for session and pane handlers. Reduces repetitive
//! error-response and session-lookup patterns across handler modules.
//!
//! Per protocol 03-session-pane-management (common error response format).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const server = @import("itshell3_server");
const SessionManager = server.state.session_manager.SessionManager;
const SessionEntry = server.state.session_entry.SessionEntry;
const ClientState = server.connection.client_state.ClientState;
const ClientManager = server.connection.client_manager.ClientManager;
const core = @import("itshell3_core");
const types = core.types;
const interfaces = server.os.interfaces;
const envelope = @import("protocol_envelope.zig");

/// Sends a JSON error response to the client with the given status and message.
/// Combines JSON formatting, envelope wrapping, and enqueue in one call.
pub fn sendErrorResponse(
    client: *ClientState,
    response_buffer: *[envelope.MAX_ENVELOPE_SIZE]u8,
    msg_type: u16,
    sequence: u64,
    status: u32,
    message: []const u8,
) void {
    var json_buffer: [256]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buffer, "{{\"status\":{d},\"error\":\"{s}\"}}", .{
        status,
        message,
    }) catch return;
    const response = envelope.wrapResponse(response_buffer, msg_type, sequence, json) orelse return;
    client.enqueueDirect(response) catch {};
}

/// Looks up a session by ID. If not found, sends an error response and returns
/// null. Combines getSession + sendErrorResponse for the common pattern.
pub fn getSessionOrSendError(
    session_manager: *SessionManager,
    client: *ClientState,
    response_buffer: *[envelope.MAX_ENVELOPE_SIZE]u8,
    session_id: types.SessionId,
    msg_type: u16,
    sequence: u64,
) ?*SessionEntry {
    return session_manager.getSession(session_id) orelse {
        sendErrorResponse(client, response_buffer, msg_type, sequence, 1, "session not found");
        return null;
    };
}

// ── JSON Field Extraction ───────────────────────────────────────────────────

/// Extracts a u32 field from a JSON payload using a comptime search key.
/// The `comptime_key` must be the literal JSON key pattern, e.g. `"\"pane_id\":"`.
pub fn extractU32Field(payload: []const u8, comptime comptime_key: []const u8) ?u32 {
    const pos = std.mem.indexOf(u8, payload, comptime_key) orelse return null;
    const after = payload[pos + comptime_key.len ..];
    var start: usize = 0;
    while (start < after.len and (after[start] == ' ' or after[start] == '\t')) : (start += 1) {}
    if (start >= after.len) return null;
    var end = start;
    while (end < after.len and after[end] >= '0' and after[end] <= '9') : (end += 1) {}
    if (end == start) return null;
    return std.fmt.parseInt(u32, after[start..end], 10) catch null;
}

/// Extracts a u16 field from a JSON payload using a comptime search key.
pub fn extractU16Field(payload: []const u8, comptime comptime_key: []const u8) ?u16 {
    const val = extractU32Field(payload, comptime_key) orelse return null;
    if (val > std.math.maxInt(u16)) return null;
    return @intCast(val);
}

/// Extracts a u8 field from a JSON payload using a comptime search key.
pub fn extractU8Field(payload: []const u8, comptime comptime_key: []const u8) ?u8 {
    const val = extractU32Field(payload, comptime_key) orelse return null;
    if (val > std.math.maxInt(u8)) return null;
    return @intCast(val);
}

/// Extracts a bool field from a JSON payload using a comptime search key.
/// The `comptime_key` must be the literal JSON key pattern, e.g. `"\"focused\":"`.
pub fn extractBoolField(payload: []const u8, comptime comptime_key: []const u8) ?bool {
    const pos = std.mem.indexOf(u8, payload, comptime_key) orelse return null;
    const after = payload[pos + comptime_key.len ..];
    var start: usize = 0;
    while (start < after.len and (after[start] == ' ' or after[start] == '\t')) : (start += 1) {}
    if (start >= after.len) return null;
    if (after.len - start >= 4 and std.mem.eql(u8, after[start .. start + 4], "true")) return true;
    if (after.len - start >= 5 and std.mem.eql(u8, after[start .. start + 5], "false")) return false;
    return null;
}

/// Extracts a string field value from a JSON payload (no allocation).
/// The `comptime_key` must include the trailing quote, e.g. `"\"text\":\""`.
pub fn extractStringField(payload: []const u8, comptime comptime_key: []const u8) ?[]const u8 {
    const pos = std.mem.indexOf(u8, payload, comptime_key) orelse return null;
    const after = payload[pos + comptime_key.len ..];
    const end = std.mem.indexOf(u8, after, "\"") orelse return null;
    return after[0..end];
}

// ── Session Resolution ──────────────────────────────────────────────────────

/// Resolves a SessionEntry from a pane_id. When pane_id is 0, returns the
/// client's attached session. Otherwise scans all sessions for the pane.
pub fn resolveSessionByPaneId(
    session_manager: *SessionManager,
    client: *ClientState,
    pane_id: types.PaneId,
) ?*SessionEntry {
    if (pane_id == 0) {
        return client.attached_session;
    }
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

// ── Attached Client Counting ────────────────────────────────────────────────

/// Counts the number of clients attached to a session in the OPERATING state.
pub fn countAttachedClients(
    client_manager: *ClientManager,
    session_id: types.SessionId,
) u32 {
    var count: u32 = 0;
    var c: u32 = 0;
    while (c < server.connection.client_manager.MAX_CLIENTS) : (c += 1) {
        const index: u16 = @intCast(c);
        if (client_manager.getClientConst(index)) |cs| {
            if (cs.connection.state == .operating and
                cs.connection.attached_session_id == session_id)
            {
                count += 1;
            }
        }
    }
    return count;
}

// ── No-Op PTY Operations ────────────────────────────────────────────────────

/// No-op PTY operations fallback for when no real PTY ops are available.
pub const no_op_pty_ops = interfaces.PtyOps{
    .forkPty = noOpFork,
    .resize = noOpResize,
    .close = noOpClose,
    .read = noOpRead,
    .write = noOpWrite,
};

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

// ── Tests ────────────────────────────────────────────────────────────────────

test "sendErrorResponse: enqueues response to client" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot_index = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot_index).?;
    _ = client.connection.transitionTo(.ready);

    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    sendErrorResponse(
        client,
        &response_buffer,
        @intFromEnum(MessageType.attach_session_response),
        42,
        3,
        "already attached to a session",
    );

    try std.testing.expect(!client.direct_queue.isEmpty());
    client.deinit();
}

test "getSessionOrSendError: returns null and enqueues error for missing session" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot_index = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot_index).?;
    _ = client.connection.transitionTo(.ready);

    const SessionManagerType = server.state.session_manager.SessionManager;
    const S = struct {
        var session_manager = SessionManagerType.init();
    };
    S.session_manager.reset();

    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const result = getSessionOrSendError(
        &S.session_manager,
        client,
        &response_buffer,
        999,
        @intFromEnum(MessageType.attach_session_response),
        1,
    );

    try std.testing.expect(result == null);
    try std.testing.expect(!client.direct_queue.isEmpty());
    client.deinit();
}

test "getSessionOrSendError: returns entry for existing session" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot_index = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot_index).?;
    _ = client.connection.transitionTo(.ready);

    const SessionManagerType = server.state.session_manager.SessionManager;
    const S = struct {
        var session_manager = SessionManagerType.init();
    };
    S.session_manager.reset();
    const session_id = S.session_manager.createSession("test", helpers.testImeEngine(), 0) catch unreachable;

    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const result = getSessionOrSendError(
        &S.session_manager,
        client,
        &response_buffer,
        session_id,
        @intFromEnum(MessageType.attach_session_response),
        1,
    );

    try std.testing.expect(result != null);
    try std.testing.expect(client.direct_queue.isEmpty());
    client.deinit();
}

test "extractU32Field: parses integer from JSON" {
    const payload = "{\"pane_id\":42}";
    try std.testing.expectEqual(@as(?u32, 42), extractU32Field(payload, "\"pane_id\":"));
}

test "extractU16Field: parses u16 from JSON" {
    const payload = "{\"keycode\":256}";
    try std.testing.expectEqual(@as(?u16, 256), extractU16Field(payload, "\"keycode\":"));
}

test "extractU8Field: parses u8 from JSON" {
    const payload = "{\"action\":2}";
    try std.testing.expectEqual(@as(?u8, 2), extractU8Field(payload, "\"action\":"));
}

test "extractStringField: extracts string value" {
    const payload = "{\"text\":\"Hello\"}";
    const text = extractStringField(payload, "\"text\":\"");
    try std.testing.expect(text != null);
    try std.testing.expectEqualSlices(u8, "Hello", text.?);
}

test "extractBoolField: parses booleans" {
    try std.testing.expectEqual(@as(?bool, true), extractBoolField("{\"focused\":true}", "\"focused\":"));
    try std.testing.expectEqual(@as(?bool, false), extractBoolField("{\"focused\":false}", "\"focused\":"));
}

test "extractU32Field: returns null for missing field" {
    try std.testing.expect(extractU32Field("{\"other\":1}", "\"pane_id\":") == null);
}

test "countAttachedClients: returns zero when no clients attached" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    try std.testing.expectEqual(@as(u32, 0), countAttachedClients(&client_manager, 1));
}

test "resolveSessionByPaneId: pane_id 0 returns attached session" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot_index = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot_index).?;

    // No attached session -- returns null.
    const SessionManagerType = server.state.session_manager.SessionManager;
    const S = struct {
        var session_manager = SessionManagerType.init();
    };
    S.session_manager.reset();
    const result = resolveSessionByPaneId(&S.session_manager, client, 0);
    try std.testing.expect(result == null);
    client.deinit();
}
