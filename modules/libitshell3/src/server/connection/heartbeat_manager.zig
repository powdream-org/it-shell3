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

/// Timer ID for the shared heartbeat timer.
pub const HEARTBEAT_TIMER_ID: u16 = 0xFF00;

/// Result of a heartbeat tick for a single client.
pub const HeartbeatTickResult = enum {
    /// Client is healthy, heartbeat sent.
    heartbeat_sent,
    /// Client has timed out (no activity for 90s).
    timed_out,
    /// Client is not in an active state (handshaking/disconnecting).
    skipped,
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

    /// Check a single client for heartbeat timeout.
    /// Returns the tick result. The caller is responsible for sending the
    /// heartbeat message or initiating disconnect.
    pub fn checkClient(self: *HeartbeatManager, client: *ClientState) HeartbeatTickResult {
        const state = client.getState();
        if (state != .ready and state != .operating) return .skipped;

        if (client.isInactiveSince(HEARTBEAT_TIMEOUT_MS)) {
            return .timed_out;
        }

        const ping_id = self.nextPingId();
        client.last_ping_id_sent = ping_id;
        return .heartbeat_sent;
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

test "HeartbeatManager.checkClient: skips handshaking clients" {
    var mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1);
    // Client is in handshaking state.
    const result = mgr.checkClient(&client);
    try std.testing.expectEqual(HeartbeatTickResult.skipped, result);
}

test "HeartbeatManager.checkClient: sends heartbeat for ready client" {
    var mgr = HeartbeatManager{};
    var client = ClientState.init(.{ .fd = 5 }, 1);
    _ = client.connection.transitionTo(.ready);
    // Ensure client is "recently active" by updating timestamp
    client.recordActivity();
    const result = mgr.checkClient(&client);
    try std.testing.expectEqual(HeartbeatTickResult.heartbeat_sent, result);
    try std.testing.expectEqual(@as(u32, 1), client.last_ping_id_sent);
}

test "HeartbeatManager.processAck: records ack and updates activity" {
    var client = ClientState.init(.{ .fd = 5 }, 1);
    HeartbeatManager.processAck(&client, 42);
    try std.testing.expectEqual(@as(u32, 42), client.last_ping_id_acked);
}

test "HeartbeatManager.processHeartbeat: echoes ping_id and records activity" {
    var client = ClientState.init(.{ .fd = 5 }, 1);
    const echo = HeartbeatManager.processHeartbeat(&client, 7);
    try std.testing.expectEqual(@as(u32, 7), echo);
}
