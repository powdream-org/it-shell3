//! Spec compliance tests: Per-Session IME Engine Lifecycle.
//!
//! Spec sources:
//!   - daemon-architecture integration-boundaries per-session engine lifecycle
//!   - daemon-behavior ime-procedures eager activate/deactivate

const std = @import("std");
const core = @import("itshell3_core");
const server = @import("itshell3_server");
const test_mod = @import("itshell3_testing");
const Session = core.Session;
const MockImeEngine = test_mod.MockImeEngine;
const MockPtyOps = test_mod.MockPtyOps;
const ClientTracker = server.ClientTracker;

test "spec: IME lifecycle — engine created with direct default" {
    var mock = MockImeEngine{ .active_input_method = "direct" };
    const s = Session.init(1, "t", 0, mock.engine());
    try std.testing.expectEqualStrings("direct", s.ime_engine.getActiveInputMethod());
}

test "spec: IME lifecycle — first attach triggers activate" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine());
    var tracker = ClientTracker{};
    tracker.clientAttached(&s);
    try std.testing.expectEqual(@as(u32, 1), tracker.attached_count);
    try std.testing.expectEqual(@as(usize, 1), mock.activate_count);
}

test "spec: IME lifecycle — second attach does not trigger activate again" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine());
    var tracker = ClientTracker{};
    tracker.clientAttached(&s);
    tracker.clientAttached(&s);
    try std.testing.expectEqual(@as(usize, 1), mock.activate_count);
}

test "spec: IME lifecycle — last detach triggers deactivate" {
    var mock = MockImeEngine{ .deactivate_result = .{ .committed_text = "bye", .preedit_changed = true } };
    var s = Session.init(1, "t", 0, mock.engine());
    var tracker = ClientTracker{};
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    tracker.clientAttached(&s);
    const dirty = tracker.clientDetached(&s, 10, &pty_ops);
    try std.testing.expectEqual(@as(usize, 1), mock.deactivate_count);
    try std.testing.expect(dirty);
    try std.testing.expectEqualStrings("bye", mock_pty.written());
}

test "spec: IME lifecycle — detach with remaining clients does not deactivate" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine());
    var tracker = ClientTracker{};
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    tracker.clientAttached(&s);
    tracker.clientAttached(&s);
    const dirty = tracker.clientDetached(&s, 10, &pty_ops);
    try std.testing.expectEqual(@as(usize, 0), mock.deactivate_count);
    try std.testing.expect(!dirty);
}

test "spec: IME lifecycle — language preserved across deactivate and activate" {
    var mock = MockImeEngine{ .active_input_method = "korean_2set", .deactivate_result = .{} };
    var s = Session.init(1, "t", 0, mock.engine());
    var tracker = ClientTracker{};
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    tracker.clientAttached(&s);
    _ = tracker.clientDetached(&s, 10, &pty_ops);
    tracker.clientAttached(&s);
    try std.testing.expectEqualStrings("korean_2set", mock.active_input_method);
}

test "spec: IME lifecycle — deactivate on empty engine returns no-op" {
    var mock = MockImeEngine{ .deactivate_result = .{} };
    var s = Session.init(1, "t", 0, mock.engine());
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    const dirty = server.ime_lifecycle.deactivateSessionIme(&s, 10, &pty_ops);
    try std.testing.expect(!dirty);
    try std.testing.expectEqual(@as(usize, 0), mock_pty.written().len);
}
