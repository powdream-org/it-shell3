const std = @import("std");
const builtin = @import("builtin");
const interfaces = @import("interfaces.zig");

// ── macOS / BSD: kqueue ────────────────────────────────────────────────────

pub const KqueueContext = struct {
    kq_fd: std.posix.fd_t,

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

fn kqRegisterRead(ctx: *anyopaque, fd: std.posix.fd_t, udata: usize) interfaces.EventLoopOps.RegisterError!void {
    if (comptime !builtin.os.tag.isBSD()) unreachable;
    const kq = toKqCtx(ctx).kq_fd;
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

fn kqRegisterWrite(ctx: *anyopaque, fd: std.posix.fd_t, udata: usize) interfaces.EventLoopOps.RegisterError!void {
    if (comptime !builtin.os.tag.isBSD()) unreachable;
    const kq = toKqCtx(ctx).kq_fd;
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

fn kqWait(ctx: *anyopaque, events: []interfaces.EventLoopOps.Event, timeout_ms: ?u32) interfaces.EventLoopOps.WaitError!usize {
    if (comptime !builtin.os.tag.isBSD()) unreachable;
    const kq = toKqCtx(ctx).kq_fd;

    var kev_buf: [64]std.posix.Kevent = undefined;
    const max_ev = @min(events.len, kev_buf.len);

    var ts_storage: std.posix.timespec = undefined;
    const ts: ?*const std.posix.timespec = if (timeout_ms) |ms| blk: {
        ts_storage = .{
            .sec = @intCast(ms / 1000),
            .nsec = @intCast((ms % 1000) * 1_000_000),
        };
        break :blk &ts_storage;
    } else null;

    const n = std.posix.kevent(kq, &.{}, kev_buf[0..max_ev], ts) catch return error.EventLoopError;

    for (kev_buf[0..n], 0..) |kev, i| {
        const filter: interfaces.EventLoopOps.Filter = switch (kev.filter) {
            std.c.EVFILT.READ => .read,
            std.c.EVFILT.WRITE => .write,
            std.c.EVFILT.SIGNAL => .signal,
            std.c.EVFILT.TIMER => .timer,
            else => .read,
        };
        events[i] = .{
            .fd = @intCast(kev.ident),
            .filter = filter,
            .udata = kev.udata,
            .flags = kev.flags,
            .data = @intCast(kev.data),
        };
    }
    return n;
}

// ── Linux: epoll ───────────────────────────────────────────────────────────

pub const EpollContext = struct {
    ep_fd: std.posix.fd_t,

    pub fn init() error{EventLoopError}!EpollContext {
        if (comptime builtin.os.tag != .linux) @compileError("EpollContext is Linux only");
        const ep = std.posix.epoll_create1(std.os.linux.EPOLL.CLOEXEC) catch return error.EventLoopError;
        return EpollContext{ .ep_fd = ep };
    }

    pub fn deinit(self: *EpollContext) void {
        std.posix.close(self.ep_fd);
    }

    pub fn eventLoopOps(_: *EpollContext) interfaces.EventLoopOps {
        return .{
            .registerRead = epRegisterRead,
            .registerWrite = epRegisterWrite,
            .unregister = epUnregister,
            .wait = epWait,
        };
    }
};

fn toEpCtx(ctx: *anyopaque) *EpollContext {
    return @ptrCast(@alignCast(ctx));
}

/// Pack fd and udata into a single u64 for epoll_event.data so that epWait
/// can reconstruct both the file descriptor and the user token.
/// Layout: upper 32 bits = fd, lower 32 bits = udata (truncated to 32).
inline fn epPackData(fd: std.posix.fd_t, udata: usize) u64 {
    std.debug.assert(udata <= 0xFFFF_FFFF); // epoll packs udata into 32 bits
    return (@as(u64, @intCast(fd)) << 32) | (@as(u64, @intCast(udata)) & 0xFFFF_FFFF);
}

fn epRegisterRead(ctx: *anyopaque, fd: std.posix.fd_t, udata: usize) interfaces.EventLoopOps.RegisterError!void {
    if (comptime builtin.os.tag != .linux) unreachable;
    const ep = toEpCtx(ctx).ep_fd;
    var ev = std.os.linux.epoll_event{
        .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.HUP | std.os.linux.EPOLL.ERR,
        .data = .{ .u64 = epPackData(fd, udata) },
    };
    std.posix.epoll_ctl(ep, std.os.linux.EPOLL.CTL_ADD, fd, &ev) catch return error.EventLoopError;
}

fn epRegisterWrite(ctx: *anyopaque, fd: std.posix.fd_t, udata: usize) interfaces.EventLoopOps.RegisterError!void {
    if (comptime builtin.os.tag != .linux) unreachable;
    const ep = toEpCtx(ctx).ep_fd;
    var ev = std.os.linux.epoll_event{
        .events = std.os.linux.EPOLL.OUT | std.os.linux.EPOLL.HUP | std.os.linux.EPOLL.ERR,
        .data = .{ .u64 = epPackData(fd, udata) },
    };
    std.posix.epoll_ctl(ep, std.os.linux.EPOLL.CTL_ADD, fd, &ev) catch return error.EventLoopError;
}

fn epUnregister(ctx: *anyopaque, fd: std.posix.fd_t) void {
    if (comptime builtin.os.tag != .linux) unreachable;
    const ep = toEpCtx(ctx).ep_fd;
    std.posix.epoll_ctl(ep, std.os.linux.EPOLL.CTL_DEL, fd, null) catch {};
}

fn epWait(ctx: *anyopaque, events: []interfaces.EventLoopOps.Event, timeout_ms: ?u32) interfaces.EventLoopOps.WaitError!usize {
    if (comptime builtin.os.tag != .linux) unreachable;
    const ep = toEpCtx(ctx).ep_fd;

    var ep_buf: [64]std.os.linux.epoll_event = undefined;
    const max_ev = @min(events.len, ep_buf.len);

    const timeout: i32 = if (timeout_ms) |ms| @intCast(ms) else -1;

    const n = std.posix.epoll_wait(ep, ep_buf[0..max_ev], timeout);

    for (ep_buf[0..n], 0..) |ep_ev, i| {
        const ev_flags = ep_ev.events;
        const filter: interfaces.EventLoopOps.Filter = if ((ev_flags & std.os.linux.EPOLL.OUT) != 0)
            .write
        else
            .read;

        // Encode HUP/ERR into the flags field (analogous to kqueue EV_EOF / EV_ERROR).
        var flags: u16 = 0;
        if ((ev_flags & std.os.linux.EPOLL.HUP) != 0) flags |= 0x8000;
        if ((ev_flags & std.os.linux.EPOLL.ERR) != 0) flags |= 0x4000;

        // Unpack fd and udata from data.u64.
        const raw = ep_ev.data.u64;
        const stored_fd: std.posix.fd_t = @intCast(raw >> 32);
        const udata: usize = @intCast(raw & 0xFFFF_FFFF);

        events[i] = .{
            .fd = stored_fd,
            .filter = filter,
            .udata = udata,
            .flags = flags,
            .data = 0, // epoll does not report bytes available
        };
    }
    return n;
}

// ── Platform alias ─────────────────────────────────────────────────────────

/// Platform-appropriate event loop context.
/// On macOS/BSD: wraps kqueue. On Linux: wraps epoll.
pub const PlatformContext = if (builtin.os.tag.isBSD())
    KqueueContext
else if (builtin.os.tag == .linux)
    EpollContext
else
    @compileError("Unsupported platform: no event loop backend available");

// ── Tests ──────────────────────────────────────────────────────────────────

const testing = std.testing;

/// Helper: create a pipe pair. Returns .{read_fd, write_fd}.
fn createPipe() ![2]std.posix.fd_t {
    return std.posix.pipe() catch return error.EventLoopError;
}

test "KqueueContext: registerRead pipe write event detected and data verified" {
    var ctx = try PlatformContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    const read_fd = pipe_fds[0];
    const write_fd = pipe_fds[1];

    try ops.registerRead(ctx_ptr, read_fd, 42);
    _ = try std.posix.write(write_fd, "hello");

    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx_ptr, &events, 100);

    try testing.expectEqual(@as(usize, 1), n);
    try testing.expectEqual(read_fd, events[0].fd);
    try testing.expectEqual(@as(usize, 42), events[0].udata);
    try testing.expectEqual(interfaces.EventLoopOps.Filter.read, events[0].filter);

    var buf: [16]u8 = undefined;
    const bytes_read = try std.posix.read(read_fd, &buf);
    try testing.expectEqual(@as(usize, 5), bytes_read);
    try testing.expectEqualSlices(u8, "hello", buf[0..bytes_read]);
}

test "KqueueContext: registerWrite immediately writable and write succeeds" {
    var ctx = try PlatformContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    const write_fd = pipe_fds[1];

    try ops.registerWrite(ctx_ptr, write_fd, 77);

    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx_ptr, &events, 100);

    try testing.expect(n >= 1);
    try testing.expectEqual(write_fd, events[0].fd);
    try testing.expectEqual(@as(usize, 77), events[0].udata);
    try testing.expectEqual(interfaces.EventLoopOps.Filter.write, events[0].filter);

    const bytes_written = try std.posix.write(write_fd, "test");
    try testing.expect(bytes_written > 0);
}

test "KqueueContext: unregister no event after write" {
    var ctx = try PlatformContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    const read_fd = pipe_fds[0];
    const write_fd = pipe_fds[1];

    try ops.registerRead(ctx_ptr, read_fd, 10);
    ops.unregister(ctx_ptr, read_fd);

    _ = try std.posix.write(write_fd, "ignored");

    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx_ptr, &events, 50);

    try testing.expectEqual(@as(usize, 0), n);
}

test "KqueueContext: timeout with no events returns 0" {
    var ctx = try PlatformContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    try ops.registerRead(ctx_ptr, pipe_fds[0], 1);

    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx_ptr, &events, 50);

    try testing.expectEqual(@as(usize, 0), n);
}

test "KqueueContext: multiple fds correct udata routing" {
    var ctx = try PlatformContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe1 = try createPipe();
    defer std.posix.close(pipe1[0]);
    defer std.posix.close(pipe1[1]);
    const pipe2 = try createPipe();
    defer std.posix.close(pipe2[0]);
    defer std.posix.close(pipe2[1]);

    try ops.registerRead(ctx_ptr, pipe1[0], 100);
    try ops.registerRead(ctx_ptr, pipe2[0], 200);

    _ = try std.posix.write(pipe1[1], "one");
    _ = try std.posix.write(pipe2[1], "two");

    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx_ptr, &events, 100);

    try testing.expectEqual(@as(usize, 2), n);

    var udata_for_pipe1: ?usize = null;
    var udata_for_pipe2: ?usize = null;
    for (events[0..n]) |ev| {
        if (ev.fd == pipe1[0]) udata_for_pipe1 = ev.udata;
        if (ev.fd == pipe2[0]) udata_for_pipe2 = ev.udata;
    }

    try testing.expectEqual(@as(?usize, 100), udata_for_pipe1);
    try testing.expectEqual(@as(?usize, 200), udata_for_pipe2);

    var buf1: [16]u8 = undefined;
    const n1 = try std.posix.read(pipe1[0], &buf1);
    try testing.expectEqualSlices(u8, "one", buf1[0..n1]);

    var buf2: [16]u8 = undefined;
    const n2 = try std.posix.read(pipe2[0], &buf2);
    try testing.expectEqualSlices(u8, "two", buf2[0..n2]);
}

test "KqueueContext: EOF detection when write end is closed" {
    var ctx = try PlatformContext.init();
    defer ctx.deinit();
    const ops = ctx.eventLoopOps();
    const ctx_ptr: *anyopaque = @ptrCast(&ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);

    const read_fd = pipe_fds[0];
    const write_fd = pipe_fds[1];

    try ops.registerRead(ctx_ptr, read_fd, 55);
    std.posix.close(write_fd);

    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx_ptr, &events, 100);

    try testing.expect(n >= 1);
    try testing.expectEqual(read_fd, events[0].fd);
    try testing.expectEqual(@as(usize, 55), events[0].udata);
    // Both kqueue (EV_EOF) and epoll (EPOLLHUP) set some flags bit on EOF.
    try testing.expect(events[0].flags != 0);

    var buf: [16]u8 = undefined;
    const bytes_read = try std.posix.read(read_fd, &buf);
    try testing.expectEqual(@as(usize, 0), bytes_read);
}
