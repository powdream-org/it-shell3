const std = @import("std");
const core = @import("itshell3_core");
const ImeEngine = core.ImeEngine;
const KeyEvent = core.KeyEvent;
const ImeResult = core.ImeResult;

/// Result of key routing through Phase 0 and Phase 1.
pub const RouteResult = union(enum) {
    /// Key was consumed by Phase 0 (language toggle).
    /// The ImeResult from setActiveInputMethod is included for toggle keys
    /// so the caller can consume committed_text from the flush.
    consumed: ImeResult,

    /// Key bypassed IME entirely (HID keycode > HID_KEYCODE_MAX).
    /// The original KeyEvent is returned for direct ghostty encoding.
    bypassed: KeyEvent,

    /// Key was processed by Phase 1 (engine.processKey).
    /// ImeResult must be consumed before the next engine call.
    processed: ImeResult,
};

/// Language toggle key configuration.
/// Phase 0 checks if a key matches a toggle binding.
pub const ToggleBinding = struct {
    hid_keycode: u8,
    /// The input method to toggle to. If the engine is already in this method,
    /// toggle to "direct" instead.
    toggle_method: []const u8,
    /// If true, only trigger on press (not repeat/release).
    press_only: bool = true,
};

/// Route a key event through Phase 0 (shortcut interception) and Phase 1
/// (engine.processKey). Phase 2 (I/O + ghostty) is the caller's responsibility.
///
/// Phase 0 checks:
/// 1. Language toggle keys -> setActiveInputMethod, consume result, STOP.
/// 2. HID keycode > HID_KEYCODE_MAX -> bypass IME entirely.
/// 3. Otherwise -> Phase 1: engine.processKey.
///
/// TODO(Plan 8): Spec integration-boundaries Phase 0 step 2 defines "Check global daemon shortcuts
/// -> STOP." Not yet implemented — daemon keybinding system is not designed.
/// Add a shortcut binding parameter when keybinding design is done.
pub fn routeKeyEvent(
    engine: ImeEngine,
    key: KeyEvent,
    toggle_bindings: []const ToggleBinding,
) RouteResult {
    // Phase 0: Check language toggle keys
    for (toggle_bindings) |binding| {
        if (key.hid_keycode == binding.hid_keycode) {
            if (binding.press_only and key.action != .press) continue;
            // Toggle: if already in the target method, switch to "direct";
            // otherwise switch to the target method.
            const current = engine.getActiveInputMethod();
            const target = if (std.mem.eql(u8, current, binding.toggle_method))
                "direct"
            else
                binding.toggle_method;
            const result = engine.setActiveInputMethod(target) catch |err| switch (err) {
                error.UnsupportedInputMethod => {
                    // Should not happen with valid toggle bindings. Log and continue.
                    return .{ .processed = engine.processKey(key) };
                },
            };
            return .{ .consumed = result };
        }
    }

    // Phase 0: HID keycode > HID_KEYCODE_MAX -> bypass IME entirely
    if (key.hid_keycode > KeyEvent.HID_KEYCODE_MAX) {
        return .{ .bypassed = key };
    }

    // Phase 1: engine.processKey
    return .{ .processed = engine.processKey(key) };
}

// ── Tests ────────────────────────────────────────────────────────────────────

const mock_ime = @import("itshell3_testing").mock_ime_engine;

test "routeKeyEvent: normal key goes to Phase 1 processKey" {
    var mock = mock_ime.MockImeEngine{
        .results = &.{.{ .committed_text = "a", .preedit_changed = false }},
    };
    const eng = mock.engine();
    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{}, .shift = false, .action = .press };
    const result = routeKeyEvent(eng, key, &.{});
    switch (result) {
        .processed => |r| {
            try std.testing.expectEqualSlices(u8, "a", r.committed_text.?);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), mock.process_key_count);
}

test "routeKeyEvent: HID keycode > HID_KEYCODE_MAX bypasses IME" {
    var mock = mock_ime.MockImeEngine{};
    const eng = mock.engine();
    const key = KeyEvent{ .hid_keycode = 0xE8, .modifiers = .{}, .shift = false, .action = .press };
    const result = routeKeyEvent(eng, key, &.{});
    switch (result) {
        .bypassed => |k| {
            try std.testing.expectEqual(@as(u8, 0xE8), k.hid_keycode);
        },
        else => return error.TestUnexpectedResult,
    }
    // Engine should NOT have been called
    try std.testing.expectEqual(@as(usize, 0), mock.process_key_count);
}

test "routeKeyEvent: toggle key triggers setActiveInputMethod" {
    var mock = mock_ime.MockImeEngine{
        .active_input_method = "direct",
        .set_aim_result = .{ .preedit_changed = false },
    };
    const eng = mock.engine();
    const bindings = [_]ToggleBinding{
        .{ .hid_keycode = 0xE6, .toggle_method = "korean_2set" }, // Right Alt
    };
    const key = KeyEvent{ .hid_keycode = 0xE6, .modifiers = .{}, .shift = false, .action = .press };
    const result = routeKeyEvent(eng, key, &bindings);
    switch (result) {
        .consumed => {
            // Toggle was handled
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), mock.set_aim_count);
    try std.testing.expectEqual(@as(usize, 0), mock.process_key_count);
}

test "routeKeyEvent: toggle key on repeat is ignored when press_only" {
    var mock = mock_ime.MockImeEngine{
        .results = &.{.{}},
    };
    const eng = mock.engine();
    const bindings = [_]ToggleBinding{
        .{ .hid_keycode = 0xE6, .toggle_method = "korean_2set", .press_only = true },
    };
    const key = KeyEvent{ .hid_keycode = 0xE6, .modifiers = .{}, .shift = false, .action = .repeat };
    const result = routeKeyEvent(eng, key, &bindings);
    // Should go through to Phase 1 since repeat is ignored for press_only toggle
    switch (result) {
        .processed => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 0), mock.set_aim_count);
}

test "routeKeyEvent: toggle when already in target method switches to direct" {
    var mock = mock_ime.MockImeEngine{
        .active_input_method = "korean_2set",
        .set_aim_result = .{ .committed_text = "flushed", .preedit_changed = true },
    };
    const eng = mock.engine();
    const bindings = [_]ToggleBinding{
        .{ .hid_keycode = 0xE6, .toggle_method = "korean_2set" },
    };
    const key = KeyEvent{ .hid_keycode = 0xE6, .modifiers = .{}, .shift = false, .action = .press };
    const result = routeKeyEvent(eng, key, &bindings);
    switch (result) {
        .consumed => |r| {
            // committed_text from flushing the active composition
            try std.testing.expectEqualSlices(u8, "flushed", r.committed_text.?);
        },
        else => return error.TestUnexpectedResult,
    }
    // Should have called setActiveInputMethod with "direct"
    try std.testing.expectEqualSlices(u8, "direct", mock.last_set_aim_method.?);
}

test "routeKeyEvent: HID_KEYCODE_MAX (0xE7) is still processed by IME" {
    var mock = mock_ime.MockImeEngine{
        .results = &.{.{}},
    };
    const eng = mock.engine();
    const key = KeyEvent{ .hid_keycode = 0xE7, .modifiers = .{}, .shift = false, .action = .press };
    const result = routeKeyEvent(eng, key, &.{});
    switch (result) {
        .processed => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), mock.process_key_count);
}
