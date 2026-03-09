//! Core types for libitshell3-ime: KeyEvent (input) and ImeResult (output).
//! Follows IME Interface Contract v0.7, Section 3.1–3.2.

const std = @import("std");

/// A key event from the client, represented as a physical key press.
/// This is the input to the IME engine's processKey() method.
pub const KeyEvent = struct {
    /// USB HID usage code (Keyboard page 0x07).
    /// Represents the PHYSICAL key position, not the character produced.
    /// e.g., 0x04 = 'a' position, 0x28 = Enter, 0x4F = Right Arrow
    /// Valid range: 0x00–HID_KEYCODE_MAX (0xE7).
    hid_keycode: u8,

    /// Modifier key state (excluding Shift -- see `shift` field).
    modifiers: Modifiers,

    /// Shift key state. Separated from modifiers because Shift changes
    /// the character produced (e.g., 'r'->ㄱ vs 'R'->ㄲ in Korean 2-set),
    /// whereas Ctrl/Alt/Cmd trigger composition flush.
    shift: bool,

    /// Key press action.
    action: Action,

    pub const Action = enum {
        press,
        release,
        repeat,
    };

    pub const Modifiers = packed struct(u8) {
        ctrl: bool = false,
        alt: bool = false,
        super_key: bool = false,
        _padding: u5 = 0,
    };

    /// Maximum valid USB HID keycode for the Keyboard/Keypad page (0x07).
    pub const HID_KEYCODE_MAX: u8 = 0xE7;

    /// Returns true if any composition-breaking modifier is held.
    pub fn hasCompositionBreakingModifier(self: KeyEvent) bool {
        return self.modifiers.ctrl or self.modifiers.alt or self.modifiers.super_key;
    }

    /// Returns true if this is a printable key position (letters, digits, punctuation).
    /// Based on HID usage codes for the US ANSI keyboard.
    pub fn isPrintablePosition(self: KeyEvent) bool {
        return (self.hid_keycode >= 0x04 and self.hid_keycode <= 0x38);
    }
};

/// The result of processing a key event through the IME engine.
/// All fields are orthogonal -- any combination is valid.
///
/// Memory: all slices point into internal buffers owned by the ImeEngine
/// instance. They are valid until the next call to processKey(), flush(),
/// reset(), deactivate(), or setActiveInputMethod() on the SAME engine instance.
pub const ImeResult = struct {
    /// UTF-8 text to commit to the terminal (write to PTY).
    /// null if nothing to commit.
    committed_text: ?[]const u8 = null,

    /// UTF-8 preedit text for display overlay.
    /// null if no active composition.
    preedit_text: ?[]const u8 = null,

    /// Key event to forward to the terminal (for escape sequence encoding).
    /// null if the key was fully consumed by the IME.
    forward_key: ?KeyEvent = null,

    /// True if preedit state changed from the previous call.
    preedit_changed: bool = false,
};

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

test "KeyEvent: hasCompositionBreakingModifier" {
    const no_mod = KeyEvent{
        .hid_keycode = 0x04,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(!no_mod.hasCompositionBreakingModifier());

    const shift_only = KeyEvent{
        .hid_keycode = 0x04,
        .modifiers = .{},
        .shift = true,
        .action = .press,
    };
    try std.testing.expect(!shift_only.hasCompositionBreakingModifier());

    const ctrl = KeyEvent{
        .hid_keycode = 0x04,
        .modifiers = .{ .ctrl = true },
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(ctrl.hasCompositionBreakingModifier());

    const alt = KeyEvent{
        .hid_keycode = 0x04,
        .modifiers = .{ .alt = true },
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(alt.hasCompositionBreakingModifier());

    const super = KeyEvent{
        .hid_keycode = 0x04,
        .modifiers = .{ .super_key = true },
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(super.hasCompositionBreakingModifier());
}

test "KeyEvent: isPrintablePosition" {
    // 'a' = 0x04 — printable
    const a_key = KeyEvent{
        .hid_keycode = 0x04,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(a_key.isPrintablePosition());

    // '/' = 0x38 — printable (upper bound)
    const slash_key = KeyEvent{
        .hid_keycode = 0x38,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(slash_key.isPrintablePosition());

    // Enter = 0x28 — inside printable range (digits/symbols area)
    const enter_key = KeyEvent{
        .hid_keycode = 0x28,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(enter_key.isPrintablePosition());

    // Arrow = 0x4F — NOT printable
    const arrow_key = KeyEvent{
        .hid_keycode = 0x4F,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(!arrow_key.isPrintablePosition());

    // 0x03 — below printable range
    const low_key = KeyEvent{
        .hid_keycode = 0x03,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(!low_key.isPrintablePosition());

    // 0x39 — just above printable range
    const above_key = KeyEvent{
        .hid_keycode = 0x39,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(!above_key.isPrintablePosition());
}

test "KeyEvent: HID_KEYCODE_MAX" {
    try std.testing.expectEqual(@as(u8, 0xE7), KeyEvent.HID_KEYCODE_MAX);
}

test "KeyEvent.Modifiers: packed struct is 1 byte" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(KeyEvent.Modifiers));
}

test "ImeResult: default is all-null" {
    const result = ImeResult{};
    try std.testing.expect(result.committed_text == null);
    try std.testing.expect(result.preedit_text == null);
    try std.testing.expect(result.forward_key == null);
    try std.testing.expect(!result.preedit_changed);
}
