//! Key encoding helper: HID keycode → ghostty Key translation + key_encode.
//! Free functions, NOT wrapper types — per design spec module-structure.
const std = @import("std");
const ghostty = @import("ghostty");

pub const Key = ghostty.input.Key;
pub const KeyEvent = ghostty.input.KeyEvent;
pub const KeyMods = ghostty.input.KeyMods;
pub const KeyAction = ghostty.input.KeyAction;
pub const KeyEncodeOptions = ghostty.input.KeyEncodeOptions;
pub const Terminal = ghostty.Terminal;

/// Maximum buffer size for a single encoded key sequence.
/// Kitty protocol can produce long sequences; 128 bytes is generous.
pub const max_encode_size = 128;

/// Encode a key event into terminal escape sequence bytes.
/// Returns the slice of `buf` that was written to, or an empty slice
/// if the event produces no output (e.g., bare modifier press in legacy mode).
pub fn encodeKey(
    buf: *[max_encode_size]u8,
    event: KeyEvent,
    opts: KeyEncodeOptions,
) std.Io.Writer.Error![]const u8 {
    var writer: std.Io.Writer = .fixed(buf);
    try ghostty.input.encodeKey(&writer, event, opts);
    return writer.buffered();
}

/// Build KeyEncodeOptions from the terminal's current DEC mode state.
pub fn keyEncodeOptionsFromTerminal(t: *const Terminal) KeyEncodeOptions {
    return KeyEncodeOptions.fromTerminal(t);
}

/// Translate a HID Usage Page 0x07 keycode to a ghostty Key.
/// Returns `.unidentified` for unmapped keycodes.
pub fn hidToKey(hid_keycode: u8) Key {
    if (hid_keycode < hid_to_key_table.len) {
        return hid_to_key_table[hid_keycode];
    }
    return .unidentified;
}

/// Comptime lookup table: HID Usage Page 0x07 keycodes → ghostty Key.
/// Index = HID keycode, value = ghostty Key.
/// Reference: USB HID Usage Tables, Keyboard/Keypad Page.
const hid_to_key_table = blk: {
    var table: [256]Key = .{.unidentified} ** 256;

    // 0x00 = Reserved (no event)
    // 0x01 = ErrorRollOver, 0x02 = POSTFail, 0x03 = ErrorUndefined

    // Letters: 0x04-0x1D → A-Z
    table[0x04] = .key_a;
    table[0x05] = .key_b;
    table[0x06] = .key_c;
    table[0x07] = .key_d;
    table[0x08] = .key_e;
    table[0x09] = .key_f;
    table[0x0A] = .key_g;
    table[0x0B] = .key_h;
    table[0x0C] = .key_i;
    table[0x0D] = .key_j;
    table[0x0E] = .key_k;
    table[0x0F] = .key_l;
    table[0x10] = .key_m;
    table[0x11] = .key_n;
    table[0x12] = .key_o;
    table[0x13] = .key_p;
    table[0x14] = .key_q;
    table[0x15] = .key_r;
    table[0x16] = .key_s;
    table[0x17] = .key_t;
    table[0x18] = .key_u;
    table[0x19] = .key_v;
    table[0x1A] = .key_w;
    table[0x1B] = .key_x;
    table[0x1C] = .key_y;
    table[0x1D] = .key_z;

    // Digits: 0x1E-0x27 → 1-9, 0
    table[0x1E] = .digit_1;
    table[0x1F] = .digit_2;
    table[0x20] = .digit_3;
    table[0x21] = .digit_4;
    table[0x22] = .digit_5;
    table[0x23] = .digit_6;
    table[0x24] = .digit_7;
    table[0x25] = .digit_8;
    table[0x26] = .digit_9;
    table[0x27] = .digit_0;

    // Functional keys
    table[0x28] = .enter;
    table[0x29] = .escape;
    table[0x2A] = .backspace;
    table[0x2B] = .tab;
    table[0x2C] = .space;

    // Symbols
    table[0x2D] = .minus;
    table[0x2E] = .equal;
    table[0x2F] = .bracket_left;
    table[0x30] = .bracket_right;
    table[0x31] = .backslash;
    // 0x32 = Non-US # and ~ (intl)
    table[0x33] = .semicolon;
    table[0x34] = .quote;
    table[0x35] = .backquote;
    table[0x36] = .comma;
    table[0x37] = .period;
    table[0x38] = .slash;
    table[0x39] = .caps_lock;

    // F-keys: 0x3A-0x45 → F1-F12
    table[0x3A] = .f1;
    table[0x3B] = .f2;
    table[0x3C] = .f3;
    table[0x3D] = .f4;
    table[0x3E] = .f5;
    table[0x3F] = .f6;
    table[0x40] = .f7;
    table[0x41] = .f8;
    table[0x42] = .f9;
    table[0x43] = .f10;
    table[0x44] = .f11;
    table[0x45] = .f12;

    // Control pad
    table[0x46] = .print_screen;
    table[0x47] = .scroll_lock;
    table[0x48] = .pause;
    table[0x49] = .insert;
    table[0x4A] = .home;
    table[0x4B] = .page_up;
    table[0x4C] = .delete;
    table[0x4D] = .end;
    table[0x4E] = .page_down;

    // Arrow keys
    table[0x4F] = .arrow_right;
    table[0x50] = .arrow_left;
    table[0x51] = .arrow_down;
    table[0x52] = .arrow_up;

    // Numpad
    table[0x53] = .num_lock;
    table[0x54] = .numpad_divide;
    table[0x55] = .numpad_multiply;
    table[0x56] = .numpad_subtract;
    table[0x57] = .numpad_add;
    table[0x58] = .numpad_enter;
    table[0x59] = .numpad_1;
    table[0x5A] = .numpad_2;
    table[0x5B] = .numpad_3;
    table[0x5C] = .numpad_4;
    table[0x5D] = .numpad_5;
    table[0x5E] = .numpad_6;
    table[0x5F] = .numpad_7;
    table[0x60] = .numpad_8;
    table[0x61] = .numpad_9;
    table[0x62] = .numpad_0;
    table[0x63] = .numpad_decimal;

    // International
    table[0x64] = .intl_backslash;

    // Extended F-keys: 0x68-0x73 → F13-F24
    table[0x68] = .f13;
    table[0x69] = .f14;
    table[0x6A] = .f15;
    table[0x6B] = .f16;
    table[0x6C] = .f17;
    table[0x6D] = .f18;
    table[0x6E] = .f19;
    table[0x6F] = .f20;
    table[0x70] = .f21;
    table[0x71] = .f22;
    table[0x72] = .f23;
    table[0x73] = .f24;

    // Modifier keys
    table[0xE0] = .control_left;
    table[0xE1] = .shift_left;
    table[0xE2] = .alt_left;
    table[0xE3] = .meta_left;
    table[0xE4] = .control_right;
    table[0xE5] = .shift_right;
    table[0xE6] = .alt_right;
    table[0xE7] = .meta_right;

    break :blk table;
};

// --- Tests ---

test "hidToKey: maps A-Z correctly" {
    try std.testing.expectEqual(Key.key_a, hidToKey(0x04));
    try std.testing.expectEqual(Key.key_z, hidToKey(0x1D));
    try std.testing.expectEqual(Key.key_h, hidToKey(0x0B));
}

test "hidToKey: maps digits correctly" {
    try std.testing.expectEqual(Key.digit_1, hidToKey(0x1E));
    try std.testing.expectEqual(Key.digit_0, hidToKey(0x27));
}

test "hidToKey: maps functional keys" {
    try std.testing.expectEqual(Key.enter, hidToKey(0x28));
    try std.testing.expectEqual(Key.escape, hidToKey(0x29));
    try std.testing.expectEqual(Key.backspace, hidToKey(0x2A));
    try std.testing.expectEqual(Key.tab, hidToKey(0x2B));
    try std.testing.expectEqual(Key.space, hidToKey(0x2C));
}

test "hidToKey: maps arrow keys" {
    try std.testing.expectEqual(Key.arrow_up, hidToKey(0x52));
    try std.testing.expectEqual(Key.arrow_down, hidToKey(0x51));
    try std.testing.expectEqual(Key.arrow_left, hidToKey(0x50));
    try std.testing.expectEqual(Key.arrow_right, hidToKey(0x4F));
}

test "hidToKey: maps F-keys" {
    try std.testing.expectEqual(Key.f1, hidToKey(0x3A));
    try std.testing.expectEqual(Key.f12, hidToKey(0x45));
    try std.testing.expectEqual(Key.f13, hidToKey(0x68));
    try std.testing.expectEqual(Key.f24, hidToKey(0x73));
}

test "hidToKey: maps modifier keys" {
    try std.testing.expectEqual(Key.control_left, hidToKey(0xE0));
    try std.testing.expectEqual(Key.shift_left, hidToKey(0xE1));
    try std.testing.expectEqual(Key.alt_left, hidToKey(0xE2));
    try std.testing.expectEqual(Key.meta_left, hidToKey(0xE3));
}

test "hidToKey: returns unidentified for unmapped codes" {
    try std.testing.expectEqual(Key.unidentified, hidToKey(0x00));
    try std.testing.expectEqual(Key.unidentified, hidToKey(0x01));
    try std.testing.expectEqual(Key.unidentified, hidToKey(0xFF));
}

test "hidToKey: maps numpad keys" {
    try std.testing.expectEqual(Key.numpad_0, hidToKey(0x62));
    try std.testing.expectEqual(Key.numpad_9, hidToKey(0x61));
    try std.testing.expectEqual(Key.numpad_enter, hidToKey(0x58));
    try std.testing.expectEqual(Key.num_lock, hidToKey(0x53));
}

test "encodeKey: produces output for Enter key in legacy mode" {
    var buf: [max_encode_size]u8 = undefined;
    const event: KeyEvent = .{
        .key = .enter,
        .action = .press,
    };
    const result = try encodeKey(&buf, event, .default);
    // Enter should produce "\r" (carriage return) in legacy mode
    try std.testing.expectEqualStrings("\r", result);
}

test "encodeKey: produces arrow key escape sequence" {
    var buf: [max_encode_size]u8 = undefined;
    const event: KeyEvent = .{
        .key = .arrow_up,
        .action = .press,
    };
    const result = try encodeKey(&buf, event, .default);
    // Arrow up in normal mode: ESC [ A
    try std.testing.expectEqualStrings("\x1B[A", result);
}

test "encodeKey: arrow key in application cursor mode" {
    var buf: [max_encode_size]u8 = undefined;
    const event: KeyEvent = .{
        .key = .arrow_up,
        .action = .press,
    };
    var opts: KeyEncodeOptions = .default;
    opts.cursor_key_application = true;
    const result = try encodeKey(&buf, event, opts);
    // Arrow up in application mode: ESC O A
    try std.testing.expectEqualStrings("\x1BOA", result);
}

test "keyEncodeOptionsFromTerminal: reads terminal modes" {
    const terminal_mod = @import("terminal.zig");
    var t = try terminal_mod.initTerminal(std.testing.allocator, 80, 24);
    defer terminal_mod.deinitTerminal(&t, std.testing.allocator);

    const opts = keyEncodeOptionsFromTerminal(&t);
    // Fresh terminal should have cursor_key_application and keypad off
    try std.testing.expect(!opts.cursor_key_application);
    try std.testing.expect(!opts.keypad_key_application);
    // Kitty flags should be disabled
    try std.testing.expectEqual(@as(u5, 0), opts.kitty_flags.int());
}
