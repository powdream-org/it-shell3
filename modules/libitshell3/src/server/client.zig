const std = @import("std");
const types = @import("../core/types.zig");

pub const ClientState = struct {
    client_id: types.ClientId,
    conn_fd: std.posix.fd_t,
    state: State,
    attached_session: ?types.SessionId,

    pub const State = enum {
        handshaking,
        ready,
        operating,
        disconnecting,
    };

    pub fn init(client_id: types.ClientId, conn_fd: std.posix.fd_t) ClientState {
        return .{
            .client_id = client_id,
            .conn_fd = conn_fd,
            .state = .handshaking,
            .attached_session = null,
        };
    }

    pub fn completeHandshake(self: *ClientState) error{InvalidTransition}!void {
        if (self.state != .handshaking) return error.InvalidTransition;
        self.state = .ready;
    }

    pub fn attach(self: *ClientState, session_id: types.SessionId) error{InvalidTransition}!void {
        switch (self.state) {
            .ready, .operating => {
                self.state = .operating;
                self.attached_session = session_id;
            },
            else => return error.InvalidTransition,
        }
    }

    pub fn detach(self: *ClientState) error{InvalidTransition}!void {
        if (self.state != .operating) return error.InvalidTransition;
        self.state = .ready;
        self.attached_session = null;
    }

    pub fn destroyOwnSession(self: *ClientState) error{InvalidTransition}!void {
        if (self.state != .operating) return error.InvalidTransition;
        self.state = .ready;
        self.attached_session = null;
    }

    pub fn beginDisconnect(self: *ClientState) error{InvalidTransition}!void {
        switch (self.state) {
            .operating, .ready => self.state = .disconnecting,
            else => return error.InvalidTransition,
        }
    }

    pub fn isAttached(self: *const ClientState) bool {
        return self.state == .operating and self.attached_session != null;
    }
};

test "init: state=handshaking, attached_session=null" {
    const cs = ClientState.init(1, 3);
    try std.testing.expectEqual(ClientState.State.handshaking, cs.state);
    try std.testing.expectEqual(@as(?types.SessionId, null), cs.attached_session);
    try std.testing.expectEqual(@as(types.ClientId, 1), cs.client_id);
    try std.testing.expectEqual(@as(std.posix.fd_t, 3), cs.conn_fd);
}

test "completeHandshake: handshaking → ready" {
    var cs = ClientState.init(1, 3);
    try cs.completeHandshake();
    try std.testing.expectEqual(ClientState.State.ready, cs.state);
}

test "completeHandshake from ready → error.InvalidTransition" {
    var cs = ClientState.init(1, 3);
    try cs.completeHandshake();
    try std.testing.expectError(error.InvalidTransition, cs.completeHandshake());
}

test "attach from ready: → operating, session set" {
    var cs = ClientState.init(1, 3);
    try cs.completeHandshake();
    try cs.attach(42);
    try std.testing.expectEqual(ClientState.State.operating, cs.state);
    try std.testing.expectEqual(@as(?types.SessionId, 42), cs.attached_session);
}

test "attach from operating (reattach): stays operating, session changes" {
    var cs = ClientState.init(1, 3);
    try cs.completeHandshake();
    try cs.attach(42);
    try cs.attach(99);
    try std.testing.expectEqual(ClientState.State.operating, cs.state);
    try std.testing.expectEqual(@as(?types.SessionId, 99), cs.attached_session);
}

test "attach from handshaking → error.InvalidTransition" {
    var cs = ClientState.init(1, 3);
    try std.testing.expectError(error.InvalidTransition, cs.attach(42));
}

test "detach from operating: → ready, session cleared" {
    var cs = ClientState.init(1, 3);
    try cs.completeHandshake();
    try cs.attach(42);
    try cs.detach();
    try std.testing.expectEqual(ClientState.State.ready, cs.state);
    try std.testing.expectEqual(@as(?types.SessionId, null), cs.attached_session);
}

test "detach from ready → error.InvalidTransition" {
    var cs = ClientState.init(1, 3);
    try cs.completeHandshake();
    try std.testing.expectError(error.InvalidTransition, cs.detach());
}

test "destroyOwnSession from operating: → ready, session cleared" {
    var cs = ClientState.init(1, 3);
    try cs.completeHandshake();
    try cs.attach(42);
    try cs.destroyOwnSession();
    try std.testing.expectEqual(ClientState.State.ready, cs.state);
    try std.testing.expectEqual(@as(?types.SessionId, null), cs.attached_session);
}

test "beginDisconnect from operating: → disconnecting" {
    var cs = ClientState.init(1, 3);
    try cs.completeHandshake();
    try cs.attach(42);
    try cs.beginDisconnect();
    try std.testing.expectEqual(ClientState.State.disconnecting, cs.state);
}

test "beginDisconnect from ready: → disconnecting" {
    var cs = ClientState.init(1, 3);
    try cs.completeHandshake();
    try cs.beginDisconnect();
    try std.testing.expectEqual(ClientState.State.disconnecting, cs.state);
}

test "beginDisconnect from handshaking → error.InvalidTransition" {
    var cs = ClientState.init(1, 3);
    try std.testing.expectError(error.InvalidTransition, cs.beginDisconnect());
}

test "isAttached: true only when operating + session set" {
    var cs = ClientState.init(1, 3);
    try std.testing.expect(!cs.isAttached());
    try cs.completeHandshake();
    try std.testing.expect(!cs.isAttached());
    try cs.attach(42);
    try std.testing.expect(cs.isAttached());
    try cs.detach();
    try std.testing.expect(!cs.isAttached());
}
