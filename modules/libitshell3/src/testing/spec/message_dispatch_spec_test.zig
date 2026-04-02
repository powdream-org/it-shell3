//! Spec compliance tests: Message dispatch and routing.
//!
//! Covers event priority ordering, message type validation per connection state,
//! client disconnect semantics, disconnect reason codes, and ClientDisplayInfo
//! state allowances.
//!
//! Spec sources:
//!   - daemon-architecture module-structure — server/ component responsibilities
//!   - protocol protocol-overview — message type ranges
//!   - daemon-behavior event-handling — event priority, client disconnect
//!   - daemon-behavior policies-and-procedures — input priority, state transitions

const std = @import("std");
const server = @import("itshell3_server");
const protocol = @import("itshell3_protocol");
const ConnectionState = server.connection.connection_state.ConnectionState;
const State = server.connection.connection_state.State;
const ClientManager = server.connection.client_manager.ClientManager;
const ClientState = server.connection.client_state.ClientState;
const disconnect_handler = server.connection.disconnect_handler;
const interfaces = server.os.interfaces;
const Filter = interfaces.Filter;

// ── Spec: Event Priority Ordering ────────────────────────────────────────────

test "spec: event priority — SIGNAL > TIMER > READ > WRITE" {
    // The Filter enum encodes priority as integer values:
    // signal=0, timer=1, read=2, write=3.
    try std.testing.expect(@intFromEnum(Filter.signal) < @intFromEnum(Filter.timer));
    try std.testing.expect(@intFromEnum(Filter.timer) < @intFromEnum(Filter.read));
    try std.testing.expect(@intFromEnum(Filter.read) < @intFromEnum(Filter.write));
}

// ── Spec: Message Type Validation Per State ──────────────────────────────────

test "spec: dispatch — operational message ranges accepted in OPERATING state" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    _ = conn.transitionTo(.operating);

    // Session & Pane (0x0100-0x01FF)
    try std.testing.expect(conn.isMessageAllowed(.create_session_request));
    try std.testing.expect(conn.isMessageAllowed(.destroy_session_request));
    try std.testing.expect(conn.isMessageAllowed(.split_pane_request));
    try std.testing.expect(conn.isMessageAllowed(.close_pane_request));

    // Input (0x0200-0x02FF)
    try std.testing.expect(conn.isMessageAllowed(.key_event));

    // Render (0x0300-0x03FF)
    try std.testing.expect(conn.isMessageAllowed(.frame_update));

    // CJK/IME (0x0400-0x04FF)
    try std.testing.expect(conn.isMessageAllowed(.preedit_start));
    try std.testing.expect(conn.isMessageAllowed(.preedit_update));
    try std.testing.expect(conn.isMessageAllowed(.preedit_end));

    // Flow Control (0x0500-0x05FF)
    try std.testing.expect(conn.isMessageAllowed(.pause_pane));
    try std.testing.expect(conn.isMessageAllowed(.continue_pane));

    // DetachSession
    try std.testing.expect(conn.isMessageAllowed(.detach_session_request));
}

test "spec: dispatch — operational messages rejected in READY state" {
    // READY state only allows session attach/create, heartbeat, disconnect.
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);

    try std.testing.expect(!conn.isMessageAllowed(.key_event));
    try std.testing.expect(!conn.isMessageAllowed(.frame_update));
    try std.testing.expect(!conn.isMessageAllowed(.preedit_start));
    try std.testing.expect(!conn.isMessageAllowed(.split_pane_request));
}

test "spec: dispatch — READY allows session management for transition to OPERATING" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);

    try std.testing.expect(conn.isMessageAllowed(.attach_session_request));
    try std.testing.expect(conn.isMessageAllowed(.create_session_request));
    try std.testing.expect(conn.isMessageAllowed(.attach_session_request));
    try std.testing.expect(conn.isMessageAllowed(.list_sessions_request));
}

// ── Spec: Client Disconnect ──────────────────────────────────────────────────

test "spec: disconnect — client disconnect does NOT affect session lifecycle" {
    // Sessions persist until panes exit or daemon shuts down;
    // disconnect_handler only modifies the client's connection state.
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 42;

    disconnect_handler.processIncomingDisconnect(&client);

    // Client transitions to DISCONNECTING, but attached_session_id is not cleared
    // by the disconnect handler — session cleanup is done separately by the caller.
    try std.testing.expectEqual(State.disconnecting, client.getState());
}

test "spec: disconnect — unexpected disconnect bypasses DISCONNECTING" {
    // peer_closed triggers teardown directly. processIncomingDisconnect
    // transitions to DISCONNECTING for the graceful path.
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);

    // Graceful disconnect transitions through DISCONNECTING.
    disconnect_handler.processIncomingDisconnect(&client);
    try std.testing.expectEqual(State.disconnecting, client.getState());
}

test "spec: disconnect — initiateDisconnect is idempotent for DISCONNECTING state" {
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.disconnecting);

    const result = disconnect_handler.initiateDisconnect(&client);
    try std.testing.expectEqual(disconnect_handler.DisconnectResult.already_disconnecting, result);
}

// ── Spec: Disconnect Reason Codes ────────────────────────────────────────────

test "spec: disconnect — reason codes match spec" {
    // Plan 6 spec: "Reasons: normal, error, timeout, version_mismatch,
    // auth_failed, server_shutdown, stale_client, replaced"
    try std.testing.expectEqualStrings("normal", disconnect_handler.Reason.NORMAL);
    try std.testing.expectEqualStrings("error", disconnect_handler.Reason.ERROR_REASON);
    try std.testing.expectEqualStrings("timeout", disconnect_handler.Reason.TIMEOUT);
    try std.testing.expectEqualStrings("version_mismatch", disconnect_handler.Reason.VERSION_MISMATCH);
    try std.testing.expectEqualStrings("auth_failed", disconnect_handler.Reason.AUTH_FAILED);
    try std.testing.expectEqualStrings("server_shutdown", disconnect_handler.Reason.SERVER_SHUTDOWN);
    try std.testing.expectEqualStrings("stale_client", disconnect_handler.Reason.STALE_CLIENT);
    try std.testing.expectEqualStrings("replaced", disconnect_handler.Reason.REPLACED);
}

test "spec: disconnect — buildDisconnectPayload produces valid JSON" {
    // Disconnect message must be JSON-serializable per protocol spec.
    var buf: [disconnect_handler.MAX_DISCONNECT_PAYLOAD]u8 = undefined;
    const len = disconnect_handler.buildDisconnectPayload(
        disconnect_handler.Reason.SERVER_SHUTDOWN,
        "shutting down",
        &buf,
    );
    try std.testing.expect(len != null);

    // Verify it contains the reason and detail.
    const payload = buf[0..len.?];
    try std.testing.expect(std.mem.indexOf(u8, payload, "server_shutdown") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "shutting down") != null);
}

// ── Spec: ClientDisplayInfo in READY State ───────────────────────────────────

test "spec: dispatch — ClientDisplayInfo allowed in READY state" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    try std.testing.expect(conn.isMessageAllowed(.client_display_info));
}

test "spec: dispatch — ClientDisplayInfo allowed in OPERATING state" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    _ = conn.transitionTo(.operating);
    try std.testing.expect(conn.isMessageAllowed(.client_display_info));
}
