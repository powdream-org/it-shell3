const std = @import("std");
const interfaces = @import("itshell3_os").interfaces;

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
    write_buf: [1024]u8 = @splat(0),
    write_length: usize = 0,

    /// Install this mock and return a PtyOps vtable pointing to it.
    pub fn ops(self: *MockPtyOps) interfaces.PtyOps {
        global_mock_pty = self;
        return .{
            .forkPty = mockForkPty,
            .resize = mockResize,
            .close = mockClose,
            .read = mockRead,
            .write = mockWrite,
        };
    }

    /// Return the bytes written so far.
    pub fn written(self: *const MockPtyOps) []const u8 {
        return self.write_buf[0..self.write_length];
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

    fn mockWrite(_: std.posix.fd_t, data: []const u8) interfaces.PtyOps.WriteError!usize {
        const self = global_mock_pty orelse unreachable;
        const available = self.write_buf.len - self.write_length;
        const to_copy = @min(data.len, available);
        @memcpy(self.write_buf[self.write_length..][0..to_copy], data[0..to_copy]);
        self.write_length += to_copy;
        return data.len;
    }
};

test "MockPtyOps: fork returns configured result" {
    var mock = MockPtyOps{
        .fork_result = .{ .master_fd = 42, .child_pid = 1234 },
    };
    const pty_ops = mock.ops();

    const result = try pty_ops.forkPty(80, 24);
    try std.testing.expectEqual(@as(std.posix.fd_t, 42), result.master_fd);
    try std.testing.expectEqual(@as(std.posix.pid_t, 1234), result.child_pid);
}

test "MockPtyOps: fork returns configured error" {
    var mock = MockPtyOps{
        .fork_error = error.ForkFailed,
    };
    const pty_ops = mock.ops();

    const result = pty_ops.forkPty(80, 24);
    try std.testing.expectError(error.ForkFailed, result);
}

test "MockPtyOps: resize sets called flag and captures dimensions" {
    var mock = MockPtyOps{};
    const pty_ops = mock.ops();

    try pty_ops.resize(5, 120, 40);
    try std.testing.expect(mock.resize_called);
    try std.testing.expectEqual(@as(u16, 120), mock.resize_cols);
    try std.testing.expectEqual(@as(u16, 40), mock.resize_rows);
}

test "MockPtyOps: close sets called flag" {
    var mock = MockPtyOps{};
    const pty_ops = mock.ops();

    pty_ops.close(5);
    try std.testing.expect(mock.close_called);
}

test "MockPtyOps: read returns configured data" {
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

test "MockPtyOps: write records data" {
    var mock = MockPtyOps{};
    const pty_ops = mock.ops();

    const n1 = try pty_ops.write(5, "hello");
    try std.testing.expectEqual(@as(usize, 5), n1);
    const n2 = try pty_ops.write(5, " world");
    try std.testing.expectEqual(@as(usize, 6), n2);
    try std.testing.expectEqualSlices(u8, "hello world", mock.written());
}

test "MockPtyOps: read returns 0 when no data configured" {
    var mock = MockPtyOps{};
    const pty_ops = mock.ops();

    var buf: [64]u8 = undefined;
    const n = try pty_ops.read(5, &buf);
    try std.testing.expectEqual(@as(usize, 0), n);
}

// ── MockSignalOps ─────────────────────────────────────────────────────────────

threadlocal var global_mock_signal: ?*MockSignalOps = null;

/// Mock signal operations for deterministic unit testing.
pub const MockSignalOps = struct {
    block_error: ?interfaces.SignalOps.SignalError = null,
    register_error: ?interfaces.SignalOps.SignalError = null,
    /// Slice of WaitResults to return from waitChild(), in order.
    /// After the slice is exhausted, waitChild() returns null.
    wait_results: []const interfaces.SignalOps.WaitResult = &.{},
    wait_index: usize = 0,
    block_called: bool = false,
    register_called: bool = false,

    pub fn ops(self: *MockSignalOps) interfaces.SignalOps {
        global_mock_signal = self;
        return .{
            .blockSignals = mockBlockSignals,
            .registerSignals = mockRegisterSignals,
            .waitChild = mockWaitChild,
        };
    }

    fn mockBlockSignals() interfaces.SignalOps.SignalError!void {
        const self = global_mock_signal orelse unreachable;
        self.block_called = true;
        if (self.block_error) |err| return err;
    }

    fn mockRegisterSignals(_: *anyopaque, _: *const interfaces.EventLoopOps) interfaces.SignalOps.SignalError!void {
        const self = global_mock_signal orelse unreachable;
        self.register_called = true;
        if (self.register_error) |err| return err;
    }

    fn mockWaitChild() ?interfaces.SignalOps.WaitResult {
        const self = global_mock_signal orelse unreachable;
        if (self.wait_index >= self.wait_results.len) return null;
        const result = self.wait_results[self.wait_index];
        self.wait_index += 1;
        return result;
    }
};

test "MockSignalOps: blockSignals sets called flag" {
    var mock = MockSignalOps{};
    const signal_ops = mock.ops();
    try signal_ops.blockSignals();
    try std.testing.expect(mock.block_called);
}

test "MockSignalOps: blockSignals returns configured error" {
    var mock = MockSignalOps{ .block_error = error.SignalSetupFailed };
    const signal_ops = mock.ops();
    const result = signal_ops.blockSignals();
    try std.testing.expectError(error.SignalSetupFailed, result);
}

test "MockSignalOps: waitChild returns results in order then null" {
    const results = [_]interfaces.SignalOps.WaitResult{
        .{ .pid = 100, .exit_status = 0 },
        .{ .pid = 200, .exit_status = 1 },
    };
    var mock = MockSignalOps{ .wait_results = &results };
    const signal_ops = mock.ops();

    const r1 = signal_ops.waitChild();
    try std.testing.expect(r1 != null);
    try std.testing.expectEqual(@as(std.posix.pid_t, 100), r1.?.pid);

    const r2 = signal_ops.waitChild();
    try std.testing.expect(r2 != null);
    try std.testing.expectEqual(@as(std.posix.pid_t, 200), r2.?.pid);

    const r3 = signal_ops.waitChild();
    try std.testing.expect(r3 == null);
}

test "MockSignalOps: waitChild returns null when no results" {
    var mock = MockSignalOps{};
    const signal_ops = mock.ops();
    try std.testing.expect(signal_ops.waitChild() == null);
}

// ── MockEventLoopOps ──────────────────────────────────────────────────────────

threadlocal var global_mock_event_loop: ?*MockEventLoopOps = null;

pub const MockRegistration = struct {
    fd: std.posix.fd_t,
    filter: enum { read, write },
    udata: usize,
};

/// Mock event loop operations for deterministic unit testing.
pub const MockEventLoopOps = struct {
    /// Configurable events to return from wait().
    events_to_return: []const interfaces.EventLoopOps.Event = &.{},
    events_index: usize = 0,
    wait_error: ?interfaces.EventLoopOps.WaitError = null,
    register_error: ?interfaces.EventLoopOps.RegisterError = null,

    /// Tracks registered file descriptors.
    registered: [64]?MockRegistration = [_]?MockRegistration{null} ** 64,
    registered_count: usize = 0,
    unregister_count: usize = 0,

    pub fn ops(self: *MockEventLoopOps) interfaces.EventLoopOps {
        global_mock_event_loop = self;
        return .{
            .registerRead = mockRegisterRead,
            .registerWrite = mockRegisterWrite,
            .unregister = mockUnregister,
            .wait = mockWait,
        };
    }

    fn mockRegisterRead(ctx: *anyopaque, fd: std.posix.fd_t, udata: usize) interfaces.EventLoopOps.RegisterError!void {
        _ = ctx;
        const self = global_mock_event_loop orelse unreachable;
        if (self.register_error) |err| return err;
        if (self.registered_count < self.registered.len) {
            self.registered[self.registered_count] = .{ .fd = fd, .filter = .read, .udata = udata };
            self.registered_count += 1;
        }
    }

    fn mockRegisterWrite(ctx: *anyopaque, fd: std.posix.fd_t, udata: usize) interfaces.EventLoopOps.RegisterError!void {
        _ = ctx;
        const self = global_mock_event_loop orelse unreachable;
        if (self.register_error) |err| return err;
        if (self.registered_count < self.registered.len) {
            self.registered[self.registered_count] = .{ .fd = fd, .filter = .write, .udata = udata };
            self.registered_count += 1;
        }
    }

    fn mockUnregister(ctx: *anyopaque, _: std.posix.fd_t) void {
        _ = ctx;
        const self = global_mock_event_loop orelse unreachable;
        self.unregister_count += 1;
    }

    fn mockWait(ctx: *anyopaque, events: []interfaces.EventLoopOps.Event, _: ?u32) interfaces.EventLoopOps.WaitError!usize {
        _ = ctx;
        const self = global_mock_event_loop orelse unreachable;
        if (self.wait_error) |err| return err;
        if (self.events_index >= self.events_to_return.len) return 0;
        const n = @min(events.len, self.events_to_return.len - self.events_index);
        for (0..n) |i| {
            events[i] = self.events_to_return[self.events_index + i];
        }
        self.events_index += n;
        return n;
    }
};

test "MockEventLoopOps: registerRead tracks fd" {
    var mock = MockEventLoopOps{};
    const event_ops = mock.ops();

    var dummy: u8 = 0;
    const ctx: *anyopaque = &dummy;

    try event_ops.registerRead(ctx, 5, 42);
    try std.testing.expectEqual(@as(usize, 1), mock.registered_count);
    try std.testing.expectEqual(@as(std.posix.fd_t, 5), mock.registered[0].?.fd);
    try std.testing.expectEqual(@as(usize, 42), mock.registered[0].?.udata);
}

test "MockEventLoopOps: registerWrite tracks fd" {
    var mock = MockEventLoopOps{};
    const event_ops = mock.ops();

    var dummy: u8 = 0;
    const ctx: *anyopaque = &dummy;

    try event_ops.registerWrite(ctx, 7, 99);
    try std.testing.expectEqual(@as(usize, 1), mock.registered_count);
    try std.testing.expectEqual(MockRegistration{ .fd = 7, .filter = .write, .udata = 99 }, mock.registered[0].?);
}

test "MockEventLoopOps: unregister increments counter" {
    var mock = MockEventLoopOps{};
    const event_ops = mock.ops();

    var dummy: u8 = 0;
    const ctx: *anyopaque = &dummy;

    event_ops.unregister(ctx, 5);
    event_ops.unregister(ctx, 6);
    try std.testing.expectEqual(@as(usize, 2), mock.unregister_count);
}

test "MockEventLoopOps: wait returns configured events" {
    const evts = [_]interfaces.EventLoopOps.Event{
        .{ .fd = 3, .filter = .read, .udata = 10 },
        .{ .fd = 4, .filter = .write, .udata = 20 },
    };
    var mock = MockEventLoopOps{ .events_to_return = &evts };
    const event_ops = mock.ops();

    var dummy: u8 = 0;
    const ctx: *anyopaque = &dummy;

    var out: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try event_ops.wait(ctx, &out, null);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(std.posix.fd_t, 3), out[0].fd);
    try std.testing.expectEqual(@as(std.posix.fd_t, 4), out[1].fd);
}

test "MockEventLoopOps: wait returns 0 when no events" {
    var mock = MockEventLoopOps{};
    const event_ops = mock.ops();

    var dummy: u8 = 0;
    const ctx: *anyopaque = &dummy;

    var out: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try event_ops.wait(ctx, &out, null);
    try std.testing.expectEqual(@as(usize, 0), n);
}
