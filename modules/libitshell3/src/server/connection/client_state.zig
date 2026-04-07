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
const protocol = @import("itshell3_protocol");
const MessageReader = protocol.message_reader.MessageReader;
const ChunkPool = protocol.message_reader.ChunkPool;
const core = @import("itshell3_core");
const MAX_PANES = core.types.MAX_PANES;
const server = @import("itshell3_server");
const ring_buffer_mod = server.delivery.ring_buffer;
const RingCursor = ring_buffer_mod.RingCursor;
const ControlChannelWriter = server.delivery.control_channel_writer.ControlChannelWriter;
const SessionEntry = server.state.session_entry.SessionEntry;

pub const ClientState = struct {
    connection: ConnectionState,

    /// Per-client ring buffer cursors for frame delivery (priority 2 channel).
    /// One cursor per pane slot. null = client has not received frames for that pane.
    ring_cursors: [MAX_PANES]?RingCursor = [_]?RingCursor{null} ** MAX_PANES,

    /// Control channel writer (priority 1 direct queue flush).
    control_channel: ControlChannelWriter = ControlChannelWriter.init(),

    /// Display info reported by the client via ClientDisplayInfo (0x0505).
    display_info: ClientDisplayInfo = .{},

    /// Pointer to the attached session (daemon-level field for direct access
    /// without lookup). null = not attached to any session.
    attached_session: ?*SessionEntry = null,

    /// Heartbeat tracking.
    last_activity_timestamp: i64 = 0,
    last_ping_id_sent: u32 = 0,
    last_ping_id_acked: u32 = 0,

    /// Health state per daemon-behavior spec client health model.
    health_state: HealthState = .healthy,
    /// Timestamp when health state last changed.
    health_state_changed_at: i64 = 0,
    /// Whether PausePane is active (orthogonal to health state per spec).
    paused: bool = false,
    /// Timestamp when PausePane was received (T=0 for escalation timeline).
    pause_started_at: i64 = 0,

    /// Flow control configuration per daemon-behavior spec flow control config.
    flow_control: FlowControlConfig = .{},

    /// Timestamp of last application-level message for stale timeout tracking.
    /// Per spec stale timeout rules: resets on ContinuePane, KeyEvent, WindowResize,
    /// ClientDisplayInfo, and request messages. HeartbeatAck does NOT reset.
    last_application_message_at: i64 = 0,

    /// Timer IDs for per-client timers (handshake timeout, ready idle timeout).
    handshake_timer_id: ?u16 = null,
    ready_idle_timer_id: ?u16 = null,

    /// Per-connection framing state. Accumulates partial messages across recv()
    /// calls. See daemon-architecture integration-boundaries spec.
    message_reader: MessageReader,

    /// Whether this client slot is occupied.
    occupied: bool = false,

    /// Client health states per daemon-behavior spec client health model.
    pub const HealthState = enum {
        healthy,
        stale,
    };

    /// Flow control configuration with transport-aware defaults.
    /// Per daemon-behavior spec flow control config.
    pub const FlowControlConfig = struct {
        max_queue_age_ms: u32 = 5000,
        auto_continue: bool = true,
        stale_timeout_ms: u32 = 60000,
        eviction_timeout_ms: u32 = 300000,

        /// Returns the default config for a given transport type.
        pub fn defaultForTransport(transport_type: ClientDisplayInfo.TransportType) FlowControlConfig {
            return switch (transport_type) {
                .ssh_tunnel => .{
                    .max_queue_age_ms = 10000,
                    .auto_continue = true,
                    .stale_timeout_ms = 120000,
                    .eviction_timeout_ms = 300000,
                },
                else => .{},
            };
        }
    };

    /// Display, power, and transport state reported by the client via
    /// ClientDisplayInfo (0x0505). See protocol flow-control-and-auxiliary spec.
    pub const ClientDisplayInfo = struct {
        display_refresh_hz: u16 = 60,
        power_state: PowerState = .ac,
        preferred_max_fps: u16 = 0,
        transport_type: TransportType = .local,
        estimated_rtt_ms: u16 = 0,
        bandwidth_hint: BandwidthHint = .local,

        pub const PowerState = enum { ac, battery, low_battery };
        pub const TransportType = enum { local, ssh_tunnel, unknown };
        pub const BandwidthHint = enum { local, lan, wan, cellular };
    };

    /// Initialize a new client state wrapping a SocketConnection.
    /// The `chunk_pool` reference is shared across all clients and must outlive
    /// this ClientState.
    pub fn init(socket: SocketConnection, client_id: u32, chunk_pool: *ChunkPool) ClientState {
        return .{
            .connection = ConnectionState.init(socket, client_id),
            .message_reader = .{ .pool = chunk_pool },
            .occupied = true,
            .last_activity_timestamp = std.time.milliTimestamp(),
        };
    }

    /// Reset this slot to unoccupied state.
    pub fn deinit(self: *ClientState) void {
        self.control_channel.deinit();
        self.message_reader.reset();
        self.attached_session = null;
        self.occupied = false;
    }

    pub fn getState(self: *const ClientState) State {
        return self.connection.state;
    }

    pub fn getClientId(self: *const ClientState) u32 {
        return self.connection.client_id;
    }

    pub fn fd(self: *const ClientState) std.posix.fd_t {
        return self.connection.socket.fd;
    }

    /// Resets the heartbeat liveness timeout.
    pub fn recordActivity(self: *ClientState) void {
        self.last_activity_timestamp = std.time.milliTimestamp();
    }

    /// Records an application-level message for stale timeout tracking.
    /// Per spec stale timeout rules: resets on KeyEvent, WindowResize, ContinuePane,
    /// ClientDisplayInfo, and request messages. Also resets heartbeat liveness.
    pub fn recordApplicationMessage(self: *ClientState) void {
        const now = std.time.milliTimestamp();
        self.last_application_message_at = now;
        self.last_activity_timestamp = now;
    }

    /// Transitions to stale health state.
    pub fn markStale(self: *ClientState) void {
        self.health_state = .stale;
        self.health_state_changed_at = std.time.milliTimestamp();
    }

    /// Recovers from stale to healthy.
    pub fn markHealthy(self: *ClientState) void {
        self.health_state = .healthy;
        self.health_state_changed_at = std.time.milliTimestamp();
    }

    pub fn enqueueDirect(self: *ClientState, data: []const u8) !void {
        try self.control_channel.enqueue(data);
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

test "ClientState.init: creates occupied client with handshaking state" {
    const testing_helpers = @import("itshell3_testing").helpers;
    const client = ClientState.init(.{ .fd = 7 }, 42, testing_helpers.testChunkPool());
    try std.testing.expect(client.occupied);
    try std.testing.expectEqual(State.handshaking, client.getState());
    try std.testing.expectEqual(@as(u32, 42), client.getClientId());
    try std.testing.expectEqual(@as(std.posix.fd_t, 7), client.fd());
    try std.testing.expect(client.last_activity_timestamp > 0);
}

test "ClientState.deinit: marks slot as unoccupied" {
    const testing_helpers = @import("itshell3_testing").helpers;
    var client = ClientState.init(.{ .fd = 7 }, 1, testing_helpers.testChunkPool());
    client.deinit();
    try std.testing.expect(!client.occupied);
}

test "ClientState.recordActivity: updates timestamp" {
    const testing_helpers = @import("itshell3_testing").helpers;
    var client = ClientState.init(.{ .fd = 7 }, 1, testing_helpers.testChunkPool());
    const before = client.last_activity_timestamp;
    // Force a different timestamp by manipulating directly.
    client.last_activity_timestamp = before - 100;
    client.recordActivity();
    try std.testing.expect(client.last_activity_timestamp >= before - 100);
}

test "ClientState.enqueueDirect: adds message to direct queue" {
    const testing_helpers = @import("itshell3_testing").helpers;
    var client = ClientState.init(.{ .fd = 7 }, 1, testing_helpers.testChunkPool());
    defer client.deinit();
    try client.enqueueDirect("test-msg");
    try std.testing.expect(!client.control_channel.direct_queue.isEmpty());
}

test "ClientState: ring_cursors all start as null" {
    const testing_helpers = @import("itshell3_testing").helpers;
    const client = ClientState.init(.{ .fd = 7 }, 1, testing_helpers.testChunkPool());
    for (client.ring_cursors) |cursor| {
        try std.testing.expect(cursor == null);
    }
}

test "ClientState: display_info has correct defaults per protocol spec" {
    const testing_helpers = @import("itshell3_testing").helpers;
    const client = ClientState.init(.{ .fd = 7 }, 1, testing_helpers.testChunkPool());
    const info = client.display_info;
    try std.testing.expectEqual(@as(u16, 60), info.display_refresh_hz);
    try std.testing.expectEqual(ClientState.ClientDisplayInfo.PowerState.ac, info.power_state);
    try std.testing.expectEqual(@as(u16, 0), info.preferred_max_fps);
    try std.testing.expectEqual(ClientState.ClientDisplayInfo.TransportType.local, info.transport_type);
    try std.testing.expectEqual(@as(u16, 0), info.estimated_rtt_ms);
    try std.testing.expectEqual(ClientState.ClientDisplayInfo.BandwidthHint.local, info.bandwidth_hint);
}

test "ClientState: attached_session defaults to null" {
    const testing_helpers = @import("itshell3_testing").helpers;
    const client = ClientState.init(.{ .fd = 7 }, 1, testing_helpers.testChunkPool());
    try std.testing.expect(client.attached_session == null);
}

test "ClientState.deinit: clears attached_session" {
    const testing_helpers = @import("itshell3_testing").helpers;
    var client = ClientState.init(.{ .fd = 7 }, 1, testing_helpers.testChunkPool());
    try std.testing.expect(client.attached_session == null);
    // Use @ptrFromInt with a well-aligned nonzero address for test purposes only.
    // This avoids constructing a real SessionEntry (which requires ImeEngine vtable).
    client.attached_session = @ptrFromInt(@alignOf(SessionEntry));
    try std.testing.expect(client.attached_session != null);
    client.deinit();
    try std.testing.expect(client.attached_session == null);
}

test "ClientState: message_reader starts empty" {
    const testing_helpers = @import("itshell3_testing").helpers;
    const client = ClientState.init(.{ .fd = 7 }, 1, testing_helpers.testChunkPool());
    try std.testing.expectEqual(@as(u32, 0), client.message_reader.length);
}

test "ClientState.deinit: resets message_reader" {
    const testing_helpers = @import("itshell3_testing").helpers;
    var client = ClientState.init(.{ .fd = 7 }, 1, testing_helpers.testChunkPool());
    try client.message_reader.feed("leftover");
    client.deinit();
    try std.testing.expectEqual(@as(u32, 0), client.message_reader.length);
}

test "ClientState: timer IDs default to null" {
    const testing_helpers = @import("itshell3_testing").helpers;
    const client = ClientState.init(.{ .fd = 7 }, 1, testing_helpers.testChunkPool());
    try std.testing.expect(client.handshake_timer_id == null);
    try std.testing.expect(client.ready_idle_timer_id == null);
}
