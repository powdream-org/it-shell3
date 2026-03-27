//! ImeEngine vtable interface for dependency injection.
//! See the IME interface-contract spec for the vtable definition.

const types = @import("types.zig");
pub const KeyEvent = types.KeyEvent;
pub const ImeResult = types.ImeResult;

/// Abstract interface for an IME engine. libitshell3's Session holds an ImeEngine
/// rather than a concrete type, enabling mock injection for tests.
pub const ImeEngine = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        processKey: *const fn (ptr: *anyopaque, key: KeyEvent) ImeResult,
        flush: *const fn (ptr: *anyopaque) ImeResult,
        reset: *const fn (ptr: *anyopaque) void,
        isEmpty: *const fn (ptr: *anyopaque) bool,
        activate: *const fn (ptr: *anyopaque) void,
        deactivate: *const fn (ptr: *anyopaque) ImeResult,
        getActiveInputMethod: *const fn (ptr: *anyopaque) []const u8,
        setActiveInputMethod: *const fn (ptr: *anyopaque, method: []const u8) error{UnsupportedInputMethod}!ImeResult,
    };

    pub fn processKey(self: ImeEngine, key: KeyEvent) ImeResult {
        return self.vtable.processKey(self.ptr, key);
    }

    pub fn flush(self: ImeEngine) ImeResult {
        return self.vtable.flush(self.ptr);
    }

    pub fn reset(self: ImeEngine) void {
        self.vtable.reset(self.ptr);
    }

    pub fn isEmpty(self: ImeEngine) bool {
        return self.vtable.isEmpty(self.ptr);
    }

    pub fn activate(self: ImeEngine) void {
        self.vtable.activate(self.ptr);
    }

    pub fn deactivate(self: ImeEngine) ImeResult {
        return self.vtable.deactivate(self.ptr);
    }

    pub fn getActiveInputMethod(self: ImeEngine) []const u8 {
        return self.vtable.getActiveInputMethod(self.ptr);
    }

    pub fn setActiveInputMethod(self: ImeEngine, method: []const u8) error{UnsupportedInputMethod}!ImeResult {
        return self.vtable.setActiveInputMethod(self.ptr, method);
    }
};

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

const std = @import("std");

test "ImeEngine: vtable dispatch works via MockImeEngine" {
    const MockImeEngine = @import("testing/mocks/mock_engine.zig").MockImeEngine;
    var mock = MockImeEngine{};
    const eng = mock.engine();

    // processKey returns empty result by default
    const result = eng.processKey(.{
        .hid_keycode = 0x04,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    });
    try std.testing.expect(result.committed_text == null);
    try std.testing.expect(result.forward_key == null);

    // isEmpty returns true by default
    try std.testing.expect(eng.isEmpty());

    // getActiveInputMethod returns "direct" by default
    try std.testing.expectEqualStrings("direct", eng.getActiveInputMethod());
}
