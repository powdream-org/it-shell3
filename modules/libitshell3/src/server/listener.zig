const std = @import("std");
const interfaces = @import("../os/interfaces.zig");

pub const Listener = struct {
    listen_fd: std.posix.fd_t,
    socket_path: []const u8,
    socket_ops: *const interfaces.SocketOps,

    pub const InitError = error{ DaemonAlreadyRunning, BindFailed, ListenFailed, AcceptFailed, PermissionDenied };

    pub fn init(socket_path: []const u8, socket_ops: *const interfaces.SocketOps) InitError!Listener {
        const probe = socket_ops.probeExisting(socket_path);
        switch (probe) {
            .daemon_running => return error.DaemonAlreadyRunning,
            .stale_socket => {
                std.posix.unlink(socket_path) catch {};
            },
            .no_socket => {},
        }

        const listen_fd = socket_ops.bindAndListen(socket_path) catch |err| return err;
        return .{
            .listen_fd = listen_fd,
            .socket_path = socket_path,
            .socket_ops = socket_ops,
        };
    }

    pub fn accept(self: *Listener) interfaces.SocketOps.SocketError!std.posix.fd_t {
        return self.socket_ops.accept(self.listen_fd);
    }

    pub fn deinit(self: *Listener) void {
        self.socket_ops.close(self.listen_fd);
        std.posix.unlink(self.socket_path) catch {};
    }
};

// --- Tests ---

const testing = std.testing;
const mock_os = @import("../testing/mock_os.zig");

test "Listener.init: no_socket probe → succeeds" {
    var mock = mock_os.MockSocketOps{
        .probe_result = .no_socket,
        .bind_fd = 10,
    };
    const socket_ops = mock.ops();

    var listener = try Listener.init("/tmp/test.sock", &socket_ops);
    defer {
        mock.close_called = false; // reset before deinit to track
        listener.socket_ops.close(listener.listen_fd);
    }

    try testing.expectEqual(@as(std.posix.fd_t, 10), listener.listen_fd);
}

test "Listener.init: stale_socket probe → succeeds (unlink + bind)" {
    var mock = mock_os.MockSocketOps{
        .probe_result = .stale_socket,
        .bind_fd = 11,
    };
    const socket_ops = mock.ops();

    var listener = try Listener.init("/tmp/test-stale.sock", &socket_ops);
    defer listener.socket_ops.close(listener.listen_fd);

    try testing.expectEqual(@as(std.posix.fd_t, 11), listener.listen_fd);
    try testing.expect(mock.bind_called);
}

test "Listener.init: daemon_running probe → error.DaemonAlreadyRunning" {
    var mock = mock_os.MockSocketOps{
        .probe_result = .daemon_running,
    };
    const socket_ops = mock.ops();

    const result = Listener.init("/tmp/test-running.sock", &socket_ops);
    try testing.expectError(error.DaemonAlreadyRunning, result);
}

test "Listener.accept: delegates to socket_ops.accept" {
    var mock = mock_os.MockSocketOps{
        .probe_result = .no_socket,
        .bind_fd = 20,
        .accept_fd = 21,
    };
    const socket_ops = mock.ops();

    var listener = try Listener.init("/tmp/test-accept.sock", &socket_ops);
    defer listener.socket_ops.close(listener.listen_fd);

    const client_fd = try listener.accept();
    try testing.expectEqual(@as(std.posix.fd_t, 21), client_fd);
    try testing.expect(mock.accept_called);
}

test "Listener.deinit: calls close" {
    var mock = mock_os.MockSocketOps{
        .probe_result = .no_socket,
        .bind_fd = 30,
    };
    const socket_ops = mock.ops();

    var listener = try Listener.init("/tmp/test-deinit.sock", &socket_ops);
    listener.deinit();
    try testing.expect(mock.close_called);
}
