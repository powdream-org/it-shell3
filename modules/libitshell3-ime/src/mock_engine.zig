//! MockImeEngine for testing libitshell3's handleKeyEvent without libhangul.
//! Follows IME Interface Contract v0.7, Section 3.8.

const std = @import("std");
const engine_mod = @import("engine.zig");
const ImeEngine = engine_mod.ImeEngine;
const KeyEvent = engine_mod.KeyEvent;
const ImeResult = engine_mod.ImeResult;

pub const MockImeEngine = struct {
    /// Queue of results to return from processKey, in order.
    results: []const ImeResult = &.{},
    call_index: usize = 0,
    active_input_method: []const u8 = "direct",
    flush_result: ImeResult = .{},
    is_empty: bool = true,

    pub fn engine(self: *MockImeEngine) ImeEngine {
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
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        if (self.call_index < self.results.len) {
            const result = self.results[self.call_index];
            self.call_index += 1;
            return result;
        }
        return .{};
    }

    fn flushImpl(ptr: *anyopaque) ImeResult {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        const result = self.flush_result;
        self.flush_result = .{};
        self.is_empty = true;
        return result;
    }

    fn resetImpl(ptr: *anyopaque) void {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        self.is_empty = true;
    }

    fn isEmptyImpl(ptr: *anyopaque) bool {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        return self.is_empty;
    }

    fn activateImpl(_: *anyopaque) void {}

    fn deactivateImpl(ptr: *anyopaque) ImeResult {
        return flushImpl(ptr);
    }

    fn getActiveInputMethodImpl(ptr: *anyopaque) []const u8 {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        return self.active_input_method;
    }

    fn setActiveInputMethodImpl(ptr: *anyopaque, method: []const u8) error{UnsupportedInputMethod}!ImeResult {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        if (!std.mem.eql(u8, method, "direct") and
            !std.mem.eql(u8, method, "korean_2set"))
        {
            return error.UnsupportedInputMethod;
        }
        if (std.mem.eql(u8, method, self.active_input_method)) {
            return .{};
        }
        const result = self.flush_result;
        self.flush_result = .{};
        self.active_input_method = method;
        self.is_empty = true;
        return result;
    }
};

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

test "MockImeEngine: processKey returns queued results" {
    const committed = "test";
    var mock = MockImeEngine{
        .results = &.{
            ImeResult{ .committed_text = committed, .preedit_changed = false },
            ImeResult{ .preedit_text = "abc", .preedit_changed = true },
        },
    };
    const eng = mock.engine();

    const key = KeyEvent{
        .hid_keycode = 0x04,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    };

    const r1 = eng.processKey(key);
    try std.testing.expectEqualStrings("test", r1.committed_text.?);

    const r2 = eng.processKey(key);
    try std.testing.expectEqualStrings("abc", r2.preedit_text.?);

    // Exhausted queue — returns empty
    const r3 = eng.processKey(key);
    try std.testing.expect(r3.committed_text == null);
}

test "MockImeEngine: flush returns flush_result then clears" {
    var mock = MockImeEngine{
        .flush_result = ImeResult{ .committed_text = "flushed", .preedit_changed = true },
        .is_empty = false,
    };
    const eng = mock.engine();

    const r1 = eng.flush();
    try std.testing.expectEqualStrings("flushed", r1.committed_text.?);
    try std.testing.expect(mock.is_empty);

    // Second flush returns empty
    const r2 = eng.flush();
    try std.testing.expect(r2.committed_text == null);
}

test "MockImeEngine: reset clears is_empty" {
    var mock = MockImeEngine{ .is_empty = false };
    const eng = mock.engine();
    try std.testing.expect(!eng.isEmpty());
    eng.reset();
    try std.testing.expect(eng.isEmpty());
}

test "MockImeEngine: activate/deactivate" {
    var mock = MockImeEngine{
        .flush_result = ImeResult{ .committed_text = "deact", .preedit_changed = true },
        .is_empty = false,
    };
    const eng = mock.engine();

    eng.activate(); // no-op

    const r = eng.deactivate();
    try std.testing.expectEqualStrings("deact", r.committed_text.?);
    try std.testing.expect(eng.isEmpty());
}

test "MockImeEngine: setActiveInputMethod same method is no-op" {
    var mock = MockImeEngine{
        .active_input_method = "direct",
        .flush_result = ImeResult{ .committed_text = "should not appear" },
    };
    const eng = mock.engine();

    const r = try eng.setActiveInputMethod("direct");
    try std.testing.expect(r.committed_text == null);
    try std.testing.expectEqualStrings("direct", eng.getActiveInputMethod());
}

test "MockImeEngine: setActiveInputMethod switch flushes" {
    var mock = MockImeEngine{
        .active_input_method = "korean_2set",
        .flush_result = ImeResult{ .committed_text = "한", .preedit_changed = true },
        .is_empty = false,
    };
    const eng = mock.engine();

    const r = try eng.setActiveInputMethod("direct");
    try std.testing.expectEqualStrings("한", r.committed_text.?);
    try std.testing.expectEqualStrings("direct", eng.getActiveInputMethod());
}

test "MockImeEngine: setActiveInputMethod unsupported returns error" {
    var mock = MockImeEngine{};
    const eng = mock.engine();

    const r = eng.setActiveInputMethod("japanese_romaji");
    try std.testing.expectError(error.UnsupportedInputMethod, r);
}
