const std = @import("std");
const ime_engine_mod = @import("../core/ime_engine.zig");
const ImeEngine = ime_engine_mod.ImeEngine;
const ImeResult = ime_engine_mod.ImeResult;
const session_mod = @import("../core/session.zig");
const ime_consumer = @import("ime_consumer.zig");

/// Tracks the number of attached clients per session and determines when to
/// call activate/deactivate on the session's IME engine.
///
/// Per spec ime-procedures section 4.3:
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
        pty_writer: ime_consumer.PtyWriter,
    ) bool {
        if (self.attached_count == 0) return false;
        self.attached_count -= 1;
        if (self.attached_count == 0) {
            return deactivateSessionIme(session, pty_fd, pty_writer);
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
/// Per spec section 4.3: deactivate() flushes pending composition.
///
/// Returns true if preedit state changed (caller should mark pane dirty).
pub fn deactivateSessionIme(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_writer: ime_consumer.PtyWriter,
) bool {
    const result = session.ime_engine.deactivate();

    // Consume the deactivation result:
    // - If committed text returned, write to the focused pane's PTY.
    // - If preedit changed, clear session.current_preedit and mark dirty.
    return ime_consumer.consumeImeResult(result, session, pty_fd, pty_writer, null);
}

/// Handle intra-session pane focus change.
/// Flushes composition to the OLD pane's PTY before the focus switch.
/// Per spec section 4.4 and section 8.3:
/// 1. engine.flush() -> ImeResult
/// 2. Consume result (write committed text to old PTY, clear preedit)
/// 3. Caller then updates session.focused_pane
///
/// Returns true if preedit state changed (caller should mark old pane dirty).
pub fn flushOnPaneFocusChange(
    session: *session_mod.Session,
    old_pane_pty_fd: std.posix.fd_t,
    pty_writer: ime_consumer.PtyWriter,
) bool {
    const result = session.ime_engine.flush();
    return ime_consumer.consumeImeResult(result, session, old_pane_pty_fd, pty_writer, null);
}

// ── Tests ────────────────────────────────────────────────────────────────────

const mock_ime = @import("../testing/mock_ime_engine.zig");
const MockPtyWriter = @import("../testing/mock_pty_writer.zig").MockPtyWriter;

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
    var mock_writer = MockPtyWriter{};

    const dirty = deactivateSessionIme(&session, 10, mock_writer.writer());

    try std.testing.expectEqual(@as(usize, 1), mock.deactivate_count);
    try std.testing.expectEqualSlices(u8, "flushed", mock_writer.written());
    try std.testing.expect(dirty);
    try std.testing.expect(session.current_preedit == null);
}

test "deactivateSessionIme: empty engine returns no-op" {
    var mock = mock_ime.MockImeEngine{
        .deactivate_result = .{}, // empty
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var mock_writer = MockPtyWriter{};

    const dirty = deactivateSessionIme(&session, 10, mock_writer.writer());

    try std.testing.expectEqual(@as(usize, 1), mock.deactivate_count);
    try std.testing.expect(!dirty);
    try std.testing.expectEqual(@as(usize, 0), mock_writer.written().len);
}

test "deactivateSessionIme: language state preserved (active_input_method unchanged)" {
    var mock = mock_ime.MockImeEngine{
        .active_input_method = "korean_2set",
        .deactivate_result = .{},
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var mock_writer = MockPtyWriter{};

    _ = deactivateSessionIme(&session, 10, mock_writer.writer());

    // Engine's active_input_method should still be "korean_2set"
    try std.testing.expectEqualSlices(u8, "korean_2set", mock.active_input_method);
}

test "flushOnPaneFocusChange: flushes composition to old pane PTY" {
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "committed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.setPreedit("composing");
    var mock_writer = MockPtyWriter{};

    const dirty = flushOnPaneFocusChange(&session, 42, mock_writer.writer());

    try std.testing.expectEqual(@as(usize, 1), mock.flush_count);
    try std.testing.expectEqualSlices(u8, "committed", mock_writer.written());
    try std.testing.expect(dirty);
    try std.testing.expect(session.current_preedit == null);
}

test "flushOnPaneFocusChange: empty engine is no-op" {
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{},
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var mock_writer = MockPtyWriter{};

    const dirty = flushOnPaneFocusChange(&session, 42, mock_writer.writer());

    try std.testing.expect(!dirty);
    try std.testing.expectEqual(@as(usize, 0), mock_writer.written().len);
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
    var mock_writer = MockPtyWriter{};

    tracker.clientAttached(&session);
    const dirty = tracker.clientDetached(&session, 10, mock_writer.writer());

    try std.testing.expectEqual(@as(u32, 0), tracker.attached_count);
    try std.testing.expectEqual(@as(usize, 1), mock.deactivate_count);
    try std.testing.expect(dirty);
    try std.testing.expectEqualSlices(u8, "bye", mock_writer.written());
}

test "ClientTracker: detach with remaining clients does NOT trigger deactivate" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var tracker = ClientTracker{};
    var mock_writer = MockPtyWriter{};

    tracker.clientAttached(&session);
    tracker.clientAttached(&session);
    const dirty = tracker.clientDetached(&session, 10, mock_writer.writer());

    try std.testing.expectEqual(@as(u32, 1), tracker.attached_count);
    try std.testing.expectEqual(@as(usize, 0), mock.deactivate_count);
    try std.testing.expect(!dirty);
}

test "ClientTracker: detach from zero count is no-op" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var tracker = ClientTracker{};
    var mock_writer = MockPtyWriter{};

    const dirty = tracker.clientDetached(&session, 10, mock_writer.writer());

    try std.testing.expectEqual(@as(u32, 0), tracker.attached_count);
    try std.testing.expectEqual(@as(usize, 0), mock.deactivate_count);
    try std.testing.expect(!dirty);
}
