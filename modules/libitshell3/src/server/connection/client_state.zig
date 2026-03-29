//! Per-client state struct wrapping ConnectionState with daemon-specific fields.
//! Owns the connection lifecycle plus ring buffer cursors, display info,
//! heartbeat tracking, and attached session reference.
//!
//! Per daemon-architecture integration-boundaries spec.

const std = @import("std");
const connection_state_mod = @import("connection_state.zig");
const ConnectionState = connection_state_mod.ConnectionState;
const State = connection_state_mod.State;
const transport = @import("itshell3_transport");
const SocketConnection = transport.transport.SocketConnection;
const server = @import("itshell3_server");
const ring_buffer_mod = server.delivery.ring_buffer;
const RingCursor = ring_buffer_mod.RingCursor;
const direct_queue_mod = server.delivery.direct_queue;
const DirectQueue = direct_queue_mod.DirectQueue;

/// Per-client daemon state. Wraps ConnectionState (which wraps SocketConnection)
/// plus daemon-specific delivery and tracking fields.
pub const ClientState = struct {
    connection: ConnectionState,

    /// Per-client ring buffer cursor for frame delivery (priority 2 channel).
    ring_cursor: RingCursor = RingCursor.init(),

    /// Per-client direct message queue (priority 1 channel).
    direct_queue: DirectQueue = DirectQueue.init(),

    /// Partial send offset for direct queue drain.
    direct_partial_offset: usize = 0,

    /// Display info from ClientDisplayInfo message.
    display_refresh_hz: u32 = 60,
    power_state: PowerState = .ac,
    transport_type: TransportType = .local,

    /// Heartbeat tracking.
    last_activity_timestamp: i64 = 0,
    last_ping_id_sent: u32 = 0,
    last_ping_id_acked: u32 = 0,

    /// Timer IDs for per-client timers (handshake timeout, ready idle timeout).
    handshake_timer_id: ?u16 = null,
    ready_idle_timer_id: ?u16 = null,

    /// Per-client buffer for accumulating partial protocol frames across recv()
    /// calls. TCP does not guarantee message boundaries, so incomplete trailing
    /// bytes from one recv() must be preserved for the next.
    recv_partial_buffer: [MAX_RECV_PARTIAL]u8 = [_]u8{0} ** MAX_RECV_PARTIAL,
    recv_partial_length: u16 = 0,

    /// Whether this client slot is occupied.
    occupied: bool = false,

    /// Maximum partial frame buffer size. Large enough to hold one max-size
    /// header plus some payload spillover. Protocol header is 16 bytes; typical
    /// partial frames are much smaller than this.
    pub const MAX_RECV_PARTIAL: u16 = 4096;

    pub const PowerState = enum { ac, battery, low_battery };
    pub const TransportType = enum { local, ssh_tunnel, unknown };

    /// Initialize a new client state wrapping a SocketConnection.
    pub fn init(socket: SocketConnection, client_id: u32) ClientState {
        return .{
            .connection = ConnectionState.init(socket, client_id),
            .occupied = true,
            .last_activity_timestamp = std.time.milliTimestamp(),
        };
    }

    /// Reset this slot to unoccupied state.
    pub fn deinit(self: *ClientState) void {
        self.direct_queue.deinit();
        self.recv_partial_length = 0;
        self.occupied = false;
    }

    /// Convenience accessor for the connection state.
    pub fn getState(self: *const ClientState) State {
        return self.connection.state;
    }

    /// Convenience accessor for client_id.
    pub fn getClientId(self: *const ClientState) u32 {
        return self.connection.client_id;
    }

    /// Convenience accessor for the socket fd (for kqueue registration).
    pub fn fd(self: *const ClientState) std.posix.fd_t {
        return self.connection.socket.fd;
    }

    /// Record that activity was observed (any message received).
    /// Resets the heartbeat liveness timeout.
    pub fn recordActivity(self: *ClientState) void {
        self.last_activity_timestamp = std.time.milliTimestamp();
    }

    /// Check if this client has been inactive for longer than timeout_ms.
    pub fn isInactiveSince(self: *const ClientState, timeout_ms: i64) bool {
        const now = std.time.milliTimestamp();
        return (now - self.last_activity_timestamp) >= timeout_ms;
    }

    /// Enqueue a message to the direct queue (priority 1 channel).
    pub fn enqueueDirect(self: *ClientState, data: []const u8) !void {
        try self.direct_queue.enqueue(data);
    }

    /// Returns any previously saved partial frame bytes.
    pub fn getRecvPartial(self: *const ClientState) []const u8 {
        return self.recv_partial_buffer[0..self.recv_partial_length];
    }

    /// Saves leftover bytes from an incomplete frame for the next recv() call.
    /// If the leftover exceeds the buffer capacity, the excess is silently
    /// dropped (protocol error -- the frame is too large for partial buffering).
    pub fn saveRecvPartial(self: *ClientState, data: []const u8) void {
        const copy_length = @min(data.len, MAX_RECV_PARTIAL);
        @memcpy(self.recv_partial_buffer[0..copy_length], data[0..copy_length]);
        self.recv_partial_length = @intCast(copy_length);
    }

    /// Clears the partial receive buffer.
    pub fn clearRecvPartial(self: *ClientState) void {
        self.recv_partial_length = 0;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

test "ClientState.init: creates occupied client with handshaking state" {
    const client = ClientState.init(.{ .fd = 7 }, 42);
    try std.testing.expect(client.occupied);
    try std.testing.expectEqual(State.handshaking, client.getState());
    try std.testing.expectEqual(@as(u32, 42), client.getClientId());
    try std.testing.expectEqual(@as(std.posix.fd_t, 7), client.fd());
    try std.testing.expect(client.last_activity_timestamp > 0);
}

test "ClientState.deinit: marks slot as unoccupied" {
    var client = ClientState.init(.{ .fd = 7 }, 1);
    client.deinit();
    try std.testing.expect(!client.occupied);
}

test "ClientState.recordActivity: updates timestamp" {
    var client = ClientState.init(.{ .fd = 7 }, 1);
    const before = client.last_activity_timestamp;
    // Force a different timestamp by manipulating directly
    client.last_activity_timestamp = before - 100;
    client.recordActivity();
    try std.testing.expect(client.last_activity_timestamp >= before - 100);
}

test "ClientState.enqueueDirect: adds message to direct queue" {
    var client = ClientState.init(.{ .fd = 7 }, 1);
    defer client.deinit();
    try client.enqueueDirect("test-msg");
    try std.testing.expect(!client.direct_queue.isEmpty());
}

test "ClientState: ring_cursor starts at zero" {
    const client = ClientState.init(.{ .fd = 7 }, 1);
    try std.testing.expectEqual(@as(usize, 0), client.ring_cursor.position);
}

test "ClientState: default display info" {
    const client = ClientState.init(.{ .fd = 7 }, 1);
    try std.testing.expectEqual(@as(u32, 60), client.display_refresh_hz);
    try std.testing.expectEqual(ClientState.PowerState.ac, client.power_state);
    try std.testing.expectEqual(ClientState.TransportType.local, client.transport_type);
}

test "ClientState.saveRecvPartial: stores and retrieves leftover bytes" {
    var client = ClientState.init(.{ .fd = 7 }, 1);
    defer client.deinit();
    const data = "partial-frame-data";
    client.saveRecvPartial(data);
    try std.testing.expectEqualStrings(data, client.getRecvPartial());
}

test "ClientState.clearRecvPartial: resets partial length to zero" {
    var client = ClientState.init(.{ .fd = 7 }, 1);
    defer client.deinit();
    client.saveRecvPartial("some bytes");
    client.clearRecvPartial();
    try std.testing.expectEqual(@as(u16, 0), client.recv_partial_length);
    try std.testing.expectEqual(@as(usize, 0), client.getRecvPartial().len);
}

test "ClientState.saveRecvPartial: truncates when exceeding capacity" {
    var client = ClientState.init(.{ .fd = 7 }, 1);
    defer client.deinit();
    // Create data larger than MAX_RECV_PARTIAL.
    var big_data: [ClientState.MAX_RECV_PARTIAL + 100]u8 = [_]u8{'x'} ** (ClientState.MAX_RECV_PARTIAL + 100);
    client.saveRecvPartial(&big_data);
    try std.testing.expectEqual(@as(u16, ClientState.MAX_RECV_PARTIAL), client.recv_partial_length);
}

test "ClientState.deinit: clears recv partial buffer" {
    var client = ClientState.init(.{ .fd = 7 }, 1);
    client.saveRecvPartial("leftover");
    client.deinit();
    try std.testing.expectEqual(@as(u16, 0), client.recv_partial_length);
}

test "ClientState.init: recv partial starts empty" {
    const client = ClientState.init(.{ .fd = 7 }, 1);
    try std.testing.expectEqual(@as(u16, 0), client.recv_partial_length);
    try std.testing.expectEqual(@as(usize, 0), client.getRecvPartial().len);
}

test "ClientState: timer IDs default to null" {
    const client = ClientState.init(.{ .fd = 7 }, 1);
    try std.testing.expect(client.handshake_timer_id == null);
    try std.testing.expect(client.ready_idle_timer_id == null);
}
