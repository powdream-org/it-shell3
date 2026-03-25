const std = @import("std");
const interfaces = @import("../os/interfaces.zig");

/// Thread-local mock state pointer. Safe because Zig tests are single-threaded.
threadlocal var global_mock_pty: ?*MockPtyOps = null;

/// Mock PTY operations for deterministic unit testing.
pub const MockPtyOps = struct {
    fork_result: ?interfaces.PtyOps.ForkPtyResult = null,
    fork_error: ?interfaces.PtyOps.ForkPtyError = null,
    read_data: ?[]const u8 = null,
    read_offset: usize = 0,
    resize_called: bool = false,
    resize_cols: u16 = 0,
    resize_rows: u16 = 0,
    close_called: bool = false,

    /// Install this mock and return a PtyOps vtable pointing to it.
    pub fn ops(self: *MockPtyOps) interfaces.PtyOps {
        global_mock_pty = self;
        return .{
            .forkPty = mockForkPty,
            .resize = mockResize,
            .close = mockClose,
            .read = mockRead,
        };
    }

    fn mockForkPty(_: u16, _: u16) interfaces.PtyOps.ForkPtyError!interfaces.PtyOps.ForkPtyResult {
        const self = global_mock_pty orelse unreachable;
        if (self.fork_error) |err| return err;
        return self.fork_result orelse error.PtyOpenFailed;
    }

    fn mockResize(_: std.posix.fd_t, cols: u16, rows: u16) interfaces.PtyOps.ResizeError!void {
        const self = global_mock_pty orelse unreachable;
        self.resize_called = true;
        self.resize_cols = cols;
        self.resize_rows = rows;
    }

    fn mockClose(_: std.posix.fd_t) void {
        const self = global_mock_pty orelse unreachable;
        self.close_called = true;
    }

    fn mockRead(_: std.posix.fd_t, buf: []u8) interfaces.PtyOps.ReadError!usize {
        const self = global_mock_pty orelse unreachable;
        const data = self.read_data orelse return 0;
        const remaining = data[self.read_offset..];
        if (remaining.len == 0) return 0;
        const n = @min(buf.len, remaining.len);
        @memcpy(buf[0..n], remaining[0..n]);
        self.read_offset += n;
        return n;
    }
};

test "mock PTY: fork returns configured result" {
    var mock = MockPtyOps{
        .fork_result = .{ .master_fd = 42, .child_pid = 1234 },
    };
    const pty_ops = mock.ops();

    const result = try pty_ops.forkPty(80, 24);
    try std.testing.expectEqual(@as(std.posix.fd_t, 42), result.master_fd);
    try std.testing.expectEqual(@as(std.posix.pid_t, 1234), result.child_pid);
}

test "mock PTY: fork returns configured error" {
    var mock = MockPtyOps{
        .fork_error = error.ForkFailed,
    };
    const pty_ops = mock.ops();

    const result = pty_ops.forkPty(80, 24);
    try std.testing.expectError(error.ForkFailed, result);
}

test "mock PTY: resize sets called flag and captures dimensions" {
    var mock = MockPtyOps{};
    const pty_ops = mock.ops();

    try pty_ops.resize(5, 120, 40);
    try std.testing.expect(mock.resize_called);
    try std.testing.expectEqual(@as(u16, 120), mock.resize_cols);
    try std.testing.expectEqual(@as(u16, 40), mock.resize_rows);
}

test "mock PTY: close sets called flag" {
    var mock = MockPtyOps{};
    const pty_ops = mock.ops();

    pty_ops.close(5);
    try std.testing.expect(mock.close_called);
}

test "mock PTY: read returns configured data" {
    const test_data = "hello from PTY";
    var mock = MockPtyOps{
        .read_data = test_data,
    };
    const pty_ops = mock.ops();

    var buf: [64]u8 = undefined;
    const n = try pty_ops.read(5, &buf);
    try std.testing.expectEqual(test_data.len, n);
    try std.testing.expectEqualStrings(test_data, buf[0..n]);

    // Second read returns 0 (no more data)
    const n2 = try pty_ops.read(5, &buf);
    try std.testing.expectEqual(@as(usize, 0), n2);
}

test "mock PTY: read returns 0 when no data configured" {
    var mock = MockPtyOps{};
    const pty_ops = mock.ops();

    var buf: [64]u8 = undefined;
    const n = try pty_ops.read(5, &buf);
    try std.testing.expectEqual(@as(usize, 0), n);
}

/// Thread-local mock state pointer for socket ops.
threadlocal var global_mock_socket: ?*MockSocketOps = null;

/// Mock socket operations for deterministic unit testing.
pub const MockSocketOps = struct {
    probe_result: interfaces.SocketOps.ProbeResult = .no_socket,
    bind_fd: ?std.posix.fd_t = null,
    bind_error: ?interfaces.SocketOps.SocketError = null,
    accept_fd: ?std.posix.fd_t = null,
    accept_error: ?interfaces.SocketOps.SocketError = null,
    bind_called: bool = false,
    accept_called: bool = false,
    close_called: bool = false,
    close_fd: std.posix.fd_t = -1,

    /// Install this mock and return a SocketOps vtable pointing to it.
    pub fn ops(self: *MockSocketOps) interfaces.SocketOps {
        global_mock_socket = self;
        return .{
            .bindAndListen = mockBindAndListen,
            .accept = mockAccept,
            .close = mockClose,
            .probeExisting = mockProbeExisting,
        };
    }

    fn mockBindAndListen(_: []const u8) interfaces.SocketOps.SocketError!std.posix.fd_t {
        const self = global_mock_socket orelse unreachable;
        self.bind_called = true;
        if (self.bind_error) |err| return err;
        return self.bind_fd orelse error.BindFailed;
    }

    fn mockAccept(_: std.posix.fd_t) interfaces.SocketOps.SocketError!std.posix.fd_t {
        const self = global_mock_socket orelse unreachable;
        self.accept_called = true;
        if (self.accept_error) |err| return err;
        return self.accept_fd orelse error.AcceptFailed;
    }

    fn mockClose(fd: std.posix.fd_t) void {
        const self = global_mock_socket orelse unreachable;
        self.close_called = true;
        self.close_fd = fd;
    }

    fn mockProbeExisting(_: []const u8) interfaces.SocketOps.ProbeResult {
        const self = global_mock_socket orelse unreachable;
        return self.probe_result;
    }
};

test "mock socket: bindAndListen returns configured fd" {
    var mock = MockSocketOps{ .bind_fd = 42 };
    const socket_ops = mock.ops();

    const fd = try socket_ops.bindAndListen("/tmp/test.sock");
    try std.testing.expectEqual(@as(std.posix.fd_t, 42), fd);
    try std.testing.expect(mock.bind_called);
}

test "mock socket: bindAndListen returns configured error" {
    var mock = MockSocketOps{ .bind_error = error.BindFailed };
    const socket_ops = mock.ops();

    const result = socket_ops.bindAndListen("/tmp/test.sock");
    try std.testing.expectError(error.BindFailed, result);
}

test "mock socket: accept returns configured fd" {
    var mock = MockSocketOps{ .accept_fd = 55 };
    const socket_ops = mock.ops();

    const fd = try socket_ops.accept(10);
    try std.testing.expectEqual(@as(std.posix.fd_t, 55), fd);
    try std.testing.expect(mock.accept_called);
}

test "mock socket: accept returns configured error" {
    var mock = MockSocketOps{ .accept_error = error.AcceptFailed };
    const socket_ops = mock.ops();

    const result = socket_ops.accept(10);
    try std.testing.expectError(error.AcceptFailed, result);
}

test "mock socket: close sets called flag and captures fd" {
    var mock = MockSocketOps{};
    const socket_ops = mock.ops();

    socket_ops.close(7);
    try std.testing.expect(mock.close_called);
    try std.testing.expectEqual(@as(std.posix.fd_t, 7), mock.close_fd);
}

test "mock socket: probeExisting returns configured result" {
    const cases = [_]interfaces.SocketOps.ProbeResult{ .no_socket, .stale_socket, .daemon_running };
    for (cases) |expected| {
        var mock = MockSocketOps{ .probe_result = expected };
        const socket_ops = mock.ops();
        try std.testing.expectEqual(expected, socket_ops.probeExisting("/tmp/test.sock"));
    }
}
