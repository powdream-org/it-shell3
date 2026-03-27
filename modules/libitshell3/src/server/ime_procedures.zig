const std = @import("std");
const ime_engine_mod = @import("../core/ime_engine.zig");
const ImeEngine = ime_engine_mod.ImeEngine;
const ImeResult = ime_engine_mod.ImeResult;
const KeyEvent = ime_engine_mod.KeyEvent;
const session_mod = @import("../core/session.zig");
const types = @import("../core/types.zig");
const ime_consumer = @import("ime_consumer.zig");

/// Section 8.1: Ownership transfer (reference procedure).
/// Flush-and-transfer sequence: flush -> consume result -> clear preedit ->
/// send PreeditEnd (stub) -> incrementSessionId -> update owner.
///
/// The buffer lifetime constraint is enforced: committed_text is consumed
/// (written to PTY) before any further engine calls.
pub fn ownershipTransfer(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_writer: ime_consumer.PtyWriter,
    new_owner: ?types.ClientId,
) void {
    // Step 1: Flush composition
    const result = session.ime_engine.flush();

    // Steps 2-3: Consume result (write committed_text to PTY before next engine call)
    _ = ime_consumer.consumeImeResult(result, session, pty_fd, pty_writer, null);

    // Step 4: Clear preedit (may have been done by consumer, but ensure it)
    session.setPreedit(null);

    // Step 5: Send PreeditEnd to all attached clients (stub — requires wire message dispatch)
    // TODO(Plan 6): Send PreeditEnd with appropriate reason and preedit_session_id

    // Step 6: Increment session_id
    session.preedit.incrementSessionId();

    // Step 7: Update owner
    session.preedit.owner = new_owner;
}

/// Section 8.2: Resolve preedit ownership before client teardown.
/// If the departing client is the preedit owner, flush and transfer to null.
/// Used by disconnect, detach, and eviction — identical from preedit perspective.
fn handlePreeditOwnerDisconnect(
    session: *session_mod.Session,
    client_id: types.ClientId,
    pty_fd: std.posix.fd_t,
    pty_writer: ime_consumer.PtyWriter,
) void {
    if (session.preedit.owner) |owner| {
        if (owner == client_id) {
            ownershipTransfer(session, pty_fd, pty_writer, null);
        }
    }
}

pub const onClientDisconnect = handlePreeditOwnerDisconnect;
pub const onClientDetach = handlePreeditOwnerDisconnect;
pub const onClientEviction = handlePreeditOwnerDisconnect;

/// Section 8.3: Intra-session pane focus change.
/// Flush composition to OLD pane before updating focused_pane.
pub fn onFocusChange(
    session: *session_mod.Session,
    old_pane_pty_fd: std.posix.fd_t,
    pty_writer: ime_consumer.PtyWriter,
    new_pane_slot: types.PaneSlot,
) void {
    // Steps 1-7: Flush and transfer ownership to null
    ownershipTransfer(session, old_pane_pty_fd, pty_writer, null);

    // Step 8: Update focused_pane (caller may also do this, but this is the
    // canonical place per the procedure)
    session.focused_pane = new_pane_slot;

    // TODO(Plan 6): Send LayoutChanged with new focused pane to all clients
}

/// Section 8.3: Pane close (non-last pane).
/// Reset (NOT flush) — composition is discarded; the PTY is being closed.
pub fn onPaneClose(session: *session_mod.Session) void {
    // Step 1: Discard composition (do NOT commit to PTY)
    session.ime_engine.reset();

    // Step 2: Clear current_preedit
    session.setPreedit(null);

    // Step 3: Clear owner
    session.preedit.owner = null;

    // Step 4: Send PreeditEnd with reason "pane_closed" (stub)
    // TODO(Plan 6): Send PreeditEnd

    // Step 5: Increment session_id (after PreeditEnd which carries old session_id)
    session.preedit.incrementSessionId();
}

/// Section 8.3: Alternate screen switch.
/// Flush + commit before screen switch.
pub fn onAlternateScreenSwitch(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_writer: ime_consumer.PtyWriter,
) void {
    // Execute ownership transfer (flush, consume, clear, PreeditEnd, increment)
    ownershipTransfer(session, pty_fd, pty_writer, null);

    // After this, caller processes the screen switch through ghostty Terminal
    // and sends FrameUpdate with frame_type=1 (I-frame), screen=alternate.
}

/// Section 8.4: Mouse click during composition.
/// Flush before mouse event forwarding. Only for MouseButton events;
/// MouseScroll and MouseMove do NOT trigger this.
pub fn onMouseClick(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_writer: ime_consumer.PtyWriter,
) void {
    ownershipTransfer(session, pty_fd, pty_writer, null);
}

/// Section 8.4: InputMethodSwitch during active preedit.
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
    pty_writer: ime_consumer.PtyWriter,
) void {
    if (commit_current) {
        // Step 1: setActiveInputMethod atomically flushes
        const result = session.ime_engine.setActiveInputMethod(new_method) catch {
            // UnsupportedInputMethod — should not happen with valid methods
            return;
        };

        // Steps 2-3: Consume committed_text (write to PTY).
        // consumeImeResult handles preedit clearing when preedit_changed=true.
        _ = ime_consumer.consumeImeResult(result, session, pty_fd, pty_writer, null);

        // Step 4: PreeditEnd with reason "committed" (stub)
        // TODO(Plan 6): Send PreeditEnd

        // Step 5: InputMethodAck (stub)
        // TODO(Plan 6): Send InputMethodAck
    } else {
        // Step 1: Discard current composition
        session.ime_engine.reset();

        // Step 2: Clear preedit
        session.setPreedit(null);

        // Step 3: Clear owner
        session.preedit.owner = null;

        // Step 4: Switch input method (no flush needed, engine is already empty)
        _ = session.ime_engine.setActiveInputMethod(new_method) catch {
            return;
        };

        // Step 5: PreeditEnd with reason "cancelled" (stub)
        // TODO(Plan 6): Send PreeditEnd

        // Step 6: Increment session_id
        session.preedit.incrementSessionId();

        // Step 7: InputMethodAck (stub)
        // TODO(Plan 6): Send InputMethodAck
    }
}

/// Section 8.5: Error recovery.
/// Best-effort commit + reset to known-good state.
pub fn errorRecovery(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_writer: ime_consumer.PtyWriter,
) void {
    // Step 2: Best-effort commit existing preedit text to PTY
    if (session.current_preedit) |preedit| {
        _ = pty_writer.write(pty_fd, preedit) catch {};
    }

    // Step 3: Force composition state to null
    session.ime_engine.reset();

    // Step 4: Clear preedit
    session.setPreedit(null);

    // Step 5: Clear owner
    session.preedit.owner = null;

    // Step 6: PreeditEnd with reason "cancelled" (stub)
    // TODO(Plan 6): Send PreeditEnd
}

// ── Tests ────────────────────────────────────────────────────────────────────

const mock_ime = @import("../testing/mock_ime_engine.zig");
const MockPtyWriter = @import("../testing/mock_pty_writer.zig").MockPtyWriter;

test "ownershipTransfer: flushes, clears preedit, increments session_id, sets owner" {
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "committed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.preedit.owner = 42;
    session.setPreedit("composing");
    var mock_writer = MockPtyWriter{};

    ownershipTransfer(&session, 10, mock_writer.writer(), 99);

    try std.testing.expectEqual(@as(usize, 1), mock.flush_count);
    try std.testing.expectEqualSlices(u8, "committed", mock_writer.written());
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
    var mock_writer = MockPtyWriter{};

    onClientDisconnect(&session, 5, 10, mock_writer.writer());

    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqualSlices(u8, "flushed", mock_writer.written());
}

test "onClientDisconnect: non-owner disconnects -> no-op" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.preedit.owner = 5;
    var mock_writer = MockPtyWriter{};

    onClientDisconnect(&session, 99, 10, mock_writer.writer());

    try std.testing.expectEqual(@as(?types.ClientId, 5), session.preedit.owner);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
}

test "onFocusChange: flushes to old pane, updates focused_pane" {
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "text", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.focused_pane = 0;
    var mock_writer = MockPtyWriter{};

    onFocusChange(&session, 42, mock_writer.writer(), 3);

    try std.testing.expectEqualSlices(u8, "text", mock_writer.written());
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
    var mock_writer = MockPtyWriter{};

    onAlternateScreenSwitch(&session, 10, mock_writer.writer());

    try std.testing.expectEqualSlices(u8, "flushed", mock_writer.written());
    try std.testing.expect(session.current_preedit == null);
}

test "onMouseClick: flushes composition before mouse event" {
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "click", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var mock_writer = MockPtyWriter{};

    onMouseClick(&session, 10, mock_writer.writer());

    try std.testing.expectEqualSlices(u8, "click", mock_writer.written());
}

test "onInputMethodSwitch: commit_current=true flushes atomically" {
    var mock = mock_ime.MockImeEngine{
        .set_aim_result = .{ .committed_text = "committed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.setPreedit("composing");
    var mock_writer = MockPtyWriter{};

    onInputMethodSwitch(&session, "direct", true, 10, mock_writer.writer());

    try std.testing.expectEqual(@as(usize, 1), mock.set_aim_count);
    try std.testing.expectEqualSlices(u8, "committed", mock_writer.written());
    try std.testing.expect(session.current_preedit == null);
}

test "onInputMethodSwitch: commit_current=false resets and switches" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    session.preedit.owner = 5;
    session.setPreedit("composing");
    var mock_writer = MockPtyWriter{};

    onInputMethodSwitch(&session, "direct", false, 10, mock_writer.writer());

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
    var mock_writer = MockPtyWriter{};

    errorRecovery(&session, 10, mock_writer.writer());

    // Best-effort commit of preedit text
    try std.testing.expectEqualSlices(u8, "broken", mock_writer.written());
    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expect(session.current_preedit == null);
    try std.testing.expect(session.preedit.owner == null);
}

test "errorRecovery: no preedit -> reset only" {
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine());
    var mock_writer = MockPtyWriter{};

    errorRecovery(&session, 10, mock_writer.writer());

    try std.testing.expectEqual(@as(usize, 0), mock_writer.written().len);
    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
}
