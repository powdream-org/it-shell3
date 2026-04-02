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
const core = @import("itshell3_core");
const types = core.types;
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

// ── Tests ────────────────────────────────────────────────────────────────────

test "sendErrorResponse: enqueues response to client" {
    const helpers = @import("itshell3_testing").helpers;
    const ClientManager = server.connection.client_manager.ClientManager;
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
    const ClientManager = server.connection.client_manager.ClientManager;
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
    const ClientManager = server.connection.client_manager.ClientManager;
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
