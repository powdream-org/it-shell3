//! IME engine interface and key event types for the input pipeline.
//! Defines the vtable-based ImeEngine abstraction that Session holds,
//! enabling mock injection for tests.

const std = @import("std");

/// A key event from the client, represented as a physical key press.
pub const KeyEvent = struct {
    /// USB HID usage code (Keyboard page 0x07).
    /// Represents the PHYSICAL key position, not the character produced.
    /// e.g., 0x04 = 'a' position, 0x28 = Enter, 0x4F = Right Arrow
    /// Valid range: 0x00-HID_KEYCODE_MAX (0xE7).
    hid_keycode: u16,

    /// Modifier key state (excluding Shift -- see `shift` field).
    modifiers: Modifiers,

    /// Shift key state. Separated from modifiers because Shift changes
    /// the character produced (e.g., 'r'->ㄱ vs 'R'->ㄲ in Korean 2-set),
    /// whereas Ctrl/Alt/Cmd trigger composition flush.
    shift: bool,

    /// Key press action.
    action: Action,

    pub const Action = enum(u8) {
        press = 0,
        release = 1,
        repeat = 2,
    };

    pub const Modifiers = packed struct(u8) {
        ctrl: bool = false,
        alt: bool = false,
        super_key: bool = false,
        _padding: u5 = 0,
    };

    /// Maximum valid USB HID keycode for the Keyboard/Keypad page (0x07).
    /// The IME engine handles keycodes in the range 0x00-0xE7 only.
    /// The server MUST NOT pass keycodes above HID_KEYCODE_MAX to processKey().
    /// Keycodes above this value bypass the IME engine entirely and are
    /// routed directly to ghostty.
    pub const HID_KEYCODE_MAX: u16 = 0xE7;

    /// Returns true if any composition-breaking modifier is held.
    pub fn hasCompositionBreakingModifier(self: KeyEvent) bool {
        return self.modifiers.ctrl or self.modifiers.alt or self.modifiers.super_key;
    }

    /// Returns true if this key position produces a printable character
    /// (letter, digit, or punctuation) on a US ANSI keyboard.
    /// Based on USB HID Keyboard/Keypad page (0x07).
    ///
    /// Printable ranges:
    ///   0x04-0x27  a-z (0x04-0x1D), 1-0 (0x1E-0x27)
    ///   0x2D-0x38  punctuation: - = [ ] \ # ; ' ` , . /
    ///
    /// Explicitly excluded control keys in the gap 0x28-0x2C:
    ///   0x28 Enter, 0x29 Escape, 0x2A Backspace, 0x2B Tab, 0x2C Space
    pub fn isPrintablePosition(self: KeyEvent) bool {
        return (self.hid_keycode >= 0x04 and self.hid_keycode <= 0x27) or
            (self.hid_keycode >= 0x2D and self.hid_keycode <= 0x38);
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
    /// Used for dirty tracking -- only send preedit updates to client
    /// when this is true.
    preedit_changed: bool = false,
};

/// Abstract interface for an IME engine. libitshell3's Session holds an ImeEngine
/// rather than a concrete type, enabling mock injection for tests.
///
/// Modeled after fcitx5's InputMethodEngine: a minimal interface where only
/// processKey() is required. activate/deactivate handle session-level focus changes.
pub const ImeEngine = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Process a key event. Returns committed text, preedit update,
        /// and/or a key to forward. This is the only required method.
        processKey: *const fn (ptr: *anyopaque, key: KeyEvent) ImeResult,

        /// Flush and commit any in-progress composition.
        /// Returns ImeResult with committed text (if composing) or empty.
        /// Also called internally by deactivate().
        flush: *const fn (ptr: *anyopaque) ImeResult,

        /// Discard in-progress composition without committing.
        /// No ImeResult returned -- composition is silently discarded.
        reset: *const fn (ptr: *anyopaque) void,

        /// Query whether composition is in progress.
        isEmpty: *const fn (ptr: *anyopaque) bool,

        /// Signal the engine that it is becoming active.
        /// No-op for Korean (state is preserved in the buffer).
        /// Active input method is preserved across
        /// deactivate/activate cycles -- NOT reset to direct.
        activate: *const fn (ptr: *anyopaque) void,

        /// Signal the engine that it is going idle.
        /// Engine MUST flush pending composition before returning.
        /// The returned ImeResult contains the flushed text.
        deactivate: *const fn (ptr: *anyopaque) ImeResult,

        // --- Input method management ---

        /// Get current active input method identifier.
        /// Returns a canonical string (e.g., "direct", "korean_2set").
        getActiveInputMethod: *const fn (ptr: *anyopaque) []const u8,

        /// Set active input method. Flushes pending composition atomically
        /// if switching away from a composing input method.
        /// Returns error.UnsupportedInputMethod if the string is not recognized.
        setActiveInputMethod: *const fn (ptr: *anyopaque, method: []const u8) error{UnsupportedInputMethod}!ImeResult,
    };

    // ── Convenience wrappers ──────────────────────────────────────────────

    /// Dispatch a key event to the underlying engine.
    pub fn processKey(self: ImeEngine, key: KeyEvent) ImeResult {
        return self.vtable.processKey(self.ptr, key);
    }

    /// Flush and commit any in-progress composition.
    pub fn flush(self: ImeEngine) ImeResult {
        return self.vtable.flush(self.ptr);
    }

    /// Discard in-progress composition without committing.
    pub fn reset(self: ImeEngine) void {
        self.vtable.reset(self.ptr);
    }

    /// Whether the composition buffer is empty.
    pub fn isEmpty(self: ImeEngine) bool {
        return self.vtable.isEmpty(self.ptr);
    }

    /// Signal the engine that it is becoming active.
    pub fn activate(self: ImeEngine) void {
        self.vtable.activate(self.ptr);
    }

    /// Signal the engine that it is going idle. Flushes pending composition.
    pub fn deactivate(self: ImeEngine) ImeResult {
        return self.vtable.deactivate(self.ptr);
    }

    /// Current active input method identifier (e.g., "direct", "korean_2set").
    pub fn getActiveInputMethod(self: ImeEngine) []const u8 {
        return self.vtable.getActiveInputMethod(self.ptr);
    }

    /// Switch the active input method, flushing pending composition atomically.
    pub fn setActiveInputMethod(self: ImeEngine, method: []const u8) error{UnsupportedInputMethod}!ImeResult {
        return self.vtable.setActiveInputMethod(self.ptr, method);
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

// Trivial test engine that returns empty results and tracks calls.
const TestEngine = struct {
    process_key_count: usize = 0,
    flush_count: usize = 0,
    reset_count: usize = 0,
    is_empty_val: bool = true,
    activate_count: usize = 0,
    deactivate_count: usize = 0,

    fn engine(self: *TestEngine) ImeEngine {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    const vtable = ImeEngine.VTable{
        .processKey = processKeyImpl,
        .flush = flushImpl,
        .reset = resetImpl,
        .isEmpty = isEmptyImpl,
        .activate = activateImpl,
        .deactivate = deactivateImpl,
        .getActiveInputMethod = getActiveInputMethodImpl,
        .setActiveInputMethod = setActiveInputMethodImpl,
    };

    fn processKeyImpl(ptr: *anyopaque, _: KeyEvent) ImeResult {
        const self: *TestEngine = @ptrCast(@alignCast(ptr));
        self.process_key_count += 1;
        return .{};
    }

    fn flushImpl(ptr: *anyopaque) ImeResult {
        const self: *TestEngine = @ptrCast(@alignCast(ptr));
        self.flush_count += 1;
        return .{};
    }

    fn resetImpl(ptr: *anyopaque) void {
        const self: *TestEngine = @ptrCast(@alignCast(ptr));
        self.reset_count += 1;
    }

    fn isEmptyImpl(ptr: *anyopaque) bool {
        const self: *TestEngine = @ptrCast(@alignCast(ptr));
        return self.is_empty_val;
    }

    fn activateImpl(ptr: *anyopaque) void {
        const self: *TestEngine = @ptrCast(@alignCast(ptr));
        self.activate_count += 1;
    }

    fn deactivateImpl(ptr: *anyopaque) ImeResult {
        const self: *TestEngine = @ptrCast(@alignCast(ptr));
        self.deactivate_count += 1;
        return .{};
    }

    fn getActiveInputMethodImpl(_: *anyopaque) []const u8 {
        return "direct";
    }

    fn setActiveInputMethodImpl(_: *anyopaque, method: []const u8) error{UnsupportedInputMethod}!ImeResult {
        if (std.mem.eql(u8, method, "direct") or std.mem.eql(u8, method, "korean_2set")) {
            return .{};
        }
        return error.UnsupportedInputMethod;
    }
};

test "ImeEngine vtable: processKey dispatches through vtable" {
    var te = TestEngine{};
    const eng = te.engine();
    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{}, .shift = false, .action = .press };
    _ = eng.processKey(key);
    try std.testing.expectEqual(@as(usize, 1), te.process_key_count);
}

test "ImeEngine vtable: flush dispatches through vtable" {
    var te = TestEngine{};
    const eng = te.engine();
    _ = eng.flush();
    try std.testing.expectEqual(@as(usize, 1), te.flush_count);
}

test "ImeEngine vtable: reset dispatches through vtable" {
    var te = TestEngine{};
    const eng = te.engine();
    eng.reset();
    try std.testing.expectEqual(@as(usize, 1), te.reset_count);
}

test "ImeEngine vtable: isEmpty dispatches through vtable" {
    var te = TestEngine{};
    const eng = te.engine();
    try std.testing.expect(eng.isEmpty());
    te.is_empty_val = false;
    try std.testing.expect(!eng.isEmpty());
}

test "ImeEngine vtable: activate dispatches through vtable" {
    var te = TestEngine{};
    const eng = te.engine();
    eng.activate();
    try std.testing.expectEqual(@as(usize, 1), te.activate_count);
}

test "ImeEngine vtable: deactivate dispatches through vtable" {
    var te = TestEngine{};
    const eng = te.engine();
    _ = eng.deactivate();
    try std.testing.expectEqual(@as(usize, 1), te.deactivate_count);
}

test "ImeEngine vtable: getActiveInputMethod returns string" {
    var te = TestEngine{};
    const eng = te.engine();
    try std.testing.expectEqualSlices(u8, "direct", eng.getActiveInputMethod());
}

test "ImeEngine vtable: setActiveInputMethod success" {
    var te = TestEngine{};
    const eng = te.engine();
    _ = try eng.setActiveInputMethod("korean_2set");
}

test "ImeEngine vtable: setActiveInputMethod error for unknown method" {
    var te = TestEngine{};
    const eng = te.engine();
    try std.testing.expectError(error.UnsupportedInputMethod, eng.setActiveInputMethod("japanese_hiragana"));
}

test "KeyEvent.hasCompositionBreakingModifier: no modifiers" {
    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(!key.hasCompositionBreakingModifier());
}

test "KeyEvent.hasCompositionBreakingModifier: shift alone does not break" {
    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{}, .shift = true, .action = .press };
    try std.testing.expect(!key.hasCompositionBreakingModifier());
}

test "KeyEvent.hasCompositionBreakingModifier: ctrl breaks" {
    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{ .ctrl = true }, .shift = false, .action = .press };
    try std.testing.expect(key.hasCompositionBreakingModifier());
}

test "KeyEvent.hasCompositionBreakingModifier: alt breaks" {
    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{ .alt = true }, .shift = false, .action = .press };
    try std.testing.expect(key.hasCompositionBreakingModifier());
}

test "KeyEvent.hasCompositionBreakingModifier: super breaks" {
    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{ .super_key = true }, .shift = false, .action = .press };
    try std.testing.expect(key.hasCompositionBreakingModifier());
}

test "KeyEvent.isPrintablePosition: letter range 0x04-0x27" {
    // 'a' position
    const key_a = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(key_a.isPrintablePosition());
    // '0' position (end of range)
    const key_0 = KeyEvent{ .hid_keycode = 0x27, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(key_0.isPrintablePosition());
}

test "KeyEvent.isPrintablePosition: punctuation range 0x2D-0x38" {
    const key_minus = KeyEvent{ .hid_keycode = 0x2D, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(key_minus.isPrintablePosition());
    const key_slash = KeyEvent{ .hid_keycode = 0x38, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(key_slash.isPrintablePosition());
}

test "KeyEvent.isPrintablePosition: control keys 0x28-0x2C excluded" {
    // Enter
    const key_enter = KeyEvent{ .hid_keycode = 0x28, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(!key_enter.isPrintablePosition());
    // Escape
    const key_esc = KeyEvent{ .hid_keycode = 0x29, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(!key_esc.isPrintablePosition());
    // Backspace
    const key_bs = KeyEvent{ .hid_keycode = 0x2A, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(!key_bs.isPrintablePosition());
    // Tab
    const key_tab = KeyEvent{ .hid_keycode = 0x2B, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(!key_tab.isPrintablePosition());
    // Space
    const key_space = KeyEvent{ .hid_keycode = 0x2C, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(!key_space.isPrintablePosition());
}

test "KeyEvent.isPrintablePosition: below 0x04 excluded" {
    const key = KeyEvent{ .hid_keycode = 0x03, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(!key.isPrintablePosition());
}

test "KeyEvent.isPrintablePosition: above 0x38 excluded" {
    const key = KeyEvent{ .hid_keycode = 0x39, .modifiers = .{}, .shift = false, .action = .press };
    try std.testing.expect(!key.isPrintablePosition());
}

test "KeyEvent.HID_KEYCODE_MAX: is 0xE7 with u16 type" {
    try std.testing.expectEqual(@as(u16, 0xE7), KeyEvent.HID_KEYCODE_MAX);
}

test "KeyEvent.Action: has explicit integer tags per protocol spec" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(KeyEvent.Action.press));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(KeyEvent.Action.release));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(KeyEvent.Action.repeat));
}

test "ImeResult: default is all null/false" {
    const result = ImeResult{};
    try std.testing.expect(result.committed_text == null);
    try std.testing.expect(result.preedit_text == null);
    try std.testing.expect(result.forward_key == null);
    try std.testing.expect(!result.preedit_changed);
}

test "ImeResult: all fields can be set" {
    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{}, .shift = false, .action = .press };
    const result = ImeResult{
        .committed_text = "han",
        .preedit_text = "ga",
        .forward_key = key,
        .preedit_changed = true,
    };
    try std.testing.expectEqualSlices(u8, "han", result.committed_text.?);
    try std.testing.expectEqualSlices(u8, "ga", result.preedit_text.?);
    try std.testing.expect(result.forward_key != null);
    try std.testing.expect(result.preedit_changed);
}

test "Modifiers packed struct: bit layout" {
    const ctrl_only = KeyEvent.Modifiers{ .ctrl = true };
    try std.testing.expectEqual(@as(u8, 0b001), @as(u8, @bitCast(ctrl_only)));

    const alt_only = KeyEvent.Modifiers{ .alt = true };
    try std.testing.expectEqual(@as(u8, 0b010), @as(u8, @bitCast(alt_only)));

    const super_only = KeyEvent.Modifiers{ .super_key = true };
    try std.testing.expectEqual(@as(u8, 0b100), @as(u8, @bitCast(super_only)));

    const all = KeyEvent.Modifiers{ .ctrl = true, .alt = true, .super_key = true };
    try std.testing.expectEqual(@as(u8, 0b111), @as(u8, @bitCast(all)));
}
