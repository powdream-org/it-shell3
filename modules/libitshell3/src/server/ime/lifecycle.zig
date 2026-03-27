const std = @import("std");
const core = @import("itshell3_core");
const session_mod = core.session;
const os = @import("../os/root.zig");
const PtyOps = os.PtyOps;
const ime_consumer = @import("consumer.zig");

/// Tracks the number of attached clients per session and determines when to
/// call activate/deactivate on the session's IME engine.
///
/// Per ime-procedures eager activate/deactivate spec:
/// - activate() is called only when the count goes from 0 to 1.
/// - deactivate() is called only when the count drops to 0.
/// - A single client detaching while others remain does NOT trigger deactivate.
pub const ClientTracker = struct {
    attached_count: u32 = 0,

    /// Record a client attaching to this session. If this is the first client
    /// (0 -> 1), calls activate() on the session's IME engine.
    pub fn clientAttached(self: *ClientTracker, session: *session_mod.Session) void {
        const was_zero = self.attached_count == 0;
        self.attached_count += 1;
        if (was_zero) {
            activateSessionIme(session);
        }
    }

    /// Record a client detaching from this session. If this is the last client
    /// (N -> 0), calls deactivate() on the session's IME engine.
    /// Returns true if preedit state changed (caller should mark pane dirty).
    pub fn clientDetached(
        self: *ClientTracker,
        session: *session_mod.Session,
        pty_fd: std.posix.fd_t,
        pty_ops: *const PtyOps,
    ) bool {
        if (self.attached_count == 0) return false;
        self.attached_count -= 1;
        if (self.attached_count == 0) {
            return deactivateSessionIme(session, pty_fd, pty_ops);
        }
        return false;
    }
};

/// Handle session gaining its first client (attached-client count goes from 0 to 1).
/// Calls activate() on the session's IME engine.
/// Per spec: activate() is a no-op for Korean, but the contract requires calling it.
pub fn activateSessionIme(session: *session_mod.Session) void {
    session.ime_engine.activate();
}

/// Handle session losing its last client (attached-client count drops to 0).
/// Calls deactivate() on the session's IME engine.
/// Per ime-procedures eager activate/deactivate spec: deactivate() flushes pending composition.
///
/// Returns true if preedit state changed (caller should mark pane dirty).
pub fn deactivateSessionIme(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
) bool {
    const result = session.ime_engine.deactivate();
    return ime_consumer.consumeImeResult(result, session, pty_fd, pty_ops, null);
}

// ── Tests ────────────────────────────────────────────────────────────────────

const test_mod = @import("itshell3_testing");
const mock_ime = test_mod.mock_ime_engine;
const MockPtyOps = test_mod.mock_os.MockPtyOps;

test "activateSessionIme: calls activate on engine" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    activateSessionIme(&session);
    try std.testing.expectEqual(@as(usize, 1), mock.activate_count);
}

test "deactivateSessionIme: calls deactivate, writes committed text to PTY" {
    var mock = mock_ime.MockImeEngine{
        .deactivate_result = .{ .committed_text = "flushed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    const dirty = deactivateSessionIme(&session, 10, &pty_ops);

    try std.testing.expectEqual(@as(usize, 1), mock.deactivate_count);
    try std.testing.expectEqualSlices(u8, "flushed", mock_pty.written());
    try std.testing.expect(dirty);
    try std.testing.expect(session.current_preedit == null);
}

test "deactivateSessionIme: empty engine returns no-op" {
    var mock = mock_ime.MockImeEngine{
        .deactivate_result = .{},
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    const dirty = deactivateSessionIme(&session, 10, &pty_ops);

    try std.testing.expectEqual(@as(usize, 1), mock.deactivate_count);
    try std.testing.expect(!dirty);
    try std.testing.expectEqual(@as(usize, 0), mock_pty.written().len);
}

test "deactivateSessionIme: language state preserved (active_input_method unchanged)" {
    var mock = mock_ime.MockImeEngine{
        .active_input_method = "korean_2set",
        .deactivate_result = .{},
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    _ = deactivateSessionIme(&session, 10, &pty_ops);

    try std.testing.expectEqualSlices(u8, "korean_2set", mock.active_input_method);
}

test "ClientTracker: first attach triggers activate" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var tracker = ClientTracker{};

    tracker.clientAttached(&session);

    try std.testing.expectEqual(@as(u32, 1), tracker.attached_count);
    try std.testing.expectEqual(@as(usize, 1), mock.activate_count);
}

test "ClientTracker: second attach does NOT trigger activate again" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var tracker = ClientTracker{};

    tracker.clientAttached(&session);
    tracker.clientAttached(&session);

    try std.testing.expectEqual(@as(u32, 2), tracker.attached_count);
    try std.testing.expectEqual(@as(usize, 1), mock.activate_count);
}

test "ClientTracker: last detach triggers deactivate" {
    var mock = mock_ime.MockImeEngine{
        .deactivate_result = .{ .committed_text = "bye", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var tracker = ClientTracker{};
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    tracker.clientAttached(&session);
    const dirty = tracker.clientDetached(&session, 10, &pty_ops);

    try std.testing.expectEqual(@as(u32, 0), tracker.attached_count);
    try std.testing.expectEqual(@as(usize, 1), mock.deactivate_count);
    try std.testing.expect(dirty);
    try std.testing.expectEqualSlices(u8, "bye", mock_pty.written());
}

test "ClientTracker: detach with remaining clients does NOT trigger deactivate" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var tracker = ClientTracker{};
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    tracker.clientAttached(&session);
    tracker.clientAttached(&session);
    const dirty = tracker.clientDetached(&session, 10, &pty_ops);

    try std.testing.expectEqual(@as(u32, 1), tracker.attached_count);
    try std.testing.expectEqual(@as(usize, 0), mock.deactivate_count);
    try std.testing.expect(!dirty);
}

test "ClientTracker: detach from zero count is no-op" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var tracker = ClientTracker{};
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    const dirty = tracker.clientDetached(&session, 10, &pty_ops);

    try std.testing.expectEqual(@as(u32, 0), tracker.attached_count);
    try std.testing.expectEqual(@as(usize, 0), mock.deactivate_count);
    try std.testing.expect(!dirty);
}
