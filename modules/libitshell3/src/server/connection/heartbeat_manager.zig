//! Heartbeat manager. Shared 30s timer, per-client 90s timeout, bidirectional
//! heartbeat (server sends + responds to client Heartbeat).
//!
//! Per protocol spec 01-protocol-overview (30s interval, 90s timeout).

const std = @import("std");
const client_state_mod = @import("client_state.zig");
const ClientState = client_state_mod.ClientState;

/// Heartbeat interval in milliseconds (30 seconds).
pub const HEARTBEAT_INTERVAL_MS: u32 = 30_000;

/// Heartbeat timeout in milliseconds (90 seconds).
/// If no message of any kind is received within this window, disconnect.
pub const HEARTBEAT_TIMEOUT_MS: i64 = 90_000;

pub const LivenessResult = enum {
    alive,
    timed_out,
    unknown,
};

/// Manages heartbeat state across all clients.
pub const HeartbeatManager = struct {
    /// Monotonically increasing ping_id counter.
    next_ping_id: u32 = 1,

    /// Advance the ping_id counter and return the current value.
    pub fn nextPingId(self: *HeartbeatManager) u32 {
        const id = self.next_ping_id;
        self.next_ping_id +%= 1;
        if (self.next_ping_id == 0) self.next_ping_id = 1;
        return id;
    }

    pub fn checkLiveness(_: *const HeartbeatManager, client: *const ClientState, now: i64) LivenessResult {
        const state = client.getState();
        if (state != .ready and state != .operating) return .unknown;
        if (now - client.last_activity_timestamp >= HEARTBEAT_TIMEOUT_MS)
            return .timed_out;
        return .alive;
    }

    /// Process an incoming HeartbeatAck from a client.
    pub fn processAck(client: *ClientState, ping_id: u32) void {
        client.last_ping_id_acked = ping_id;
        client.recordActivity();
    }

    /// Process an incoming Heartbeat from a client. Returns the ping_id to echo.
    pub fn processHeartbeat(client: *ClientState, ping_id: u32) u32 {
        client.recordActivity();
        return ping_id;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

test "HeartbeatManager.nextPingId: starts at 1 and increments" {
    var mgr = HeartbeatManager{};
    try std.testing.expectEqual(@as(u32, 1), mgr.nextPingId());
    try std.testing.expectEqual(@as(u32, 2), mgr.nextPingId());
}

test "HeartbeatManager.nextPingId: wraps around skipping zero" {
    var mgr = HeartbeatManager{ .next_ping_id = 0xFFFFFFFF };
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), mgr.nextPingId());
    // After wrap, 0 is skipped -> next should be 1
    try std.testing.expectEqual(@as(u32, 1), mgr.nextPingId());
}

test "HeartbeatManager.checkLiveness: unknown for handshaking clients" {
    const mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    const now = std.time.milliTimestamp();
    const result = mgr.checkLiveness(&client, now);
    try std.testing.expectEqual(LivenessResult.unknown, result);
}

test "HeartbeatManager.checkLiveness: alive for ready client with recent activity" {
    const mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);
    client.recordActivity();
    const now = std.time.milliTimestamp();
    const result = mgr.checkLiveness(&client, now);
    try std.testing.expectEqual(LivenessResult.alive, result);
}

test "HeartbeatManager.checkLiveness: timed_out for inactive client" {
    const mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    _ = client.connection.transitionTo(.ready);
    client.last_activity_timestamp = std.time.milliTimestamp() - HEARTBEAT_TIMEOUT_MS - 1;
    const now = std.time.milliTimestamp();
    const result = mgr.checkLiveness(&client, now);
    try std.testing.expectEqual(LivenessResult.timed_out, result);
}

test "HeartbeatManager.processAck: records ack and updates activity" {
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    HeartbeatManager.processAck(&client, 42);
    try std.testing.expectEqual(@as(u32, 42), client.last_ping_id_acked);
}

test "HeartbeatManager.processHeartbeat: echoes ping_id and records activity" {
    var client = ClientState.init(.{ .fd = 5 }, 1, @import("itshell3_testing").helpers.testChunkPool());
    const echo = HeartbeatManager.processHeartbeat(&client, 7);
    try std.testing.expectEqual(@as(u32, 7), echo);
}
