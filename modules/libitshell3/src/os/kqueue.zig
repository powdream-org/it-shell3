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

// ── Tests ──────────────────────────────────────────────────────────────────

const testing = std.testing;

/// Helper: create a pipe pair. Returns .{read_fd, write_fd}.
fn createPipe() ![2]std.posix.fd_t {
    return std.posix.pipe() catch return error.KqueueError;
}

test "kqueue: registerRead + pipe write → event detected and data verified" {
    var kq_ctx = try KqueueContext.init();
    defer kq_ctx.deinit();
    const ops = kq_ctx.eventLoopOps();
    const ctx: *anyopaque = @ptrCast(&kq_ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    const read_fd = pipe_fds[0];
    const write_fd = pipe_fds[1];

    // Register read end with udata = 42
    try ops.registerRead(ctx, read_fd, 42);

    // Write data to pipe
    _ = try std.posix.write(write_fd, "hello");

    // Wait for event
    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx, &events, 100);

    // Verify: 1 event, correct fd, correct udata
    try testing.expectEqual(@as(usize, 1), n);
    try testing.expectEqual(read_fd, events[0].fd);
    try testing.expectEqual(@as(usize, 42), events[0].udata);
    try testing.expectEqual(interfaces.EventLoopOps.Filter.read, events[0].filter);

    // Actually read and verify data
    var buf: [16]u8 = undefined;
    const bytes_read = try std.posix.read(read_fd, &buf);
    try testing.expectEqual(@as(usize, 5), bytes_read);
    try testing.expectEqualSlices(u8, "hello", buf[0..bytes_read]);
}

test "kqueue: registerWrite → immediately writable and write succeeds" {
    var kq_ctx = try KqueueContext.init();
    defer kq_ctx.deinit();
    const ops = kq_ctx.eventLoopOps();
    const ctx: *anyopaque = @ptrCast(&kq_ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    const write_fd = pipe_fds[1];

    // Register write end — pipe write end is always writable initially
    try ops.registerWrite(ctx, write_fd, 77);

    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx, &events, 100);

    // Verify event fires
    try testing.expect(n >= 1);
    try testing.expectEqual(write_fd, events[0].fd);
    try testing.expectEqual(@as(usize, 77), events[0].udata);
    try testing.expectEqual(interfaces.EventLoopOps.Filter.write, events[0].filter);

    // Actually write to verify the fd is writable
    const bytes_written = try std.posix.write(write_fd, "test");
    try testing.expect(bytes_written > 0);
}

test "kqueue: unregister → no event after write" {
    var kq_ctx = try KqueueContext.init();
    defer kq_ctx.deinit();
    const ops = kq_ctx.eventLoopOps();
    const ctx: *anyopaque = @ptrCast(&kq_ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    const read_fd = pipe_fds[0];
    const write_fd = pipe_fds[1];

    // Register then unregister
    try ops.registerRead(ctx, read_fd, 10);
    ops.unregister(ctx, read_fd);

    // Write to pipe — should NOT trigger an event
    _ = try std.posix.write(write_fd, "ignored");

    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx, &events, 50);

    // Verify: 0 events (timed out, nothing registered)
    try testing.expectEqual(@as(usize, 0), n);
}

test "kqueue: timeout with no events returns 0" {
    var kq_ctx = try KqueueContext.init();
    defer kq_ctx.deinit();
    const ops = kq_ctx.eventLoopOps();
    const ctx: *anyopaque = @ptrCast(&kq_ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    // Register read end but don't write anything
    try ops.registerRead(ctx, pipe_fds[0], 1);

    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx, &events, 50);

    try testing.expectEqual(@as(usize, 0), n);
}

test "kqueue: multiple fds → correct udata routing" {
    var kq_ctx = try KqueueContext.init();
    defer kq_ctx.deinit();
    const ops = kq_ctx.eventLoopOps();
    const ctx: *anyopaque = @ptrCast(&kq_ctx);

    // Create two pipes
    const pipe1 = try createPipe();
    defer std.posix.close(pipe1[0]);
    defer std.posix.close(pipe1[1]);
    const pipe2 = try createPipe();
    defer std.posix.close(pipe2[0]);
    defer std.posix.close(pipe2[1]);

    // Register both read ends with different udata
    try ops.registerRead(ctx, pipe1[0], 100);
    try ops.registerRead(ctx, pipe2[0], 200);

    // Write to both pipes
    _ = try std.posix.write(pipe1[1], "one");
    _ = try std.posix.write(pipe2[1], "two");

    // Wait for events
    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx, &events, 100);

    try testing.expectEqual(@as(usize, 2), n);

    // Build a map of fd → udata from returned events
    var udata_for_pipe1: ?usize = null;
    var udata_for_pipe2: ?usize = null;
    for (events[0..n]) |ev| {
        if (ev.fd == pipe1[0]) udata_for_pipe1 = ev.udata;
        if (ev.fd == pipe2[0]) udata_for_pipe2 = ev.udata;
    }

    try testing.expectEqual(@as(?usize, 100), udata_for_pipe1);
    try testing.expectEqual(@as(?usize, 200), udata_for_pipe2);

    // Actually read from both and verify data
    var buf1: [16]u8 = undefined;
    const n1 = try std.posix.read(pipe1[0], &buf1);
    try testing.expectEqualSlices(u8, "one", buf1[0..n1]);

    var buf2: [16]u8 = undefined;
    const n2 = try std.posix.read(pipe2[0], &buf2);
    try testing.expectEqualSlices(u8, "two", buf2[0..n2]);
}

test "kqueue: EOF detection when write end is closed" {
    var kq_ctx = try KqueueContext.init();
    defer kq_ctx.deinit();
    const ops = kq_ctx.eventLoopOps();
    const ctx: *anyopaque = @ptrCast(&kq_ctx);

    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    // write_fd will be closed explicitly below

    const read_fd = pipe_fds[0];
    const write_fd = pipe_fds[1];

    // Register read end
    try ops.registerRead(ctx, read_fd, 55);

    // Close write end → triggers EOF on read end
    std.posix.close(write_fd);

    var events: [4]interfaces.EventLoopOps.Event = undefined;
    const n = try ops.wait(ctx, &events, 100);

    // Verify: event fires with EV_EOF flag
    try testing.expect(n >= 1);
    try testing.expectEqual(read_fd, events[0].fd);
    try testing.expectEqual(@as(usize, 55), events[0].udata);
    try testing.expect((events[0].flags & std.c.EV.EOF) != 0);

    // Actually read to confirm 0 bytes (EOF)
    var buf: [16]u8 = undefined;
    const bytes_read = try std.posix.read(read_fd, &buf);
    try testing.expectEqual(@as(usize, 0), bytes_read);
}
