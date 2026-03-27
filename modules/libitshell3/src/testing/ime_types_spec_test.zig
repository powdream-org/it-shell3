//! Spec compliance tests: KeyEvent, ImeResult, ImeEngine behavioral requirements.
//!
//! Spec sources:
//!   - interface-contract types spec (KeyEvent, ImeResult)
//!   - interface-contract engine-interface spec (ImeEngine vtable)

const std = @import("std");
const core = @import("itshell3_core");
const KeyEvent = core.KeyEvent;
const ImeResult = core.ImeResult;
const test_mod = @import("itshell3_testing");
const MockImeEngine = test_mod.MockImeEngine;

// ---- KeyEvent behavioral spec ----

test "hasCompositionBreakingModifier: Shift does NOT break composition" {
    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{}, .shift = true, .action = .press };
    try std.testing.expect(!key.hasCompositionBreakingModifier());
}

test "hasCompositionBreakingModifier: Ctrl/Alt/Super all break composition" {
    for ([_]KeyEvent.Modifiers{
        .{ .ctrl = true },
        .{ .alt = true },
        .{ .super_key = true },
    }) |mods| {
        const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = mods, .shift = false, .action = .press };
        try std.testing.expect(key.hasCompositionBreakingModifier());
    }
}

test "isPrintablePosition: letters 0x04-0x27, punctuation 0x2D-0x38, gap 0x28-0x2C excluded" {
    // Letters+digits range
    var code: u8 = 0x04;
    while (code <= 0x27) : (code += 1) {
        const k = KeyEvent{ .hid_keycode = code, .modifiers = .{}, .shift = false, .action = .press };
        try std.testing.expect(k.isPrintablePosition());
    }
    // Gap: Enter, Escape, Backspace, Tab, Space — spec explicitly excludes
    for ([_]u8{ 0x28, 0x29, 0x2A, 0x2B, 0x2C }) |c| {
        const k = KeyEvent{ .hid_keycode = c, .modifiers = .{}, .shift = false, .action = .press };
        try std.testing.expect(!k.isPrintablePosition());
    }
    // Punctuation range
    code = 0x2D;
    while (code <= 0x38) : (code += 1) {
        const k = KeyEvent{ .hid_keycode = code, .modifiers = .{}, .shift = false, .action = .press };
        try std.testing.expect(k.isPrintablePosition());
    }
    // Boundaries: below and above ranges
    const below = KeyEvent{ .hid_keycode = 0x03, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(!below.isPrintablePosition());
    const above = KeyEvent{ .hid_keycode = 0x39, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(!above.isPrintablePosition());
}

// ---- ImeResult behavioral spec ----

test "ImeResult: default constructor produces all-null/false state" {
    const r = ImeResult{};
    try std.testing.expect(r.committed_text == null);
    try std.testing.expect(r.preedit_text == null);
    try std.testing.expect(r.forward_key == null);
    try std.testing.expect(!r.preedit_changed);
}

// ---- ImeEngine vtable behavioral spec ----

test "ImeEngine: convenience wrappers dispatch all 8 methods through vtable" {
    var mock = MockImeEngine{};
    const eng = mock.engine();
    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{}, .shift = false, .action = .press };

    _ = eng.processKey(key);
    _ = eng.flush();
    eng.reset();
    try std.testing.expect(eng.isEmpty());
    eng.activate();
    _ = eng.deactivate();
    try std.testing.expectEqualStrings("direct", eng.getActiveInputMethod());
    _ = try eng.setActiveInputMethod("korean_2set");
}

test "setActiveInputMethod: unknown method returns error.UnsupportedInputMethod" {
    var mock = MockImeEngine{};
    try std.testing.expectError(error.UnsupportedInputMethod, mock.engine().setActiveInputMethod("japanese_romaji"));
}
