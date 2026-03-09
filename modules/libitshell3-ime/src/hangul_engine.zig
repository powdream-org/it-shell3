//! HangulImeEngine: Concrete IME engine wrapping libhangul for Korean + direct mode.
//! Follows IME Interface Contract v0.7, Section 3.7.

const std = @import("std");
const c = @import("c.zig");
const engine_mod = @import("engine.zig");
const ImeEngine = engine_mod.ImeEngine;
const KeyEvent = engine_mod.KeyEvent;
const ImeResult = engine_mod.ImeResult;
const hid_to_ascii = @import("hid_to_ascii.zig");
const ucs4 = @import("ucs4.zig");

/// HID constants for special keys
const HID_ENTER: u8 = 0x28;
const HID_ESCAPE: u8 = 0x29;
const HID_BACKSPACE: u8 = 0x2A;
const HID_TAB: u8 = 0x2B;
const HID_SPACE: u8 = 0x2C;
const HID_ARROW_RIGHT: u8 = 0x4F;
const HID_ARROW_LEFT: u8 = 0x50;
const HID_ARROW_DOWN: u8 = 0x51;
const HID_ARROW_UP: u8 = 0x52;

pub const HangulImeEngine = struct {
    hic: *c.HangulInputContext,
    active_input_method: []const u8,
    engine_mode: EngineMode,

    committed_buf: [256]u8 = undefined,
    preedit_buf: [64]u8 = undefined,
    committed_len: usize = 0,
    preedit_len: usize = 0,

    prev_preedit_len: usize = 0,

    const EngineMode = enum { direct, composing };

    pub fn init(input_method: []const u8) !HangulImeEngine {
        const mode = deriveMode(input_method);
        const keyboard_id: [*c]const u8 = if (libhangulKeyboardId(input_method)) |id| id.ptr else "2";

        const hic = c.hangul_ic_new(keyboard_id) orelse return error.LibhangulInitFailed;
        return HangulImeEngine{
            .hic = hic,
            .active_input_method = input_method,
            .engine_mode = mode,
        };
    }

    pub fn deinit(self: *HangulImeEngine) void {
        c.hangul_ic_delete(self.hic);
    }

    pub fn engine(self: *HangulImeEngine) ImeEngine {
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

    // -----------------------------------------------------------------------
    // processKey — the core method
    // -----------------------------------------------------------------------

    fn processKeyImpl(ptr: *anyopaque, key: KeyEvent) ImeResult {
        const self: *HangulImeEngine = @ptrCast(@alignCast(ptr));

        // Ignore release events
        if (key.action == .release) {
            return .{};
        }

        return switch (self.engine_mode) {
            .direct => self.processKeyDirect(key),
            .composing => self.processKeyComposing(key),
        };
    }

    /// Direct mode: HID→ASCII for printable, forward everything else.
    fn processKeyDirect(self: *HangulImeEngine, key: KeyEvent) ImeResult {
        // Space always forwards (consistent across all modes per spec Section 3.2)
        if (key.hid_keycode == HID_SPACE and !key.hasCompositionBreakingModifier()) {
            return ImeResult{
                .forward_key = key,
            };
        }

        // Modified keys or non-printable → forward
        if (key.hasCompositionBreakingModifier()) {
            return ImeResult{ .forward_key = key };
        }

        // Try HID→ASCII for printable keys
        if (hid_to_ascii.hidToAscii(key.hid_keycode, key.shift)) |ascii| {
            self.committed_buf[0] = ascii;
            self.committed_len = 1;
            return ImeResult{
                .committed_text = self.committed_buf[0..1],
            };
        }

        // Non-printable → forward
        return ImeResult{ .forward_key = key };
    }

    /// Composing mode (Korean): handles modifiers, special keys, backspace, printable.
    fn processKeyComposing(self: *HangulImeEngine, key: KeyEvent) ImeResult {
        // Backspace: try IME backspace first
        if (key.hid_keycode == HID_BACKSPACE and !key.hasCompositionBreakingModifier()) {
            return self.handleBackspace(key);
        }

        // Composition-breaking modifier → flush + forward
        if (key.hasCompositionBreakingModifier()) {
            return self.flushAndForward(key);
        }

        // Special keys (Enter, Escape, Tab, Space, Arrows) → flush + forward
        if (isSpecialKey(key.hid_keycode)) {
            return self.flushAndForward(key);
        }

        // Printable key → feed to libhangul
        if (hid_to_ascii.hidToAscii(key.hid_keycode, key.shift)) |ascii| {
            return self.feedLibhangul(key, ascii);
        }

        // Non-printable, non-special → flush + forward
        return self.flushAndForward(key);
    }

    fn handleBackspace(self: *HangulImeEngine, key: KeyEvent) ImeResult {
        const consumed = c.hangul_ic_backspace(self.hic);
        if (consumed) {
            return self.readPreeditResult();
        }
        // Not consumed by libhangul — forward backspace
        return self.makePreeditUnchangedResult(key);
    }

    fn flushAndForward(self: *HangulImeEngine, key: KeyEvent) ImeResult {
        var result = ImeResult{
            .forward_key = key,
        };

        if (!c.hangul_ic_is_empty(self.hic)) {
            const flushed = c.hangul_ic_flush(self.hic);
            const n = ucs4.ucs4ToUtf8(flushed, &self.committed_buf);
            if (n > 0) {
                self.committed_len = n;
                result.committed_text = self.committed_buf[0..n];
            }
        }

        // Preedit is now null; check if it changed
        result.preedit_changed = self.prev_preedit_len > 0;
        self.preedit_len = 0;
        self.prev_preedit_len = 0;

        return result;
    }

    fn feedLibhangul(self: *HangulImeEngine, key: KeyEvent, ascii: u8) ImeResult {
        const consumed = c.hangul_ic_process(self.hic, @intCast(ascii));

        // Read committed text from libhangul (regardless of consumed)
        self.committed_len = 0;
        const commit_str = c.hangul_ic_get_commit_string(self.hic);
        const commit_n = ucs4.ucs4ToUtf8(commit_str, &self.committed_buf);
        if (commit_n > 0) {
            self.committed_len = commit_n;
        }

        // Read preedit from libhangul (regardless of consumed)
        self.preedit_len = 0;
        const preedit_str = c.hangul_ic_get_preedit_string(self.hic);
        const preedit_n = ucs4.ucs4ToUtf8(preedit_str, &self.preedit_buf);
        if (preedit_n > 0) {
            self.preedit_len = preedit_n;
        }

        if (!consumed) {
            // Key rejected — flush remaining composition and forward
            if (!c.hangul_ic_is_empty(self.hic)) {
                const flushed = c.hangul_ic_flush(self.hic);
                const flush_n = ucs4.ucs4ToUtf8(flushed, self.committed_buf[self.committed_len..]);
                self.committed_len += flush_n;
            }
            self.preedit_len = 0;

            const preedit_changed = self.prev_preedit_len > 0 or preedit_n > 0;
            self.prev_preedit_len = 0;

            return ImeResult{
                .committed_text = if (self.committed_len > 0) self.committed_buf[0..self.committed_len] else null,
                .preedit_text = null,
                .forward_key = key,
                .preedit_changed = preedit_changed,
            };
        }

        // Consumed — build result with committed + preedit
        // preedit_changed per spec: true on null->non-null, non-null->null,
        // or non-null->different-non-null transitions.
        const preedit_changed = blk: {
            if (self.prev_preedit_len == 0 and self.preedit_len == 0) break :blk false;
            if (self.prev_preedit_len == 0 and self.preedit_len > 0) break :blk true;
            if (self.prev_preedit_len > 0 and self.preedit_len == 0) break :blk true;
            break :blk true; // non-null -> non-null (content always changes on keystroke)
        };

        self.prev_preedit_len = self.preedit_len;

        return ImeResult{
            .committed_text = if (self.committed_len > 0) self.committed_buf[0..self.committed_len] else null,
            .preedit_text = if (self.preedit_len > 0) self.preedit_buf[0..self.preedit_len] else null,
            .preedit_changed = preedit_changed,
        };
    }

    /// Read current preedit from libhangul and build result (used after backspace).
    fn readPreeditResult(self: *HangulImeEngine) ImeResult {
        self.preedit_len = 0;
        const preedit_str = c.hangul_ic_get_preedit_string(self.hic);
        const preedit_n = ucs4.ucs4ToUtf8(preedit_str, &self.preedit_buf);
        if (preedit_n > 0) {
            self.preedit_len = preedit_n;
        }

        const preedit_changed = blk: {
            if (self.prev_preedit_len == 0 and self.preedit_len == 0) break :blk false;
            break :blk true;
        };
        self.prev_preedit_len = self.preedit_len;

        return ImeResult{
            .preedit_text = if (self.preedit_len > 0) self.preedit_buf[0..self.preedit_len] else null,
            .preedit_changed = preedit_changed,
        };
    }

    /// Build result for forwarded key when preedit is unchanged (e.g., backspace on empty).
    fn makePreeditUnchangedResult(_: *HangulImeEngine, key: KeyEvent) ImeResult {
        return ImeResult{
            .forward_key = key,
        };
    }

    // -----------------------------------------------------------------------
    // flush / reset / isEmpty / activate / deactivate
    // -----------------------------------------------------------------------

    fn flushImpl(ptr: *anyopaque) ImeResult {
        const self: *HangulImeEngine = @ptrCast(@alignCast(ptr));
        if (c.hangul_ic_is_empty(self.hic)) {
            return .{};
        }

        const flushed = c.hangul_ic_flush(self.hic);
        const n = ucs4.ucs4ToUtf8(flushed, &self.committed_buf);

        const preedit_was_active = self.prev_preedit_len > 0;
        self.committed_len = n;
        self.preedit_len = 0;
        self.prev_preedit_len = 0;

        return ImeResult{
            .committed_text = if (n > 0) self.committed_buf[0..n] else null,
            .preedit_text = null,
            .preedit_changed = preedit_was_active,
        };
    }

    fn resetImpl(ptr: *anyopaque) void {
        const self: *HangulImeEngine = @ptrCast(@alignCast(ptr));
        c.hangul_ic_reset(self.hic);
        self.committed_len = 0;
        self.preedit_len = 0;
        self.prev_preedit_len = 0;
    }

    fn isEmptyImpl(ptr: *anyopaque) bool {
        const self: *HangulImeEngine = @ptrCast(@alignCast(ptr));
        return c.hangul_ic_is_empty(self.hic);
    }

    fn activateImpl(_: *anyopaque) void {
        // No-op for Korean — state is preserved in the buffer.
    }

    fn deactivateImpl(ptr: *anyopaque) ImeResult {
        // Engine MUST flush pending composition before returning.
        return flushImpl(ptr);
    }

    // -----------------------------------------------------------------------
    // Input method management
    // -----------------------------------------------------------------------

    fn getActiveInputMethodImpl(ptr: *anyopaque) []const u8 {
        const self: *HangulImeEngine = @ptrCast(@alignCast(ptr));
        return self.active_input_method;
    }

    fn setActiveInputMethodImpl(ptr: *anyopaque, method: []const u8) error{UnsupportedInputMethod}!ImeResult {
        const self: *HangulImeEngine = @ptrCast(@alignCast(ptr));

        // Validate the method string
        if (!isValidInputMethod(method)) {
            return error.UnsupportedInputMethod;
        }

        // Same method — no-op
        if (std.mem.eql(u8, method, self.active_input_method)) {
            return .{};
        }

        // Flush pending composition
        var result = ImeResult{};
        if (!c.hangul_ic_is_empty(self.hic)) {
            const flushed = c.hangul_ic_flush(self.hic);
            const n = ucs4.ucs4ToUtf8(flushed, &self.committed_buf);
            if (n > 0) {
                self.committed_len = n;
                result.committed_text = self.committed_buf[0..n];
            }
            result.preedit_changed = self.prev_preedit_len > 0;
        }

        // Switch to the new method
        self.active_input_method = method;
        self.engine_mode = deriveMode(method);
        self.preedit_len = 0;
        self.prev_preedit_len = 0;

        // Update libhangul keyboard if switching to a Korean layout
        if (libhangulKeyboardId(method)) |kb_id| {
            c.hangul_ic_select_keyboard(self.hic, kb_id.ptr);
        }

        return result;
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    fn isSpecialKey(hid: u8) bool {
        return switch (hid) {
            HID_ENTER, HID_ESCAPE, HID_TAB, HID_SPACE => true,
            HID_ARROW_RIGHT, HID_ARROW_LEFT, HID_ARROW_DOWN, HID_ARROW_UP => true,
            else => false,
        };
    }

    fn isValidInputMethod(method: []const u8) bool {
        if (std.mem.eql(u8, method, "direct")) return true;
        return libhangulKeyboardId(method) != null;
    }

    const KbMapping = struct { canonical: []const u8, libhangul_id: []const u8 };
    const keyboard_map = [_]KbMapping{
        .{ .canonical = "korean_2set", .libhangul_id = "2" },
        .{ .canonical = "korean_2set_old", .libhangul_id = "2y" },
        .{ .canonical = "korean_3set_dubeol", .libhangul_id = "32" },
        .{ .canonical = "korean_3set_390", .libhangul_id = "39" },
        .{ .canonical = "korean_3set_final", .libhangul_id = "3f" },
        .{ .canonical = "korean_3set_noshift", .libhangul_id = "3s" },
        .{ .canonical = "korean_3set_old", .libhangul_id = "3y" },
        .{ .canonical = "korean_romaja", .libhangul_id = "ro" },
        .{ .canonical = "korean_ahnmatae", .libhangul_id = "ahn" },
    };

    pub fn libhangulKeyboardId(input_method: []const u8) ?[]const u8 {
        for (&keyboard_map) |*entry| {
            if (std.mem.eql(u8, input_method, entry.canonical)) return entry.libhangul_id;
        }
        return null;
    }

    fn deriveMode(input_method: []const u8) EngineMode {
        if (std.mem.startsWith(u8, input_method, "korean_")) return .composing;
        return .direct;
    }
};

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

test "HangulImeEngine: init and deinit" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    try std.testing.expectEqualStrings("korean_2set", eng.active_input_method);
    try std.testing.expectEqual(HangulImeEngine.EngineMode.composing, eng.engine_mode);
}

test "HangulImeEngine: init with direct mode" {
    var eng = try HangulImeEngine.init("direct");
    defer eng.deinit();
    try std.testing.expectEqualStrings("direct", eng.active_input_method);
    try std.testing.expectEqual(HangulImeEngine.EngineMode.direct, eng.engine_mode);
}

test "HangulImeEngine: direct mode passthrough for letter" {
    var eng = try HangulImeEngine.init("direct");
    defer eng.deinit();
    const iface = eng.engine();

    const result = iface.processKey(.{
        .hid_keycode = 0x04, // 'a'
        .modifiers = .{},
        .shift = false,
        .action = .press,
    });
    try std.testing.expectEqualStrings("a", result.committed_text.?);
    try std.testing.expect(result.preedit_text == null);
    try std.testing.expect(result.forward_key == null);
    try std.testing.expect(!result.preedit_changed);
}

test "HangulImeEngine: direct mode Shift+'a' -> 'A'" {
    var eng = try HangulImeEngine.init("direct");
    defer eng.deinit();
    const iface = eng.engine();

    const result = iface.processKey(.{
        .hid_keycode = 0x04, // 'a'
        .modifiers = .{},
        .shift = true,
        .action = .press,
    });
    try std.testing.expectEqualStrings("A", result.committed_text.?);
}

test "HangulImeEngine: direct mode Ctrl+C forwards" {
    var eng = try HangulImeEngine.init("direct");
    defer eng.deinit();
    const iface = eng.engine();

    const result = iface.processKey(.{
        .hid_keycode = 0x06, // 'c'
        .modifiers = .{ .ctrl = true },
        .shift = false,
        .action = .press,
    });
    try std.testing.expect(result.committed_text == null);
    try std.testing.expect(result.forward_key != null);
    try std.testing.expect(result.forward_key.?.modifiers.ctrl);
}

test "HangulImeEngine: direct mode Enter forwards" {
    var eng = try HangulImeEngine.init("direct");
    defer eng.deinit();
    const iface = eng.engine();

    const result = iface.processKey(.{
        .hid_keycode = HID_ENTER,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    });
    try std.testing.expect(result.committed_text == null);
    try std.testing.expect(result.forward_key != null);
    try std.testing.expectEqual(HID_ENTER, result.forward_key.?.hid_keycode);
}

test "HangulImeEngine: direct mode Space forwards" {
    var eng = try HangulImeEngine.init("direct");
    defer eng.deinit();
    const iface = eng.engine();

    const result = iface.processKey(.{
        .hid_keycode = HID_SPACE,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    });
    try std.testing.expect(result.committed_text == null);
    try std.testing.expect(result.forward_key != null);
    try std.testing.expectEqual(HID_SPACE, result.forward_key.?.hid_keycode);
}

test "HangulImeEngine: direct mode Arrow forwards" {
    var eng = try HangulImeEngine.init("direct");
    defer eng.deinit();
    const iface = eng.engine();

    const result = iface.processKey(.{
        .hid_keycode = HID_ARROW_RIGHT,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    });
    try std.testing.expect(result.forward_key != null);
    try std.testing.expectEqual(HID_ARROW_RIGHT, result.forward_key.?.hid_keycode);
}

test "HangulImeEngine: direct mode Escape forwards" {
    var eng = try HangulImeEngine.init("direct");
    defer eng.deinit();
    const iface = eng.engine();

    const result = iface.processKey(.{
        .hid_keycode = HID_ESCAPE,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    });
    try std.testing.expect(result.forward_key != null);
    try std.testing.expectEqual(HID_ESCAPE, result.forward_key.?.hid_keycode);
}

test "HangulImeEngine: release event is ignored" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    const result = iface.processKey(.{
        .hid_keycode = 0x15, // 'r'
        .modifiers = .{},
        .shift = false,
        .action = .release,
    });
    try std.testing.expect(result.committed_text == null);
    try std.testing.expect(result.preedit_text == null);
    try std.testing.expect(result.forward_key == null);
    try std.testing.expect(!result.preedit_changed);
}

test "HangulImeEngine: Korean basic composition ㄱ" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // 'r' -> ㄱ (preedit)
    const r1 = iface.processKey(.{
        .hid_keycode = 0x15,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    });
    try std.testing.expect(r1.preedit_text != null);
    try std.testing.expect(r1.preedit_changed);
    try std.testing.expect(r1.committed_text == null);
}

test "HangulImeEngine: Korean composition 가 (consonant + vowel)" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // 'r' -> ㄱ
    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    // 'k' -> 가
    const r2 = iface.processKey(.{ .hid_keycode = 0x0E, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(r2.preedit_text != null);
    try std.testing.expect(r2.preedit_changed);
}

test "HangulImeEngine: Korean syllable break commits previous" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // 'r' -> ㄱ, 'k' -> 가, 's' -> 간
    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    _ = iface.processKey(.{ .hid_keycode = 0x0E, .modifiers = .{}, .shift = false, .action = .press });
    _ = iface.processKey(.{ .hid_keycode = 0x16, .modifiers = .{}, .shift = false, .action = .press });
    // 'r' -> commit 간, preedit ㄱ
    const r = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(r.committed_text != null);
    try std.testing.expect(r.preedit_text != null);
    try std.testing.expect(r.preedit_changed);
}

test "HangulImeEngine: Arrow during composition flushes" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // 'r' -> ㄱ, 'k' -> 가
    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    _ = iface.processKey(.{ .hid_keycode = 0x0E, .modifiers = .{}, .shift = false, .action = .press });
    // Arrow Right -> flush 가, forward arrow
    const r = iface.processKey(.{ .hid_keycode = HID_ARROW_RIGHT, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(r.committed_text != null);
    try std.testing.expect(r.preedit_text == null);
    try std.testing.expect(r.forward_key != null);
    try std.testing.expectEqual(HID_ARROW_RIGHT, r.forward_key.?.hid_keycode);
    try std.testing.expect(r.preedit_changed);
}

test "HangulImeEngine: Ctrl+C during composition flushes" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // 'r' -> ㄱ, 'k' -> 가
    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    _ = iface.processKey(.{ .hid_keycode = 0x0E, .modifiers = .{}, .shift = false, .action = .press });
    // Ctrl+C
    const r = iface.processKey(.{ .hid_keycode = 0x06, .modifiers = .{ .ctrl = true }, .shift = false, .action = .press });
    try std.testing.expect(r.committed_text != null);
    try std.testing.expect(r.forward_key != null);
    try std.testing.expect(r.forward_key.?.modifiers.ctrl);
    try std.testing.expect(r.preedit_changed);
}

test "HangulImeEngine: Enter during composition flushes" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // 'r' -> ㄱ
    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    // Enter
    const r = iface.processKey(.{ .hid_keycode = HID_ENTER, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(r.committed_text != null);
    try std.testing.expect(r.forward_key != null);
    try std.testing.expectEqual(HID_ENTER, r.forward_key.?.hid_keycode);
    try std.testing.expect(r.preedit_changed);
}

test "HangulImeEngine: Space during composition flushes" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // 'r' -> ㄱ
    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    // Space
    const r = iface.processKey(.{ .hid_keycode = HID_SPACE, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(r.committed_text != null);
    try std.testing.expect(r.forward_key != null);
    try std.testing.expectEqual(HID_SPACE, r.forward_key.?.hid_keycode);
    try std.testing.expect(r.preedit_changed);
}

test "HangulImeEngine: Backspace undoes jamo" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // 'r' -> ㄱ, 'k' -> 가, 's' -> 간
    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    _ = iface.processKey(.{ .hid_keycode = 0x0E, .modifiers = .{}, .shift = false, .action = .press });
    _ = iface.processKey(.{ .hid_keycode = 0x16, .modifiers = .{}, .shift = false, .action = .press });

    // Backspace: 간 -> 가
    const r1 = iface.processKey(.{ .hid_keycode = HID_BACKSPACE, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(r1.preedit_text != null);
    try std.testing.expect(r1.preedit_changed);
    try std.testing.expect(r1.committed_text == null);
    try std.testing.expect(r1.forward_key == null);
}

test "HangulImeEngine: Backspace on empty composition forwards" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // Backspace with no composition
    const r = iface.processKey(.{ .hid_keycode = HID_BACKSPACE, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(r.forward_key != null);
    try std.testing.expectEqual(HID_BACKSPACE, r.forward_key.?.hid_keycode);
    try std.testing.expect(r.committed_text == null);
    try std.testing.expect(!r.preedit_changed);
}

test "HangulImeEngine: Shifted key produces double consonant" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // Shift+'r' -> ㄲ
    const r = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = true, .action = .press });
    try std.testing.expect(r.preedit_text != null);
    try std.testing.expect(r.preedit_changed);
}

test "HangulImeEngine: flush" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // Type 'r' -> ㄱ
    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(!iface.isEmpty());

    const r = iface.flush();
    try std.testing.expect(r.committed_text != null);
    try std.testing.expect(r.preedit_changed);
    try std.testing.expect(iface.isEmpty());
}

test "HangulImeEngine: flush on empty returns empty" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    const r = iface.flush();
    try std.testing.expect(r.committed_text == null);
    try std.testing.expect(!r.preedit_changed);
}

test "HangulImeEngine: reset discards composition" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // Type 'r' -> ㄱ
    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(!iface.isEmpty());

    iface.reset();
    try std.testing.expect(iface.isEmpty());
}

test "HangulImeEngine: deactivate flushes" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // Type 'r' -> ㄱ
    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });

    const r = iface.deactivate();
    try std.testing.expect(r.committed_text != null);
    try std.testing.expect(iface.isEmpty());
}

test "HangulImeEngine: activate is no-op" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();
    iface.activate(); // should not crash
}

test "HangulImeEngine: setActiveInputMethod same is no-op" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    const r = try iface.setActiveInputMethod("korean_2set");
    try std.testing.expect(r.committed_text == null);
    try std.testing.expect(!r.preedit_changed);
}

test "HangulImeEngine: setActiveInputMethod switch flushes" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    // Type 'r' -> ㄱ
    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });

    const r = try iface.setActiveInputMethod("direct");
    try std.testing.expect(r.committed_text != null);
    try std.testing.expect(r.preedit_changed);
    try std.testing.expectEqualStrings("direct", iface.getActiveInputMethod());
}

test "HangulImeEngine: setActiveInputMethod switch without composition" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    const r = try iface.setActiveInputMethod("direct");
    try std.testing.expect(r.committed_text == null);
    try std.testing.expect(!r.preedit_changed);
    try std.testing.expectEqualStrings("direct", iface.getActiveInputMethod());
}

test "HangulImeEngine: setActiveInputMethod unsupported returns error" {
    var eng = try HangulImeEngine.init("direct");
    defer eng.deinit();
    const iface = eng.engine();

    const r = iface.setActiveInputMethod("japanese_romaji");
    try std.testing.expectError(error.UnsupportedInputMethod, r);
}

test "HangulImeEngine: libhangulKeyboardId mapping" {
    try std.testing.expectEqualStrings("2", HangulImeEngine.libhangulKeyboardId("korean_2set").?);
    try std.testing.expectEqualStrings("2y", HangulImeEngine.libhangulKeyboardId("korean_2set_old").?);
    try std.testing.expectEqualStrings("32", HangulImeEngine.libhangulKeyboardId("korean_3set_dubeol").?);
    try std.testing.expectEqualStrings("39", HangulImeEngine.libhangulKeyboardId("korean_3set_390").?);
    try std.testing.expectEqualStrings("3f", HangulImeEngine.libhangulKeyboardId("korean_3set_final").?);
    try std.testing.expectEqualStrings("3s", HangulImeEngine.libhangulKeyboardId("korean_3set_noshift").?);
    try std.testing.expectEqualStrings("3y", HangulImeEngine.libhangulKeyboardId("korean_3set_old").?);
    try std.testing.expectEqualStrings("ro", HangulImeEngine.libhangulKeyboardId("korean_romaja").?);
    try std.testing.expectEqualStrings("ahn", HangulImeEngine.libhangulKeyboardId("korean_ahnmatae").?);
    try std.testing.expect(HangulImeEngine.libhangulKeyboardId("direct") == null);
    try std.testing.expect(HangulImeEngine.libhangulKeyboardId("unknown") == null);
}

test "HangulImeEngine: deriveMode" {
    try std.testing.expectEqual(HangulImeEngine.EngineMode.composing, HangulImeEngine.deriveMode("korean_2set"));
    try std.testing.expectEqual(HangulImeEngine.EngineMode.composing, HangulImeEngine.deriveMode("korean_3set_final"));
    try std.testing.expectEqual(HangulImeEngine.EngineMode.direct, HangulImeEngine.deriveMode("direct"));
    try std.testing.expectEqual(HangulImeEngine.EngineMode.direct, HangulImeEngine.deriveMode("unknown"));
}

test "HangulImeEngine: Space with empty composition forwards" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    const r = iface.processKey(.{ .hid_keycode = HID_SPACE, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(r.forward_key != null);
    try std.testing.expectEqual(HID_SPACE, r.forward_key.?.hid_keycode);
    try std.testing.expect(r.committed_text == null);
    try std.testing.expect(!r.preedit_changed);
}

test "HangulImeEngine: Ctrl+C with no composition forwards" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    const r = iface.processKey(.{ .hid_keycode = 0x06, .modifiers = .{ .ctrl = true }, .shift = false, .action = .press });
    try std.testing.expect(r.forward_key != null);
    try std.testing.expect(r.committed_text == null);
    try std.testing.expect(!r.preedit_changed);
}

test "HangulImeEngine: Escape during composition flushes" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    const r = iface.processKey(.{ .hid_keycode = HID_ESCAPE, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(r.committed_text != null);
    try std.testing.expect(r.forward_key != null);
    try std.testing.expectEqual(HID_ESCAPE, r.forward_key.?.hid_keycode);
    try std.testing.expect(r.preedit_changed);
}

test "HangulImeEngine: Tab during composition flushes" {
    var eng = try HangulImeEngine.init("korean_2set");
    defer eng.deinit();
    const iface = eng.engine();

    _ = iface.processKey(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    const r = iface.processKey(.{ .hid_keycode = HID_TAB, .modifiers = .{}, .shift = false, .action = .press });
    try std.testing.expect(r.committed_text != null);
    try std.testing.expect(r.forward_key != null);
    try std.testing.expectEqual(HID_TAB, r.forward_key.?.hid_keycode);
    try std.testing.expect(r.preedit_changed);
}
