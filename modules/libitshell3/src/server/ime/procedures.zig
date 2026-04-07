//! IME preedit procedures. Implements ownership transfer, disconnect/detach
//! cleanup, focus change, pane close, alternate screen switch, mouse click,
//! input method switch, and error recovery. See ime-procedures spec.

const std = @import("std");
const core = @import("itshell3_core");
const session_mod = core.session;
const types = core.types;
const interfaces = @import("../os/interfaces.zig");
const PtyOps = interfaces.PtyOps;
const ime_consumer = @import("consumer.zig");
const server = @import("itshell3_server");
const ClientManager = server.connection.client_manager.ClientManager;
const broadcast_mod = server.connection.broadcast;
const preedit_builder = server.handlers.preedit_message_builder;
const input_method_builder = server.handlers.input_method_message_builder;

/// Context for broadcasting preedit messages to session clients.
pub const BroadcastContext = struct {
    client_manager: *ClientManager,
    session_id: types.SessionId,
    /// Pane ID for the pane where composition is active.
    pane_id: types.PaneId,
    /// Sequence number source. Incremented for each broadcast message.
    sequence: *u64,
};

/// Sends a PreeditEnd broadcast to all session clients.
fn sendPreeditEnd(
    ctx: ?*const BroadcastContext,
    preedit_session_id: u32,
    reason: []const u8,
    committed_text: []const u8,
) void {
    const bc = ctx orelse return;
    var buf: preedit_builder.ScratchBuf = undefined;
    bc.sequence.* += 1;
    const msg = preedit_builder.buildPreeditEnd(
        bc.pane_id,
        preedit_session_id,
        reason,
        committed_text,
        bc.sequence.*,
        &buf,
    ) orelse return;
    _ = broadcast_mod.broadcastToSession(bc.client_manager, bc.session_id, msg, null);
}

/// Sends an InputMethodAck broadcast to all session clients.
fn sendInputMethodAck(
    ctx: ?*const BroadcastContext,
    active_input_method: []const u8,
    previous_input_method: []const u8,
    active_keyboard_layout: []const u8,
) void {
    const bc = ctx orelse return;
    var buf: input_method_builder.ScratchBuf = undefined;
    bc.sequence.* += 1;
    const msg = input_method_builder.buildInputMethodAck(
        bc.pane_id,
        active_input_method,
        previous_input_method,
        active_keyboard_layout,
        bc.sequence.*,
        &buf,
    ) orelse return;
    _ = broadcast_mod.broadcastToSession(bc.client_manager, bc.session_id, msg, null);
}

/// Ownership transfer (reference procedure, see ime-procedures spec).
/// Flush-and-transfer sequence: flush -> consume result -> clear preedit ->
/// send PreeditEnd -> incrementSessionId -> update owner.
///
/// The buffer lifetime constraint is enforced: committed_text is consumed
/// (written to PTY) before any further engine calls.
pub fn ownershipTransfer(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    new_owner: ?types.ClientId,
) void {
    ownershipTransferWithBroadcast(session, pty_fd, pty_ops, new_owner, "committed", null);
}

/// Ownership transfer with broadcast context for sending PreeditEnd.
/// The `reason` parameter specifies the PreeditEnd reason string (e.g.,
/// "committed", "replaced_by_other_client", "client_disconnected",
/// "client_evicted").
pub fn ownershipTransferWithBroadcast(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    new_owner: ?types.ClientId,
    reason: []const u8,
    broadcast_context: ?*const BroadcastContext,
) void {
    const preedit_session_id = session.preedit.session_id;
    const result = session.ime_engine.flush();
    const committed = result.committed_text orelse "";
    _ = ime_consumer.consumeImeResult(result, session, pty_fd, pty_ops, null);
    session.setPreedit(null);
    sendPreeditEnd(broadcast_context, preedit_session_id, reason, committed);
    session.preedit.incrementSessionId();
    session.preedit.owner = new_owner;
}

/// Resolve preedit ownership before client teardown (see ime-procedures spec).
/// If the departing client is the preedit owner, flush and transfer to null.
fn handlePreeditOwnerDisconnect(
    session: *session_mod.Session,
    client_id: types.ClientId,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    reason: []const u8,
) void {
    handlePreeditOwnerDisconnectWithBroadcast(session, client_id, pty_fd, pty_ops, reason, null);
}

fn handlePreeditOwnerDisconnectWithBroadcast(
    session: *session_mod.Session,
    client_id: types.ClientId,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    reason: []const u8,
    broadcast_context: ?*const BroadcastContext,
) void {
    if (session.preedit.owner) |owner| {
        if (owner == client_id) {
            ownershipTransferWithBroadcast(session, pty_fd, pty_ops, null, reason, broadcast_context);
        }
    }
}

/// Client disconnect: PreeditEnd reason is "client_disconnected".
pub fn onClientDisconnect(
    session: *session_mod.Session,
    client_id: types.ClientId,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
) void {
    handlePreeditOwnerDisconnect(session, client_id, pty_fd, pty_ops, "client_disconnected");
}

/// Client eviction: PreeditEnd reason is "client_evicted".
pub fn onClientEviction(
    session: *session_mod.Session,
    client_id: types.ClientId,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
) void {
    handlePreeditOwnerDisconnect(session, client_id, pty_fd, pty_ops, "client_evicted");
}

/// Client disconnect with broadcast context.
pub fn onClientDisconnectWithBroadcast(
    session: *session_mod.Session,
    client_id: types.ClientId,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    broadcast_context: ?*const BroadcastContext,
) void {
    handlePreeditOwnerDisconnectWithBroadcast(session, client_id, pty_fd, pty_ops, "client_disconnected", broadcast_context);
}

/// Client eviction with broadcast context.
pub fn onClientEvictionWithBroadcast(
    session: *session_mod.Session,
    client_id: types.ClientId,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    broadcast_context: ?*const BroadcastContext,
) void {
    handlePreeditOwnerDisconnectWithBroadcast(session, client_id, pty_fd, pty_ops, "client_evicted", broadcast_context);
}

/// Intra-session pane focus change (see ime-procedures spec).
/// Flush composition to OLD pane before updating focused_pane.
pub fn onFocusChange(
    session: *session_mod.Session,
    old_pane_pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    new_pane_slot: types.PaneSlot,
) void {
    onFocusChangeWithBroadcast(session, old_pane_pty_fd, pty_ops, new_pane_slot, null);
}

/// Focus change with broadcast context for sending PreeditEnd.
pub fn onFocusChangeWithBroadcast(
    session: *session_mod.Session,
    old_pane_pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    new_pane_slot: types.PaneSlot,
    broadcast_context: ?*const BroadcastContext,
) void {
    // Always flush composition to old pane before updating focused_pane.
    // The flush is safe even when there's no active composition.
    const preedit_session_id = session.preedit.session_id;
    const had_owner = session.preedit.owner != null;
    const result = session.ime_engine.flush();
    const committed = result.committed_text orelse "";
    _ = ime_consumer.consumeImeResult(result, session, old_pane_pty_fd, pty_ops, null);
    session.setPreedit(null);
    if (had_owner) {
        sendPreeditEnd(broadcast_context, preedit_session_id, "focus_changed", committed);
        session.preedit.incrementSessionId();
        session.preedit.owner = null;
    }
    session.focused_pane = new_pane_slot;
}

/// Pane close for non-last pane (see ime-procedures spec).
/// Reset (NOT flush) -- composition is discarded; the PTY is being closed.
pub fn onPaneClose(session: *session_mod.Session) void {
    onPaneCloseWithBroadcast(session, null);
}

/// Pane close with broadcast context for sending PreeditEnd.
pub fn onPaneCloseWithBroadcast(
    session: *session_mod.Session,
    broadcast_context: ?*const BroadcastContext,
) void {
    const preedit_session_id = session.preedit.session_id;
    const had_owner = session.preedit.owner != null;
    session.ime_engine.reset();
    session.setPreedit(null);
    session.preedit.owner = null;
    if (had_owner) {
        sendPreeditEnd(broadcast_context, preedit_session_id, "pane_closed", "");
        session.preedit.incrementSessionId();
    }
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

/// Alternate screen switch with broadcast context.
pub fn onAlternateScreenSwitchWithBroadcast(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    broadcast_context: ?*const BroadcastContext,
) void {
    ownershipTransferWithBroadcast(session, pty_fd, pty_ops, null, "committed", broadcast_context);
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

/// Mouse click with broadcast context.
pub fn onMouseClickWithBroadcast(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    broadcast_context: ?*const BroadcastContext,
) void {
    ownershipTransferWithBroadcast(session, pty_fd, pty_ops, null, "committed", broadcast_context);
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
    onInputMethodSwitchWithBroadcast(session, new_method, commit_current, pty_fd, pty_ops, null);
}

/// InputMethodSwitch with broadcast context for sending PreeditEnd and
/// InputMethodAck.
pub fn onInputMethodSwitchWithBroadcast(
    session: *session_mod.Session,
    new_method: []const u8,
    commit_current: bool,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    broadcast_context: ?*const BroadcastContext,
) void {
    // Capture previous input method for InputMethodAck.
    var previous_buf: [types.MAX_INPUT_METHOD_NAME]u8 = @splat(0);
    const previous_len = session.active_input_method_length;
    @memcpy(previous_buf[0..previous_len], session.active_input_method[0..previous_len]);
    const previous_input_method = previous_buf[0..previous_len];

    if (commit_current) {
        const preedit_session_id = session.preedit.session_id;
        const result = session.ime_engine.setActiveInputMethod(new_method) catch {
            return;
        };
        const committed = result.committed_text orelse "";
        _ = ime_consumer.consumeImeResult(result, session, pty_fd, pty_ops, null);
        sendPreeditEnd(broadcast_context, preedit_session_id, "committed", committed);
        session.preedit.owner = null;
        session.preedit.incrementSessionId();
    } else {
        const preedit_session_id = session.preedit.session_id;
        session.ime_engine.reset();
        session.setPreedit(null);
        session.preedit.owner = null;
        _ = session.ime_engine.setActiveInputMethod(new_method) catch {
            return;
        };
        sendPreeditEnd(broadcast_context, preedit_session_id, "cancelled", "");
        session.preedit.incrementSessionId();
    }

    // Update session's active input method.
    const new_len: u8 = @intCast(@min(new_method.len, types.MAX_INPUT_METHOD_NAME));
    @memcpy(session.active_input_method[0..new_len], new_method[0..new_len]);
    if (new_len < types.MAX_INPUT_METHOD_NAME) {
        @memset(session.active_input_method[new_len..], 0);
    }
    session.active_input_method_length = new_len;

    // Broadcast InputMethodAck.
    sendInputMethodAck(
        broadcast_context,
        new_method,
        previous_input_method,
        session.getActiveKeyboardLayout(),
    );
}

/// Error recovery (see ime-procedures spec).
/// Best-effort commit + reset to known-good state.
pub fn errorRecovery(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
) void {
    errorRecoveryWithBroadcast(session, pty_fd, pty_ops, null);
}

/// Error recovery with broadcast context.
pub fn errorRecoveryWithBroadcast(
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    broadcast_context: ?*const BroadcastContext,
) void {
    const preedit_session_id = session.preedit.session_id;
    const had_owner = session.preedit.owner != null;
    if (session.current_preedit) |preedit| {
        _ = pty_ops.write(pty_fd, preedit) catch {};
    }
    session.ime_engine.reset();
    session.setPreedit(null);
    session.preedit.owner = null;
    if (had_owner) {
        sendPreeditEnd(broadcast_context, preedit_session_id, "cancelled", "");
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "ownershipTransfer: flushes, clears preedit, increments session_id, sets owner" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "committed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
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
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "flushed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 5;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onClientDisconnect(&session, 5, 10, &pty_ops);

    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqualSlices(u8, "flushed", mock_pty.written());
}

test "onClientDisconnect: non-owner disconnects -> no-op" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 5;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onClientDisconnect(&session, 99, 10, &pty_ops);

    try std.testing.expectEqual(@as(?types.ClientId, 5), session.preedit.owner);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
}

test "onFocusChange: flushes to old pane, updates focused_pane" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "text", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.focused_pane = 0;
    session.preedit.owner = 42;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onFocusChange(&session, 42, &pty_ops, 3);

    try std.testing.expectEqualSlices(u8, "text", mock_pty.written());
    try std.testing.expectEqual(@as(?types.PaneSlot, 3), session.focused_pane);
    try std.testing.expect(session.current_preedit == null);
}

test "onPaneClose: resets (not flushes), clears preedit and owner, increments session_id" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 10;
    session.setPreedit("composing");

    onPaneClose(&session);

    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
    try std.testing.expect(session.current_preedit == null);
    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqual(@as(u32, 1), session.preedit.session_id);
}

test "onPaneClose: no owner -> no session_id increment" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.setPreedit("composing");

    onPaneClose(&session);

    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expect(session.current_preedit == null);
    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqual(@as(u32, 0), session.preedit.session_id);
}

test "onAlternateScreenSwitch: flushes and clears" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "flushed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onAlternateScreenSwitch(&session, 10, &pty_ops);

    try std.testing.expectEqualSlices(u8, "flushed", mock_pty.written());
    try std.testing.expect(session.current_preedit == null);
}

test "onMouseClick: flushes composition before mouse event" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "click", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onMouseClick(&session, 10, &pty_ops);

    try std.testing.expectEqualSlices(u8, "click", mock_pty.written());
}

test "onInputMethodSwitch: commit_current=true flushes atomically and clears owner" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock = mock_ime.MockImeEngine{
        .set_active_input_method_result = .{ .committed_text = "committed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 5;
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onInputMethodSwitch(&session, "direct", true, 10, &pty_ops);

    try std.testing.expectEqual(@as(usize, 1), mock.set_active_input_method_count);
    try std.testing.expectEqualSlices(u8, "committed", mock_pty.written());
    try std.testing.expect(session.current_preedit == null);
    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqual(@as(u32, 1), session.preedit.session_id);
}

test "onInputMethodSwitch: commit_current=false resets and switches" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 5;
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    onInputMethodSwitch(&session, "direct", false, 10, &pty_ops);

    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
    try std.testing.expectEqual(@as(usize, 1), mock.set_active_input_method_count);
    try std.testing.expect(session.current_preedit == null);
    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqual(@as(u32, 1), session.preedit.session_id);
}

test "onInputMethodSwitch: updates session active_input_method" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    try std.testing.expectEqualSlices(u8, "direct", session.getActiveInputMethod());
    onInputMethodSwitch(&session, "korean_2set", true, 10, &pty_ops);
    try std.testing.expectEqualSlices(u8, "korean_2set", session.getActiveInputMethod());
}

test "errorRecovery: best-effort commit + reset to known-good state" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
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
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    errorRecovery(&session, 10, &pty_ops);

    try std.testing.expectEqual(@as(usize, 0), mock_pty.written().len);
    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
}

// ── WithBroadcast Variant Tests ─────────────────────────────────────────────

fn testBroadcastContext(client_manager: *ClientManager, session_id: types.SessionId, seq: *u64) BroadcastContext {
    return .{
        .client_manager = client_manager,
        .session_id = session_id,
        .pane_id = 0,
        .sequence = seq,
    };
}

test "ownershipTransferWithBroadcast: flushes and sends PreeditEnd broadcast" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    const helpers = test_mod.helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "flushed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 42;
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    var seq: u64 = 100;
    var bc = testBroadcastContext(&client_manager, 1, &seq);

    ownershipTransferWithBroadcast(&session, 10, &pty_ops, 99, "replaced_by_other_client", &bc);

    // Verify engine was flushed and text written to PTY.
    try std.testing.expectEqual(@as(usize, 1), mock.flush_count);
    try std.testing.expectEqualSlices(u8, "flushed", mock_pty.written());
    try std.testing.expect(session.current_preedit == null);
    try std.testing.expectEqual(@as(?types.ClientId, 99), session.preedit.owner);
    try std.testing.expectEqual(@as(u32, 1), session.preedit.session_id);
    // Sequence should have been incremented for the PreeditEnd message.
    try std.testing.expect(seq > 100);
    // Client should have received a broadcast message.
    try std.testing.expect(!client.control_channel.direct_queue.isEmpty());

    client.deinit();
}

test "onClientDisconnectWithBroadcast: owner disconnect sends PreeditEnd" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    const helpers = test_mod.helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "text", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 5;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    var seq: u64 = 50;
    var bc = testBroadcastContext(&client_manager, 1, &seq);

    onClientDisconnectWithBroadcast(&session, 5, 10, &pty_ops, &bc);

    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqualSlices(u8, "text", mock_pty.written());
    try std.testing.expect(!client.control_channel.direct_queue.isEmpty());

    client.deinit();
}

test "onClientDisconnectWithBroadcast: non-owner disconnect is a no-op" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    const helpers = test_mod.helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };

    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 5;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    var seq: u64 = 50;
    var bc = testBroadcastContext(&client_manager, 1, &seq);

    onClientDisconnectWithBroadcast(&session, 99, 10, &pty_ops, &bc);

    try std.testing.expectEqual(@as(?types.ClientId, 5), session.preedit.owner);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
}

test "onFocusChangeWithBroadcast: sends PreeditEnd when owner exists" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    const helpers = test_mod.helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    var mock = mock_ime.MockImeEngine{
        .flush_result = .{ .committed_text = "focus", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.focused_pane = 0;
    session.preedit.owner = 42;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    var seq: u64 = 10;
    var bc = testBroadcastContext(&client_manager, 1, &seq);

    onFocusChangeWithBroadcast(&session, 42, &pty_ops, 3, &bc);

    try std.testing.expectEqualSlices(u8, "focus", mock_pty.written());
    try std.testing.expectEqual(@as(?types.PaneSlot, 3), session.focused_pane);
    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expect(!client.control_channel.direct_queue.isEmpty());

    client.deinit();
}

test "onPaneCloseWithBroadcast: sends PreeditEnd when owner exists" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const helpers = test_mod.helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 10;
    session.setPreedit("composing");

    var seq: u64 = 20;
    var bc = testBroadcastContext(&client_manager, 1, &seq);

    onPaneCloseWithBroadcast(&session, &bc);

    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expect(!client.control_channel.direct_queue.isEmpty());

    client.deinit();
}

test "onInputMethodSwitchWithBroadcast: sends PreeditEnd and InputMethodAck" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    const helpers = test_mod.helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    var mock = mock_ime.MockImeEngine{
        .active_input_method = "korean_2set",
        .set_active_input_method_result = .{ .committed_text = "switch", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 5;
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    var seq: u64 = 30;
    var bc = testBroadcastContext(&client_manager, 1, &seq);

    onInputMethodSwitchWithBroadcast(&session, "direct", true, 10, &pty_ops, &bc);

    try std.testing.expectEqualSlices(u8, "switch", mock_pty.written());
    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqualSlices(u8, "direct", session.getActiveInputMethod());
    // Should have sent PreeditEnd + InputMethodAck => 2 broadcast messages.
    try std.testing.expect(seq > 31);
    try std.testing.expect(!client.control_channel.direct_queue.isEmpty());

    client.deinit();
}

test "errorRecoveryWithBroadcast: sends PreeditEnd when owner exists" {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    const helpers = test_mod.helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    var mock = mock_ime.MockImeEngine{};
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 7;
    session.setPreedit("broken");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    var seq: u64 = 40;
    var bc = testBroadcastContext(&client_manager, 1, &seq);

    errorRecoveryWithBroadcast(&session, 10, &pty_ops, &bc);

    try std.testing.expectEqualSlices(u8, "broken", mock_pty.written());
    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expect(!client.control_channel.direct_queue.isEmpty());

    client.deinit();
}
