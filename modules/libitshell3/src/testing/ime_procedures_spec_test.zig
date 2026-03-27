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
const MockPtyWriter = test_mod.MockPtyWriter;
const procs = server.ime_procedures;

// ---- Ownership transfer ----

test "ownershipTransfer: flush, clear preedit, increment session_id, update owner" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "c", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine());
    s.preedit.owner = 42;
    s.preedit.session_id = 5;
    s.setPreedit("active");
    var pw = MockPtyWriter{};

    procs.ownershipTransfer(&s, 10, pw.writer(), 99);

    try std.testing.expectEqualStrings("c", pw.written());
    try std.testing.expect(s.current_preedit == null);
    try std.testing.expectEqual(@as(u32, 6), s.preedit.session_id);
    try std.testing.expectEqual(@as(?types.ClientId, 99), s.preedit.owner);
}

// ---- Client disconnect/detach/eviction ----

test "onClientDisconnect: owner disconnects -> flush, owner=null" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "d", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine());
    s.preedit.owner = 5;
    var pw = MockPtyWriter{};
    procs.onClientDisconnect(&s, 5, 10, pw.writer());
    try std.testing.expect(s.preedit.owner == null);
    try std.testing.expectEqualStrings("d", pw.written());
}

test "onClientDisconnect: non-owner -> no-op" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine());
    s.preedit.owner = 5;
    var pw = MockPtyWriter{};
    procs.onClientDisconnect(&s, 99, 10, pw.writer());
    try std.testing.expectEqual(@as(?types.ClientId, 5), s.preedit.owner);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
}

test "onClientDisconnect: no active composition -> no-op" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine());
    var pw = MockPtyWriter{};
    procs.onClientDisconnect(&s, 42, 10, pw.writer());
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
}

// ---- Focus change ----

test "onFocusChange: flush to OLD pane, then update focused_pane" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "old", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine());
    var pw = MockPtyWriter{};
    procs.onFocusChange(&s, 42, pw.writer(), 3);
    try std.testing.expectEqualStrings("old", pw.written());
    try std.testing.expectEqual(@as(?types.PaneSlot, 3), s.focused_pane);
    try std.testing.expect(s.current_preedit == null);
}

test "onFocusChange: empty engine still updates focused_pane" {
    var mock = MockImeEngine{ .flush_result = .{} };
    var s = Session.init(1, "t", 0, mock.engine());
    var pw = MockPtyWriter{};
    procs.onFocusChange(&s, 42, pw.writer(), 5);
    try std.testing.expectEqual(@as(?types.PaneSlot, 5), s.focused_pane);
    try std.testing.expectEqual(@as(usize, 0), pw.written().len);
}

// ---- Pane close ----

test "onPaneClose: reset NOT flush, clear preedit/owner, increment session_id" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine());
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

test "onAlternateScreenSwitch: flush and clear" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "alt", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine());
    s.setPreedit("comp");
    var pw = MockPtyWriter{};
    procs.onAlternateScreenSwitch(&s, 10, pw.writer());
    try std.testing.expectEqualStrings("alt", pw.written());
    try std.testing.expect(s.current_preedit == null);
}

// ---- Mouse ----

test "onMouseClick: flushes before forwarding" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "click", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine());
    var pw = MockPtyWriter{};
    procs.onMouseClick(&s, 10, pw.writer());
    try std.testing.expectEqualStrings("click", pw.written());
}

// ---- InputMethodSwitch ----

test "onInputMethodSwitch: commit_current=true flushes atomically" {
    var mock = MockImeEngine{ .set_aim_result = .{ .committed_text = "sw", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine());
    s.setPreedit("comp");
    var pw = MockPtyWriter{};
    procs.onInputMethodSwitch(&s, "direct", true, 10, pw.writer());
    try std.testing.expectEqual(@as(usize, 1), mock.set_aim_count);
    try std.testing.expectEqualStrings("sw", pw.written());
    try std.testing.expect(s.current_preedit == null);
}

test "onInputMethodSwitch: commit_current=false resets and switches" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine());
    s.preedit.owner = 5;
    s.preedit.session_id = 7;
    s.setPreedit("comp");
    var pw = MockPtyWriter{};
    procs.onInputMethodSwitch(&s, "direct", false, 10, pw.writer());
    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
    try std.testing.expectEqual(@as(usize, 1), mock.set_aim_count);
    try std.testing.expect(s.current_preedit == null);
    try std.testing.expect(s.preedit.owner == null);
    try std.testing.expectEqual(@as(u32, 8), s.preedit.session_id);
    try std.testing.expectEqual(@as(usize, 0), pw.written().len);
}

// ---- Error recovery ----

test "errorRecovery: best-effort commit + reset to known-good state" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine());
    s.preedit.owner = 7;
    s.setPreedit("broken");
    var pw = MockPtyWriter{};
    procs.errorRecovery(&s, 10, pw.writer());
    try std.testing.expectEqualStrings("broken", pw.written());
    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expect(s.current_preedit == null);
    try std.testing.expect(s.preedit.owner == null);
}

// ---- No composition restoration on focus return ----

test "no composition restoration after focus return" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "x", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine());
    s.preedit.owner = 1;
    var pw = MockPtyWriter{};
    procs.onFocusChange(&s, 42, pw.writer(), 3);
    // Switch back -- engine empty, no restoration
    mock.flush_result = .{};
    pw = MockPtyWriter{};
    procs.onFocusChange(&s, 43, pw.writer(), 0);
    try std.testing.expectEqual(@as(usize, 0), pw.written().len);
}
