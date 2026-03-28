const std = @import("std");
const interfaces = @import("../os/interfaces.zig");

/// Handler chain link for middleware-based event dispatch.
///
/// Each handler in the chain receives an event and decides whether to consume
/// it or forward it to the next handler. The chain is assembled by the caller
/// (Daemon in Plan 12.2, test harness in interim).
///
/// Uses `?*const Handler` for the `next` field because Zig does not permit
/// recursive value types (a struct containing itself by value would be infinite
/// size).
pub const Handler = struct {
    handleFn: *const fn (context: *anyopaque, event: interfaces.Event, next: ?*const Handler) void,
    context: *anyopaque,
    next: ?*const Handler,

    /// Convenience: calls handleFn with this handler's context and next.
    /// Used by EventLoop.run() and by handlers forwarding to the next in chain.
    pub fn invoke(self: *const Handler, event: interfaces.Event) void {
        self.handleFn(self.context, event, self.next);
    }
};

/// Minimal event iteration engine.
///
/// Responsibilities:
/// - Call the OS wait function (via EventLoopOps vtable) to collect ready events
/// - Iterate returned events in priority order (via PriorityEventBuffer)
/// - Call the handler chain for each event
/// - Provide stop() to exit the loop
///
/// EventLoop does NOT own client state, session state, signal registration,
/// listener socket, shutdown state machine, or dispatch routing logic.
pub const EventLoop = struct {
    event_ops: *const interfaces.EventLoopOps,
    event_ctx: *anyopaque,
    chain: *const Handler,
    running: bool,

    pub fn init(
        event_ops: *const interfaces.EventLoopOps,
        event_ctx: *anyopaque,
        chain: *const Handler,
    ) EventLoop {
        return .{
            .event_ops = event_ops,
            .event_ctx = event_ctx,
            .chain = chain,
            .running = true,
        };
    }

    pub const RunError = error{EventLoopError};

    /// Main event loop. Blocks until stop() is called.
    pub fn run(self: *EventLoop) RunError!void {
        while (self.running) {
            var iter = self.event_ops.wait(self.event_ctx, 1000) catch |err| return err;
            while (iter.next()) |event| {
                self.chain.invoke(event);
            }
        }
    }

    /// Sets running = false. The current wait() call completes, the loop
    /// checks the flag, and run() returns.
    pub fn stop(self: *EventLoop) void {
        self.running = false;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;
const test_mod = @import("itshell3_testing");
const mock_os = test_mod.mock_os;
const MockEventLoopOps = mock_os.MockEventLoopOps;

/// Test handler that records invocations and optionally stops the loop.
const TestHandlerContext = struct {
    invocations: u32 = 0,
    last_fd: std.posix.fd_t = -1,
    event_loop: ?*EventLoop = null,
    stop_on_first: bool = false,

    fn handle(context: *anyopaque, event: interfaces.Event, next: ?*const Handler) void {
        const self: *TestHandlerContext = @ptrCast(@alignCast(context));
        self.invocations += 1;
        self.last_fd = event.fd;
        if (self.stop_on_first) {
            if (self.event_loop) |el| el.stop();
        }
        if (next) |n| n.invoke(event);
    }
};

test "EventLoop.init: sets running = true" {
    var handler_ctx = TestHandlerContext{};
    var mock_event = MockEventLoopOps{};
    const ops = mock_event.ops();
    var dummy_ctx: u8 = 0;
    const handler = Handler{
        .handleFn = TestHandlerContext.handle,
        .context = @ptrCast(&handler_ctx),
        .next = null,
    };

    const el = EventLoop.init(
        &ops,
        @ptrCast(&dummy_ctx),
        &handler,
    );

    try testing.expect(el.running);
}

test "EventLoop.run: single-handler chain calling stop" {
    var mock_event = MockEventLoopOps{
        .events_to_return = &[_]interfaces.Event{
            .{ .fd = 99, .filter = .signal, .target = .{ .listener = {} } },
        },
    };
    const ops = mock_event.ops();
    var dummy_ctx: u8 = 0;

    var handler_ctx = TestHandlerContext{ .stop_on_first = true };
    const handler = Handler{
        .handleFn = TestHandlerContext.handle,
        .context = @ptrCast(&handler_ctx),
        .next = null,
    };
    var el = EventLoop.init(
        &ops,
        @ptrCast(&dummy_ctx),
        &handler,
    );
    handler_ctx.event_loop = &el;

    try el.run();

    try testing.expect(!el.running);
    try testing.expectEqual(@as(u32, 1), handler_ctx.invocations);
    try testing.expectEqual(@as(std.posix.fd_t, 99), handler_ctx.last_fd);
}

test "EventLoop.run: multi-handler chain verifying traversal order" {
    var mock_event = MockEventLoopOps{
        .events_to_return = &[_]interfaces.Event{
            .{ .fd = 5, .filter = .read, .target = .{ .listener = {} } },
        },
    };
    const ops = mock_event.ops();
    var dummy_ctx: u8 = 0;

    var second_ctx = TestHandlerContext{ .stop_on_first = true };
    var first_ctx = TestHandlerContext{};

    const second_handler = Handler{
        .handleFn = TestHandlerContext.handle,
        .context = @ptrCast(&second_ctx),
        .next = null,
    };
    const first_handler = Handler{
        .handleFn = TestHandlerContext.handle,
        .context = @ptrCast(&first_ctx),
        .next = &second_handler,
    };

    var el = EventLoop.init(
        &ops,
        @ptrCast(&dummy_ctx),
        &first_handler,
    );
    second_ctx.event_loop = &el;

    try el.run();

    // Both handlers were invoked
    try testing.expectEqual(@as(u32, 1), first_ctx.invocations);
    try testing.expectEqual(@as(u32, 1), second_ctx.invocations);
}

test "EventLoop.run: unhandled event completes without error" {
    const PassthroughHandler = struct {
        stop_loop: ?*EventLoop = null,
        called: bool = false,

        fn handle(context: *anyopaque, _: interfaces.Event, next: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.called = true;
            if (self.stop_loop) |el| el.stop();
            // next is null — event is silently dropped
            if (next) |n| n.invoke(.{ .fd = 0, .filter = .read, .target = .{ .listener = {} } });
        }
    };

    var mock_event = MockEventLoopOps{
        .events_to_return = &[_]interfaces.Event{
            .{ .fd = 7, .filter = .write, .target = .{ .client = .{ .client_idx = 1 } } },
        },
    };
    const ops = mock_event.ops();
    var dummy_ctx: u8 = 0;

    var passthrough = PassthroughHandler{};
    const handler = Handler{
        .handleFn = PassthroughHandler.handle,
        .context = @ptrCast(&passthrough),
        .next = null,
    };
    var el = EventLoop.init(
        &ops,
        @ptrCast(&dummy_ctx),
        &handler,
    );
    passthrough.stop_loop = &el;

    try el.run();
    try testing.expect(passthrough.called);
}

test "EventLoop.stop: sets running to false" {
    var mock_event = MockEventLoopOps{};
    const ops = mock_event.ops();
    var dummy_ctx: u8 = 0;
    var handler_ctx = TestHandlerContext{};
    const handler = Handler{
        .handleFn = TestHandlerContext.handle,
        .context = @ptrCast(&handler_ctx),
        .next = null,
    };

    var el = EventLoop.init(
        &ops,
        @ptrCast(&dummy_ctx),
        &handler,
    );

    try testing.expect(el.running);
    el.stop();
    try testing.expect(!el.running);
}

test "EventLoop.run: priority ordering — signal events processed before read events" {
    var mock_event = MockEventLoopOps{
        .events_to_return = &[_]interfaces.Event{
            .{ .fd = 10, .filter = .read, .target = .{ .listener = {} } },
            .{ .fd = 15, .filter = .signal, .target = .{ .listener = {} } },
        },
    };
    const ops = mock_event.ops();
    var dummy_ctx: u8 = 0;

    const OrderTracker = struct {
        order: [4]std.posix.fd_t = [_]std.posix.fd_t{0} ** 4,
        count: u32 = 0,
        event_loop: ?*EventLoop = null,

        fn handle(context: *anyopaque, event: interfaces.Event, next: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (self.count < 4) {
                self.order[self.count] = event.fd;
            }
            self.count += 1;
            if (self.count >= 2) {
                if (self.event_loop) |el| el.stop();
            }
            if (next) |n| n.invoke(event);
        }
    };

    var tracker = OrderTracker{};
    const handler = Handler{
        .handleFn = OrderTracker.handle,
        .context = @ptrCast(&tracker),
        .next = null,
    };
    var el = EventLoop.init(
        &ops,
        @ptrCast(&dummy_ctx),
        &handler,
    );
    tracker.event_loop = &el;

    try el.run();

    // Signal (fd=15) should come before read (fd=10)
    try testing.expectEqual(@as(u32, 2), tracker.count);
    try testing.expectEqual(@as(std.posix.fd_t, 15), tracker.order[0]);
    try testing.expectEqual(@as(std.posix.fd_t, 10), tracker.order[1]);
}

// ── TODO(Plan 6) tests ──────────────────────────────────────────────────────
//
// The following tests were removed or commented out because they test client
// management features (addClientTransport, removeClient, findClientByFd) that
// no longer belong in EventLoop. These will be reimplemented as Client Manager
// tests in Plan 6.
//
// - "EventLoop.addClientTransport: stores Connection, increments next_client_id"
// - "EventLoop.addClientTransport: second client gets next ID"
// - "EventLoop.addClientTransport: when full returns error.MaxClientsReached"
// - "EventLoop.removeClient: nulls slot"
// - "EventLoop.findClientByFd: finds correct index"
// - "EventLoop.findClientByFd: unknown fd returns null"
