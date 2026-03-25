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
