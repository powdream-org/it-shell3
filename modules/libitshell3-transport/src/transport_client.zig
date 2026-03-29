//! Client-side Unix socket connection to the it-shell3 daemon.

const std = @import("std");
const transport = @import("transport.zig");
const helper = @import("transport_helper.zig");

const socket_t = helper.socket_t;
const MAX_SOCKET_PATH = helper.MAX_SOCKET_PATH;
const newFd = helper.newFd;
const makeAddr = helper.makeAddr;

/// Errors from attempting to connect to the daemon socket.
pub const ConnectError = error{
    PathTooLong,
    SocketCreate,
    ConnectionRefused,
    NotFound,
    Unexpected,
};

/// Connects to a daemon's Unix socket at `socket_path`.
pub fn connect(socket_path: []const u8) ConnectError!transport.SocketConnection {
    if (socket_path.len >= MAX_SOCKET_PATH) return error.PathTooLong;

    const fd = newFd() catch return error.SocketCreate;
    errdefer std.posix.close(fd);

    const addr = makeAddr(socket_path);
    std.posix.connect(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch |err| switch (err) {
        error.ConnectionRefused => return error.ConnectionRefused,
        error.FileNotFound => return error.NotFound,
        else => return error.Unexpected,
    };

    return .{ .fd = fd };
}

// ── Tests ────────────────────────────────────────────────────────────────

const builtin = @import("builtin");
const testing = std.testing;
const server = @import("transport_server.zig");

test "connect: succeeds when a listener is active" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("connect tests require BSD or Linux");

    const helpers = @import("testing/helpers.zig");
    const socket_path = helpers.generateTestSocketPath();

    var listener = try server.listen(socket_path);
    defer listener.deinit();

    const conn = try connect(socket_path);
    std.posix.close(conn.fd);
}

test "connect: returns NotFound when no socket file exists" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("connect tests require BSD or Linux");

    const result = connect("/tmp/itshell3-test-nonexistent-path.sock");
    try testing.expectError(error.NotFound, result);
}

test "connect: returns ConnectionRefused for stale socket" {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("connect tests require BSD or Linux");

    const helpers = @import("testing/helpers.zig");
    const socket_path = helpers.generateTestSocketPath();

    // Create a socket file by binding then closing — leaves a stale file.
    const tmp_fd = newFd() catch return;
    const addr = makeAddr(socket_path);
    std.posix.bind(tmp_fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch return;
    std.posix.close(tmp_fd);
    defer std.posix.unlink(socket_path) catch {};

    const result = connect(socket_path);
    try testing.expectError(error.ConnectionRefused, result);
}

test "connect: returns PathTooLong for excessive path" {
    const long_path = "x" ** (MAX_SOCKET_PATH + 1);
    const result = connect(long_path);
    try testing.expectError(error.PathTooLong, result);
}
