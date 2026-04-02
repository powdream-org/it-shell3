const std = @import("std");
const KeyEvent = @import("itshell3_core").KeyEvent;

/// Decompose a wire modifier byte and HID keycode into a KeyEvent.
///
/// The wire protocol carries hid_keycode as u16, but the daemon-internal
/// KeyEvent uses u8 (valid HID range 0x00-0xE7). Keycodes above 0xFF
/// are clamped to 0 (invalid/unknown), as they cannot represent valid
/// USB HID Keyboard/Keypad page codes. Keycodes in range 0x00-0xFF are
/// narrowed to u8 via @intCast.
///
/// Wire modifier bitmask layout (from protocol input-and-renderstate spec):
///   Bit 0: Shift     -> KeyEvent.shift
///   Bit 1: Ctrl      -> KeyEvent.modifiers.ctrl
///   Bit 2: Alt       -> KeyEvent.modifiers.alt
///   Bit 3: Super/Cmd -> KeyEvent.modifiers.super_key
///   Bit 4: CapsLock  -> KeyEvent.modifiers.caps_lock
///   Bit 5: NumLock   -> KeyEvent.modifiers.num_lock
pub fn decomposeWireEvent(
    hid_keycode: u16,
    wire_modifiers: u8,
    action: KeyEvent.Action,
) KeyEvent {
    // Validate wire u16 keycode to daemon-internal u8.
    // Keycodes > 0xFF are outside the USB HID Keyboard/Keypad page
    // and cannot be represented in u8 -- clamp to 0.
    const validated_keycode: u8 = if (hid_keycode > std.math.maxInt(u8))
        0
    else
        @intCast(hid_keycode);

    return KeyEvent{
        .hid_keycode = validated_keycode,
        .shift = (wire_modifiers & 0x01) != 0,
        .modifiers = .{
            .ctrl = (wire_modifiers & 0x02) != 0,
            .alt = (wire_modifiers & 0x04) != 0,
            .super_key = (wire_modifiers & 0x08) != 0,
            .caps_lock = (wire_modifiers & 0x10) != 0,
            .num_lock = (wire_modifiers & 0x20) != 0,
        },
        .action = action,
    };
}

// -- Tests --

test "decomposeWireEvent: no modifiers" {
    const key = decomposeWireEvent(0x04, 0x00, .press);
    try std.testing.expectEqual(@as(u8, 0x04), key.hid_keycode);
    try std.testing.expect(!key.shift);
    try std.testing.expect(!key.modifiers.ctrl);
    try std.testing.expect(!key.modifiers.alt);
    try std.testing.expect(!key.modifiers.super_key);
    try std.testing.expectEqual(KeyEvent.Action.press, key.action);
}

test "decomposeWireEvent: shift only (bit 0)" {
    const key = decomposeWireEvent(0x04, 0x01, .press);
    try std.testing.expect(key.shift);
    try std.testing.expect(!key.modifiers.ctrl);
    try std.testing.expect(!key.modifiers.alt);
    try std.testing.expect(!key.modifiers.super_key);
}

test "decomposeWireEvent: ctrl only (bit 1)" {
    const key = decomposeWireEvent(0x04, 0x02, .press);
    try std.testing.expect(!key.shift);
    try std.testing.expect(key.modifiers.ctrl);
    try std.testing.expect(!key.modifiers.alt);
    try std.testing.expect(!key.modifiers.super_key);
}

test "decomposeWireEvent: alt only (bit 2)" {
    const key = decomposeWireEvent(0x04, 0x04, .press);
    try std.testing.expect(!key.shift);
    try std.testing.expect(!key.modifiers.ctrl);
    try std.testing.expect(key.modifiers.alt);
    try std.testing.expect(!key.modifiers.super_key);
}

test "decomposeWireEvent: super only (bit 3)" {
    const key = decomposeWireEvent(0x04, 0x08, .press);
    try std.testing.expect(!key.shift);
    try std.testing.expect(!key.modifiers.ctrl);
    try std.testing.expect(!key.modifiers.alt);
    try std.testing.expect(key.modifiers.super_key);
}

test "decomposeWireEvent: CapsLock (bit 4) populates caps_lock field" {
    const key = decomposeWireEvent(0x04, 0x10, .press);
    try std.testing.expect(!key.shift);
    try std.testing.expect(!key.modifiers.ctrl);
    try std.testing.expect(!key.modifiers.alt);
    try std.testing.expect(!key.modifiers.super_key);
    try std.testing.expect(key.modifiers.caps_lock);
    try std.testing.expect(!key.modifiers.num_lock);
    // CapsLock does not break composition.
    try std.testing.expect(!key.hasCompositionBreakingModifier());
}

test "decomposeWireEvent: NumLock (bit 5) populates num_lock field" {
    const key = decomposeWireEvent(0x04, 0x20, .press);
    try std.testing.expect(!key.shift);
    try std.testing.expect(!key.modifiers.ctrl);
    try std.testing.expect(!key.modifiers.alt);
    try std.testing.expect(!key.modifiers.super_key);
    try std.testing.expect(!key.modifiers.caps_lock);
    try std.testing.expect(key.modifiers.num_lock);
    // NumLock does not break composition.
    try std.testing.expect(!key.hasCompositionBreakingModifier());
}

test "decomposeWireEvent: all modifier bits set" {
    const key = decomposeWireEvent(0x15, 0x3F, .press);
    try std.testing.expectEqual(@as(u8, 0x15), key.hid_keycode);
    try std.testing.expect(key.shift);
    try std.testing.expect(key.modifiers.ctrl);
    try std.testing.expect(key.modifiers.alt);
    try std.testing.expect(key.modifiers.super_key);
}

test "decomposeWireEvent: action repeat" {
    const key = decomposeWireEvent(0x04, 0x00, .repeat);
    try std.testing.expectEqual(KeyEvent.Action.repeat, key.action);
}

test "decomposeWireEvent: action release" {
    const key = decomposeWireEvent(0x04, 0x00, .release);
    try std.testing.expectEqual(KeyEvent.Action.release, key.action);
}

test "decomposeWireEvent: wire u16 keycode > 0xFF is clamped to 0" {
    // Wire protocol carries u16 but daemon-internal KeyEvent uses u8.
    // Keycodes exceeding u8 range are invalid HID codes and clamped to 0.
    const key = decomposeWireEvent(0x0100, 0x00, .press);
    try std.testing.expectEqual(@as(u8, 0), key.hid_keycode);
    try std.testing.expectEqual(KeyEvent.Action.press, key.action);

    // Also test a value near the u16 maximum.
    const high_key = decomposeWireEvent(0xFFFF, 0x03, .release);
    try std.testing.expectEqual(@as(u8, 0), high_key.hid_keycode);
    try std.testing.expect(high_key.shift);
    try std.testing.expect(high_key.modifiers.ctrl);
    try std.testing.expectEqual(KeyEvent.Action.release, high_key.action);
}

test "decomposeWireEvent: wire u16 keycode 0xFF narrows to u8 correctly" {
    // 0xFF fits in u8 and should be narrowed, not clamped.
    const key = decomposeWireEvent(0xFF, 0x00, .press);
    try std.testing.expectEqual(@as(u8, 0xFF), key.hid_keycode);
}

test "decomposeWireEvent: shift+ctrl combo (bits 0+1)" {
    const key = decomposeWireEvent(0x04, 0x03, .press);
    try std.testing.expect(key.shift);
    try std.testing.expect(key.modifiers.ctrl);
    try std.testing.expect(!key.modifiers.alt);
    try std.testing.expect(!key.modifiers.super_key);
}
