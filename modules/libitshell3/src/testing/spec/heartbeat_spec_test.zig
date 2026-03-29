//! Spec compliance tests: Heartbeat.
//!
//! Spec sources:
//!   - daemon-behavior 03-policies-and-procedures Section 10 — heartbeat policy
//!   - protocol 01-protocol-overview — 30s interval, 90s timeout, bidirectional
//!   - daemon-behavior 03-policies-and-procedures Section 3.3 — HeartbeatAck
//!     does NOT reset stale timeout
//!
//! These tests are derived from the SPEC, not the implementation.
//! QA-owned: verifies that the implementation conforms to the design spec.

const std = @import("std");
const server = @import("itshell3_server");
const HeartbeatManager = server.connection.heartbeat_manager.HeartbeatManager;
const heartbeat_manager_mod = server.connection.heartbeat_manager;
const ClientState = server.connection.client_state.ClientState;
const State = server.connection.connection_state.State;

// ── Spec: Heartbeat Interval ─────────────────────────────────────────────────

test "spec: heartbeat — interval is 30 seconds" {
    // daemon-behavior 03-policies-and-procedures Section 10.1:
    // "Heartbeat interval: 30s — How often to send Heartbeat if no other messages sent"
    try std.testing.expectEqual(@as(u32, 30_000), heartbeat_manager_mod.HEARTBEAT_INTERVAL_MS);
}

test "spec: heartbeat — connection timeout is 90 seconds" {
    // daemon-behavior 03-policies-and-procedures Section 10.1:
    // "Connection timeout: 90s — No message of any kind received within this
    //  period -> connection is dead"
    try std.testing.expectEqual(@as(i64, 90_000), heartbeat_manager_mod.HEARTBEAT_TIMEOUT_MS);
}

// ── Spec: Bidirectional Heartbeat ────────────────────────────────────────────

test "spec: heartbeat — server sends heartbeat with monotonic ping_id" {
    // daemon-behavior 03-policies-and-procedures Section 10.2:
    // "Either side MAY send Heartbeat (0x0003) if no other messages have been
    //  sent within the heartbeat interval."
    // Plan 6 spec: "ping_id is a monotonic counter"
    var mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);
    client.recordActivity();

    const result1 = mgr.checkClient(&client);
    try std.testing.expectEqual(heartbeat_manager_mod.HeartbeatTickResult.heartbeat_sent, result1);
    const ping1 = client.last_ping_id_sent;

    // Reset activity to avoid timeout on second check.
    client.recordActivity();
    const result2 = mgr.checkClient(&client);
    try std.testing.expectEqual(heartbeat_manager_mod.HeartbeatTickResult.heartbeat_sent, result2);
    const ping2 = client.last_ping_id_sent;

    // ping_id must be strictly increasing.
    try std.testing.expect(ping2 > ping1);
}

test "spec: heartbeat — server responds to client heartbeat echoing ping_id" {
    // daemon-behavior 03-policies-and-procedures Section 10.2:
    // "The receiver responds with HeartbeatAck (0x0004)."
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    const echo = HeartbeatManager.processHeartbeat(&client, 42);
    try std.testing.expectEqual(@as(u32, 42), echo);
}

test "spec: heartbeat — processAck records the acked ping_id" {
    // Receiving HeartbeatAck confirms connection liveness.
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    HeartbeatManager.processAck(&client, 7);
    try std.testing.expectEqual(@as(u32, 7), client.last_ping_id_acked);
}

// ── Spec: 90s Timeout ────────────────────────────────────────────────────────

test "spec: heartbeat — timeout fires when no message received for 90s" {
    // daemon-behavior 03-policies-and-procedures Section 10.2:
    // "If no message of any kind is received within 90 seconds (3 missed
    //  heartbeat intervals), the daemon sends Disconnect(reason: timeout)."
    var mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);

    // Simulate 90s of inactivity by setting the timestamp far in the past.
    client.last_activity_timestamp = std.time.milliTimestamp() - 91_000;

    const result = mgr.checkClient(&client);
    try std.testing.expectEqual(heartbeat_manager_mod.HeartbeatTickResult.timed_out, result);
}

test "spec: heartbeat — does NOT timeout when activity is recent" {
    var mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);
    client.recordActivity(); // Recent activity.

    const result = mgr.checkClient(&client);
    try std.testing.expectEqual(heartbeat_manager_mod.HeartbeatTickResult.heartbeat_sent, result);
}

// ── Spec: HeartbeatAck Records Activity ──────────────────────────────────────

test "spec: heartbeat — HeartbeatAck counts as a received message for connection liveness" {
    // daemon-behavior 03-policies-and-procedures Section 10.2:
    // "If no message of any kind is received within 90 seconds..."
    // HeartbeatAck IS a message, so it resets the connection liveness timeout.
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);

    // Make the client appear inactive.
    client.last_activity_timestamp = std.time.milliTimestamp() - 80_000;

    // Process a HeartbeatAck — this should update activity timestamp.
    HeartbeatManager.processAck(&client, 1);

    // Now the client should NOT be inactive since processAck called recordActivity.
    try std.testing.expect(!client.isInactiveSince(heartbeat_manager_mod.HEARTBEAT_TIMEOUT_MS));
}

// ── Spec: Heartbeat Skips Non-Active Clients ─────────────────────────────────

test "spec: heartbeat — skips clients in HANDSHAKING state" {
    // Heartbeat is only for READY and OPERATING clients. HANDSHAKING clients
    // have their own timeout (5s handshake timeout).
    var mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    // Client is in HANDSHAKING state.
    const result = mgr.checkClient(&client);
    try std.testing.expectEqual(heartbeat_manager_mod.HeartbeatTickResult.skipped, result);
}

test "spec: heartbeat — skips clients in DISCONNECTING state" {
    // DISCONNECTING clients are being torn down; no heartbeat needed.
    var mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.disconnecting);
    const result = mgr.checkClient(&client);
    try std.testing.expectEqual(heartbeat_manager_mod.HeartbeatTickResult.skipped, result);
}

test "spec: heartbeat — sends to OPERATING clients" {
    var mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.recordActivity();

    const result = mgr.checkClient(&client);
    try std.testing.expectEqual(heartbeat_manager_mod.HeartbeatTickResult.heartbeat_sent, result);
}

// ── Spec: ping_id Wrapping ───────────────────────────────────────────────────

test "spec: heartbeat — ping_id wraps around and skips zero" {
    // ping_id is a monotonic counter. Must not be 0 (0 is reserved/invalid).
    var mgr = HeartbeatManager{ .next_ping_id = 0xFFFFFFFF };
    const id1 = mgr.nextPingId();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), id1);
    const id2 = mgr.nextPingId();
    // After 0xFFFFFFFF, wraps to 1 (skipping 0).
    try std.testing.expectEqual(@as(u32, 1), id2);
}
