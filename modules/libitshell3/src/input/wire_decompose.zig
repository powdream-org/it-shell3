const std = @import("std");
const ime_engine_mod = @import("../core/ime_engine.zig");
const KeyEvent = ime_engine_mod.KeyEvent;

/// Decompose a wire modifier byte and HID keycode into a KeyEvent.
///
/// Wire modifier bitmask layout (from protocol doc 04 Section 2.1):
///   Bit 0: Shift     -> KeyEvent.shift
///   Bit 1: Ctrl      -> KeyEvent.modifiers.ctrl
///   Bit 2: Alt       -> KeyEvent.modifiers.alt
///   Bit 3: Super/Cmd -> KeyEvent.modifiers.super_key
///   Bit 4: CapsLock  -> Not consumed by IME
///   Bit 5: NumLock   -> Not consumed by IME
pub fn decomposeWireEvent(
    hid_keycode: u8,
    wire_modifiers: u8,
    action: KeyEvent.Action,
) KeyEvent {
    return KeyEvent{
        .hid_keycode = hid_keycode,
        .shift = (wire_modifiers & 0x01) != 0,
        .modifiers = .{
            .ctrl = (wire_modifiers & 0x02) != 0,
            .alt = (wire_modifiers & 0x04) != 0,
            .super_key = (wire_modifiers & 0x08) != 0,
        },
        .action = action,
    };
}

// ── Tests ────────────────────────────────────────────────────────────────────

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

test "decomposeWireEvent: CapsLock (bit 4) not consumed by IME" {
    const key = decomposeWireEvent(0x04, 0x10, .press);
    // CapsLock bit should NOT affect any KeyEvent field
    try std.testing.expect(!key.shift);
    try std.testing.expect(!key.modifiers.ctrl);
    try std.testing.expect(!key.modifiers.alt);
    try std.testing.expect(!key.modifiers.super_key);
}

test "decomposeWireEvent: NumLock (bit 5) not consumed by IME" {
    const key = decomposeWireEvent(0x04, 0x20, .press);
    try std.testing.expect(!key.shift);
    try std.testing.expect(!key.modifiers.ctrl);
    try std.testing.expect(!key.modifiers.alt);
    try std.testing.expect(!key.modifiers.super_key);
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

test "decomposeWireEvent: shift+ctrl combo (bits 0+1)" {
    const key = decomposeWireEvent(0x04, 0x03, .press);
    try std.testing.expect(key.shift);
    try std.testing.expect(key.modifiers.ctrl);
    try std.testing.expect(!key.modifiers.alt);
    try std.testing.expect(!key.modifiers.super_key);
}
