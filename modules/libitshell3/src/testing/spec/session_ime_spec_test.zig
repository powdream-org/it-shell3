//! Spec compliance tests: Session/SessionEntry IME-related behavioral requirements.
//!
//! Spec sources:
//!   - daemon-architecture state-and-types (Session/SessionEntry fields)
//!   - daemon-architecture integration-boundaries per-session engine state

const std = @import("std");
const core = @import("itshell3_core");
const types = core.types;
const Session = core.Session;
const server = @import("itshell3_server");
const SessionEntry = server.SessionEntry;
const test_mod = @import("itshell3_testing");
const MockImeEngine = test_mod.MockImeEngine;

// ---- Session.init default behavior ----

test "spec: session init — focused_pane is nullable and defaults to initial slot" {
    var mock = MockImeEngine{};
    var s = Session.init(1, "t", 0, mock.engine());
    try std.testing.expectEqual(@as(?types.PaneSlot, 0), s.focused_pane);
    s.focused_pane = null;
    try std.testing.expect(s.focused_pane == null);
    s.focused_pane = 3;
    try std.testing.expectEqual(@as(?types.PaneSlot, 3), s.focused_pane);
}

test "spec: session init — default input method is direct and layout is qwerty" {
    var mock = MockImeEngine{};
    const s = Session.init(1, "t", 0, mock.engine());
    try std.testing.expectEqualStrings("direct", s.getActiveInputMethod());
    try std.testing.expectEqualStrings("qwerty", s.getActiveKeyboardLayout());
}

test "spec: session init — preedit state defaults to null and zero" {
    var mock = MockImeEngine{};
    const s = Session.init(1, "t", 0, mock.engine());
    try std.testing.expect(s.current_preedit == null);
    try std.testing.expect(s.last_preedit_row == null);
    try std.testing.expect(s.preedit.owner == null);
    try std.testing.expectEqual(@as(u32, 0), s.preedit.session_id);
}

test "spec: session init — truncates name longer than buffer size" {
    var mock = MockImeEngine{};
    const s = Session.init(1, "a" ** 100, 0, mock.engine());
    try std.testing.expectEqual(@as(u8, 64), s.name_length);
}

// ---- SessionEntry default behavior ----

test "spec: session entry init — latest_client_id defaults to 0" {
    var mock = MockImeEngine{};
    const entry = SessionEntry.init(Session.init(1, "t", 0, mock.engine()));
    try std.testing.expectEqual(@as(u32, 0), entry.latest_client_id);
}
