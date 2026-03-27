//! Spec compliance tests for MockImeEngine in testing/.
//!
//! Verifies the mock faithfully models the ImeEngine contract.

const std = @import("std");
const core = @import("itshell3_core");
const test_mod = @import("itshell3_testing");
const MockImeEngine = test_mod.MockImeEngine;
const KeyEvent = core.KeyEvent;
const ImeResult = core.ImeResult;

test "spec: mock engine — engine returns valid ImeEngine" {
    var mock = MockImeEngine{};
    const eng = mock.engine();
    try std.testing.expect(@intFromPtr(eng.ptr) != 0);
    try std.testing.expect(@intFromPtr(eng.vtable) != 0);
}

test "spec: mock engine — processKey returns queued results then empty" {
    var mock = MockImeEngine{ .results = &.{
        ImeResult{ .committed_text = "a" },
        ImeResult{ .preedit_text = "b", .preedit_changed = true },
    } };
    const eng = mock.engine();
    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expectEqualStrings("a", eng.processKey(key).committed_text.?);
    try std.testing.expectEqualStrings("b", eng.processKey(key).preedit_text.?);
    try std.testing.expect(eng.processKey(key).committed_text == null);
}

test "spec: mock engine — flush returns result then clears" {
    var mock = MockImeEngine{ .flush_result = .{ .committed_text = "f", .preedit_changed = true } };
    const eng = mock.engine();
    try std.testing.expectEqualStrings("f", eng.flush().committed_text.?);
    try std.testing.expect(eng.flush().committed_text == null); // second flush empty
}

test "spec: mock engine — reset increments count" {
    var mock = MockImeEngine{};
    mock.engine().reset();
    mock.engine().reset();
    try std.testing.expectEqual(@as(usize, 2), mock.reset_count);
}

test "spec: mock engine — isEmpty returns configured value" {
    var mock = MockImeEngine{ .is_empty_val = false };
    try std.testing.expect(!mock.engine().isEmpty());
    mock.is_empty_val = true;
    try std.testing.expect(mock.engine().isEmpty());
}

test "spec: mock engine — deactivate returns configured result" {
    var mock = MockImeEngine{ .deactivate_result = .{ .committed_text = "d" } };
    try std.testing.expectEqualStrings("d", mock.engine().deactivate().committed_text.?);
    try std.testing.expectEqual(@as(usize, 1), mock.deactivate_count);
}

test "spec: mock engine — getActiveInputMethod defaults to direct" {
    var mock = MockImeEngine{};
    try std.testing.expectEqualStrings("direct", mock.engine().getActiveInputMethod());
}

test "spec: mock engine — setActiveInputMethod rejects unknown method" {
    var mock = MockImeEngine{};
    try std.testing.expectError(error.UnsupportedInputMethod, mock.engine().setActiveInputMethod("japanese"));
    try std.testing.expectEqual(@as(usize, 1), mock.set_active_input_method_count);
}

test "spec: mock engine — setActiveInputMethod accepts direct and korean_2set" {
    var mock = MockImeEngine{ .set_active_input_method_result = .{ .committed_text = "x" } };
    const r = try mock.engine().setActiveInputMethod("korean_2set");
    try std.testing.expectEqualStrings("x", r.committed_text.?);
}

test "spec: mock engine — last_process_key tracks last key" {
    var mock = MockImeEngine{};
    _ = mock.engine().processKey(.{ .hid_keycode = 0x15, .modifiers = .{ .ctrl = true }, .shift = true, .action = .press });
    try std.testing.expectEqual(@as(u16, 0x15), mock.last_process_key.?.hid_keycode);
    try std.testing.expect(mock.last_process_key.?.modifiers.ctrl);
    try std.testing.expect(mock.last_process_key.?.shift);
}
