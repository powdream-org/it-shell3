const std = @import("std");
const builtin = @import("builtin");
const interfaces = @import("../interfaces.zig");
const PriorityEventBuffer = @import("../priority_event_buffer.zig").PriorityEventBuffer;

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

/// Base offset for signal targets in udata encoding.
const SIGNAL_BASE: usize = 0x0200_0000;
/// Base offset for client targets in udata encoding.
const CLIENT_BASE: usize = 0x0400_0000;
/// Base offset for timer targets in udata encoding.
const TIMER_BASE: usize = 0x0600_0000;

// Compile-time check: PTY range must not overlap client range.
// Max PTY udata = 1 + (maxInt(u16) * PANE_SLOT_RANGE) + maxInt(PaneSlot).
comptime {
    const max_pty_udata = 1 + @as(usize, std.math.maxInt(u16)) * PANE_SLOT_RANGE + std.math.maxInt(types.PaneSlot);
    if (max_pty_udata >= SIGNAL_BASE) @compileError("PTY udata range overlaps signal range");
}

/// Encode an EventTarget into a usize for kevent udata field.
/// Encoding scheme (internal to kqueue backend):
///   listener: 0
///   signal: SIGNAL_BASE + signal_number
///   pty: 1 + session_idx * PANE_SLOT_RANGE + pane_slot
///   client: CLIENT_BASE + client_idx
///   timer: TIMER_BASE + timer_id
fn encodeTarget(target: interfaces.EventTarget) usize {
    return switch (target) {
        .listener => 0,
        .signal => |s| SIGNAL_BASE + @as(usize, s.signal_number),
        .pty => |p| 1 + @as(usize, p.session_idx) * PANE_SLOT_RANGE + @as(usize, p.pane_slot),
        .client => |c| CLIENT_BASE + @as(usize, c.client_idx),
        .timer => |t| TIMER_BASE + @as(usize, t.timer_id),
    };
}

/// Decode a usize from kevent udata back to EventTarget.
fn decodeTarget(udata: usize) interfaces.EventTarget {
    if (udata == 0) return .{ .listener = {} };
    if (udata >= TIMER_BASE) return .{ .timer = .{ .timer_id = @intCast(udata - TIMER_BASE) } };
    if (udata >= CLIENT_BASE) return .{ .client = .{ .client_idx = @intCast(udata - CLIENT_BASE) } };
    if (udata >= SIGNAL_BASE) return .{ .signal = .{ .signal_number = @intCast(udata - SIGNAL_BASE) } };
    // pty: udata = 1 + session_idx * PANE_SLOT_RANGE + pane_slot
    const encoded = udata - 1;
    return .{ .pty = .{
        .session_idx = @intCast(encoded / PANE_SLOT_RANGE),
        .pane_slot = @intCast(encoded % PANE_SLOT_RANGE),
    } };
}

fn kqRegisterRead(ctx: *anyopaque, fd: std.posix.fd_t, target: interfaces.EventTarget) interfaces.EventLoopOps.RegisterError!void {
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

fn kqRegisterWrite(ctx: *anyopaque, fd: std.posix.fd_t, target: interfaces.EventTarget) interfaces.EventLoopOps.RegisterError!void {
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
        kq_ctx.event_buffer.add(.{
            .fd = @intCast(kev.ident),
            .filter = filter,
            .target = decodeTarget(kev.udata),
            .flags = kev.flags,
            .data = @intCast(kev.data),
        });
    }

    return kq_ctx.event_buffer.iterator();
}

// ── Tests ──────────────────────────────────────────────────────────────────

const testing = std.testing;

/// Helper: create a pipe pair. Returns .{read_fd, write_fd}.
fn createPipe() ![2]std.posix.fd_t {
    return std.posix.pipe() catch return error.EventLoopError;
}

test "KqueueContext: registerRead pipe write event detected and target verified" {
    if (comptime !builtin.os.tag.isBSD()) return;
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

    try testing.expect(event != null);
    try testing.expectEqual(read_fd, event.?.fd);
    try testing.expectEqual(interfaces.Filter.read, event.?.filter);
    switch (event.?.target) {
        .client => |c| try testing.expectEqual(@as(u16, 42), c.client_idx),
        else => return error.TestUnexpectedResult,
    }

    var buf: [16]u8 = undefined;
    const bytes_read = try std.posix.read(read_fd, &buf);
    try testing.expectEqual(@as(usize, 5), bytes_read);
    try testing.expectEqualSlices(u8, "hello", buf[0..bytes_read]);
}

test "KqueueContext: registerWrite immediately writable and write succeeds" {
    if (comptime !builtin.os.tag.isBSD()) return;
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

    try testing.expect(event != null);
    try testing.expectEqual(write_fd, event.?.fd);
    try testing.expectEqual(interfaces.Filter.write, event.?.filter);
    switch (event.?.target) {
        .client => |c| try testing.expectEqual(@as(u16, 77), c.client_idx),
        else => return error.TestUnexpectedResult,
    }

    const bytes_written = try std.posix.write(write_fd, "test");
    try testing.expect(bytes_written > 0);
}

test "KqueueContext: unregister no event after write" {
    if (comptime !builtin.os.tag.isBSD()) return;
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
    try testing.expect(iter.next() == null);
}

test "KqueueContext: timeout with no events returns empty iterator" {
    if (comptime !builtin.os.tag.isBSD()) return;
    var ctx = try KqueueContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    try ops.registerRead(ctx_ptr, pipe_fds[0], .{ .listener = {} });

    var iter = try ops.wait(ctx_ptr, 50);
    try testing.expect(iter.next() == null);
}

test "KqueueContext: multiple fds correct target routing" {
    if (comptime !builtin.os.tag.isBSD()) return;
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
            switch (event.target) {
                .pty => |p| {
                    try testing.expectEqual(@as(u16, 1), p.session_idx);
                    try testing.expectEqual(@as(u8, 2), p.pane_slot);
                },
                else => return error.TestUnexpectedResult,
            }
            found_pipe1 = true;
        }
        if (event.fd == pipe2[0]) {
            switch (event.target) {
                .client => |c| try testing.expectEqual(@as(u16, 5), c.client_idx),
                else => return error.TestUnexpectedResult,
            }
            found_pipe2 = true;
        }
    }

    try testing.expect(found_pipe1);
    try testing.expect(found_pipe2);
}

test "KqueueContext: EOF detection when write end is closed" {
    if (comptime !builtin.os.tag.isBSD()) return;
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
    try testing.expect(event != null);
    try testing.expectEqual(read_fd, event.?.fd);
    // Both kqueue (EV_EOF) and epoll (EPOLLHUP) set some flags bit on EOF.
    try testing.expect(event.?.flags != 0);

    var buf: [16]u8 = undefined;
    const bytes_read = try std.posix.read(read_fd, &buf);
    try testing.expectEqual(@as(usize, 0), bytes_read);
}

test "encodeTarget and decodeTarget: round-trip all variants" {
    // listener
    const listener = interfaces.EventTarget{ .listener = {} };
    const listener_enc = encodeTarget(listener);
    const listener_dec = decodeTarget(listener_enc);
    switch (listener_dec) {
        .listener => {},
        else => return error.TestUnexpectedResult,
    }

    // signal
    const signal = interfaces.EventTarget{ .signal = .{ .signal_number = 15 } };
    const signal_enc = encodeTarget(signal);
    const signal_dec = decodeTarget(signal_enc);
    switch (signal_dec) {
        .signal => |s| try testing.expectEqual(@as(u32, 15), s.signal_number),
        else => return error.TestUnexpectedResult,
    }

    // pty
    const pty = interfaces.EventTarget{ .pty = .{ .session_idx = 10, .pane_slot = 3 } };
    const pty_enc = encodeTarget(pty);
    const pty_dec = decodeTarget(pty_enc);
    switch (pty_dec) {
        .pty => |p| {
            try testing.expectEqual(@as(u16, 10), p.session_idx);
            try testing.expectEqual(@as(u8, 3), p.pane_slot);
        },
        else => return error.TestUnexpectedResult,
    }

    // client
    const client = interfaces.EventTarget{ .client = .{ .client_idx = 63 } };
    const client_enc = encodeTarget(client);
    const client_dec = decodeTarget(client_enc);
    switch (client_dec) {
        .client => |c| try testing.expectEqual(@as(u16, 63), c.client_idx),
        else => return error.TestUnexpectedResult,
    }

    // timer
    const timer = interfaces.EventTarget{ .timer = .{ .timer_id = 999 } };
    const timer_enc = encodeTarget(timer);
    const timer_dec = decodeTarget(timer_enc);
    switch (timer_dec) {
        .timer => |t| try testing.expectEqual(@as(u16, 999), t.timer_id),
        else => return error.TestUnexpectedResult,
    }
}
