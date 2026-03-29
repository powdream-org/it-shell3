//! kqueue-based event loop backend for macOS/BSD. Implements the EventLoopOps
//! vtable using kevent for fd monitoring, timers, and signal delivery.

const std = @import("std");
const builtin = @import("builtin");
const interfaces = @import("interfaces.zig");
const PriorityEventBuffer = @import("priority_event_buffer.zig").PriorityEventBuffer;

// ── macOS / BSD: kqueue ────────────────────────────────────────────────────

pub const KqueueContext = struct {
    kq_fd: std.posix.fd_t,
    event_buffer: PriorityEventBuffer = .{},

    pub fn init() error{EventLoopError}!KqueueContext {
        if (comptime !builtin.os.tag.isBSD()) @compileError("KqueueContext is macOS/BSD only");
        const kq = std.posix.kqueue() catch return error.EventLoopError;
        return KqueueContext{ .kq_fd = kq };
    }

    pub fn deinit(self: *KqueueContext) void {
        std.posix.close(self.kq_fd);
    }

    /// Returns an EventLoopOps vtable. The caller must pass `self` as `ctx`
    /// when invoking any vtable function.
    pub fn eventLoopOps(_: *KqueueContext) interfaces.EventLoopOps {
        return .{
            .registerRead = kqRegisterRead,
            .registerWrite = kqRegisterWrite,
            .unregister = kqUnregister,
            .registerTimer = kqRegisterTimer,
            .cancelTimer = kqCancelTimer,
            .wait = kqWait,
        };
    }
};

fn toKqCtx(ctx: *anyopaque) *KqueueContext {
    return @ptrCast(@alignCast(ctx));
}

const core = @import("itshell3_core");
const types = core.types;

/// Number of pane slots per session, derived from the PaneSlot type.
const PANE_SLOT_RANGE: usize = std.math.maxInt(types.PaneSlot) + 1;

/// Sentinel value for null target in udata encoding.
const NULL_TARGET_SENTINEL: usize = 0x0200_0000;
/// Base offset for client targets in udata encoding.
const CLIENT_BASE: usize = 0x0400_0000;
/// Base offset for timer targets in udata encoding.
const TIMER_BASE: usize = 0x0600_0000;

// Compile-time check: PTY range must not overlap client range.
// Max PTY udata = 1 + (maxInt(u16) * PANE_SLOT_RANGE) + maxInt(PaneSlot).
comptime {
    const max_pty_udata = 1 + @as(usize, std.math.maxInt(u16)) * PANE_SLOT_RANGE + std.math.maxInt(types.PaneSlot);
    if (max_pty_udata >= NULL_TARGET_SENTINEL) @compileError("PTY udata range overlaps null target sentinel");
}

/// Encode an optional EventTarget into a usize for kevent udata field.
/// Encoding scheme (internal to kqueue backend):
///   null: NULL_TARGET_SENTINEL
///   listener: 0
///   pty: 1 + session_idx * PANE_SLOT_RANGE + pane_slot
///   client: CLIENT_BASE + client_idx
///   timer: TIMER_BASE + timer_id
fn encodeTarget(target: ?interfaces.EventTarget) usize {
    const t = target orelse return NULL_TARGET_SENTINEL;
    return switch (t) {
        .listener => 0,
        .pty => |p| 1 + @as(usize, p.session_idx) * PANE_SLOT_RANGE + @as(usize, p.pane_slot),
        .client => |c| CLIENT_BASE + @as(usize, c.client_idx),
        .timer => |t_inner| TIMER_BASE + @as(usize, t_inner.timer_id),
    };
}

/// Decode a usize from kevent udata back to an optional EventTarget.
fn decodeTarget(udata: usize) ?interfaces.EventTarget {
    if (udata == NULL_TARGET_SENTINEL) return null;
    if (udata == 0) return .{ .listener = {} };
    if (udata >= TIMER_BASE) return .{ .timer = .{ .timer_id = @intCast(udata - TIMER_BASE) } };
    if (udata >= CLIENT_BASE) return .{ .client = .{ .client_idx = @intCast(udata - CLIENT_BASE) } };
    // pty: udata = 1 + session_idx * PANE_SLOT_RANGE + pane_slot
    const encoded = udata - 1;
    return .{ .pty = .{
        .session_idx = @intCast(encoded / PANE_SLOT_RANGE),
        .pane_slot = @intCast(encoded % PANE_SLOT_RANGE),
    } };
}

fn kqRegisterRead(ctx: *anyopaque, fd: std.posix.fd_t, target: ?interfaces.EventTarget) interfaces.EventLoopOps.RegisterError!void {
    if (comptime !builtin.os.tag.isBSD()) unreachable;
    const kq = toKqCtx(ctx).kq_fd;
    const udata = encodeTarget(target);
    const change = [1]std.posix.Kevent{.{
        .ident = @intCast(fd),
        .filter = std.c.EVFILT.READ,
        .flags = std.c.EV.ADD | std.c.EV.ENABLE,
        .fflags = 0,
        .data = 0,
        .udata = udata,
    }};
    _ = std.posix.kevent(kq, &change, &.{}, null) catch return error.EventLoopError;
}

fn kqRegisterWrite(ctx: *anyopaque, fd: std.posix.fd_t, target: ?interfaces.EventTarget) interfaces.EventLoopOps.RegisterError!void {
    if (comptime !builtin.os.tag.isBSD()) unreachable;
    const kq = toKqCtx(ctx).kq_fd;
    const udata = encodeTarget(target);
    const change = [1]std.posix.Kevent{.{
        .ident = @intCast(fd),
        .filter = std.c.EVFILT.WRITE,
        .flags = std.c.EV.ADD | std.c.EV.ENABLE,
        .fflags = 0,
        .data = 0,
        .udata = udata,
    }};
    _ = std.posix.kevent(kq, &change, &.{}, null) catch return error.EventLoopError;
}

fn kqUnregister(ctx: *anyopaque, fd: std.posix.fd_t) void {
    if (comptime !builtin.os.tag.isBSD()) unreachable;
    const kq = toKqCtx(ctx).kq_fd;
    const changes = [2]std.posix.Kevent{
        .{
            .ident = @intCast(fd),
            .filter = std.c.EVFILT.READ,
            .flags = std.c.EV.DELETE,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        },
        .{
            .ident = @intCast(fd),
            .filter = std.c.EVFILT.WRITE,
            .flags = std.c.EV.DELETE,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        },
    };
    _ = std.posix.kevent(kq, &changes, &.{}, null) catch {};
}

fn kqRegisterTimer(ctx: *anyopaque, timer_id: u16, interval_ms: u32, target: ?interfaces.EventTarget) interfaces.EventLoopOps.RegisterError!void {
    if (comptime !builtin.os.tag.isBSD()) unreachable;
    const kq = toKqCtx(ctx).kq_fd;
    const udata = encodeTarget(target);
    const change = [1]std.posix.Kevent{.{
        .ident = @as(usize, timer_id),
        .filter = std.c.EVFILT.TIMER,
        .flags = std.c.EV.ADD | std.c.EV.ENABLE,
        .fflags = 0,
        .data = @as(isize, @intCast(interval_ms)),
        .udata = udata,
    }};
    _ = std.posix.kevent(kq, &change, &.{}, null) catch return error.EventLoopError;
}

fn kqCancelTimer(ctx: *anyopaque, timer_id: u16) void {
    if (comptime !builtin.os.tag.isBSD()) unreachable;
    const kq = toKqCtx(ctx).kq_fd;
    const change = [1]std.posix.Kevent{.{
        .ident = @as(usize, timer_id),
        .filter = std.c.EVFILT.TIMER,
        .flags = std.c.EV.DELETE,
        .fflags = 0,
        .data = 0,
        .udata = 0,
    }};
    _ = std.posix.kevent(kq, &change, &.{}, null) catch {};
}

fn kqWait(ctx: *anyopaque, timeout_ms: ?u32) interfaces.EventLoopOps.WaitError!PriorityEventBuffer.Iterator {
    if (comptime !builtin.os.tag.isBSD()) unreachable;
    const kq_ctx = toKqCtx(ctx);
    const kq = kq_ctx.kq_fd;

    var kev_buf: [interfaces.MAX_EVENTS_PER_BATCH]std.posix.Kevent = undefined;

    var ts_storage: std.posix.timespec = undefined;
    const ts: ?*const std.posix.timespec = if (timeout_ms) |ms| blk: {
        ts_storage = .{
            .sec = @intCast(ms / 1000),
            .nsec = @intCast((ms % 1000) * 1_000_000),
        };
        break :blk &ts_storage;
    } else null;

    const n = std.posix.kevent(kq, &.{}, &kev_buf, ts) catch return error.EventLoopError;

    kq_ctx.event_buffer.reset();

    for (kev_buf[0..n]) |kev| {
        const filter: interfaces.Filter = switch (kev.filter) {
            std.c.EVFILT.READ => .read,
            std.c.EVFILT.WRITE => .write,
            std.c.EVFILT.SIGNAL => .signal,
            std.c.EVFILT.TIMER => .timer,
            else => continue,
        };
        // Signal events have no meaningful target — the signal number is
        // carried in the fd (ident) field.
        const target: ?interfaces.EventTarget = if (filter == .signal) null else decodeTarget(kev.udata);
        kq_ctx.event_buffer.add(.{
            .fd = @intCast(kev.ident),
            .filter = filter,
            .target = target,
        });
    }

    return kq_ctx.event_buffer.iterator();
}

// ── Tests ──────────────────────────────────────────────────────────────────

test "KqueueContext: registerRead pipe write event detected and target verified" {
    if (comptime !builtin.os.tag.isBSD()) return;
    const createPipe = @import("itshell3_testing").helpers.createPipe;
    var ctx = try KqueueContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    const read_fd = pipe_fds[0];
    const write_fd = pipe_fds[1];

    const target = interfaces.EventTarget{ .client = .{ .client_idx = 42 } };
    try ops.registerRead(ctx_ptr, read_fd, target);
    _ = try std.posix.write(write_fd, "hello");

    var iter = try ops.wait(ctx_ptr, 100);
    const event = iter.next();

    try std.testing.expect(event != null);
    try std.testing.expectEqual(read_fd, event.?.fd);
    try std.testing.expectEqual(interfaces.Filter.read, event.?.filter);
    if (event.?.target) |decoded_target| {
        switch (decoded_target) {
            .client => |c| try std.testing.expectEqual(@as(u16, 42), c.client_idx),
            else => return error.TestUnexpectedResult,
        }
    } else return error.TestUnexpectedResult;

    var buf: [16]u8 = undefined;
    const bytes_read = try std.posix.read(read_fd, &buf);
    try std.testing.expectEqual(@as(usize, 5), bytes_read);
    try std.testing.expectEqualSlices(u8, "hello", buf[0..bytes_read]);
}

test "KqueueContext: registerWrite immediately writable and write succeeds" {
    if (comptime !builtin.os.tag.isBSD()) return;
    const createPipe = @import("itshell3_testing").helpers.createPipe;
    var ctx = try KqueueContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    const write_fd = pipe_fds[1];
    const target = interfaces.EventTarget{ .client = .{ .client_idx = 77 } };

    try ops.registerWrite(ctx_ptr, write_fd, target);

    var iter = try ops.wait(ctx_ptr, 100);
    const event = iter.next();

    try std.testing.expect(event != null);
    try std.testing.expectEqual(write_fd, event.?.fd);
    try std.testing.expectEqual(interfaces.Filter.write, event.?.filter);
    if (event.?.target) |decoded_target| {
        switch (decoded_target) {
            .client => |c| try std.testing.expectEqual(@as(u16, 77), c.client_idx),
            else => return error.TestUnexpectedResult,
        }
    } else return error.TestUnexpectedResult;

    const bytes_written = try std.posix.write(write_fd, "test");
    try std.testing.expect(bytes_written > 0);
}

test "KqueueContext: unregister no event after write" {
    if (comptime !builtin.os.tag.isBSD()) return;
    const createPipe = @import("itshell3_testing").helpers.createPipe;
    var ctx = try KqueueContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    const read_fd = pipe_fds[0];
    const write_fd = pipe_fds[1];

    try ops.registerRead(ctx_ptr, read_fd, .{ .listener = {} });
    ops.unregister(ctx_ptr, read_fd);

    _ = try std.posix.write(write_fd, "ignored");

    var iter = try ops.wait(ctx_ptr, 50);
    try std.testing.expect(iter.next() == null);
}

test "KqueueContext: timeout with no events returns empty iterator" {
    if (comptime !builtin.os.tag.isBSD()) return;
    const createPipe = @import("itshell3_testing").helpers.createPipe;
    var ctx = try KqueueContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    try ops.registerRead(ctx_ptr, pipe_fds[0], .{ .listener = {} });

    var iter = try ops.wait(ctx_ptr, 50);
    try std.testing.expect(iter.next() == null);
}

test "KqueueContext: multiple fds correct target routing" {
    if (comptime !builtin.os.tag.isBSD()) return;
    const createPipe = @import("itshell3_testing").helpers.createPipe;
    var ctx = try KqueueContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe1 = try createPipe();
    defer std.posix.close(pipe1[0]);
    defer std.posix.close(pipe1[1]);
    const pipe2 = try createPipe();
    defer std.posix.close(pipe2[0]);
    defer std.posix.close(pipe2[1]);

    const target1 = interfaces.EventTarget{ .pty = .{ .session_idx = 1, .pane_slot = 2 } };
    const target2 = interfaces.EventTarget{ .client = .{ .client_idx = 5 } };

    try ops.registerRead(ctx_ptr, pipe1[0], target1);
    try ops.registerRead(ctx_ptr, pipe2[0], target2);

    _ = try std.posix.write(pipe1[1], "one");
    _ = try std.posix.write(pipe2[1], "two");

    var iter = try ops.wait(ctx_ptr, 100);

    var found_pipe1 = false;
    var found_pipe2 = false;
    while (iter.next()) |event| {
        if (event.fd == pipe1[0]) {
            if (event.target) |target| {
                switch (target) {
                    .pty => |p| {
                        try std.testing.expectEqual(@as(u16, 1), p.session_idx);
                        try std.testing.expectEqual(@as(u8, 2), p.pane_slot);
                    },
                    else => return error.TestUnexpectedResult,
                }
            } else return error.TestUnexpectedResult;
            found_pipe1 = true;
        }
        if (event.fd == pipe2[0]) {
            if (event.target) |target| {
                switch (target) {
                    .client => |c| try std.testing.expectEqual(@as(u16, 5), c.client_idx),
                    else => return error.TestUnexpectedResult,
                }
            } else return error.TestUnexpectedResult;
            found_pipe2 = true;
        }
    }

    try std.testing.expect(found_pipe1);
    try std.testing.expect(found_pipe2);
}

test "KqueueContext: EOF detection when write end is closed" {
    if (comptime !builtin.os.tag.isBSD()) return;
    const createPipe = @import("itshell3_testing").helpers.createPipe;
    var ctx = try KqueueContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);

    const read_fd = pipe_fds[0];
    const write_fd = pipe_fds[1];

    try ops.registerRead(ctx_ptr, read_fd, .{ .client = .{ .client_idx = 55 } });
    std.posix.close(write_fd);

    var iter = try ops.wait(ctx_ptr, 100);
    const event = iter.next();
    try std.testing.expect(event != null);
    try std.testing.expectEqual(read_fd, event.?.fd);

    var buf: [16]u8 = undefined;
    const bytes_read = try std.posix.read(read_fd, &buf);
    try std.testing.expectEqual(@as(usize, 0), bytes_read);
}

test "encodeTarget and decodeTarget: round-trip all variants" {
    // null
    const null_enc = encodeTarget(null);
    const null_dec = decodeTarget(null_enc);
    try std.testing.expect(null_dec == null);

    // listener
    const listener: ?interfaces.EventTarget = .{ .listener = {} };
    const listener_enc = encodeTarget(listener);
    const listener_dec = decodeTarget(listener_enc);
    if (listener_dec) |dec| {
        switch (dec) {
            .listener => {},
            else => return error.TestUnexpectedResult,
        }
    } else return error.TestUnexpectedResult;

    // pty
    const pty: ?interfaces.EventTarget = .{ .pty = .{ .session_idx = 10, .pane_slot = 3 } };
    const pty_enc = encodeTarget(pty);
    const pty_dec = decodeTarget(pty_enc);
    if (pty_dec) |dec| {
        switch (dec) {
            .pty => |p| {
                try std.testing.expectEqual(@as(u16, 10), p.session_idx);
                try std.testing.expectEqual(@as(u8, 3), p.pane_slot);
            },
            else => return error.TestUnexpectedResult,
        }
    } else return error.TestUnexpectedResult;

    // client
    const client: ?interfaces.EventTarget = .{ .client = .{ .client_idx = 63 } };
    const client_enc = encodeTarget(client);
    const client_dec = decodeTarget(client_enc);
    if (client_dec) |dec| {
        switch (dec) {
            .client => |c| try std.testing.expectEqual(@as(u16, 63), c.client_idx),
            else => return error.TestUnexpectedResult,
        }
    } else return error.TestUnexpectedResult;

    // timer
    const timer: ?interfaces.EventTarget = .{ .timer = .{ .timer_id = 999 } };
    const timer_enc = encodeTarget(timer);
    const timer_dec = decodeTarget(timer_enc);
    if (timer_dec) |dec| {
        switch (dec) {
            .timer => |t| try std.testing.expectEqual(@as(u16, 999), t.timer_id),
            else => return error.TestUnexpectedResult,
        }
    } else return error.TestUnexpectedResult;
}

test "encodeTarget/decodeTarget: null target round-trip" {
    const encoded = encodeTarget(null);
    try std.testing.expectEqual(NULL_TARGET_SENTINEL, encoded);
    const decoded = decodeTarget(encoded);
    try std.testing.expect(decoded == null);
}

test "encodeTarget/decodeTarget: null vs listener non-collision" {
    const null_udata = encodeTarget(null);
    const listener_udata = encodeTarget(.{ .listener = {} });
    try std.testing.expect(null_udata != listener_udata);
}

test "encodeTarget/decodeTarget: null vs pty boundary non-collision" {
    const null_udata = encodeTarget(null);
    const pty_max_udata = encodeTarget(.{ .pty = .{
        .session_idx = std.math.maxInt(u16),
        .pane_slot = std.math.maxInt(types.PaneSlot),
    } });
    try std.testing.expect(null_udata != pty_max_udata);
}

test "encodeTarget/decodeTarget: null vs client boundary non-collision" {
    const null_udata = encodeTarget(null);
    const client_max_udata = encodeTarget(.{ .client = .{
        .client_idx = std.math.maxInt(u16),
    } });
    try std.testing.expect(null_udata != client_max_udata);
}

test "encodeTarget/decodeTarget: null vs timer boundary non-collision" {
    const null_udata = encodeTarget(null);
    const timer_max_udata = encodeTarget(.{ .timer = .{
        .timer_id = std.math.maxInt(u16),
    } });
    try std.testing.expect(null_udata != timer_max_udata);
}

test "encodeTarget/decodeTarget: all variants produce distinct udata ranges" {
    const null_udata = encodeTarget(null);
    const listener_udata = encodeTarget(.{ .listener = {} });
    const pty_udata = encodeTarget(.{ .pty = .{ .session_idx = 0, .pane_slot = 0 } });
    const client_udata = encodeTarget(.{ .client = .{ .client_idx = 0 } });
    const timer_udata = encodeTarget(.{ .timer = .{ .timer_id = 0 } });

    const all = [_]usize{ null_udata, listener_udata, pty_udata, client_udata, timer_udata };
    // Verify no two values are the same.
    for (all, 0..) |a, i| {
        for (all, 0..) |b, j| {
            if (i != j) try std.testing.expect(a != b);
        }
    }
}
