//! Graceful disconnect handling. Manages DISCONNECTING state transitions,
//! reason codes, and connection teardown.
//!
//! Per protocol spec 02-handshake-capability-negotiation (Disconnect payload)
//! and daemon-behavior 02-event-handling (client disconnect cleanup).

const std = @import("std");
const connection_state_mod = @import("connection_state.zig");
const ConnectionState = connection_state_mod.ConnectionState;
const State = connection_state_mod.State;
const client_state_mod = @import("client_state.zig");
const ClientState = client_state_mod.ClientState;
const protocol = @import("itshell3_protocol");
const Disconnect = protocol.handshake.Disconnect;

/// Disconnect reason strings per spec.
pub const Reason = struct {
    pub const NORMAL = "normal";
    pub const ERROR_REASON = "error";
    pub const TIMEOUT = "timeout";
    pub const VERSION_MISMATCH = "version_mismatch";
    pub const AUTH_FAILED = "auth_failed";
    pub const SERVER_SHUTDOWN = "server_shutdown";
    pub const STALE_CLIENT = "stale_client";
    pub const REPLACED = "replaced";
};

/// Maximum size for a serialized Disconnect message payload.
pub const MAX_DISCONNECT_PAYLOAD: usize = 512;

/// Result of initiating a disconnect.
pub const DisconnectResult = enum {
    /// Transition to DISCONNECTING succeeded.
    transitioned,
    /// Already in DISCONNECTING state.
    already_disconnecting,
};

/// Initiate a graceful disconnect for a client. Transitions the connection
/// to DISCONNECTING state. The caller is responsible for sending the Disconnect
/// message and scheduling teardown.
pub fn initiateDisconnect(client: *ClientState, _: []const u8) DisconnectResult {
    if (client.connection.state == .disconnecting) return .already_disconnecting;
    _ = client.connection.transitionTo(.disconnecting);
    return .transitioned;
}

/// Process an incoming Disconnect message from a client. Transitions to
/// DISCONNECTING state and signals that teardown should begin.
pub fn processIncomingDisconnect(client: *ClientState) void {
    if (client.connection.state != .disconnecting) {
        _ = client.connection.transitionTo(.disconnecting);
    }
}

/// Execute connection teardown. Closes the socket fd.
/// The caller must also unregister the fd from kqueue and remove from ClientManager.
pub fn teardown(client: *ClientState) void {
    client.connection.socket.close();
    client.deinit();
}

/// Build a Disconnect message payload JSON.
pub fn buildDisconnectPayload(
    reason: []const u8,
    detail: []const u8,
    buf: *[MAX_DISCONNECT_PAYLOAD]u8,
) ?usize {
    const msg = Disconnect{
        .reason = reason,
        .detail = detail,
    };
    var fba = std.heap.FixedBufferAllocator.init(buf);
    const json = std.json.Stringify.valueAlloc(fba.allocator(), msg, .{
        .emit_null_optional_fields = false,
    }) catch return null;
    return json.len;
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "initiateDisconnect: transitions to disconnecting" {
    var client = ClientState.init(.{ .fd = 5 }, 1);
    const result = initiateDisconnect(&client, Reason.NORMAL);
    try std.testing.expectEqual(DisconnectResult.transitioned, result);
    try std.testing.expectEqual(State.disconnecting, client.getState());
}

test "initiateDisconnect: already disconnecting returns already_disconnecting" {
    var client = ClientState.init(.{ .fd = 5 }, 1);
    _ = client.connection.transitionTo(.disconnecting);
    const result = initiateDisconnect(&client, Reason.NORMAL);
    try std.testing.expectEqual(DisconnectResult.already_disconnecting, result);
}

test "processIncomingDisconnect: transitions to disconnecting" {
    var client = ClientState.init(.{ .fd = 5 }, 1);
    _ = client.connection.transitionTo(.ready);
    processIncomingDisconnect(&client);
    try std.testing.expectEqual(State.disconnecting, client.getState());
}

test "processIncomingDisconnect: idempotent when already disconnecting" {
    var client = ClientState.init(.{ .fd = 5 }, 1);
    _ = client.connection.transitionTo(.disconnecting);
    processIncomingDisconnect(&client);
    try std.testing.expectEqual(State.disconnecting, client.getState());
}

test "buildDisconnectPayload: produces valid JSON" {
    var buf: [MAX_DISCONNECT_PAYLOAD]u8 = undefined;
    const len = buildDisconnectPayload(Reason.NORMAL, "user request", &buf);
    try std.testing.expect(len != null);
    const payload = buf[0..len.?];
    try std.testing.expect(std.mem.indexOf(u8, payload, "normal") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "user request") != null);
}
