//! Server-side connection state machine wrapping transport.SocketConnection.
//! Tracks connection lifecycle, client identity, negotiated capabilities,
//! attached session, and per-connection sequence numbers.
//!
//! Per daemon-architecture integration-boundaries and protocol overview specs.

const std = @import("std");
const transport = @import("itshell3_transport");
const SocketConnection = transport.transport.SocketConnection;
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;

/// Connection lifecycle states. The daemon starts at handshaking (after
/// Listener.accept()). DISCONNECTED and CONNECTING are client-side only.
pub const State = enum {
    handshaking,
    ready,
    operating,
    disconnecting,
};

pub const ConnectionState = struct {
    socket: SocketConnection,
    state: State,
    client_id: u32,
    /// Negotiated general capability names. Fixed buffer for zero-allocation.
    negotiated_caps: [MAX_CAPABILITIES]CapabilityEntry = [_]CapabilityEntry{.{}} ** MAX_CAPABILITIES,
    negotiated_caps_count: u8 = 0,
    /// Negotiated render capability names. Fixed buffer for zero-allocation.
    negotiated_render_caps: [MAX_RENDER_CAPABILITIES]CapabilityEntry = [_]CapabilityEntry{.{}} ** MAX_RENDER_CAPABILITIES,
    negotiated_render_caps_count: u8 = 0,
    /// Session this connection is attached to (0 = not attached).
    attached_session_id: u32 = 0,
    /// Server-side send sequence counter. Starts at 1, wraps 0xFFFFFFFF -> 1.
    send_sequence: u32 = 1,
    /// Last received sequence from client (for debugging/logging).
    recv_sequence_last: u32 = 0,

    pub const MAX_CAPABILITIES: u8 = 16;
    pub const MAX_RENDER_CAPABILITIES: u8 = 8;
    pub const MAX_CAPABILITY_NAME: u8 = 32;

    pub const CapabilityEntry = struct {
        name: [MAX_CAPABILITY_NAME]u8 = [_]u8{0} ** MAX_CAPABILITY_NAME,
        name_length: u8 = 0,

        pub fn getName(self: *const CapabilityEntry) []const u8 {
            return self.name[0..self.name_length];
        }
    };

    pub fn init(socket: SocketConnection, client_id: u32) ConnectionState {
        return .{
            .socket = socket,
            .state = .handshaking,
            .client_id = client_id,
        };
    }

    /// Whether the transition succeeded. Returns false for invalid transitions.
    pub fn transitionTo(self: *ConnectionState, target: State) bool {
        const valid = switch (self.state) {
            .handshaking => target == .ready or target == .disconnecting,
            .ready => target == .operating or target == .disconnecting,
            // TODO(Plan 7): Add `target == .operating` for session switching
            // (AttachSessionRequest to a different session while OPERATING).
            .operating => target == .ready or target == .disconnecting,
            .disconnecting => false,
        };
        if (valid) self.state = target;
        return valid;
    }

    /// Returns the current sequence and increments. Wraps to 1, skipping 0.
    pub fn advanceSendSequence(self: *ConnectionState) u32 {
        const seq = self.send_sequence;
        self.send_sequence = if (self.send_sequence == 0xFFFFFFFF) 1 else self.send_sequence + 1;
        return seq;
    }

    /// Whether `msg_type` is valid for the current connection state.
    pub fn isMessageAllowed(self: *const ConnectionState, msg_type: MessageType) bool {
        return switch (self.state) {
            .handshaking => switch (msg_type) {
                .client_hello => true,
                .@"error" => true,
                .disconnect => true,
                else => false,
            },
            .ready => switch (msg_type) {
                .heartbeat, .heartbeat_ack => true,
                .disconnect => true,
                .@"error" => true,
                .client_display_info => true,
                // Session attach/create/list messages are valid in READY
                .create_session_request, .list_sessions_request, .attach_session_request, .attach_or_create_request => true,
                else => false,
            },
            .operating => switch (msg_type) {
                .heartbeat, .heartbeat_ack => true,
                .disconnect => true,
                .@"error" => true,
                .client_display_info => true,
                .detach_session_request => true,
                // All operational messages are allowed
                else => isOperationalMessageType(msg_type),
            },
            .disconnecting => switch (msg_type) {
                .disconnect => true,
                .@"error" => true,
                else => false,
            },
        };
    }

    pub fn addCapability(self: *ConnectionState, name: []const u8) void {
        addCapabilityTo(&self.negotiated_caps, &self.negotiated_caps_count, MAX_CAPABILITIES, name);
    }

    pub fn addRenderCapability(self: *ConnectionState, name: []const u8) void {
        addCapabilityTo(&self.negotiated_render_caps, &self.negotiated_render_caps_count, MAX_RENDER_CAPABILITIES, name);
    }

    fn addCapabilityTo(
        buffer: anytype,
        count: *u8,
        comptime max: u8,
        name: []const u8,
    ) void {
        if (count.* >= max) return;
        if (name.len > MAX_CAPABILITY_NAME) return;
        var entry = CapabilityEntry{};
        @memcpy(entry.name[0..name.len], name);
        entry.name_length = @intCast(name.len);
        buffer[count.*] = entry;
        count.* += 1;
    }
};

/// Returns true if the message type is an operational (non-lifecycle) type
/// that should be allowed in OPERATING state. Covers 0x0100-0x08FF
/// (session, pane, input, render, IME, flow control, CJK preedit,
/// connection health) and 0x0A00-0x0AFF (extension negotiation).
fn isOperationalMessageType(msg_type: MessageType) bool {
    const raw = @intFromEnum(msg_type);
    if (raw >= 0x0100 and raw <= 0x08FF) return true;
    if (raw >= 0x0A00 and raw <= 0x0AFF) return true;
    return false;
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "ConnectionState.init: starts in handshaking state" {
    const conn = ConnectionState.init(.{ .fd = 5 }, 42);
    try std.testing.expectEqual(State.handshaking, conn.state);
    try std.testing.expectEqual(@as(u32, 42), conn.client_id);
    try std.testing.expectEqual(@as(u32, 1), conn.send_sequence);
    try std.testing.expectEqual(@as(u32, 0), conn.attached_session_id);
}

test "ConnectionState.transitionTo: handshaking to ready" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expect(conn.transitionTo(.ready));
    try std.testing.expectEqual(State.ready, conn.state);
}

test "ConnectionState.transitionTo: handshaking to disconnecting" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expect(conn.transitionTo(.disconnecting));
    try std.testing.expectEqual(State.disconnecting, conn.state);
}

test "ConnectionState.transitionTo: handshaking to operating is invalid" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expect(!conn.transitionTo(.operating));
    try std.testing.expectEqual(State.handshaking, conn.state);
}

test "ConnectionState.transitionTo: ready to operating" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    try std.testing.expect(conn.transitionTo(.operating));
    try std.testing.expectEqual(State.operating, conn.state);
}

test "ConnectionState.transitionTo: operating to ready (detach)" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    _ = conn.transitionTo(.operating);
    try std.testing.expect(conn.transitionTo(.ready));
    try std.testing.expectEqual(State.ready, conn.state);
}

test "ConnectionState.transitionTo: disconnecting is terminal" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.disconnecting);
    try std.testing.expect(!conn.transitionTo(.ready));
    try std.testing.expect(!conn.transitionTo(.handshaking));
    try std.testing.expectEqual(State.disconnecting, conn.state);
}

test "ConnectionState.advanceSendSequence: starts at 1 and increments" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expectEqual(@as(u32, 1), conn.advanceSendSequence());
    try std.testing.expectEqual(@as(u32, 2), conn.advanceSendSequence());
    try std.testing.expectEqual(@as(u32, 3), conn.advanceSendSequence());
}

test "ConnectionState.advanceSendSequence: wraps from max to 1" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    conn.send_sequence = 0xFFFFFFFF;
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), conn.advanceSendSequence());
    try std.testing.expectEqual(@as(u32, 1), conn.advanceSendSequence());
}

test "ConnectionState.isMessageAllowed: handshaking only allows ClientHello and Error" {
    const conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expect(conn.isMessageAllowed(.client_hello));
    try std.testing.expect(conn.isMessageAllowed(.@"error"));
    try std.testing.expect(conn.isMessageAllowed(.disconnect));
    try std.testing.expect(!conn.isMessageAllowed(.heartbeat));
    try std.testing.expect(!conn.isMessageAllowed(.key_event));
}

test "ConnectionState.isMessageAllowed: ready allows heartbeat and session attach" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    try std.testing.expect(conn.isMessageAllowed(.heartbeat));
    try std.testing.expect(conn.isMessageAllowed(.heartbeat_ack));
    try std.testing.expect(conn.isMessageAllowed(.attach_session_request));
    try std.testing.expect(conn.isMessageAllowed(.disconnect));
    try std.testing.expect(!conn.isMessageAllowed(.key_event));
}

test "ConnectionState.isMessageAllowed: operating allows all operational messages" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    _ = conn.transitionTo(.operating);
    try std.testing.expect(conn.isMessageAllowed(.key_event));
    try std.testing.expect(conn.isMessageAllowed(.frame_update));
    try std.testing.expect(conn.isMessageAllowed(.heartbeat));
    try std.testing.expect(conn.isMessageAllowed(.disconnect));
    try std.testing.expect(conn.isMessageAllowed(.preedit_start));
}

test "ConnectionState.isMessageAllowed: disconnecting only allows Disconnect and Error" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.disconnecting);
    try std.testing.expect(conn.isMessageAllowed(.disconnect));
    try std.testing.expect(conn.isMessageAllowed(.@"error"));
    try std.testing.expect(!conn.isMessageAllowed(.heartbeat));
    try std.testing.expect(!conn.isMessageAllowed(.key_event));
}

test "ConnectionState.addCapability: stores capabilities" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    conn.addCapability("clipboard_sync");
    conn.addCapability("mouse");
    try std.testing.expectEqual(@as(u8, 2), conn.negotiated_caps_count);
    try std.testing.expectEqualStrings("clipboard_sync", conn.negotiated_caps[0].getName());
    try std.testing.expectEqualStrings("mouse", conn.negotiated_caps[1].getName());
}

test "ConnectionState.addRenderCapability: stores render capabilities" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    conn.addRenderCapability("cell_data");
    try std.testing.expectEqual(@as(u8, 1), conn.negotiated_render_caps_count);
    try std.testing.expectEqualStrings("cell_data", conn.negotiated_render_caps[0].getName());
}
