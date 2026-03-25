const std = @import("std");
const interfaces = @import("interfaces.zig");

pub const KqueueContext = struct {
    kq_fd: std.posix.fd_t,

    pub fn init() error{KqueueError}!KqueueContext {
        const kq = std.posix.kqueue() catch return error.KqueueError;
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
    const kq = toKqCtx(ctx).kq_fd;
    const change = [1]std.posix.Kevent{.{
        .ident = @intCast(fd),
        .filter = std.c.EVFILT.READ,
        .flags = std.c.EV.ADD | std.c.EV.ENABLE,
        .fflags = 0,
        .data = 0,
        .udata = udata,
    }};
    _ = std.posix.kevent(kq, &change, &.{}, null) catch return error.KqueueError;
}

fn kqRegisterWrite(ctx: *anyopaque, fd: std.posix.fd_t, udata: usize) interfaces.EventLoopOps.RegisterError!void {
    const kq = toKqCtx(ctx).kq_fd;
    const change = [1]std.posix.Kevent{.{
        .ident = @intCast(fd),
        .filter = std.c.EVFILT.WRITE,
        .flags = std.c.EV.ADD | std.c.EV.ENABLE,
        .fflags = 0,
        .data = 0,
        .udata = udata,
    }};
    _ = std.posix.kevent(kq, &change, &.{}, null) catch return error.KqueueError;
}

fn kqUnregister(ctx: *anyopaque, fd: std.posix.fd_t) void {
    const kq = toKqCtx(ctx).kq_fd;
    const del_read = [1]std.posix.Kevent{.{
        .ident = @intCast(fd),
        .filter = std.c.EVFILT.READ,
        .flags = std.c.EV.DELETE,
        .fflags = 0,
        .data = 0,
        .udata = 0,
    }};
    const del_write = [1]std.posix.Kevent{.{
        .ident = @intCast(fd),
        .filter = std.c.EVFILT.WRITE,
        .flags = std.c.EV.DELETE,
        .fflags = 0,
        .data = 0,
        .udata = 0,
    }};
    _ = std.posix.kevent(kq, &del_read, &.{}, null) catch {};
    _ = std.posix.kevent(kq, &del_write, &.{}, null) catch {};
}

fn kqWait(ctx: *anyopaque, events: []interfaces.EventLoopOps.Event, timeout_ms: ?u32) interfaces.EventLoopOps.WaitError!usize {
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

    const n = std.posix.kevent(kq, &.{}, kev_buf[0..max_ev], ts) catch return error.KqueueError;

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
