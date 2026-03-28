const std = @import("std");
const core = @import("itshell3_core");
const types = core.types;

/// Maximum number of raw OS events to collect per wait() call.
/// Used by PriorityEventBuffer per-tier capacity and OS backend raw buffers.
pub const MAX_EVENTS_PER_BATCH: usize = 64;

/// Event filter with explicit priority ordering as the backing integer.
/// Values: signal=0 (highest), timer=1, read=2, write=3 (lowest).
pub const Filter = enum(u2) {
    signal = 0,
    timer = 1,
    read = 2,
    write = 3,

    pub const count = @typeInfo(Filter).@"enum".fields.len;
};

/// Identifies the target of an event, replacing raw udata integer encoding.
/// Each OS backend encodes/decodes EventTarget into platform-specific udata.
pub const EventTarget = union(enum) {
    listener: void,
    pty: struct { session_idx: u16, pane_slot: types.PaneSlot },
    client: struct { client_idx: u16 },
    timer: struct { timer_id: u16 },
};

/// A priority-classified event from the OS event loop.
pub const Event = struct {
    fd: std.posix.fd_t,
    filter: Filter,
    target: ?EventTarget,
};

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
    /// Write to PTY master fd.
    write: *const fn (master_fd: std.posix.fd_t, data: []const u8) WriteError!usize,

    pub const ForkPtyResult = struct {
        master_fd: std.posix.fd_t,
        child_pid: std.posix.pid_t,
    };
    pub const ForkPtyError = error{ ForkFailed, PtyOpenFailed, ExecFailed };
    pub const ResizeError = error{IoctlFailed};
    pub const ReadError = std.posix.ReadError;
    pub const WriteError = error{WriteFailed};
};

/// Event loop operations interface (kqueue/epoll abstraction).
pub const EventLoopOps = struct {
    /// Register a file descriptor for read events.
    registerRead: *const fn (ctx: *anyopaque, fd: std.posix.fd_t, target: ?EventTarget) RegisterError!void,
    /// Register a file descriptor for write events.
    registerWrite: *const fn (ctx: *anyopaque, fd: std.posix.fd_t, target: ?EventTarget) RegisterError!void,
    /// Unregister a file descriptor.
    unregister: *const fn (ctx: *anyopaque, fd: std.posix.fd_t) void,
    /// Wait for events. Fills a PriorityEventBuffer and returns its iterator.
    wait: *const fn (ctx: *anyopaque, timeout_ms: ?u32) WaitError!PriorityEventBuffer.Iterator,

    pub const RegisterError = error{EventLoopError};
    pub const WaitError = error{EventLoopError};
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

// Forward import for PriorityEventBuffer used in wait() signature.
const PriorityEventBuffer = @import("priority_event_buffer.zig").PriorityEventBuffer;

// ── Tests ────────────────────────────────────────────────────────────────────

test "PtyOps: vtable can be constructed with function pointers" {
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
    const stub_write = struct {
        fn f(_: std.posix.fd_t, data: []const u8) PtyOps.WriteError!usize {
            return data.len;
        }
    }.f;

    const ops = PtyOps{
        .forkPty = stub_fork,
        .resize = stub_resize,
        .close = stub_close,
        .read = stub_read,
        .write = stub_write,
    };

    const result = try ops.forkPty(80, 24);
    try std.testing.expectEqual(@as(std.posix.fd_t, 3), result.master_fd);
    try std.testing.expectEqual(@as(std.posix.pid_t, 100), result.child_pid);
}

test "Event: struct has correct fields" {
    const event = Event{
        .fd = 5,
        .filter = .read,
        .target = .{ .client = .{ .client_idx = 42 } },
    };
    try std.testing.expectEqual(@as(std.posix.fd_t, 5), event.fd);
    try std.testing.expectEqual(Filter.read, event.filter);
}

test "Filter: priority ordering and count" {
    try std.testing.expectEqual(@as(u2, 0), @intFromEnum(Filter.signal));
    try std.testing.expectEqual(@as(u2, 1), @intFromEnum(Filter.timer));
    try std.testing.expectEqual(@as(u2, 2), @intFromEnum(Filter.read));
    try std.testing.expectEqual(@as(u2, 3), @intFromEnum(Filter.write));
    try std.testing.expectEqual(@as(usize, 4), Filter.count);
}

test "EventTarget: tagged union variants" {
    const listener_target = EventTarget{ .listener = {} };
    const pty_target = EventTarget{ .pty = .{ .session_idx = 3, .pane_slot = 7 } };
    const client_target = EventTarget{ .client = .{ .client_idx = 10 } };
    const timer_target = EventTarget{ .timer = .{ .timer_id = 5 } };

    switch (listener_target) {
        .listener => {},
        else => return error.TestUnexpectedResult,
    }
    switch (pty_target) {
        .pty => |p| {
            try std.testing.expectEqual(@as(u16, 3), p.session_idx);
            try std.testing.expectEqual(@as(types.PaneSlot, 7), p.pane_slot);
        },
        else => return error.TestUnexpectedResult,
    }
    switch (client_target) {
        .client => |c| try std.testing.expectEqual(@as(u16, 10), c.client_idx),
        else => return error.TestUnexpectedResult,
    }
    switch (timer_target) {
        .timer => |t| try std.testing.expectEqual(@as(u16, 5), t.timer_id),
        else => return error.TestUnexpectedResult,
    }
}

test "SignalOps.WaitResult: struct layout" {
    const result = SignalOps.WaitResult{ .pid = 1234, .exit_status = 0 };
    try std.testing.expectEqual(@as(std.posix.pid_t, 1234), result.pid);
    try std.testing.expectEqual(@as(u8, 0), result.exit_status);
}
