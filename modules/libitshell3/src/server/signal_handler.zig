const std = @import("std");
const os = @import("itshell3_os");
const interfaces = os.interfaces;
const core = @import("itshell3_core");
const session_manager_mod = core.session_manager;
const types = core.types;

pub const SessionManager = session_manager_mod.SessionManager;

/// Handle a signal event delivered via the event loop.
///
/// - SIGCHLD: drain waitChild() in a loop, marking matching panes exited.
/// - SIGTERM/SIGINT: set shutdown_requested = true.
/// - SIGHUP: ignored (future: reload config).
pub fn handleSignalEvent(
    event: interfaces.EventLoopOps.Event,
    signal_ops: *const interfaces.SignalOps,
    session_manager: *SessionManager,
    shutdown_requested: *bool,
) void {
    // The signal number is carried in udata (as registered via registerSignals).
    const sig: u32 = @intCast(event.udata);

    switch (sig) {
        std.posix.SIG.CHLD => {
            // Drain all exited children
            while (signal_ops.waitChild()) |result| {
                markPaneExited(session_manager, result.pid, result.exit_status);
            }
        },
        std.posix.SIG.TERM, std.posix.SIG.INT => {
            shutdown_requested.* = true;
        },
        std.posix.SIG.HUP => {
            // Ignored for now — future: reload config
        },
        else => {},
    }
}

fn markPaneExited(sm: *SessionManager, pid: std.posix.pid_t, exit_status: u8) void {
    for (&sm.sessions) |*slot| {
        if (slot.*) |*entry| {
            var i: u5 = 0;
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
const pane_mod = core.pane;
const session_mod = core.session;

// File-scope statics for tests.
var test_sm = SessionManager.init();

const testImeEngine = test_helpers.testImeEngine;

test "handleSignalEvent: SIGCHLD with matching pane -> pane marked exited" {
    test_sm.reset();
    const session_id = try test_sm.createSession("test", testImeEngine());
    const entry = test_sm.getSession(session_id).?;

    // The session already allocated slot 0 in createSession; put a pane there
    const pane_slot: types.PaneSlot = 0;
    const pane = pane_mod.Pane.init(1, pane_slot, 10, 1234, 80, 24);
    entry.setPaneAtSlot(pane_slot, pane);

    var mock_signal = mock_os.MockSignalOps{
        .wait_results = &[_]interfaces.SignalOps.WaitResult{
            .{ .pid = 1234, .exit_status = 0 },
        },
    };
    const signal_ops = mock_signal.ops();

    const event = interfaces.EventLoopOps.Event{
        .fd = std.posix.SIG.CHLD,
        .filter = .signal,
        .udata = std.posix.SIG.CHLD,
    };

    var shutdown = false;
    handleSignalEvent(event, &signal_ops, &test_sm, &shutdown);

    const updated_pane = entry.getPaneAtSlot(pane_slot).?;
    try testing.expect(updated_pane.pane_exited);
    try testing.expect(!updated_pane.is_running);
    try testing.expect(!shutdown);
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

    const event = interfaces.EventLoopOps.Event{
        .fd = std.posix.SIG.CHLD,
        .filter = .signal,
        .udata = std.posix.SIG.CHLD,
    };

    var shutdown = false;
    handleSignalEvent(event, &signal_ops, &test_sm, &shutdown);

    const updated_pane = entry.getPaneAtSlot(pane_slot).?;
    try testing.expect(!updated_pane.pane_exited);
    try testing.expect(updated_pane.is_running);
    try testing.expect(!shutdown);
}

test "handleSignalEvent: SIGTERM -> shutdown_requested = true" {
    test_sm.reset();
    var mock_signal = mock_os.MockSignalOps{};
    const signal_ops = mock_signal.ops();

    const event = interfaces.EventLoopOps.Event{
        .fd = std.posix.SIG.TERM,
        .filter = .signal,
        .udata = std.posix.SIG.TERM,
    };

    var shutdown = false;
    handleSignalEvent(event, &signal_ops, &test_sm, &shutdown);
    try testing.expect(shutdown);
}

test "handleSignalEvent: SIGINT -> shutdown_requested = true" {
    test_sm.reset();
    var mock_signal = mock_os.MockSignalOps{};
    const signal_ops = mock_signal.ops();

    const event = interfaces.EventLoopOps.Event{
        .fd = std.posix.SIG.INT,
        .filter = .signal,
        .udata = std.posix.SIG.INT,
    };

    var shutdown = false;
    handleSignalEvent(event, &signal_ops, &test_sm, &shutdown);
    try testing.expect(shutdown);
}
