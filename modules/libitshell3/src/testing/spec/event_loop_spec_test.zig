//! Spec compliance tests: EventLoop, PriorityEventBuffer, and Handler chain.
//!
//! Covers EventLoop field constraints, run/stop behavior, priority-ordered
//! event buffering, handler chain forwarding/consuming, and EventTarget semantics.
//!
//! Spec source: event-loop-redesign spec.

const std = @import("std");
const server = @import("itshell3_server");
const test_mod = @import("itshell3_testing");

const EventLoop = server.handlers.EventLoop;
const Handler = server.handlers.Handler;
const interfaces = server.os.interfaces;
const Event = interfaces.Event;
const Filter = interfaces.Filter;
const EventTarget = interfaces.EventTarget;
const PriorityEventBuffer = server.os.priority_event_buffer.PriorityEventBuffer;
const MockEventLoopOps = test_mod.mock_os.MockEventLoopOps;

// ── Spec: EventLoop API ──────────────────────────────────────────────────────

test "spec: EventLoop — has no client state fields" {
    // EventLoop does NOT own client state — that belongs to ClientManager.
    const fields = @typeInfo(EventLoop).@"struct".fields;
    try std.testing.expectEqual(@as(usize, 4), fields.len);

    // Verify no field name contains "client"
    inline for (fields) |field| {
        if (comptime std.mem.indexOf(u8, field.name, "client") != null) {
            @compileError("EventLoop must not have client state fields");
        }
    }
}

test "spec: EventLoop — has no session_manager field" {
    const fields = @typeInfo(EventLoop).@"struct".fields;
    inline for (fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "session_manager")) {
            @compileError("EventLoop must not have a session_manager field");
        }
    }
}

test "spec: EventLoop — has no shutdown_requested field" {
    // stop() replaces shutdown_requested — no separate field needed.
    const fields = @typeInfo(EventLoop).@"struct".fields;
    inline for (fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "shutdown_requested")) {
            @compileError("EventLoop must not have a shutdown_requested field");
        }
    }
}

test "spec: EventLoop.run — iterates events from wait and calls handler chain" {
    const InvocationTracker = struct {
        events_seen: [8]std.posix.fd_t = [_]std.posix.fd_t{0} ** 8,
        count: u32 = 0,
        event_loop: ?*EventLoop = null,

        fn handle(context: *anyopaque, event: Event, next: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (self.count < 8) {
                self.events_seen[self.count] = event.fd;
            }
            self.count += 1;
            // Stop after processing all events in the batch
            if (self.count >= 3) {
                if (self.event_loop) |el| el.stop();
            }
            if (next) |n| n.invoke(event);
        }
    };

    var mock_event = MockEventLoopOps{
        .events_to_return = &[_]Event{
            .{ .fd = 10, .filter = .read, .target = .{ .listener = {} } },
            .{ .fd = 20, .filter = .write, .target = .{ .client = .{ .client_idx = 1 } } },
            .{ .fd = 30, .filter = .signal, .target = null },
        },
    };
    const ops = mock_event.ops();
    var dummy_ctx: u8 = 0;

    var tracker = InvocationTracker{};
    const handler = Handler{
        .handleFn = InvocationTracker.handle,
        .context = @ptrCast(&tracker),
        .next = null,
    };
    var el = EventLoop.init(&ops, @ptrCast(&dummy_ctx), &handler);
    tracker.event_loop = &el;

    try el.run();

    // All 3 events were delivered to the handler
    try std.testing.expectEqual(@as(u32, 3), tracker.count);
}

test "spec: EventLoop.stop — causes run to exit" {
    const StopHandler = struct {
        event_loop: ?*EventLoop = null,

        fn handle(context: *anyopaque, _: Event, _: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (self.event_loop) |el| el.stop();
        }
    };

    var mock_event = MockEventLoopOps{
        .events_to_return = &[_]Event{
            .{ .fd = 1, .filter = .read, .target = .{ .listener = {} } },
        },
    };
    const ops = mock_event.ops();
    var dummy_ctx: u8 = 0;

    var stop_handler = StopHandler{};
    const handler = Handler{
        .handleFn = StopHandler.handle,
        .context = @ptrCast(&stop_handler),
        .next = null,
    };
    var el = EventLoop.init(&ops, @ptrCast(&dummy_ctx), &handler);
    stop_handler.event_loop = &el;

    try el.run();

    // run() returned, meaning stop() caused the loop to exit
    try std.testing.expect(!el.running);
}

// ── Spec: PriorityEventBuffer ────────────────────────────────────────────────

test "spec: PriorityEventBuffer.add — places events in correct priority tier" {
    var buf = PriorityEventBuffer{};

    buf.add(.{ .fd = 1, .filter = .signal, .target = null });
    buf.add(.{ .fd = 2, .filter = .timer, .target = null });
    buf.add(.{ .fd = 3, .filter = .read, .target = .{ .listener = {} } });
    buf.add(.{ .fd = 4, .filter = .write, .target = .{ .client = .{ .client_idx = 0 } } });

    // Verify each tier got exactly one event
    try std.testing.expectEqual(@as(u32, 1), buf.sizes[@intFromEnum(Filter.signal)]);
    try std.testing.expectEqual(@as(u32, 1), buf.sizes[@intFromEnum(Filter.timer)]);
    try std.testing.expectEqual(@as(u32, 1), buf.sizes[@intFromEnum(Filter.read)]);
    try std.testing.expectEqual(@as(u32, 1), buf.sizes[@intFromEnum(Filter.write)]);

    // Verify the fd values landed in the right tier
    try std.testing.expectEqual(@as(std.posix.fd_t, 1), buf.buffers[@intFromEnum(Filter.signal)][0].fd);
    try std.testing.expectEqual(@as(std.posix.fd_t, 2), buf.buffers[@intFromEnum(Filter.timer)][0].fd);
    try std.testing.expectEqual(@as(std.posix.fd_t, 3), buf.buffers[@intFromEnum(Filter.read)][0].fd);
    try std.testing.expectEqual(@as(std.posix.fd_t, 4), buf.buffers[@intFromEnum(Filter.write)][0].fd);
}

test "spec: PriorityEventBuffer.iterator — yields events in SIGNAL > TIMER > READ > WRITE order" {
    var buf = PriorityEventBuffer{};

    // Insert in reverse priority order to prove the buffer reorders
    buf.add(.{ .fd = 40, .filter = .write, .target = null });
    buf.add(.{ .fd = 30, .filter = .read, .target = null });
    buf.add(.{ .fd = 20, .filter = .timer, .target = null });
    buf.add(.{ .fd = 10, .filter = .signal, .target = null });

    var iter = buf.iterator();

    // Must come out in priority order regardless of insertion order
    try std.testing.expectEqual(@as(std.posix.fd_t, 10), iter.next().?.fd); // signal
    try std.testing.expectEqual(@as(std.posix.fd_t, 20), iter.next().?.fd); // timer
    try std.testing.expectEqual(@as(std.posix.fd_t, 30), iter.next().?.fd); // read
    try std.testing.expectEqual(@as(std.posix.fd_t, 40), iter.next().?.fd); // write
    try std.testing.expect(iter.next() == null);
}

test "spec: PriorityEventBuffer.iterator — insertion order preserved within each tier" {
    var buf = PriorityEventBuffer{};

    buf.add(.{ .fd = 100, .filter = .read, .target = null });
    buf.add(.{ .fd = 200, .filter = .read, .target = null });
    buf.add(.{ .fd = 300, .filter = .read, .target = null });
    buf.add(.{ .fd = 50, .filter = .signal, .target = null });
    buf.add(.{ .fd = 60, .filter = .signal, .target = null });

    var iter = buf.iterator();

    // Signals first, in insertion order
    try std.testing.expectEqual(@as(std.posix.fd_t, 50), iter.next().?.fd);
    try std.testing.expectEqual(@as(std.posix.fd_t, 60), iter.next().?.fd);
    // Then reads, in insertion order
    try std.testing.expectEqual(@as(std.posix.fd_t, 100), iter.next().?.fd);
    try std.testing.expectEqual(@as(std.posix.fd_t, 200), iter.next().?.fd);
    try std.testing.expectEqual(@as(std.posix.fd_t, 300), iter.next().?.fd);
    try std.testing.expect(iter.next() == null);
}

test "spec: PriorityEventBuffer.reset — clears all tiers" {
    var buf = PriorityEventBuffer{};

    buf.add(.{ .fd = 1, .filter = .signal, .target = null });
    buf.add(.{ .fd = 2, .filter = .timer, .target = null });
    buf.add(.{ .fd = 3, .filter = .read, .target = null });
    buf.add(.{ .fd = 4, .filter = .write, .target = null });

    try std.testing.expect(!buf.isEmpty());

    buf.reset();

    // All sizes must be zero
    for (buf.sizes) |size| {
        try std.testing.expectEqual(@as(u32, 0), size);
    }
    // isEmpty must return true
    try std.testing.expect(buf.isEmpty());

    // Iterator must yield nothing
    var iter = buf.iterator();
    try std.testing.expect(iter.next() == null);
}

test "spec: PriorityEventBuffer.isEmpty — correct before and after adds" {
    var buf = PriorityEventBuffer{};

    // Fresh buffer is empty
    try std.testing.expect(buf.isEmpty());

    // After adding any event, no longer empty
    buf.add(.{ .fd = 1, .filter = .write, .target = null });
    try std.testing.expect(!buf.isEmpty());

    // Adding to a different tier: still not empty
    buf.add(.{ .fd = 2, .filter = .signal, .target = null });
    try std.testing.expect(!buf.isEmpty());
}

test "spec: PriorityEventBuffer.add — full tier silently drops without crash" {
    var buf = PriorityEventBuffer{};

    // Fill the signal tier to capacity
    for (0..interfaces.MAX_EVENTS_PER_BATCH) |i| {
        buf.add(.{ .fd = @intCast(i), .filter = .signal, .target = null });
    }
    try std.testing.expectEqual(@as(u32, interfaces.MAX_EVENTS_PER_BATCH), buf.sizes[0]);

    // One more should be silently dropped (no crash, no error)
    buf.add(.{ .fd = 999, .filter = .signal, .target = null });
    try std.testing.expectEqual(@as(u32, interfaces.MAX_EVENTS_PER_BATCH), buf.sizes[0]);

    // Other tiers should be unaffected
    try std.testing.expectEqual(@as(u32, 0), buf.sizes[1]);
    try std.testing.expectEqual(@as(u32, 0), buf.sizes[2]);
    try std.testing.expectEqual(@as(u32, 0), buf.sizes[3]);
}

// ── Spec: Handler Chain ──────────────────────────────────────────────────────

test "spec: Handler.invoke — calls handleFn with correct context and next" {
    const Ctx = struct {
        received_fd: std.posix.fd_t = -1,
        received_next: bool = false,

        fn handle(context: *anyopaque, event: Event, next: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.received_fd = event.fd;
            self.received_next = (next != null);
        }
    };

    var ctx = Ctx{};
    const sentinel_handler = Handler{
        .handleFn = Ctx.handle,
        .context = @ptrCast(&ctx),
        .next = null,
    };

    // Create a handler with a non-null next to verify it is passed through
    var dummy_ctx = Ctx{};
    const next_handler = Handler{
        .handleFn = Ctx.handle,
        .context = @ptrCast(&dummy_ctx),
        .next = null,
    };

    const handler_with_next = Handler{
        .handleFn = Ctx.handle,
        .context = @ptrCast(&ctx),
        .next = &next_handler,
    };

    // Test with null next
    sentinel_handler.invoke(.{ .fd = 42, .filter = .read, .target = null });
    try std.testing.expectEqual(@as(std.posix.fd_t, 42), ctx.received_fd);
    try std.testing.expect(!ctx.received_next);

    // Test with non-null next
    ctx.received_fd = -1;
    ctx.received_next = false;
    handler_with_next.invoke(.{ .fd = 77, .filter = .signal, .target = null });
    try std.testing.expectEqual(@as(std.posix.fd_t, 77), ctx.received_fd);
    try std.testing.expect(ctx.received_next);
}

test "spec: Handler chain — first handler can forward to next" {
    const ForwardingCtx = struct {
        invoked: bool = false,

        fn handle(context: *anyopaque, event: Event, next: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.invoked = true;
            // Forward to next handler
            if (next) |n| n.invoke(event);
        }
    };

    const ConsumingCtx = struct {
        invoked: bool = false,
        received_fd: std.posix.fd_t = -1,

        fn handle(context: *anyopaque, event: Event, _: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.invoked = true;
            self.received_fd = event.fd;
            // Consumes: does not call next
        }
    };

    var second = ConsumingCtx{};
    const second_handler = Handler{
        .handleFn = ConsumingCtx.handle,
        .context = @ptrCast(&second),
        .next = null,
    };

    var first = ForwardingCtx{};
    const first_handler = Handler{
        .handleFn = ForwardingCtx.handle,
        .context = @ptrCast(&first),
        .next = &second_handler,
    };

    first_handler.invoke(.{ .fd = 55, .filter = .timer, .target = null });

    try std.testing.expect(first.invoked);
    try std.testing.expect(second.invoked);
    try std.testing.expectEqual(@as(std.posix.fd_t, 55), second.received_fd);
}

test "spec: Handler chain — unhandled event completes without error" {
    // Unhandled events are silently dropped — a normal condition during
    // incremental plan implementation.
    const PassthroughCtx = struct {
        fn handle(_: *anyopaque, event: Event, next: ?*const Handler) void {
            // Does not recognize the event, tries to forward
            if (next) |n| n.invoke(event);
            // next is null, event is silently dropped -- no crash, no error
        }
    };

    var dummy: u8 = 0;
    const handler = Handler{
        .handleFn = PassthroughCtx.handle,
        .context = @ptrCast(&dummy),
        .next = null,
    };

    // This must not crash or error
    handler.invoke(.{ .fd = 99, .filter = .write, .target = .{ .client = .{ .client_idx = 5 } } });
}

test "spec: Handler chain — handler can consume event without forwarding" {
    // A consuming handler that does NOT call next prevents downstream handlers
    // from receiving the event.
    const ConsumingCtx = struct {
        consumed: bool = false,

        fn handle(context: *anyopaque, _: Event, _: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.consumed = true;
            // Intentionally does NOT call next
        }
    };

    const NeverReachedCtx = struct {
        reached: bool = false,

        fn handle(context: *anyopaque, _: Event, _: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.reached = true;
        }
    };

    var never_reached = NeverReachedCtx{};
    const second_handler = Handler{
        .handleFn = NeverReachedCtx.handle,
        .context = @ptrCast(&never_reached),
        .next = null,
    };

    var consumer = ConsumingCtx{};
    const first_handler = Handler{
        .handleFn = ConsumingCtx.handle,
        .context = @ptrCast(&consumer),
        .next = &second_handler,
    };

    first_handler.invoke(.{ .fd = 7, .filter = .read, .target = .{ .pty = .{ .session_idx = 0, .pane_slot = 1 } } });

    try std.testing.expect(consumer.consumed);
    try std.testing.expect(!never_reached.reached);
}

// ── Spec: EventTarget ────────────────────────────────────────────────────────

test "spec: EventTarget — Event.target is optional" {
    const event = Event{
        .fd = 42,
        .filter = .read,
        .target = null,
    };
    try std.testing.expect(event.target == null);

    // An Event with non-null target
    const event_with_target = Event{
        .fd = 43,
        .filter = .read,
        .target = .{ .listener = {} },
    };
    try std.testing.expect(event_with_target.target != null);
}

test "spec: EventTarget — signal events have null target" {
    // Signal events carry the signal number in the fd field; handlers dispatch
    // via event.filter == .signal, not by matching on event.target.
    const sigchld_event = Event{
        .fd = 20, // SIGCHLD number carried in fd
        .filter = .signal,
        .target = null,
    };

    // Signal events are identified by filter, not target
    try std.testing.expectEqual(Filter.signal, sigchld_event.filter);
    try std.testing.expect(sigchld_event.target == null);

    // Handlers match on filter for signals
    const is_signal = sigchld_event.filter == .signal;
    try std.testing.expect(is_signal);
}
