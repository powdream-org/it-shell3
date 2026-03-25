const std = @import("std");

/// PTY operations interface — vtable for testability.
/// Real implementation in pty.zig; mock in testing/mock_os.zig.
pub const PtyOps = struct {
    /// Fork a child process with a PTY. Returns master fd and child pid.
    forkPty: *const fn (cols: u16, rows: u16) ForkPtyError!ForkPtyResult,
    /// Resize the PTY terminal.
    resize: *const fn (master_fd: std.posix.fd_t, cols: u16, rows: u16) ResizeError!void,
    /// Close the PTY master fd.
    close: *const fn (master_fd: std.posix.fd_t) void,
    /// Read from PTY master fd.
    read: *const fn (master_fd: std.posix.fd_t, buf: []u8) ReadError!usize,

    pub const ForkPtyResult = struct {
        master_fd: std.posix.fd_t,
        child_pid: std.posix.pid_t,
    };
    pub const ForkPtyError = error{ ForkFailed, PtyOpenFailed, ExecFailed };
    pub const ResizeError = error{IoctlFailed};
    pub const ReadError = std.posix.ReadError;
};

/// Event loop operations interface (kqueue/epoll abstraction).
pub const EventLoopOps = struct {
    /// Register a file descriptor for read events.
    registerRead: *const fn (ctx: *anyopaque, fd: std.posix.fd_t, udata: usize) RegisterError!void,
    /// Register a file descriptor for write events.
    registerWrite: *const fn (ctx: *anyopaque, fd: std.posix.fd_t, udata: usize) RegisterError!void,
    /// Unregister a file descriptor.
    unregister: *const fn (ctx: *anyopaque, fd: std.posix.fd_t) void,
    /// Wait for events. Returns number of events ready.
    wait: *const fn (ctx: *anyopaque, events: []Event, timeout_ms: ?u32) WaitError!usize,

    pub const RegisterError = error{KqueueError};
    pub const WaitError = error{KqueueError};

    pub const Event = struct {
        fd: std.posix.fd_t,
        filter: Filter,
        udata: usize,
        flags: u16 = 0,
        data: i64 = 0,
    };
    pub const Filter = enum { read, write, signal, timer };
};

/// Signal operations interface.
pub const SignalOps = struct {
    /// Block signals from default handling (for kqueue delivery).
    blockSignals: *const fn () SignalError!void,
    /// Register signal filters with the event loop.
    registerSignals: *const fn (ctx: *anyopaque, event_ops: *const EventLoopOps) SignalError!void,
    /// Wait for a child process (WNOHANG). Returns null if no child ready.
    waitChild: *const fn () ?WaitResult,

    pub const WaitResult = struct { pid: std.posix.pid_t, exit_status: u8 };
    pub const SignalError = error{SignalSetupFailed};
};

test "PtyOps vtable can be constructed with function pointers" {
    const stub_fork = struct {
        fn f(_: u16, _: u16) PtyOps.ForkPtyError!PtyOps.ForkPtyResult {
            return .{ .master_fd = 3, .child_pid = 100 };
        }
    }.f;
    const stub_resize = struct {
        fn f(_: std.posix.fd_t, _: u16, _: u16) PtyOps.ResizeError!void {}
    }.f;
    const stub_close = struct {
        fn f(_: std.posix.fd_t) void {}
    }.f;
    const stub_read = struct {
        fn f(_: std.posix.fd_t, _: []u8) PtyOps.ReadError!usize {
            return 0;
        }
    }.f;

    const ops = PtyOps{
        .forkPty = stub_fork,
        .resize = stub_resize,
        .close = stub_close,
        .read = stub_read,
    };

    const result = try ops.forkPty(80, 24);
    try std.testing.expectEqual(@as(std.posix.fd_t, 3), result.master_fd);
    try std.testing.expectEqual(@as(std.posix.pid_t, 100), result.child_pid);
}

test "EventLoopOps Event struct has correct defaults" {
    const event = EventLoopOps.Event{
        .fd = 5,
        .filter = .read,
        .udata = 42,
    };
    try std.testing.expectEqual(@as(u16, 0), event.flags);
    try std.testing.expectEqual(@as(i64, 0), event.data);
}

test "SignalOps WaitResult struct layout" {
    const result = SignalOps.WaitResult{ .pid = 1234, .exit_status = 0 };
    try std.testing.expectEqual(@as(std.posix.pid_t, 1234), result.pid);
    try std.testing.expectEqual(@as(u8, 0), result.exit_status);
}
