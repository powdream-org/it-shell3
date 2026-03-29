//! Signal chain handler. SIGCHLD drains exited children and marks panes;
//! SIGTERM/SIGINT/SIGHUP stop the event loop for graceful shutdown.

const std = @import("std");
const interfaces = @import("../os/interfaces.zig");
const core = @import("itshell3_core");
const types = core.types;
const session_manager_mod = @import("../state/session_manager.zig");
const event_loop_mod = @import("event_loop.zig");

pub const SessionManager = session_manager_mod.SessionManager;
const Handler = event_loop_mod.Handler;

/// Context for the signal handler chain link.
pub const SignalHandlerContext = struct {
    signal_ops: *const interfaces.SignalOps,
    session_manager: *SessionManager,
    event_loop: *event_loop_mod.EventLoop,
};

/// Chain handler entry point for signal events.
/// Matches on event.filter == .signal. If the event is not a signal,
/// forwards to the next handler in the chain.
pub fn chainHandle(context: *anyopaque, event: interfaces.Event, next: ?*const Handler) void {
    if (event.filter != .signal) {
        if (next) |n| n.invoke(event);
        return;
    }
    const ctx: *SignalHandlerContext = @ptrCast(@alignCast(context));
    handleSignalEvent(event, ctx.signal_ops, ctx.session_manager, ctx.event_loop);
}

/// Handles SIGCHLD by reaping children and marking panes exited, and
/// SIGTERM/SIGINT/SIGHUP by stopping the event loop.
pub fn handleSignalEvent(
    event: interfaces.Event,
    signal_ops: *const interfaces.SignalOps,
    session_manager: *SessionManager,
    event_loop: *event_loop_mod.EventLoop,
) void {
    // The signal number is carried in the fd field (as registered via kqueue
    // EVFILT_SIGNAL where ident = signal number).
    const sig: u32 = @intCast(event.fd);

    switch (sig) {
        std.posix.SIG.CHLD => {
            // Drain all exited children
            while (signal_ops.waitChild()) |result| {
                markPaneExited(session_manager, result.pid, result.exit_status);
            }
        },
        std.posix.SIG.TERM, std.posix.SIG.INT, std.posix.SIG.HUP => {
            // TODO(Plan 10): Graceful shutdown procedure (client drain, preedit
            // flush, child SIGHUP forwarding) before calling stop().
            event_loop.stop();
        },
        else => {},
    }
}

fn markPaneExited(sm: *SessionManager, pid: std.posix.pid_t, exit_status: u8) void {
    for (&sm.sessions) |*slot| {
        if (slot.*) |*entry| {
            var i: u32 = 0;
            while (i < types.MAX_PANES) : (i += 1) {
                if (entry.pane_slots[i]) |*pane| {
                    if (pane.child_pid == pid) {
                        pane.markExited(exit_status);
                        return;
                    }
                }
            }
        }
    }
}

// --- Tests ---

const testing = std.testing;
const test_mod = @import("itshell3_testing");
const mock_os = test_mod.mock_os;
const test_helpers = test_mod.helpers;
const pane_mod = @import("../state/pane.zig");
const session_mod = core.session;

// File-scope statics for tests.
var test_sm = SessionManager.init();

const testImeEngine = test_helpers.testImeEngine;

const MockEventLoopOps = mock_os.MockEventLoopOps;

// File-scope statics for makeTestEventLoop.
var test_dummy_ctx: u8 = 0;
var test_mock_event = MockEventLoopOps{};
var test_mock_ops: interfaces.EventLoopOps = undefined;
var test_mock_ops_initialized: bool = false;
const test_dummy_handler = event_loop_mod.Handler{
    .handleFn = struct {
        fn f(_: *anyopaque, _: interfaces.Event, _: ?*const event_loop_mod.Handler) void {}
    }.f,
    .context = @ptrCast(&test_dummy_ctx),
    .next = null,
};

/// Build a dummy EventLoop for tests that only need its running flag.
fn makeTestEventLoop() event_loop_mod.EventLoop {
    if (!test_mock_ops_initialized) {
        test_mock_ops = test_mock_event.ops();
        test_mock_ops_initialized = true;
    }
    return event_loop_mod.EventLoop{
        .event_ops = &test_mock_ops,
        .event_ctx = @ptrCast(&test_dummy_ctx),
        .chain = &test_dummy_handler,
        .running = true,
    };
}

test "handleSignalEvent: SIGCHLD with matching pane -> pane marked exited" {
    test_sm.reset();
    const session_id = try test_sm.createSession("test", testImeEngine());
    const entry = test_sm.getSession(session_id).?;

    const pane_slot: types.PaneSlot = 0;
    const pane = pane_mod.Pane.init(1, pane_slot, 10, 1234, 80, 24);
    entry.setPaneAtSlot(pane_slot, pane);

    var mock_signal = mock_os.MockSignalOps{
        .wait_results = &[_]interfaces.SignalOps.WaitResult{
            .{ .pid = 1234, .exit_status = 0 },
        },
    };
    const signal_ops = mock_signal.ops();

    const event = interfaces.Event{
        .fd = std.posix.SIG.CHLD,
        .filter = .signal,
        .target = null,
    };

    var test_el = makeTestEventLoop();
    handleSignalEvent(event, &signal_ops, &test_sm, &test_el);

    const updated_pane = entry.getPaneAtSlot(pane_slot).?;
    try testing.expect(updated_pane.pane_exited);
    try testing.expect(!updated_pane.is_running);
    try testing.expect(test_el.running); // SIGCHLD does not stop
}

test "handleSignalEvent: SIGCHLD with no children -> no change" {
    test_sm.reset();
    const session_id = try test_sm.createSession("test", testImeEngine());
    const entry = test_sm.getSession(session_id).?;

    const pane_slot: types.PaneSlot = 0;
    const pane = pane_mod.Pane.init(1, pane_slot, 10, 5678, 80, 24);
    entry.setPaneAtSlot(pane_slot, pane);

    var mock_signal = mock_os.MockSignalOps{
        .wait_results = &[_]interfaces.SignalOps.WaitResult{},
    };
    const signal_ops = mock_signal.ops();

    const event = interfaces.Event{
        .fd = std.posix.SIG.CHLD,
        .filter = .signal,
        .target = null,
    };

    var test_el = makeTestEventLoop();
    handleSignalEvent(event, &signal_ops, &test_sm, &test_el);

    const updated_pane = entry.getPaneAtSlot(pane_slot).?;
    try testing.expect(!updated_pane.pane_exited);
    try testing.expect(updated_pane.is_running);
    try testing.expect(test_el.running);
}

test "handleSignalEvent: SIGTERM -> event loop stopped" {
    test_sm.reset();
    var mock_signal = mock_os.MockSignalOps{};
    const signal_ops = mock_signal.ops();

    const event = interfaces.Event{
        .fd = std.posix.SIG.TERM,
        .filter = .signal,
        .target = null,
    };

    var test_el = makeTestEventLoop();
    handleSignalEvent(event, &signal_ops, &test_sm, &test_el);
    try testing.expect(!test_el.running);
}

test "handleSignalEvent: SIGHUP -> event loop stopped" {
    test_sm.reset();
    var mock_signal = mock_os.MockSignalOps{};
    const signal_ops = mock_signal.ops();

    const event = interfaces.Event{
        .fd = std.posix.SIG.HUP,
        .filter = .signal,
        .target = null,
    };

    var test_el = makeTestEventLoop();
    handleSignalEvent(event, &signal_ops, &test_sm, &test_el);
    try testing.expect(!test_el.running);
}

test "handleSignalEvent: SIGINT -> event loop stopped" {
    test_sm.reset();
    var mock_signal = mock_os.MockSignalOps{};
    const signal_ops = mock_signal.ops();

    const event = interfaces.Event{
        .fd = std.posix.SIG.INT,
        .filter = .signal,
        .target = null,
    };

    var test_el = makeTestEventLoop();
    handleSignalEvent(event, &signal_ops, &test_sm, &test_el);
    try testing.expect(!test_el.running);
}

test "chainHandle: non-signal event forwards to next handler" {
    var forwarded = false;
    const NextCtx = struct {
        flag: *bool,
        fn handle(context: *anyopaque, _: interfaces.Event, _: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.flag.* = true;
        }
    };

    var next_ctx = NextCtx{ .flag = &forwarded };
    const next = Handler{
        .handleFn = NextCtx.handle,
        .context = @ptrCast(&next_ctx),
        .next = null,
    };

    var test_el = makeTestEventLoop();
    var signal_ctx = SignalHandlerContext{
        .signal_ops = undefined,
        .session_manager = &test_sm,
        .event_loop = &test_el,
    };

    const read_event = interfaces.Event{
        .fd = 42,
        .filter = .read,
        .target = null,
    };

    chainHandle(@ptrCast(&signal_ctx), read_event, &next);
    try testing.expect(forwarded);
}
