//! HID-to-ASCII lookup tables for US QWERTY keyboard layout.
//! Used by the IME engine to convert physical key positions to ASCII
//! characters for feeding to hangul_ic_process().
//!
//! Covers HID keycodes 0x04–0x38 (letters, digits, punctuation).

const std = @import("std");

/// Convert a HID keycode to its ASCII character on US QWERTY layout.
/// Returns null if the keycode is not a printable character.
pub fn hidToAscii(hid_keycode: u8, shift: bool) ?u8 {
    if (hid_keycode < 0x04 or hid_keycode > 0x38) return null;
    const idx = hid_keycode - 0x04;
    const entry = table[idx];
    if (entry.unshifted == 0) return null;
    return if (shift) entry.shifted else entry.unshifted;
}

const Entry = struct {
    unshifted: u8,
    shifted: u8,
};

/// Lookup table indexed by (hid_keycode - 0x04).
/// HID 0x04..0x38 = 53 entries.
const table = [53]Entry{
    // 0x04–0x1D: Letters a–z / A–Z
    .{ .unshifted = 'a', .shifted = 'A' }, // 0x04
    .{ .unshifted = 'b', .shifted = 'B' }, // 0x05
    .{ .unshifted = 'c', .shifted = 'C' }, // 0x06
    .{ .unshifted = 'd', .shifted = 'D' }, // 0x07
    .{ .unshifted = 'e', .shifted = 'E' }, // 0x08
    .{ .unshifted = 'f', .shifted = 'F' }, // 0x09
    .{ .unshifted = 'g', .shifted = 'G' }, // 0x0A
    .{ .unshifted = 'h', .shifted = 'H' }, // 0x0B
    .{ .unshifted = 'i', .shifted = 'I' }, // 0x0C
    .{ .unshifted = 'j', .shifted = 'J' }, // 0x0D
    .{ .unshifted = 'k', .shifted = 'K' }, // 0x0E
    .{ .unshifted = 'l', .shifted = 'L' }, // 0x0F
    .{ .unshifted = 'm', .shifted = 'M' }, // 0x10
    .{ .unshifted = 'n', .shifted = 'N' }, // 0x11
    .{ .unshifted = 'o', .shifted = 'O' }, // 0x12
    .{ .unshifted = 'p', .shifted = 'P' }, // 0x13
    .{ .unshifted = 'q', .shifted = 'Q' }, // 0x14
    .{ .unshifted = 'r', .shifted = 'R' }, // 0x15
    .{ .unshifted = 's', .shifted = 'S' }, // 0x16
    .{ .unshifted = 't', .shifted = 'T' }, // 0x17
    .{ .unshifted = 'u', .shifted = 'U' }, // 0x18
    .{ .unshifted = 'v', .shifted = 'V' }, // 0x19
    .{ .unshifted = 'w', .shifted = 'W' }, // 0x1A
    .{ .unshifted = 'x', .shifted = 'X' }, // 0x1B
    .{ .unshifted = 'y', .shifted = 'Y' }, // 0x1C
    .{ .unshifted = 'z', .shifted = 'Z' }, // 0x1D

    // 0x1E–0x27: Digits 1–9, 0 / Shifted symbols
    .{ .unshifted = '1', .shifted = '!' }, // 0x1E
    .{ .unshifted = '2', .shifted = '@' }, // 0x1F
    .{ .unshifted = '3', .shifted = '#' }, // 0x20
    .{ .unshifted = '4', .shifted = '$' }, // 0x21
    .{ .unshifted = '5', .shifted = '%' }, // 0x22
    .{ .unshifted = '6', .shifted = '^' }, // 0x23
    .{ .unshifted = '7', .shifted = '&' }, // 0x24
    .{ .unshifted = '8', .shifted = '*' }, // 0x25
    .{ .unshifted = '9', .shifted = '(' }, // 0x26
    .{ .unshifted = '0', .shifted = ')' }, // 0x27

    // 0x28–0x2B: Enter, Escape, Backspace, Tab — NOT printable characters
    // They are handled as special keys by the engine, but they fall within
    // the printable HID range (0x04–0x38). Return 0 so hidToAscii returns null.
    .{ .unshifted = 0, .shifted = 0 }, // 0x28 Enter
    .{ .unshifted = 0, .shifted = 0 }, // 0x29 Escape
    .{ .unshifted = 0, .shifted = 0 }, // 0x2A Backspace
    .{ .unshifted = 0, .shifted = 0 }, // 0x2B Tab

    // 0x2C: Space
    .{ .unshifted = ' ', .shifted = ' ' }, // 0x2C

    // 0x2D–0x38: Punctuation / symbols
    .{ .unshifted = '-', .shifted = '_' }, // 0x2D
    .{ .unshifted = '=', .shifted = '+' }, // 0x2E
    .{ .unshifted = '[', .shifted = '{' }, // 0x2F
    .{ .unshifted = ']', .shifted = '}' }, // 0x30
    .{ .unshifted = '\\', .shifted = '|' }, // 0x31
    .{ .unshifted = 0, .shifted = 0 }, // 0x32 Non-US # (not on US ANSI)
    .{ .unshifted = ';', .shifted = ':' }, // 0x33
    .{ .unshifted = '\'', .shifted = '"' }, // 0x34
    .{ .unshifted = '`', .shifted = '~' }, // 0x35
    .{ .unshifted = ',', .shifted = '<' }, // 0x36
    .{ .unshifted = '.', .shifted = '>' }, // 0x37
    .{ .unshifted = '/', .shifted = '?' }, // 0x38
};

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

test "hidToAscii: letters unshifted" {
    try std.testing.expectEqual(@as(?u8, 'a'), hidToAscii(0x04, false));
    try std.testing.expectEqual(@as(?u8, 'z'), hidToAscii(0x1D, false));
    try std.testing.expectEqual(@as(?u8, 'r'), hidToAscii(0x15, false));
    try std.testing.expectEqual(@as(?u8, 'k'), hidToAscii(0x0E, false));
}

test "hidToAscii: letters shifted" {
    try std.testing.expectEqual(@as(?u8, 'A'), hidToAscii(0x04, true));
    try std.testing.expectEqual(@as(?u8, 'Z'), hidToAscii(0x1D, true));
    try std.testing.expectEqual(@as(?u8, 'R'), hidToAscii(0x15, true));
}

test "hidToAscii: digits and symbols" {
    try std.testing.expectEqual(@as(?u8, '1'), hidToAscii(0x1E, false));
    try std.testing.expectEqual(@as(?u8, '!'), hidToAscii(0x1E, true));
    try std.testing.expectEqual(@as(?u8, '0'), hidToAscii(0x27, false));
    try std.testing.expectEqual(@as(?u8, ')'), hidToAscii(0x27, true));
}

test "hidToAscii: special keys return null" {
    try std.testing.expectEqual(@as(?u8, null), hidToAscii(0x28, false)); // Enter
    try std.testing.expectEqual(@as(?u8, null), hidToAscii(0x29, false)); // Escape
    try std.testing.expectEqual(@as(?u8, null), hidToAscii(0x2A, false)); // Backspace
    try std.testing.expectEqual(@as(?u8, null), hidToAscii(0x2B, false)); // Tab
}

test "hidToAscii: space" {
    try std.testing.expectEqual(@as(?u8, ' '), hidToAscii(0x2C, false));
    try std.testing.expectEqual(@as(?u8, ' '), hidToAscii(0x2C, true));
}

test "hidToAscii: punctuation" {
    try std.testing.expectEqual(@as(?u8, '-'), hidToAscii(0x2D, false));
    try std.testing.expectEqual(@as(?u8, '_'), hidToAscii(0x2D, true));
    try std.testing.expectEqual(@as(?u8, ';'), hidToAscii(0x33, false));
    try std.testing.expectEqual(@as(?u8, ':'), hidToAscii(0x33, true));
    try std.testing.expectEqual(@as(?u8, '/'), hidToAscii(0x38, false));
    try std.testing.expectEqual(@as(?u8, '?'), hidToAscii(0x38, true));
}

test "hidToAscii: out of range returns null" {
    try std.testing.expectEqual(@as(?u8, null), hidToAscii(0x00, false));
    try std.testing.expectEqual(@as(?u8, null), hidToAscii(0x03, false));
    try std.testing.expectEqual(@as(?u8, null), hidToAscii(0x39, false)); // CapsLock
    try std.testing.expectEqual(@as(?u8, null), hidToAscii(0x4F, false)); // Arrow Right
    try std.testing.expectEqual(@as(?u8, null), hidToAscii(0xE7, false)); // Max HID
}

test "hidToAscii: Non-US hash returns null" {
    try std.testing.expectEqual(@as(?u8, null), hidToAscii(0x32, false));
    try std.testing.expectEqual(@as(?u8, null), hidToAscii(0x32, true));
}

test "hidToAscii: all 26 letters are mapped" {
    for (0x04..0x1E) |hid| {
        const ch = hidToAscii(@intCast(hid), false);
        try std.testing.expect(ch != null);
        try std.testing.expect(ch.? >= 'a' and ch.? <= 'z');
    }
}
