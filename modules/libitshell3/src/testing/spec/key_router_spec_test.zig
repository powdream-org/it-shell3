//! Spec compliance tests: Key Router (Phase 0 + Phase 1).
//!
//! Spec source: daemon-architecture integration-boundaries Phase 0/1 pipeline.

const std = @import("std");
const core = @import("itshell3_core");
const input = @import("itshell3_input");
const test_mod = @import("itshell3_testing");
const KeyEvent = core.KeyEvent;
const ImeResult = core.ImeResult;
const MockImeEngine = test_mod.MockImeEngine;
const handleKeyEvent = input.handleKeyEvent;
const RouteResult = input.RouteResult;
const ToggleBinding = input.ToggleBinding;

test "spec: key router — normal key dispatched to Phase 1 processKey" {
    var mock = MockImeEngine{ .results = &.{.{ .committed_text = "a" }} };
    const result = handleKeyEvent(mock.engine(), .{ .hid_keycode = 0x04, .modifiers = .{}, .shift = false, .action = .press }, &.{});
    switch (result) {
        .processed => |r| try std.testing.expectEqualStrings("a", r.committed_text.?),
        else => return error.TestUnexpectedResult,
    }
}

test "spec: key router — HID above HID_KEYCODE_MAX bypasses IME" {
    var mock = MockImeEngine{};
    const result = handleKeyEvent(mock.engine(), .{ .hid_keycode = 0xE8, .modifiers = .{}, .shift = false, .action = .press }, &.{});
    switch (result) {
        .bypassed => |k| try std.testing.expectEqual(@as(u16, 0xE8), k.hid_keycode),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 0), mock.process_key_count);
}

test "spec: key router — HID_KEYCODE_MAX 0xE7 still goes through IME" {
    var mock = MockImeEngine{ .results = &.{.{}} };
    const result = handleKeyEvent(mock.engine(), .{ .hid_keycode = 0xE7, .modifiers = .{}, .shift = false, .action = .press }, &.{});
    switch (result) {
        .processed => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), mock.process_key_count);
}

test "spec: key router — toggle key consumes and calls setActiveInputMethod" {
    var mock = MockImeEngine{ .active_input_method = "direct", .set_active_input_method_result = .{} };
    const bindings = [_]ToggleBinding{.{ .hid_keycode = 0xE6, .toggle_method = "korean_2set" }};
    const result = handleKeyEvent(mock.engine(), .{ .hid_keycode = 0xE6, .modifiers = .{}, .shift = false, .action = .press }, &bindings);
    switch (result) {
        .consumed => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), mock.set_active_input_method_count);
    try std.testing.expectEqual(@as(usize, 0), mock.process_key_count);
}

test "spec: key router — toggle repeat ignored when press_only" {
    var mock = MockImeEngine{ .results = &.{.{}} };
    const bindings = [_]ToggleBinding{.{ .hid_keycode = 0xE6, .toggle_method = "korean_2set", .press_only = true }};
    const result = handleKeyEvent(mock.engine(), .{ .hid_keycode = 0xE6, .modifiers = .{}, .shift = false, .action = .repeat }, &bindings);
    switch (result) {
        .processed => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 0), mock.set_active_input_method_count);
}

test "spec: key router — toggle with unsupported method falls through to processKey" {
    // Edge case: toggle binding references a method the engine does not support.
    // The router catches UnsupportedInputMethod and falls through to Phase 1.
    var mock = MockImeEngine{ .results = &.{.{ .committed_text = "fallthrough" }} };
    const bindings = [_]ToggleBinding{.{ .hid_keycode = 0xE6, .toggle_method = "japanese_romaji" }};
    const result = handleKeyEvent(mock.engine(), .{ .hid_keycode = 0xE6, .modifiers = .{}, .shift = false, .action = .press }, &bindings);
    switch (result) {
        .processed => |r| try std.testing.expectEqualStrings("fallthrough", r.committed_text.?),
        else => return error.TestUnexpectedResult,
    }
    // setActiveInputMethod was attempted (and failed), then processKey was called
    try std.testing.expectEqual(@as(usize, 1), mock.set_active_input_method_count);
    try std.testing.expectEqual(@as(usize, 1), mock.process_key_count);
}

test "spec: key router — toggle when already in target switches to direct" {
    var mock = MockImeEngine{ .active_input_method = "korean_2set", .set_active_input_method_result = .{ .committed_text = "flushed", .preedit_changed = true } };
    const bindings = [_]ToggleBinding{.{ .hid_keycode = 0xE6, .toggle_method = "korean_2set" }};
    const result = handleKeyEvent(mock.engine(), .{ .hid_keycode = 0xE6, .modifiers = .{}, .shift = false, .action = .press }, &bindings);
    switch (result) {
        .consumed => |r| try std.testing.expectEqualStrings("flushed", r.committed_text.?),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("direct", mock.last_set_active_input_method.?);
}
