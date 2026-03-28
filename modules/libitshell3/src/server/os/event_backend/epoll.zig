const std = @import("std");
const builtin = @import("builtin");
const interfaces = @import("../interfaces.zig");
const PriorityEventBuffer = @import("../priority_event_buffer.zig").PriorityEventBuffer;
const core = @import("itshell3_core");
const types = core.types;

// ── Encoding constants ─────────────────────────────────────────────────────

/// Bit position for the tag field in epoll u64 data encoding.
const TAG_SHIFT: u6 = 60;
/// Bit position for the primary index (session_idx, client_idx, timer_id, signal_number).
const PRIMARY_SHIFT: u6 = 44;
/// Bit position for the secondary index (pane_slot in PTY targets).
const SECONDARY_SHIFT: u6 = 36;
/// Mask for the fd stored in the lower 32 bits.
const FD_MASK: u64 = 0xFFFF_FFFF;
/// Mask for a 16-bit field.
const FIELD_16_MASK: u64 = 0xFFFF;
/// Mask for a PaneSlot-width field (8-bit).
const PANE_SLOT_MASK: u64 = std.math.maxInt(types.PaneSlot);

/// Tag values for EventTarget variants in epoll u64 encoding.
const TAG_LISTENER: u4 = 0;
const TAG_PTY: u4 = 1;
const TAG_CLIENT: u4 = 2;
const TAG_TIMER: u4 = 3;
const TAG_NULL: u4 = 4;

// ── Linux: epoll ───────────────────────────────────────────────────────────

pub const EpollContext = struct {
    ep_fd: std.posix.fd_t,
    event_buffer: PriorityEventBuffer = .{},

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

/// Encode an optional EventTarget into a u64 for epoll_event.data.
/// Encoding scheme (internal to epoll backend):
///   Layout: upper 32 bits = tag + type data, lower 32 bits = fd
///   Tag in bits[63:60]:
///     0 = listener
///     1 = pty (session_idx in [59:44], pane_slot in [43:36])
///     2 = client (client_idx in [59:44])
///     3 = timer (timer_id in [59:44])
///     4 = null (no target)
///   Lower 32 bits = fd (stored so we can reconstruct it on output)
fn epEncodeTarget(fd: std.posix.fd_t, target: ?interfaces.EventTarget) u64 {
    const fd_bits: u64 = @as(u64, @intCast(fd)) & FD_MASK;
    const t = target orelse return (@as(u64, TAG_NULL) << TAG_SHIFT) | fd_bits;
    return switch (t) {
        .listener => (@as(u64, TAG_LISTENER) << TAG_SHIFT) | fd_bits,
        .pty => |p| (@as(u64, TAG_PTY) << TAG_SHIFT) | (@as(u64, p.session_idx) << PRIMARY_SHIFT) | (@as(u64, p.pane_slot) << SECONDARY_SHIFT) | fd_bits,
        .client => |c| (@as(u64, TAG_CLIENT) << TAG_SHIFT) | (@as(u64, c.client_idx) << PRIMARY_SHIFT) | fd_bits,
        .timer => |t_inner| (@as(u64, TAG_TIMER) << TAG_SHIFT) | (@as(u64, t_inner.timer_id) << PRIMARY_SHIFT) | fd_bits,
    };
}

/// Decode a u64 from epoll_event.data back to fd + optional EventTarget.
fn epDecodeData(raw: u64) struct { fd: std.posix.fd_t, target: ?interfaces.EventTarget } {
    const tag: u4 = @intCast((raw >> TAG_SHIFT) & 0xF);
    const stored_fd: std.posix.fd_t = @intCast(raw & FD_MASK);
    const target: ?interfaces.EventTarget = switch (tag) {
        TAG_LISTENER => .{ .listener = {} },
        TAG_PTY => .{ .pty = .{
            .session_idx = @intCast((raw >> PRIMARY_SHIFT) & FIELD_16_MASK),
            .pane_slot = @intCast((raw >> SECONDARY_SHIFT) & PANE_SLOT_MASK),
        } },
        TAG_CLIENT => .{ .client = .{ .client_idx = @intCast((raw >> PRIMARY_SHIFT) & FIELD_16_MASK) } },
        TAG_TIMER => .{ .timer = .{ .timer_id = @intCast((raw >> PRIMARY_SHIFT) & FIELD_16_MASK) } },
        TAG_NULL => null,
        else => .{ .listener = {} },
    };
    return .{ .fd = stored_fd, .target = target };
}

fn epRegisterRead(ctx: *anyopaque, fd: std.posix.fd_t, target: ?interfaces.EventTarget) interfaces.EventLoopOps.RegisterError!void {
    if (comptime builtin.os.tag != .linux) unreachable;
    const ep = toEpCtx(ctx).ep_fd;
    var ev = std.os.linux.epoll_event{
        .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.HUP | std.os.linux.EPOLL.ERR | std.os.linux.EPOLL.RDHUP,
        .data = .{ .u64 = epEncodeTarget(fd, target) },
    };
    std.posix.epoll_ctl(ep, std.os.linux.EPOLL.CTL_ADD, fd, &ev) catch return error.EventLoopError;
}

fn epRegisterWrite(ctx: *anyopaque, fd: std.posix.fd_t, target: ?interfaces.EventTarget) interfaces.EventLoopOps.RegisterError!void {
    if (comptime builtin.os.tag != .linux) unreachable;
    const ep = toEpCtx(ctx).ep_fd;
    var ev = std.os.linux.epoll_event{
        .events = std.os.linux.EPOLL.OUT | std.os.linux.EPOLL.HUP | std.os.linux.EPOLL.ERR | std.os.linux.EPOLL.RDHUP,
        .data = .{ .u64 = epEncodeTarget(fd, target) },
    };
    std.posix.epoll_ctl(ep, std.os.linux.EPOLL.CTL_ADD, fd, &ev) catch return error.EventLoopError;
}

fn epUnregister(ctx: *anyopaque, fd: std.posix.fd_t) void {
    if (comptime builtin.os.tag != .linux) unreachable;
    const ep = toEpCtx(ctx).ep_fd;
    std.posix.epoll_ctl(ep, std.os.linux.EPOLL.CTL_DEL, fd, null) catch {};
}

fn epWait(ctx: *anyopaque, timeout_ms: ?u32) interfaces.EventLoopOps.WaitError!PriorityEventBuffer.Iterator {
    if (comptime builtin.os.tag != .linux) unreachable;
    const ep_ctx = toEpCtx(ctx);
    const ep = ep_ctx.ep_fd;

    var ep_buf: [interfaces.MAX_EVENTS_PER_BATCH]std.os.linux.epoll_event = undefined;
    const timeout: i32 = if (timeout_ms) |ms| @intCast(ms) else -1;

    const n = std.posix.epoll_wait(ep, &ep_buf, timeout);

    ep_ctx.event_buffer.reset();

    for (ep_buf[0..n]) |ep_ev| {
        const ev_flags = ep_ev.events;
        const filter: interfaces.Filter = if ((ev_flags & std.os.linux.EPOLL.OUT) != 0)
            .write
        else
            .read;

        // Encode HUP/ERR into the flags field (analogous to kqueue EV_EOF / EV_ERROR).
        var flags: u16 = 0;
        if ((ev_flags & std.os.linux.EPOLL.HUP) != 0) flags |= 0x8000;
        if ((ev_flags & std.os.linux.EPOLL.ERR) != 0) flags |= 0x4000;

        const decoded = epDecodeData(ep_ev.data.u64);

        ep_ctx.event_buffer.add(.{
            .fd = decoded.fd,
            .filter = filter,
            .target = decoded.target,
            .flags = flags,
            .data = 0, // epoll does not report bytes available
        });
    }

    return ep_ctx.event_buffer.iterator();
}

// ── Tests ──────────────────────────────────────────────────────────────────

const testing = std.testing;

test "epEncodeTarget and epDecodeData: round-trip all variants" {
    // listener
    {
        const target: ?interfaces.EventTarget = .{ .listener = {} };
        const encoded = epEncodeTarget(7, target);
        const decoded = epDecodeData(encoded);
        try testing.expectEqual(@as(std.posix.fd_t, 7), decoded.fd);
        if (decoded.target) |dec| {
            switch (dec) {
                .listener => {},
                else => return error.TestUnexpectedResult,
            }
        } else return error.TestUnexpectedResult;
    }

    // pty
    {
        const target: ?interfaces.EventTarget = .{ .pty = .{ .session_idx = 10, .pane_slot = 3 } };
        const encoded = epEncodeTarget(42, target);
        const decoded = epDecodeData(encoded);
        try testing.expectEqual(@as(std.posix.fd_t, 42), decoded.fd);
        if (decoded.target) |dec| {
            switch (dec) {
                .pty => |p| {
                    try testing.expectEqual(@as(u16, 10), p.session_idx);
                    try testing.expectEqual(@as(u8, 3), p.pane_slot);
                },
                else => return error.TestUnexpectedResult,
            }
        } else return error.TestUnexpectedResult;
    }

    // client
    {
        const target: ?interfaces.EventTarget = .{ .client = .{ .client_idx = 63 } };
        const encoded = epEncodeTarget(100, target);
        const decoded = epDecodeData(encoded);
        try testing.expectEqual(@as(std.posix.fd_t, 100), decoded.fd);
        if (decoded.target) |dec| {
            switch (dec) {
                .client => |c| try testing.expectEqual(@as(u16, 63), c.client_idx),
                else => return error.TestUnexpectedResult,
            }
        } else return error.TestUnexpectedResult;
    }

    // timer
    {
        const target: ?interfaces.EventTarget = .{ .timer = .{ .timer_id = 999 } };
        const encoded = epEncodeTarget(55, target);
        const decoded = epDecodeData(encoded);
        try testing.expectEqual(@as(std.posix.fd_t, 55), decoded.fd);
        if (decoded.target) |dec| {
            switch (dec) {
                .timer => |t| try testing.expectEqual(@as(u16, 999), t.timer_id),
                else => return error.TestUnexpectedResult,
            }
        } else return error.TestUnexpectedResult;
    }

    // null
    {
        const encoded = epEncodeTarget(200, null);
        const decoded = epDecodeData(encoded);
        try testing.expectEqual(@as(std.posix.fd_t, 200), decoded.fd);
        try testing.expect(decoded.target == null);
    }
}

test "epEncodeTarget and epDecodeData: pty boundary values" {
    // max session_idx (u16 max) and max pane_slot (u8 max)
    const target = interfaces.EventTarget{ .pty = .{
        .session_idx = std.math.maxInt(u16),
        .pane_slot = std.math.maxInt(types.PaneSlot),
    } };
    const encoded = epEncodeTarget(1, target);
    const decoded = epDecodeData(encoded);
    try testing.expectEqual(@as(std.posix.fd_t, 1), decoded.fd);
    if (decoded.target) |dec| {
        switch (dec) {
            .pty => |p| {
                try testing.expectEqual(std.math.maxInt(u16), p.session_idx);
                try testing.expectEqual(std.math.maxInt(types.PaneSlot), p.pane_slot);
            },
            else => return error.TestUnexpectedResult,
        }
    } else return error.TestUnexpectedResult;
}

test "epEncodeTarget and epDecodeData: fd preserved in lower 32 bits" {
    // Use a large fd value to verify the lower 32-bit mask works
    const target = interfaces.EventTarget{ .client = .{ .client_idx = 1 } };
    const large_fd: std.posix.fd_t = 0x7FFF_FFFF; // max positive i32
    const encoded = epEncodeTarget(large_fd, target);
    const decoded = epDecodeData(encoded);
    try testing.expectEqual(large_fd, decoded.fd);
}

test "epEncodeTarget/epDecodeData: null target round-trip" {
    const encoded = epEncodeTarget(5, null);
    const decoded = epDecodeData(encoded);
    try testing.expectEqual(@as(std.posix.fd_t, 5), decoded.fd);
    try testing.expect(decoded.target == null);
}

test "epEncodeTarget/epDecodeData: null vs listener non-collision" {
    const null_encoded = epEncodeTarget(5, null);
    const listener_encoded = epEncodeTarget(5, .{ .listener = {} });
    try testing.expect(null_encoded != listener_encoded);
}

test "epEncodeTarget/epDecodeData: null vs pty boundary non-collision" {
    const null_encoded = epEncodeTarget(5, null);
    const pty_max_encoded = epEncodeTarget(5, .{ .pty = .{
        .session_idx = std.math.maxInt(u16),
        .pane_slot = std.math.maxInt(types.PaneSlot),
    } });
    try testing.expect(null_encoded != pty_max_encoded);
}

test "epEncodeTarget/epDecodeData: null vs client boundary non-collision" {
    const null_encoded = epEncodeTarget(5, null);
    const client_max_encoded = epEncodeTarget(5, .{ .client = .{
        .client_idx = std.math.maxInt(u16),
    } });
    try testing.expect(null_encoded != client_max_encoded);
}

test "epEncodeTarget/epDecodeData: null vs timer boundary non-collision" {
    const null_encoded = epEncodeTarget(5, null);
    const timer_max_encoded = epEncodeTarget(5, .{ .timer = .{
        .timer_id = std.math.maxInt(u16),
    } });
    try testing.expect(null_encoded != timer_max_encoded);
}

test "epEncodeTarget/epDecodeData: all variants produce distinct udata ranges" {
    const fd: std.posix.fd_t = 5;
    const null_val = epEncodeTarget(fd, null);
    const listener_val = epEncodeTarget(fd, .{ .listener = {} });
    const pty_val = epEncodeTarget(fd, .{ .pty = .{ .session_idx = 0, .pane_slot = 0 } });
    const client_val = epEncodeTarget(fd, .{ .client = .{ .client_idx = 0 } });
    const timer_val = epEncodeTarget(fd, .{ .timer = .{ .timer_id = 0 } });

    const all = [_]u64{ null_val, listener_val, pty_val, client_val, timer_val };
    // Verify no two values are the same.
    for (all, 0..) |a, i| {
        for (all, 0..) |b, j| {
            if (i != j) try testing.expect(a != b);
        }
    }
}

// ── Linux-only integration tests ───────────────────────────────────────────
// These tests exercise EpollContext with real pipes and are skipped on non-Linux.

/// Helper: create a pipe pair. Returns .{read_fd, write_fd}.
fn createPipe() ![2]std.posix.fd_t {
    return std.posix.pipe() catch return error.EventLoopError;
}

test "EpollContext: registerRead pipe write event detected and target verified" {
    if (comptime builtin.os.tag != .linux) return;

    var ctx = try EpollContext.init();
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
    if (event.?.target) |decoded_target| {
        switch (decoded_target) {
            .client => |c| try testing.expectEqual(@as(u16, 42), c.client_idx),
            else => return error.TestUnexpectedResult,
        }
    } else return error.TestUnexpectedResult;

    var buf: [16]u8 = undefined;
    const bytes_read = try std.posix.read(read_fd, &buf);
    try testing.expectEqual(@as(usize, 5), bytes_read);
    try testing.expectEqualSlices(u8, "hello", buf[0..bytes_read]);
}

test "EpollContext: registerWrite immediately writable and write succeeds" {
    if (comptime builtin.os.tag != .linux) return;

    var ctx = try EpollContext.init();
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
    if (event.?.target) |decoded_target| {
        switch (decoded_target) {
            .client => |c| try testing.expectEqual(@as(u16, 77), c.client_idx),
            else => return error.TestUnexpectedResult,
        }
    } else return error.TestUnexpectedResult;

    const bytes_written = try std.posix.write(write_fd, "test");
    try testing.expect(bytes_written > 0);
}

test "EpollContext: unregister no event after write" {
    if (comptime builtin.os.tag != .linux) return;

    var ctx = try EpollContext.init();
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

test "EpollContext: timeout with no events returns empty iterator" {
    if (comptime builtin.os.tag != .linux) return;

    var ctx = try EpollContext.init();
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

test "EpollContext: multiple fds correct target routing" {
    if (comptime builtin.os.tag != .linux) return;

    var ctx = try EpollContext.init();
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
                        try testing.expectEqual(@as(u16, 1), p.session_idx);
                        try testing.expectEqual(@as(u8, 2), p.pane_slot);
                    },
                    else => return error.TestUnexpectedResult,
                }
            } else return error.TestUnexpectedResult;
            found_pipe1 = true;
        }
        if (event.fd == pipe2[0]) {
            if (event.target) |target| {
                switch (target) {
                    .client => |c| try testing.expectEqual(@as(u16, 5), c.client_idx),
                    else => return error.TestUnexpectedResult,
                }
            } else return error.TestUnexpectedResult;
            found_pipe2 = true;
        }
    }

    try testing.expect(found_pipe1);
    try testing.expect(found_pipe2);
}

test "EpollContext: EOF detection when write end is closed" {
    if (comptime builtin.os.tag != .linux) return;

    var ctx = try EpollContext.init();
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
