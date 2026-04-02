//! IME engine interface and key event types for the input pipeline.
//! Defines the vtable-based ImeEngine abstraction that Session holds,
//! enabling mock injection for tests.
//!
//! KeyEvent and ImeResult are imported from libitshell3-ime (canonical source).
//! This file re-exports them so that libitshell3 consumers use a single import path.

const std = @import("std");
const ime_types = @import("itshell3_ime");

/// Re-exported from libitshell3-ime. See the IME interface-contract spec
/// for the canonical type definition.
pub const KeyEvent = ime_types.KeyEvent;

/// Re-exported from libitshell3-ime. See the IME interface-contract spec
/// for the canonical type definition.
pub const ImeResult = ime_types.ImeResult;

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

    // -- Convenience wrappers --

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

// -- Tests --

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
