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
const LivenessResult = heartbeat_manager_mod.LivenessResult;
const ClientState = server.connection.client_state.ClientState;
const State = server.connection.connection_state.State;

// ── Spec: Heartbeat Interval ─────────────────────────────────────────────────

test "spec: heartbeat — interval is 30 seconds" {
    try std.testing.expectEqual(@as(u32, 30_000), heartbeat_manager_mod.HEARTBEAT_INTERVAL_MS);
}

test "spec: heartbeat — connection timeout is 90 seconds" {
    try std.testing.expectEqual(@as(i64, 90_000), heartbeat_manager_mod.HEARTBEAT_TIMEOUT_MS);
}

// ── Spec: Bidirectional Heartbeat ────────────────────────────────────────────

test "spec: heartbeat — server sends heartbeat with monotonic ping_id" {
    var mgr = HeartbeatManager{};
    const id1 = mgr.nextPingId();
    const id2 = mgr.nextPingId();
    try std.testing.expect(id2 > id1);
}

test "spec: heartbeat — server responds to client heartbeat echoing ping_id" {
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    const echo = HeartbeatManager.processHeartbeat(&client, 42);
    try std.testing.expectEqual(@as(u32, 42), echo);
}

test "spec: heartbeat — processAck records the acked ping_id" {
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    HeartbeatManager.processAck(&client, 7);
    try std.testing.expectEqual(@as(u32, 7), client.last_ping_id_acked);
}

// ── Spec: 90s Timeout ────────────────────────────────────────────────────────

test "spec: heartbeat — timeout fires when no message received for 90s" {
    const mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);
    client.last_activity_timestamp = std.time.milliTimestamp() - 91_000;
    const now = std.time.milliTimestamp();
    const result = mgr.checkLiveness(&client, now);
    try std.testing.expectEqual(LivenessResult.timed_out, result);
}

test "spec: heartbeat — does NOT timeout when activity is recent" {
    const mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);
    client.recordActivity();
    const now = std.time.milliTimestamp();
    const result = mgr.checkLiveness(&client, now);
    try std.testing.expectEqual(LivenessResult.alive, result);
}

// ── Spec: HeartbeatAck Records Activity ──────────────────────────────────────

test "spec: heartbeat — HeartbeatAck counts as a received message for connection liveness" {
    const mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);
    client.last_activity_timestamp = std.time.milliTimestamp() - 80_000;

    HeartbeatManager.processAck(&client, 1);

    const now = std.time.milliTimestamp();
    const result = mgr.checkLiveness(&client, now);
    try std.testing.expectEqual(LivenessResult.alive, result);
}

// ── Spec: Heartbeat Skips Non-Active Clients ─────────────────────────────────

test "spec: heartbeat — unknown for clients in HANDSHAKING state" {
    const mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    const now = std.time.milliTimestamp();
    const result = mgr.checkLiveness(&client, now);
    try std.testing.expectEqual(LivenessResult.unknown, result);
}

test "spec: heartbeat — unknown for clients in DISCONNECTING state" {
    const mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.disconnecting);
    const now = std.time.milliTimestamp();
    const result = mgr.checkLiveness(&client, now);
    try std.testing.expectEqual(LivenessResult.unknown, result);
}

test "spec: heartbeat — alive for OPERATING clients" {
    const mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.recordActivity();
    const now = std.time.milliTimestamp();
    const result = mgr.checkLiveness(&client, now);
    try std.testing.expectEqual(LivenessResult.alive, result);
}

// ── Spec: ping_id Wrapping ───────────────────────────────────────────────────

test "spec: heartbeat — ping_id wraps around and skips zero" {
    var mgr = HeartbeatManager{ .next_ping_id = 0xFFFFFFFF };
    const id1 = mgr.nextPingId();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), id1);
    const id2 = mgr.nextPingId();
    try std.testing.expectEqual(@as(u32, 1), id2);
}
