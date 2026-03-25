const std = @import("std");
const interfaces = @import("interfaces.zig");

pub const real_socket_ops: interfaces.SocketOps = .{
    .bindAndListen = realBindAndListen,
    .accept = realAccept,
    .close = realClose,
    .probeExisting = realProbeExisting,
};

fn createAndBind(socket_path: []const u8) interfaces.SocketOps.SocketError!std.posix.fd_t {
    const fd = std.posix.socket(
        std.posix.AF.UNIX,
        std.posix.SOCK.STREAM,
        0,
    ) catch return error.BindFailed;
    errdefer std.posix.close(fd);

    var addr: std.posix.sockaddr.un = undefined;
    @memset(std.mem.asBytes(&addr), 0);
    addr.family = std.posix.AF.UNIX;

    if (socket_path.len >= addr.path.len) return error.BindFailed;
    @memcpy(addr.path[0..socket_path.len], socket_path);

    std.posix.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch return error.BindFailed;
    return fd;
}

fn realBindAndListen(socket_path: []const u8) interfaces.SocketOps.SocketError!std.posix.fd_t {
    const fd = createAndBind(socket_path) catch |err| blk: {
        if (err == error.BindFailed) {
            // Probe to check if stale
            const probe = realProbeExisting(socket_path);
            if (probe == .stale_socket) {
                std.posix.unlink(socket_path) catch {};
                break :blk try createAndBind(socket_path);
            }
        }
        return err;
    };

    errdefer std.posix.close(fd);
    std.posix.listen(fd, 5) catch return error.ListenFailed;

    // chmod 0600 via path — owner read/write only (best effort)
    var path_buf: [std.posix.PATH_MAX:0]u8 = undefined;
    if (socket_path.len < path_buf.len) {
        @memcpy(path_buf[0..socket_path.len], socket_path);
        path_buf[socket_path.len] = 0;
        _ = std.c.chmod(path_buf[0..socket_path.len :0], 0o600);
    }

    return fd;
}

fn realAccept(listen_fd: std.posix.fd_t) interfaces.SocketOps.SocketError!std.posix.fd_t {
    var addr: std.posix.sockaddr.un = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.un);
    const client_fd = std.posix.accept(listen_fd, @ptrCast(&addr), &addr_len, 0) catch {
        return error.AcceptFailed;
    };
    return client_fd;
}

fn realClose(fd: std.posix.fd_t) void {
    std.posix.close(fd);
}

fn realProbeExisting(socket_path: []const u8) interfaces.SocketOps.ProbeResult {
    const fd = std.posix.socket(
        std.posix.AF.UNIX,
        std.posix.SOCK.STREAM,
        0,
    ) catch return .no_socket;
    defer std.posix.close(fd);

    var addr: std.posix.sockaddr.un = undefined;
    @memset(std.mem.asBytes(&addr), 0);
    addr.family = std.posix.AF.UNIX;

    if (socket_path.len >= addr.path.len) return .no_socket;
    @memcpy(addr.path[0..socket_path.len], socket_path);

    std.posix.connect(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch |err| {
        return switch (err) {
            error.ConnectionRefused => .stale_socket,
            error.FileNotFound => .no_socket,
            else => .no_socket,
        };
    };

    return .daemon_running;
}

test "realProbeExisting: non-existent path returns no_socket" {
    const result = realProbeExisting("/tmp/itshell3-nonexistent-probe-test.sock");
    try std.testing.expectEqual(interfaces.SocketOps.ProbeResult.no_socket, result);
}

test "realBindAndListen: creates socket and returns valid fd" {
    var path_buf: [64]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/tmp/itshell3-test-bind-{d}.sock", .{std.c.getpid()});

    std.posix.unlink(path) catch {};
    defer std.posix.unlink(path) catch {};

    const fd = try realBindAndListen(path);
    defer std.posix.close(fd);

    try std.testing.expect(fd >= 0);
}

test "realBindAndListen: stale socket is cleaned up and rebound" {
    var path_buf: [64]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/tmp/itshell3-test-stale-{d}.sock", .{std.c.getpid()});

    std.posix.unlink(path) catch {};
    defer std.posix.unlink(path) catch {};

    // First bind
    const fd1 = try realBindAndListen(path);
    std.posix.close(fd1);
    // Socket file still exists but nobody is listening → stale

    // Second bind should succeed (stale cleanup)
    const fd2 = try realBindAndListen(path);
    defer std.posix.close(fd2);
    try std.testing.expect(fd2 >= 0);
}
