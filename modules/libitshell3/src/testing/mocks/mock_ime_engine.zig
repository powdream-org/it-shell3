//! Mock ImeEngine for deterministic daemon-side testing.
//! Supports configurable responses and call history tracking.

const std = @import("std");
const core = @import("itshell3_core");
const ImeEngine = core.ImeEngine;
const KeyEvent = core.KeyEvent;
const ImeResult = core.ImeResult;

pub const MockImeEngine = struct {
    results: []const ImeResult = &.{},
    call_index: usize = 0,
    flush_result: ImeResult = .{},
    deactivate_result: ImeResult = .{},
    active_input_method: []const u8 = "direct",
    set_active_input_method_result: ImeResult = .{},
    is_empty_val: bool = true,

    // --- Call history tracking ---
    process_key_count: usize = 0,
    flush_count: usize = 0,
    reset_count: usize = 0,
    activate_count: usize = 0,
    deactivate_count: usize = 0,
    set_active_input_method_count: usize = 0,
    last_process_key: ?KeyEvent = null,
    last_set_active_input_method: ?[]const u8 = null,

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

    fn processKeyImpl(ptr: *anyopaque, key: KeyEvent) ImeResult {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        self.process_key_count += 1;
        self.last_process_key = key;
        if (self.call_index < self.results.len) {
            const result = self.results[self.call_index];
            self.call_index += 1;
            return result;
        }
        return .{};
    }

    fn flushImpl(ptr: *anyopaque) ImeResult {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        self.flush_count += 1;
        const result = self.flush_result;
        // Per spec: flush on already-empty engine returns empty.
        // Clear after returning so a second flush returns empty.
        self.flush_result = .{};
        return result;
    }

    fn resetImpl(ptr: *anyopaque) void {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        self.reset_count += 1;
    }

    fn isEmptyImpl(ptr: *anyopaque) bool {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        return self.is_empty_val;
    }

    fn activateImpl(ptr: *anyopaque) void {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        self.activate_count += 1;
    }

    fn deactivateImpl(ptr: *anyopaque) ImeResult {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        self.deactivate_count += 1;
        return self.deactivate_result;
    }

    fn getActiveInputMethodImpl(ptr: *anyopaque) []const u8 {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        return self.active_input_method;
    }

    fn setActiveInputMethodImpl(ptr: *anyopaque, method: []const u8) error{UnsupportedInputMethod}!ImeResult {
        const self: *MockImeEngine = @ptrCast(@alignCast(ptr));
        self.set_active_input_method_count += 1;
        self.last_set_active_input_method = method;
        // Per the engine-interface spec: return error for unrecognized strings.
        if (!std.mem.eql(u8, method, "direct") and !std.mem.eql(u8, method, "korean_2set")) {
            return error.UnsupportedInputMethod;
        }
        return self.set_active_input_method_result;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

test "MockImeEngine: processKey returns queued results in order" {
    const results = [_]ImeResult{
        .{ .committed_text = "a", .preedit_changed = true },
        .{ .preedit_text = "b", .preedit_changed = true },
    };
    var mock = MockImeEngine{ .results = &results };
    const eng = mock.engine();

    const key = KeyEvent{ .hid_keycode = 0x04, .modifiers = .{}, .shift = false, .action = .press };

    const r1 = eng.processKey(key);
    try std.testing.expectEqualSlices(u8, "a", r1.committed_text.?);
    try std.testing.expectEqual(@as(usize, 1), mock.process_key_count);

    const r2 = eng.processKey(key);
    try std.testing.expectEqualSlices(u8, "b", r2.preedit_text.?);
    try std.testing.expectEqual(@as(usize, 2), mock.process_key_count);

    // Past end of queue: returns empty
    const r3 = eng.processKey(key);
    try std.testing.expect(r3.committed_text == null);
}

test "MockImeEngine: flush returns configured result" {
    var mock = MockImeEngine{
        .flush_result = .{ .committed_text = "flushed", .preedit_changed = true },
    };
    const eng = mock.engine();
    const r = eng.flush();
    try std.testing.expectEqualSlices(u8, "flushed", r.committed_text.?);
    try std.testing.expectEqual(@as(usize, 1), mock.flush_count);
}

test "MockImeEngine: reset increments count" {
    var mock = MockImeEngine{};
    const eng = mock.engine();
    eng.reset();
    eng.reset();
    try std.testing.expectEqual(@as(usize, 2), mock.reset_count);
}

test "MockImeEngine: isEmpty returns configured value" {
    var mock = MockImeEngine{ .is_empty_val = false };
    const eng = mock.engine();
    try std.testing.expect(!eng.isEmpty());
    mock.is_empty_val = true;
    try std.testing.expect(eng.isEmpty());
}

test "MockImeEngine: activate/deactivate track counts" {
    var mock = MockImeEngine{};
    const eng = mock.engine();
    eng.activate();
    try std.testing.expectEqual(@as(usize, 1), mock.activate_count);
    _ = eng.deactivate();
    try std.testing.expectEqual(@as(usize, 1), mock.deactivate_count);
}

test "MockImeEngine: getActiveInputMethod returns configured string" {
    var mock = MockImeEngine{ .active_input_method = "korean_2set" };
    const eng = mock.engine();
    try std.testing.expectEqualSlices(u8, "korean_2set", eng.getActiveInputMethod());
}

test "MockImeEngine: setActiveInputMethod tracks calls" {
    var mock = MockImeEngine{};
    const eng = mock.engine();
    _ = try eng.setActiveInputMethod("korean_2set");
    try std.testing.expectEqual(@as(usize, 1), mock.set_active_input_method_count);
    try std.testing.expectEqualSlices(u8, "korean_2set", mock.last_set_active_input_method.?);
}

test "MockImeEngine: last_process_key tracks last key" {
    var mock = MockImeEngine{};
    const eng = mock.engine();
    const key = KeyEvent{ .hid_keycode = 0x15, .modifiers = .{ .ctrl = true }, .shift = true, .action = .press };
    _ = eng.processKey(key);
    try std.testing.expect(mock.last_process_key != null);
    try std.testing.expectEqual(@as(u16, 0x15), mock.last_process_key.?.hid_keycode);
    try std.testing.expect(mock.last_process_key.?.modifiers.ctrl);
    try std.testing.expect(mock.last_process_key.?.shift);
}

test "MockImeEngine: setActiveInputMethod rejects unknown method" {
    var mock = MockImeEngine{};
    const eng = mock.engine();
    try std.testing.expectError(error.UnsupportedInputMethod, eng.setActiveInputMethod("japanese_hiragana"));
    // Call should still be tracked
    try std.testing.expectEqual(@as(usize, 1), mock.set_active_input_method_count);
}

test "MockImeEngine: flush clears flush_result after first call" {
    var mock = MockImeEngine{
        .flush_result = .{ .committed_text = "first", .preedit_changed = true },
    };
    const eng = mock.engine();

    const r1 = eng.flush();
    try std.testing.expectEqualSlices(u8, "first", r1.committed_text.?);

    // Second flush returns empty (engine is now empty)
    const r2 = eng.flush();
    try std.testing.expect(r2.committed_text == null);
    try std.testing.expect(!r2.preedit_changed);
}
