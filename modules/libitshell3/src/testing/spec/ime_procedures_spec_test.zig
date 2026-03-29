//! Spec compliance tests: IME Procedures.
//!
//! Spec source: daemon-behavior ime-procedures (ownership transfer, client-triggered,
//! state-triggered, input-triggered, error recovery).

const std = @import("std");
const core = @import("itshell3_core");
const server = @import("itshell3_server");
const test_mod = @import("itshell3_testing");
const Session = core.Session;
const types = core.types;
const MockImeEngine = test_mod.MockImeEngine;
const MockPtyOps = test_mod.MockPtyOps;
const procs = server.ime.procedures;

// ---- Ownership transfer ----

test "spec: ownership transfer — flush, clear preedit, increment session_id, update owner" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "c", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    s.preedit.owner = 42;
    s.preedit.session_id = 5;
    s.setPreedit("active");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    procs.ownershipTransfer(&s, 10, &pty_ops, 99);

    try std.testing.expectEqualStrings("c", mock_pty.written());
    try std.testing.expect(s.current_preedit == null);
    try std.testing.expectEqual(@as(u32, 6), s.preedit.session_id);
    try std.testing.expectEqual(@as(?types.ClientId, 99), s.preedit.owner);
}

// ---- Client disconnect/detach/eviction ----

test "spec: client disconnect — owner disconnects triggers flush and clears owner" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "d", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    s.preedit.owner = 5;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    procs.onClientDisconnect(&s, 5, 10, &pty_ops);
    try std.testing.expect(s.preedit.owner == null);
    try std.testing.expectEqualStrings("d", mock_pty.written());
}

test "spec: client disconnect — non-owner disconnect is no-op" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    s.preedit.owner = 5;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    procs.onClientDisconnect(&s, 99, 10, &pty_ops);
    try std.testing.expectEqual(@as(?types.ClientId, 5), s.preedit.owner);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
}

test "spec: client disconnect — no active composition is no-op" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    procs.onClientDisconnect(&s, 42, 10, &pty_ops);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
}

// ---- Focus change ----

test "spec: focus change — flush to old pane then update focused_pane" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "old", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    procs.onFocusChange(&s, 42, &pty_ops, 3);
    try std.testing.expectEqualStrings("old", mock_pty.written());
    try std.testing.expectEqual(@as(?types.PaneSlot, 3), s.focused_pane);
    try std.testing.expect(s.current_preedit == null);
}

test "spec: focus change — empty engine still updates focused_pane" {
    var mock = MockImeEngine{ .flush_result = .{} };
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    procs.onFocusChange(&s, 42, &pty_ops, 5);
    try std.testing.expectEqual(@as(?types.PaneSlot, 5), s.focused_pane);
    try std.testing.expectEqual(@as(usize, 0), mock_pty.written().len);
}

// ---- Pane close ----

test "spec: pane close — reset not flush, clear preedit and owner, increment session_id" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    s.preedit.owner = 1;
    s.preedit.session_id = 3;
    s.setPreedit("comp");

    procs.onPaneClose(&s);

    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
    try std.testing.expect(s.current_preedit == null);
    try std.testing.expect(s.preedit.owner == null);
    try std.testing.expectEqual(@as(u32, 4), s.preedit.session_id);
}

// ---- Alternate screen ----

test "spec: alternate screen switch — flush and clear" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "alt", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    s.setPreedit("comp");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    procs.onAlternateScreenSwitch(&s, 10, &pty_ops);
    try std.testing.expectEqualStrings("alt", mock_pty.written());
    try std.testing.expect(s.current_preedit == null);
}

// ---- Mouse ----

test "spec: mouse click — flushes before forwarding" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "click", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    procs.onMouseClick(&s, 10, &pty_ops);
    try std.testing.expectEqualStrings("click", mock_pty.written());
}

// ---- InputMethodSwitch ----

test "spec: input method switch — commit_current true flushes atomically" {
    var mock = MockImeEngine{ .set_active_input_method_result = .{ .committed_text = "sw", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    s.setPreedit("comp");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    procs.onInputMethodSwitch(&s, "direct", true, 10, &pty_ops);
    try std.testing.expectEqual(@as(usize, 1), mock.set_active_input_method_count);
    try std.testing.expectEqualStrings("sw", mock_pty.written());
    try std.testing.expect(s.current_preedit == null);
}

test "spec: input method switch — commit_current false resets and switches" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    s.preedit.owner = 5;
    s.preedit.session_id = 7;
    s.setPreedit("comp");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    procs.onInputMethodSwitch(&s, "direct", false, 10, &pty_ops);
    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
    try std.testing.expectEqual(@as(usize, 1), mock.set_active_input_method_count);
    try std.testing.expect(s.current_preedit == null);
    try std.testing.expect(s.preedit.owner == null);
    try std.testing.expectEqual(@as(u32, 8), s.preedit.session_id);
    try std.testing.expectEqual(@as(usize, 0), mock_pty.written().len);
}

// ---- Error recovery ----

test "spec: error recovery — best-effort commit plus reset to known-good state" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    s.preedit.owner = 7;
    s.setPreedit("broken");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    procs.errorRecovery(&s, 10, &pty_ops);
    try std.testing.expectEqualStrings("broken", mock_pty.written());
    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expect(s.current_preedit == null);
    try std.testing.expect(s.preedit.owner == null);
}

// ---- No composition restoration on focus return ----

test "spec: focus return — no composition restoration after focus return" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "x", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine(), 0);
    s.preedit.owner = 1;
    var mock_pty = MockPtyOps{};
    var pty_ops = mock_pty.ops();
    procs.onFocusChange(&s, 42, &pty_ops, 3);
    // Switch back -- engine empty, no restoration
    mock.flush_result = .{};
    mock_pty = MockPtyOps{};
    pty_ops = mock_pty.ops();
    procs.onFocusChange(&s, 43, &pty_ops, 0);
    try std.testing.expectEqual(@as(usize, 0), mock_pty.written().len);
}
