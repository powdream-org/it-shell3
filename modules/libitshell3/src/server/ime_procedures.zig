const std = @import("std");
const core = @import("itshell3_core");
const session_mod = core.session;
const types = core.types;
const os = @import("itshell3_os");
const PtyOps = os.PtyOps;
const ime_consumer = @import("ime_consumer.zig");

/// Ownership transfer (reference procedure, see ime-procedures spec).
/// Flush-and-transfer sequence: flush -> consume result -> clear preedit ->
/// send PreeditEnd (stub) -> incrementSessionId -> update owner.
///
/// The buffer lifetime constraint is enforced: committed_text is consumed
/// (written to PTY) before any further engine calls.
pub fn ownershipTransfer(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    new_owner: ?types.ClientId,
) void {
    const result = session.ime_engine.flush();

    _ = ime_consumer.consumeImeResult(result, session, pty_fd, pty_ops, null);

    session.setPreedit(null);

    // TODO(Plan 6): Send PreeditEnd with appropriate reason and preedit_session_id

    session.preedit.incrementSessionId();
    session.preedit.owner = new_owner;
}

/// Resolve preedit ownership before client teardown (see ime-procedures spec).
/// If the departing client is the preedit owner, flush and transfer to null.
/// Used by disconnect, detach, and eviction -- identical from preedit perspective.
fn handlePreeditOwnerDisconnect(
    session: *session_mod.Session,
    client_id: types.ClientId,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
) void {
    if (session.preedit.owner) |owner| {
        if (owner == client_id) {
            ownershipTransfer(session, pty_fd, pty_ops, null);
        }
    }
}

pub const onClientDisconnect = handlePreeditOwnerDisconnect;
pub const onClientDetach = handlePreeditOwnerDisconnect;
pub const onClientEviction = handlePreeditOwnerDisconnect;

/// Intra-session pane focus change (see ime-procedures spec).
/// Flush composition to OLD pane before updating focused_pane.
pub fn onFocusChange(
    session: *session_mod.Session,
    old_pane_pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    new_pane_slot: types.PaneSlot,
) void {
    ownershipTransfer(session, old_pane_pty_fd, pty_ops, null);
    session.focused_pane = new_pane_slot;
    // TODO(Plan 6): Send LayoutChanged with new focused pane to all clients
}

/// Pane close for non-last pane (see ime-procedures spec).
/// Reset (NOT flush) -- composition is discarded; the PTY is being closed.
pub fn onPaneClose(session: *session_mod.Session) void {
    session.ime_engine.reset();
    session.setPreedit(null);
    session.preedit.owner = null;
    // TODO(Plan 6): Send PreeditEnd
    session.preedit.incrementSessionId();
}

/// Alternate screen switch (see ime-procedures spec).
/// Flush + commit before screen switch.
pub fn onAlternateScreenSwitch(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
) void {
    ownershipTransfer(session, pty_fd, pty_ops, null);
}

/// Mouse click during composition (see ime-procedures spec).
/// Flush before mouse event forwarding. Only for MouseButton events;
/// MouseScroll and MouseMove do NOT trigger this.
pub fn onMouseClick(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
) void {
    ownershipTransfer(session, pty_fd, pty_ops, null);
}

/// InputMethodSwitch during active preedit (see ime-procedures spec).
///
/// When commit_current=true:
///   setActiveInputMethod (atomically flushes) -> consume committed_text -> write to PTY
///
/// When commit_current=false:
///   reset -> clear preedit/owner -> setActiveInputMethod -> PreeditEnd + increment
pub fn onInputMethodSwitch(
    session: *session_mod.Session,
    new_method: []const u8,
    commit_current: bool,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
) void {
    if (commit_current) {
        const result = session.ime_engine.setActiveInputMethod(new_method) catch {
            return;
        };
        // consumeImeResult handles preedit clearing when preedit_changed=true.
        _ = ime_consumer.consumeImeResult(result, session, pty_fd, pty_ops, null);
        // TODO(Plan 6): Send PreeditEnd, InputMethodAck
    } else {
        session.ime_engine.reset();
        session.setPreedit(null);
        session.preedit.owner = null;
        _ = session.ime_engine.setActiveInputMethod(new_method) catch {
            return;
        };
        // TODO(Plan 6): Send PreeditEnd
        session.preedit.incrementSessionId();
        // TODO(Plan 6): Send InputMethodAck
    }
}

/// Error recovery (see ime-procedures spec).
/// Best-effort commit + reset to known-good state.
pub fn errorRecovery(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
) void {
    if (session.current_preedit) |preedit| {
        _ = pty_ops.write(pty_fd, preedit) catch {};
    }
    session.ime_engine.reset();
    session.setPreedit(null);
    session.preedit.owner = null;
    // TODO(Plan 6): Send PreeditEnd
}

// ── Tests ────────────────────────────────────────────────────────────────────

const test_mod = @import("itshell3_testing");
const mock_ime = test_mod.mock_ime_engine;
const MockPtyOps = test_mod.mock_os.MockPtyOps;

test "ownershipTransfer: flushes, clears preedit, increments session_id, sets owner" {
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "committed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.preedit.owner = 42;
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    ownershipTransfer(&session, 10, &pty_ops, 99);

    try std.testing.expectEqual(@as(usize, 1), mock.flush_count);
    try std.testing.expectEqualSlices(u8, "committed", mock_pty.written());
    try std.testing.expect(session.current_preedit == null);
    try std.testing.expectEqual(@as(u32, 1), session.preedit.session_id);
    try std.testing.expectEqual(@as(?types.ClientId, 99), session.preedit.owner);
}

test "onClientDisconnect: owner disconnects -> flush and clear owner" {
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "flushed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.preedit.owner = 5;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onClientDisconnect(&session, 5, 10, &pty_ops);

    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqualSlices(u8, "flushed", mock_pty.written());
}

test "onClientDisconnect: non-owner disconnects -> no-op" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.preedit.owner = 5;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onClientDisconnect(&session, 99, 10, &pty_ops);

    try std.testing.expectEqual(@as(?types.ClientId, 5), session.preedit.owner);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
}

test "onFocusChange: flushes to old pane, updates focused_pane" {
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "text", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.focused_pane = 0;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onFocusChange(&session, 42, &pty_ops, 3);

    try std.testing.expectEqualSlices(u8, "text", mock_pty.written());
    try std.testing.expectEqual(@as(?types.PaneSlot, 3), session.focused_pane);
    try std.testing.expect(session.current_preedit == null);
}

test "onPaneClose: resets (not flushes), clears preedit and owner, increments session_id" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.preedit.owner = 10;
    session.setPreedit("composing");

    onPaneClose(&session);

    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
    try std.testing.expect(session.current_preedit == null);
    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqual(@as(u32, 1), session.preedit.session_id);
}

test "onAlternateScreenSwitch: flushes and clears" {
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "flushed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onAlternateScreenSwitch(&session, 10, &pty_ops);

    try std.testing.expectEqualSlices(u8, "flushed", mock_pty.written());
    try std.testing.expect(session.current_preedit == null);
}

test "onMouseClick: flushes composition before mouse event" {
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "click", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onMouseClick(&session, 10, &pty_ops);

    try std.testing.expectEqualSlices(u8, "click", mock_pty.written());
}

test "onInputMethodSwitch: commit_current=true flushes atomically" {
    var mock = mock_ime.MockImeEngine{
        .set_aim_result = .{ .committed_text = "committed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onInputMethodSwitch(&session, "direct", true, 10, &pty_ops);

    try std.testing.expectEqual(@as(usize, 1), mock.set_aim_count);
    try std.testing.expectEqualSlices(u8, "committed", mock_pty.written());
    try std.testing.expect(session.current_preedit == null);
}

test "onInputMethodSwitch: commit_current=false resets and switches" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.preedit.owner = 5;
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onInputMethodSwitch(&session, "direct", false, 10, &pty_ops);

    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
    try std.testing.expectEqual(@as(usize, 1), mock.set_aim_count);
    try std.testing.expect(session.current_preedit == null);
    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqual(@as(u32, 1), session.preedit.session_id);
}

test "errorRecovery: best-effort commit + reset to known-good state" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.preedit.owner = 7;
    session.setPreedit("broken");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    errorRecovery(&session, 10, &pty_ops);

    try std.testing.expectEqualSlices(u8, "broken", mock_pty.written());
    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expect(session.current_preedit == null);
    try std.testing.expect(session.preedit.owner == null);
}

test "errorRecovery: no preedit -> reset only" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    errorRecovery(&session, 10, &pty_ops);

    try std.testing.expectEqual(@as(usize, 0), mock_pty.written().len);
    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
}
