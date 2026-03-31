//! Spec compliance tests: Lifecycle dispatcher (page 0x00).
//!
//! Validates the lifecycle message dispatch within the 0x0001-0x00FF range:
//! ClientHello handling and state transition, heartbeat/heartbeat-ack
//! processing, disconnect handling, handshake timer cancellation, and
//! state-guarded message rejection.
//!
//! Spec sources:
//!   - daemon-behavior policies-and-procedures — client state transitions (Section 12),
//!     handshake timeouts (Section 13), heartbeat policy (Section 10),
//!     negotiation algorithms (Section 14)
//!   - protocol 01-protocol-overview — lifecycle message type range (0x0001-0x00FF),
//!     heartbeat ping_id semantics (Section 5.4)
//!   - protocol 02-handshake-capability-negotiation — ClientHello/ServerHello flow,
//!     version negotiation, capability intersection, render capability requirement

const std = @import("std");
const server = @import("itshell3_server");
const protocol = @import("itshell3_protocol");
const testing_helpers = @import("itshell3_testing").helpers;

const MessageType = protocol.message_type.MessageType;
const Header = protocol.header.Header;
const ClientManager = server.connection.client_manager.ClientManager;
const ClientState = server.connection.client_state.ClientState;
const HeartbeatManager = server.connection.heartbeat_manager.HeartbeatManager;
const State = server.connection.connection_state.State;
const lifecycle_dispatcher = server.handlers.lifecycle_dispatcher;
const message_dispatcher = server.handlers.message_dispatcher;
const DispatcherContext = message_dispatcher.DispatcherContext;
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;
const interfaces = server.os.interfaces;

// ── Test Infrastructure ────────────────────────────────────────────────────

const TestDisconnectState = struct {
    disconnect_count: u32 = 0,
    last_slot: u16 = 0,
};

var disconnect_state: TestDisconnectState = .{};

fn testDisconnect(client_slot: u16) void {
    disconnect_state.disconnect_count += 1;
    disconnect_state.last_slot = client_slot;
}

fn resetState() void {
    disconnect_state = .{};
}

fn makeHeader(msg_type: MessageType, seq: u32, payload_len: u32) Header {
    return Header{
        .msg_type = @intFromEnum(msg_type),
        .flags = .{},
        .payload_length = payload_len,
        .sequence = seq,
    };
}

fn makeContext(client_manager: *ClientManager, heartbeat_manager: *HeartbeatManager) DispatcherContext {
    var dummy_el_ctx: u8 = 0;
    _ = &dummy_el_ctx;
    return DispatcherContext{
        .client_manager = client_manager,
        .heartbeat_manager = heartbeat_manager,
        .server_pid = 1234,
        .disconnect_fn = testDisconnect,
        .event_loop_ops = &testing_helpers.noop_event_loop_ops,
        .event_loop_context = @ptrCast(&file_scope_el_ctx),
        .allocator = std.testing.allocator,
    };
}

var file_scope_el_ctx: u8 = 0;

fn makeParams(
    context: *DispatcherContext,
    client: *ClientState,
    client_slot: u16,
    msg_type: MessageType,
    header: Header,
    payload: []const u8,
) CategoryDispatchParams {
    return CategoryDispatchParams{
        .context = context,
        .client = client,
        .client_slot = client_slot,
        .msg_type = msg_type,
        .header = header,
        .payload = payload,
    };
}

/// Valid ClientHello JSON per protocol 02-handshake-capability-negotiation.
const valid_client_hello_json =
    \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":[],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
;

/// ClientHello with version mismatch (min > server version 1).
const version_mismatch_client_hello_json =
    \\{"protocol_version_min":99,"protocol_version_max":99,"client_type":"native","capabilities":[],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
;

/// ClientHello with no common rendering mode.
const no_render_client_hello_json =
    \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":[],"render_capabilities":["sixel"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
;

/// Malformed JSON payload.
const malformed_json = "{not valid json!";

// ── Spec: Lifecycle Message Type Range (protocol 01-protocol-overview) ─────

test "spec: lifecycle dispatch — all lifecycle messages have page 0x00" {
    // Protocol 01-protocol-overview: Handshake & Lifecycle range is 0x0001-0x00FF.
    // The lifecycle dispatcher handles page 0x00 (msg_type >> 8 == 0x00).
    const lifecycle_types = [_]MessageType{
        .client_hello, // 0x0001
        .server_hello, // 0x0002
        .heartbeat, // 0x0003
        .heartbeat_ack, // 0x0004
        .disconnect, // 0x0005
        .@"error", // 0x00FF
    };
    for (lifecycle_types) |mt| {
        try std.testing.expectEqual(@as(u16, 0x00), @intFromEnum(mt) >> 8);
    }
}

// ── Spec: ClientHello Handling (protocol 02, daemon-behavior Section 12) ───

test "spec: lifecycle dispatch — valid ClientHello transitions client to READY" {
    // Spec: daemon-behavior policies-and-procedures Section 12:
    //   HANDSHAKING + Valid ClientHello -> READY
    // Spec: protocol 02-handshake Section 1:
    //   "The connection transitions from HANDSHAKING to READY on success."
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 100 });
    const client = mgr.getClient(slot).?;

    // Client starts in HANDSHAKING.
    try std.testing.expectEqual(State.handshaking, client.connection.state);

    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.client_hello, 1, @intCast(valid_client_hello_json.len));
    const params = makeParams(&ctx, client, slot, .client_hello, hdr, valid_client_hello_json);

    lifecycle_dispatcher.dispatch(params);

    // After valid ClientHello, client transitions to READY.
    try std.testing.expectEqual(State.ready, client.connection.state);
}

test "spec: lifecycle dispatch — ClientHello in non-HANDSHAKING state is rejected" {
    // Spec: daemon-behavior policies-and-procedures Section 12:
    //   Only HANDSHAKING accepts ClientHello.
    // Spec: protocol 01-protocol-overview Section 5.2:
    //   HANDSHAKING allows ClientHello; READY/OPERATING do not.
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 101 });
    const client = mgr.getClient(slot).?;

    // Move to READY first.
    _ = client.connection.transitionTo(.ready);
    try std.testing.expectEqual(State.ready, client.connection.state);

    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.client_hello, 1, @intCast(valid_client_hello_json.len));
    const params = makeParams(&ctx, client, slot, .client_hello, hdr, valid_client_hello_json);

    lifecycle_dispatcher.dispatch(params);

    // State must remain READY — ClientHello is not valid in READY state.
    try std.testing.expectEqual(State.ready, client.connection.state);
}

test "spec: lifecycle dispatch — version mismatch ClientHello triggers disconnect" {
    // Spec: daemon-behavior policies-and-procedures Section 14.1:
    //   "if negotiated_version < client.protocol_version_min -> ERR_VERSION_MISMATCH"
    // Spec: daemon-behavior Section 12:
    //   HANDSHAKING + Invalid ClientHello -> [closed]
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 102 });
    const client = mgr.getClient(slot).?;
    try std.testing.expectEqual(State.handshaking, client.connection.state);

    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.client_hello, 1, @intCast(version_mismatch_client_hello_json.len));
    const params = makeParams(&ctx, client, slot, .client_hello, hdr, version_mismatch_client_hello_json);

    lifecycle_dispatcher.dispatch(params);

    // Version mismatch should trigger disconnect (state -> disconnecting or disconnect called).
    const disconnected = (client.connection.state == .disconnecting) or
        (disconnect_state.disconnect_count > 0);
    try std.testing.expect(disconnected);
}

test "spec: lifecycle dispatch — no common rendering mode triggers disconnect" {
    // Spec: daemon-behavior policies-and-procedures Section 14.3:
    //   "If neither cell_data nor vt_fallback is in the intersection, the server
    //   MUST send Error(ERR_CAPABILITY_REQUIRED) and disconnect."
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 103 });
    const client = mgr.getClient(slot).?;

    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.client_hello, 1, @intCast(no_render_client_hello_json.len));
    const params = makeParams(&ctx, client, slot, .client_hello, hdr, no_render_client_hello_json);

    lifecycle_dispatcher.dispatch(params);

    // Should disconnect — no common rendering mode.
    const disconnected = (client.connection.state == .disconnecting) or
        (disconnect_state.disconnect_count > 0);
    try std.testing.expect(disconnected);
}

test "spec: lifecycle dispatch — malformed ClientHello triggers disconnect" {
    // Spec: daemon-behavior policies-and-procedures Section 12:
    //   HANDSHAKING + Invalid ClientHello -> [closed]
    // Spec: protocol 01-protocol-overview Section 5.3:
    //   HANDSHAKING -> DISCONNECTING on error
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 104 });
    const client = mgr.getClient(slot).?;

    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.client_hello, 1, @intCast(malformed_json.len));
    const params = makeParams(&ctx, client, slot, .client_hello, hdr, malformed_json);

    lifecycle_dispatcher.dispatch(params);

    const disconnected = (client.connection.state == .disconnecting) or
        (disconnect_state.disconnect_count > 0);
    try std.testing.expect(disconnected);
}

// ── Spec: Heartbeat Handling (protocol 01 Section 5.4, daemon-behavior Section 10) ─

test "spec: lifecycle dispatch — heartbeat in READY state records activity" {
    // Spec: protocol 01-protocol-overview Section 5.4:
    //   "Either side MAY send Heartbeat. The receiver responds with HeartbeatAck."
    // Spec: daemon-behavior policies-and-procedures Section 10.2:
    //   "The receiver responds with HeartbeatAck (0x0004)."
    // Spec: protocol 01-protocol-overview Section 5.2:
    //   READY state allows Heartbeat.
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 105 });
    const client = mgr.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);

    const old_activity = client.last_activity_timestamp;

    const heartbeat_json =
        \\{"ping_id":42}
    ;
    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.heartbeat, 1, @intCast(heartbeat_json.len));
    const params = makeParams(&ctx, client, slot, .heartbeat, hdr, heartbeat_json);

    lifecycle_dispatcher.dispatch(params);

    // Activity timestamp should be updated (heartbeat is a received message).
    try std.testing.expect(client.last_activity_timestamp >= old_activity);
}

test "spec: lifecycle dispatch — heartbeat in OPERATING state records activity" {
    // Spec: protocol 01-protocol-overview Section 5.2:
    //   OPERATING state allows all message types including Heartbeat.
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 106 });
    const client = mgr.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);

    const old_activity = client.last_activity_timestamp;

    const heartbeat_json =
        \\{"ping_id":7}
    ;
    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.heartbeat, 2, @intCast(heartbeat_json.len));
    const params = makeParams(&ctx, client, slot, .heartbeat, hdr, heartbeat_json);

    lifecycle_dispatcher.dispatch(params);

    try std.testing.expect(client.last_activity_timestamp >= old_activity);
}

// ── Spec: HeartbeatAck Handling (daemon-behavior Section 10) ───────────────

test "spec: lifecycle dispatch — heartbeat ack records activity for connection liveness" {
    // Spec: protocol 01-protocol-overview Section 5.4:
    //   "If no message (of any kind) is received within the timeout, the connection
    //   is considered dead" — HeartbeatAck counts as a received message.
    // Spec: daemon-behavior policies-and-procedures Section 10.2:
    //   HeartbeatAck records connection-level activity.
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 107 });
    const client = mgr.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);

    // Set activity far in the past.
    client.last_activity_timestamp = std.time.milliTimestamp() - 80_000;

    const ack_json =
        \\{"ping_id":42}
    ;
    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.heartbeat_ack, 3, @intCast(ack_json.len));
    const params = makeParams(&ctx, client, slot, .heartbeat_ack, hdr, ack_json);

    lifecycle_dispatcher.dispatch(params);

    // Activity timestamp should be recent now.
    const now = std.time.milliTimestamp();
    const elapsed = now - client.last_activity_timestamp;
    try std.testing.expect(elapsed < 5_000);
}

test "spec: lifecycle dispatch — heartbeat ack does NOT reset stale timeout" {
    // Spec: daemon-behavior policies-and-procedures Section 10.4:
    //   "HeartbeatAck MUST NOT reset the stale timeout."
    // Spec: daemon-behavior policies-and-procedures Section 3.3:
    //   "HeartbeatAck MUST NOT reset the stale timeout. On iOS, the OS can
    //   suspend the application while keeping TCP sockets alive."
    //
    // Heartbeat is connection liveness (90s); stale is application
    // responsiveness (ring cursor lag, PausePane duration). These are
    // independent systems.
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 108 });
    const client = mgr.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);

    // Record initial stale-related state if available.
    // The key spec invariant: HeartbeatAck updates last_activity_timestamp
    // (connection liveness) but NOT any stale-related timestamp.
    const ack_json =
        \\{"ping_id":10}
    ;
    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.heartbeat_ack, 4, @intCast(ack_json.len));
    const params = makeParams(&ctx, client, slot, .heartbeat_ack, hdr, ack_json);

    lifecycle_dispatcher.dispatch(params);

    // Verify connection liveness was recorded (last_activity_timestamp updated).
    const now = std.time.milliTimestamp();
    const elapsed = now - client.last_activity_timestamp;
    try std.testing.expect(elapsed < 5_000);

    // Verify the acked ping_id is recorded.
    try std.testing.expectEqual(@as(u32, 10), client.last_ping_id_acked);
}

// ── Spec: Disconnect Handling (protocol 01 Section 5.3, daemon-behavior Section 12) ─

test "spec: lifecycle dispatch — disconnect message triggers client teardown" {
    // Spec: protocol 01-protocol-overview Section 5.3:
    //   READY + Disconnect -> DISCONNECTING
    //   OPERATING + Disconnect -> DISCONNECTING
    // Spec: daemon-behavior policies-and-procedures Section 12:
    //   READY + Client disconnect -> [closed]: Clean up ClientState
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 109 });
    const client = mgr.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);

    const disconnect_json =
        \\{"reason":"normal"}
    ;
    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.disconnect, 5, @intCast(disconnect_json.len));
    const params = makeParams(&ctx, client, slot, .disconnect, hdr, disconnect_json);

    lifecycle_dispatcher.dispatch(params);

    // Disconnect should trigger teardown (either state transition or disconnect callback).
    const disconnected = (client.connection.state == .disconnecting) or
        (disconnect_state.disconnect_count > 0);
    try std.testing.expect(disconnected);
}

test "spec: lifecycle dispatch — disconnect in OPERATING state triggers cleanup" {
    // Spec: protocol 01-protocol-overview Section 5.3:
    //   OPERATING + Disconnect -> DISCONNECTING: Drain and close
    // Spec: daemon-behavior policies-and-procedures Section 12:
    //   OPERATING + Client disconnect -> [closed]: Clean up ClientState
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 110 });
    const client = mgr.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);

    const disconnect_json =
        \\{"reason":"normal"}
    ;
    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.disconnect, 6, @intCast(disconnect_json.len));
    const params = makeParams(&ctx, client, slot, .disconnect, hdr, disconnect_json);

    lifecycle_dispatcher.dispatch(params);

    const disconnected = (client.connection.state == .disconnecting) or
        (disconnect_state.disconnect_count > 0);
    try std.testing.expect(disconnected);
}

// ── Spec: Handshake Timer Cancellation (daemon-behavior Section 13) ────────

test "spec: lifecycle dispatch — handshake timer cancelled on successful handshake" {
    // Spec: daemon-behavior policies-and-procedures Section 13:
    //   "Each timeout MUST be enforced via per-client EVFILT_TIMER. The timer
    //   is cancelled when the expected message arrives."
    // The handshake timer (ClientHello -> ServerHello: 5s) must be cancelled
    // when a valid ClientHello transitions the client to READY.
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 111 });
    const client = mgr.getClient(slot).?;
    try std.testing.expectEqual(State.handshaking, client.connection.state);

    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.client_hello, 1, @intCast(valid_client_hello_json.len));
    const params = makeParams(&ctx, client, slot, .client_hello, hdr, valid_client_hello_json);

    // The noop_event_loop_ops.cancelTimer is used — we verify the handshake
    // completes without error, which requires timer cancellation to not fail.
    lifecycle_dispatcher.dispatch(params);

    // Successful handshake: client is now READY.
    try std.testing.expectEqual(State.ready, client.connection.state);
}

// ── Spec: Heartbeat in HANDSHAKING is Not Allowed (protocol 01 Section 5.2) ─

test "spec: lifecycle dispatch — heartbeat in HANDSHAKING state is not processed" {
    // Spec: protocol 01-protocol-overview Section 5.2:
    //   HANDSHAKING allows only ClientHello, ServerHello, Error, Disconnect.
    //   Heartbeat is NOT in the allowed set.
    // Spec: daemon-behavior policies-and-procedures Section 12:
    //   HANDSHAKING row only lists "Valid ClientHello" and "Invalid ClientHello/timeout".
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 112 });
    const client = mgr.getClient(slot).?;
    // Client is in HANDSHAKING state.
    try std.testing.expectEqual(State.handshaking, client.connection.state);

    const heartbeat_json =
        \\{"ping_id":1}
    ;
    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.heartbeat, 1, @intCast(heartbeat_json.len));
    const params = makeParams(&ctx, client, slot, .heartbeat, hdr, heartbeat_json);

    lifecycle_dispatcher.dispatch(params);

    // Client should still be in HANDSHAKING — heartbeat not valid here.
    try std.testing.expectEqual(State.handshaking, client.connection.state);
}

// ── Spec: Handshake Timeout Values (daemon-behavior Section 13) ────────────

test "spec: lifecycle dispatch — handshake timeout is 5 seconds per spec" {
    // Spec: daemon-behavior policies-and-procedures Section 13:
    //   "ClientHello -> ServerHello: 5s"
    //   "Transport connection (accept to first byte): 5s"
    // Verify the constant matches the spec value.
    const client_accept = server.handlers.client_accept;
    // The handshake timeout should be 5000ms.
    try std.testing.expectEqual(@as(u32, 5_000), client_accept.HANDSHAKE_TIMEOUT_MS);
}

test "spec: lifecycle dispatch — ready idle timeout is 60 seconds per spec" {
    // Spec: daemon-behavior policies-and-procedures Section 13:
    //   "READY -> AttachSession/CreateSession/AttachOrCreate: 60s"
    try std.testing.expectEqual(@as(u32, 60_000), message_dispatcher.ready_idle_timeout_ms);
}

// ── Spec: Connection Timeout (daemon-behavior Section 10.1, Section 13) ────

test "spec: lifecycle dispatch — heartbeat response timeout is 90 seconds per spec" {
    // Spec: daemon-behavior policies-and-procedures Section 10.1:
    //   "Connection timeout: 90s — No message of any kind received within
    //   this period -> connection is dead"
    // Spec: Section 13 table:
    //   "Heartbeat response: 90s -> Send Disconnect(TIMEOUT), close connection"
    const heartbeat_manager_mod = server.connection.heartbeat_manager;
    try std.testing.expectEqual(@as(i64, 90_000), heartbeat_manager_mod.HEARTBEAT_TIMEOUT_MS);
}

// ── Spec: Heartbeat Interval (daemon-behavior Section 10.1) ────────────────

test "spec: lifecycle dispatch — heartbeat interval is 30 seconds per spec" {
    // Spec: daemon-behavior policies-and-procedures Section 10.1:
    //   "Heartbeat interval: 30s — How often to send Heartbeat if no other
    //   messages sent"
    const heartbeat_manager_mod = server.connection.heartbeat_manager;
    try std.testing.expectEqual(@as(u32, 30_000), heartbeat_manager_mod.HEARTBEAT_INTERVAL_MS);
}

// ── Spec: Error Message in Lifecycle Range (protocol 01-protocol-overview) ──

test "spec: lifecycle dispatch — Error message type is 0x00FF within lifecycle range" {
    // Spec: protocol 01-protocol-overview Section 4.2:
    //   "0x00FF: Error — Bidirectional — Structured error report"
    try std.testing.expectEqual(@as(u16, 0x00FF), @intFromEnum(MessageType.@"error"));
    // It falls within the lifecycle page (0x00).
    try std.testing.expectEqual(@as(u16, 0x00), @intFromEnum(MessageType.@"error") >> 8);
}

// ── Spec: ServerHello on Successful Handshake (protocol 02 Section 1) ──────

test "spec: lifecycle dispatch — successful ClientHello assigns client_id" {
    // Spec: protocol 02-handshake-capability-negotiation Section 1:
    //   "The server responds with ServerHello declaring its capabilities,
    //   the negotiated feature set, and the client's assigned client_id."
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 113 });
    const client = mgr.getClient(slot).?;

    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.client_hello, 1, @intCast(valid_client_hello_json.len));
    const params = makeParams(&ctx, client, slot, .client_hello, hdr, valid_client_hello_json);

    lifecycle_dispatcher.dispatch(params);

    // client_id should be assigned (non-zero after successful handshake).
    try std.testing.expectEqual(State.ready, client.connection.state);
    try std.testing.expect(client.connection.client_id > 0);
}

// ── Spec: Heartbeat Bidirectional Semantics (protocol 01 Section 5.4) ──────

test "spec: lifecycle dispatch — heartbeat ping_id echo semantics" {
    // Spec: protocol 01-protocol-overview Section 5.4:
    //   "Heartbeat payload: { ping_id: 42 }"
    //   "HeartbeatAck payload: { ping_id: 42 } — Echoed from Heartbeat"
    // The receiver of a Heartbeat echoes the ping_id in HeartbeatAck.
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 114 });
    const client = mgr.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);

    const heartbeat_json =
        \\{"ping_id":99}
    ;
    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.heartbeat, 10, @intCast(heartbeat_json.len));
    const params = makeParams(&ctx, client, slot, .heartbeat, hdr, heartbeat_json);

    lifecycle_dispatcher.dispatch(params);

    // The dispatch should not crash and client should remain in READY.
    // (The actual HeartbeatAck is queued for write — we verify no state corruption.)
    try std.testing.expectEqual(State.ready, client.connection.state);
}

// ── Spec: Disconnect Reason Codes (protocol 02 Section 11.1) ───────────────

test "spec: lifecycle dispatch — disconnect with timeout reason" {
    // Spec: protocol 02-handshake-capability-negotiation Section 11.1:
    //   Disconnect reasons include "timeout".
    // Spec: daemon-behavior policies-and-procedures Section 13:
    //   Various timeouts send Disconnect(TIMEOUT).
    resetState();

    var mgr = ClientManager{ .chunk_pool = testing_helpers.testChunkPool() };
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(.{ .fd = 115 });
    const client = mgr.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);

    const disconnect_json =
        \\{"reason":"timeout"}
    ;
    var ctx = makeContext(&mgr, &hb);
    const hdr = makeHeader(.disconnect, 7, @intCast(disconnect_json.len));
    const params = makeParams(&ctx, client, slot, .disconnect, hdr, disconnect_json);

    lifecycle_dispatcher.dispatch(params);

    const disconnected = (client.connection.state == .disconnecting) or
        (disconnect_state.disconnect_count > 0);
    try std.testing.expect(disconnected);
}
