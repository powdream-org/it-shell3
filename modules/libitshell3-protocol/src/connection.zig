const std = @import("std");
const message_type_mod = @import("message_type.zig");
const transport_mod = @import("transport.zig");
const reader_mod = @import("reader.zig");

pub const ConnectionState = enum {
    disconnected,
    connecting,
    handshaking,
    ready,
    operating,
    disconnecting,
};

pub const NegotiatedCaps = struct {
    clipboard_sync: bool = false,
    mouse: bool = false,
    selection: bool = false,
    search: bool = false,
    fd_passing: bool = false,
    agent_detection: bool = false,
    flow_control: bool = false,
    pixel_dimensions: bool = false,
    sixel: bool = false,
    kitty_graphics: bool = false,
    notifications: bool = false,
};

pub const Connection = struct {
    transport: transport_mod.Transport,
    state: ConnectionState,
    client_id: ?u32,
    attached_session_id: ?u32,
    send_seq: reader_mod.SequenceTracker,
    recv_seq_last: u32,
    negotiated_caps: NegotiatedCaps,

    pub fn init(transport: transport_mod.Transport) Connection {
        return .{
            .transport = transport,
            .state = .handshaking,
            .client_id = null,
            .attached_session_id = null,
            .send_seq = .{},
            .recv_seq_last = 0,
            .negotiated_caps = .{},
        };
    }

    /// Validate that a message type is allowed in the current state.
    pub fn validateMessageType(self: *const Connection, msg_type: u16) error{InvalidState}!void {
        const mt: message_type_mod.MessageType = @enumFromInt(msg_type);
        switch (self.state) {
            .handshaking => switch (mt) {
                .client_hello, .server_hello, .@"error", .disconnect => {},
                else => return error.InvalidState,
            },
            .ready => switch (mt) {
                .create_session_request,
                .create_session_response,
                .list_sessions_request,
                .list_sessions_response,
                .attach_session_request,
                .attach_session_response,
                .attach_or_create_request,
                .attach_or_create_response,
                .heartbeat,
                .heartbeat_ack,
                .disconnect,
                .@"error",
                .client_display_info,
                .client_display_info_ack,
                => {},
                else => return error.InvalidState,
            },
            .operating => {}, // All message types allowed
            .disconnecting => switch (mt) {
                .disconnect, .@"error" => {},
                else => return error.InvalidState,
            },
            .disconnected, .connecting => return error.InvalidState,
        }
    }

    /// Transition: handshaking -> ready
    pub fn completeHandshake(self: *Connection, client_id: u32, caps: NegotiatedCaps) error{InvalidTransition}!void {
        if (self.state != .handshaking) return error.InvalidTransition;
        self.state = .ready;
        self.client_id = client_id;
        self.negotiated_caps = caps;
    }

    /// Transition: ready -> operating
    pub fn attachSession(self: *Connection, session_id: u32) error{InvalidTransition}!void {
        if (self.state != .ready) return error.InvalidTransition;
        self.state = .operating;
        self.attached_session_id = session_id;
    }

    /// Transition: operating -> ready
    pub fn detachSession(self: *Connection) error{InvalidTransition}!void {
        if (self.state != .operating) return error.InvalidTransition;
        self.state = .ready;
        self.attached_session_id = null;
    }

    /// Transition: ready|operating -> disconnecting
    pub fn beginDisconnect(self: *Connection) error{InvalidTransition}!void {
        switch (self.state) {
            .ready, .operating => self.state = .disconnecting,
            else => return error.InvalidTransition,
        }
    }

    /// Transition: disconnecting -> disconnected
    pub fn completeDisconnect(self: *Connection) void {
        self.transport.close();
        self.state = .disconnected;
    }
};

// --- Tests ---

test "Connection.init: state is handshaking" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    const conn = Connection.init(bt.transport());
    try std.testing.expectEqual(ConnectionState.handshaking, conn.state);
    try std.testing.expectEqual(@as(?u32, null), conn.client_id);
}

test "Connection.completeHandshake: handshaking to ready" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    var conn = Connection.init(bt.transport());
    try conn.completeHandshake(5, .{ .mouse = true });
    try std.testing.expectEqual(ConnectionState.ready, conn.state);
    try std.testing.expectEqual(@as(?u32, 5), conn.client_id);
    try std.testing.expect(conn.negotiated_caps.mouse);
}

test "Connection.completeHandshake: from ready returns error" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    var conn = Connection.init(bt.transport());
    try conn.completeHandshake(1, .{});
    try std.testing.expectError(error.InvalidTransition, conn.completeHandshake(2, .{}));
}

test "Connection.attachSession: ready to operating" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    var conn = Connection.init(bt.transport());
    try conn.completeHandshake(1, .{});
    try conn.attachSession(42);
    try std.testing.expectEqual(ConnectionState.operating, conn.state);
    try std.testing.expectEqual(@as(?u32, 42), conn.attached_session_id);
}

test "Connection.attachSession: from handshaking returns error" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    var conn = Connection.init(bt.transport());
    try std.testing.expectError(error.InvalidTransition, conn.attachSession(1));
}

test "Connection.detachSession: operating to ready" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    var conn = Connection.init(bt.transport());
    try conn.completeHandshake(1, .{});
    try conn.attachSession(1);
    try conn.detachSession();
    try std.testing.expectEqual(ConnectionState.ready, conn.state);
    try std.testing.expectEqual(@as(?u32, null), conn.attached_session_id);
}

test "Connection.beginDisconnect: from operating" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    var conn = Connection.init(bt.transport());
    try conn.completeHandshake(1, .{});
    try conn.attachSession(1);
    try conn.beginDisconnect();
    try std.testing.expectEqual(ConnectionState.disconnecting, conn.state);
}

test "Connection.beginDisconnect: from ready" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    var conn = Connection.init(bt.transport());
    try conn.completeHandshake(1, .{});
    try conn.beginDisconnect();
    try std.testing.expectEqual(ConnectionState.disconnecting, conn.state);
}

test "Connection.beginDisconnect: from handshaking returns error" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    var conn = Connection.init(bt.transport());
    try std.testing.expectError(error.InvalidTransition, conn.beginDisconnect());
}

test "Connection.validateMessageType: handshaking allows hello" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    const conn = Connection.init(bt.transport());
    try conn.validateMessageType(@intFromEnum(message_type_mod.MessageType.client_hello));
    try std.testing.expectError(error.InvalidState, conn.validateMessageType(@intFromEnum(message_type_mod.MessageType.key_event)));
}

test "Connection.validateMessageType: operating allows everything" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    var conn = Connection.init(bt.transport());
    try conn.completeHandshake(1, .{});
    try conn.attachSession(1);
    try conn.validateMessageType(@intFromEnum(message_type_mod.MessageType.key_event));
    try conn.validateMessageType(@intFromEnum(message_type_mod.MessageType.frame_update));
}

test "Connection.validateMessageType: disconnecting allows only disconnect and error" {
    const allocator = std.testing.allocator;
    var bt = transport_mod.BufferTransport.init(allocator, "");
    defer bt.deinit();
    var conn = Connection.init(bt.transport());
    try conn.completeHandshake(1, .{});
    try conn.beginDisconnect();
    try conn.validateMessageType(@intFromEnum(message_type_mod.MessageType.disconnect));
    try std.testing.expectError(error.InvalidState, conn.validateMessageType(@intFromEnum(message_type_mod.MessageType.key_event)));
}
