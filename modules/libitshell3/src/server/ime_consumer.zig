const std = @import("std");
const ime_engine_mod = @import("../core/ime_engine.zig");
const ImeResult = ime_engine_mod.ImeResult;
const KeyEvent = ime_engine_mod.KeyEvent;
const session_mod = @import("../core/session.zig");
const types = @import("../core/types.zig");

/// Interface for PTY write operations, enabling mock injection for tests.
pub const PtyWriter = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        write: *const fn (ptr: *anyopaque, fd: std.posix.fd_t, data: []const u8) WriteError!usize,
    };

    pub const WriteError = error{WriteFailed};

    pub fn write(self: PtyWriter, fd: std.posix.fd_t, data: []const u8) WriteError!usize {
        return self.vtable.write(self.ptr, fd, data);
    }
};

/// Interface for key encoding (ghostty key_encode.encode), enabling mock injection.
pub const KeyEncoder = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Encode a key event into bytes. Returns the encoded bytes (slice into
        /// internal buffer, valid until next call).
        encode: *const fn (ptr: *anyopaque, key: KeyEvent) ?[]const u8,
    };

    pub fn encode(self: KeyEncoder, key: KeyEvent) ?[]const u8 {
        return self.vtable.encode(self.ptr, key);
    }
};

/// Consume an ImeResult by performing Phase 2 actions:
/// - committed_text -> write to PTY fd
/// - preedit_text (when preedit_changed) -> copy to session.preedit_buf
/// - forward_key -> encode via key encoder + write to PTY fd
/// - preedit cleared (preedit_text=null, preedit_changed=true) -> clear session.current_preedit
///
/// NEVER uses ghostty_surface_text() for committed text (Korean doubling bug).
/// ImeResult MUST be consumed BEFORE any subsequent engine call (invariant from spec section 5.5).
///
/// Returns true if preedit state changed (caller should mark pane dirty).
pub fn consumeImeResult(
    result: ImeResult,
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_writer: PtyWriter,
    key_encoder: ?KeyEncoder,
) bool {
    var preedit_dirty = false;

    // 1. Write committed text to PTY
    if (result.committed_text) |text| {
        _ = pty_writer.write(pty_fd, text) catch {};
    }

    // 2. Handle preedit state change
    if (result.preedit_changed) {
        session.setPreedit(result.preedit_text);
        preedit_dirty = true;
    }

    // 3. Encode and write forwarded key to PTY
    if (result.forward_key) |fwd_key| {
        if (key_encoder) |encoder| {
            if (encoder.encode(fwd_key)) |encoded| {
                _ = pty_writer.write(pty_fd, encoded) catch {};
            }
        }
    }

    return preedit_dirty;
}

// ── Tests ────────────────────────────────────────────────────────────────────

const mock_ime = @import("../testing/mock_ime_engine.zig");
const MockPtyWriter = @import("../testing/mock_pty_writer.zig").MockPtyWriter;

/// Mock key encoder that returns a fixed string.
const MockKeyEncoder = struct {
    result: ?[]const u8 = null,

    fn encoder(self: *MockKeyEncoder) KeyEncoder {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    const vtable = KeyEncoder.VTable{
        .encode = encodeImpl,
    };

    fn encodeImpl(ptr: *anyopaque, _: KeyEvent) ?[]const u8 {
        const self: *MockKeyEncoder = @ptrCast(@alignCast(ptr));
        return self.result;
    }
};

fn makeTestSession() struct { engine: mock_ime.MockImeEngine, session: session_mod.Session } {
    var eng = mock_ime.MockImeEngine{};
    const s = session_mod.Session.init(1, "test", 0, eng.engine());
    return .{ .engine = eng, .session = s };
}

test "consumeImeResult: committed_text written to PTY" {
    var ts = makeTestSession();
    var mock_writer = MockPtyWriter{};

    const result = ImeResult{ .committed_text = "han" };
    const dirty = consumeImeResult(result, &ts.session, 10, mock_writer.writer(), null);

    try std.testing.expectEqualSlices(u8, "han", mock_writer.written());
    try std.testing.expect(!dirty);
}

test "consumeImeResult: preedit_text copied to session buffer when preedit_changed" {
    var ts = makeTestSession();
    var mock_writer = MockPtyWriter{};

    const result = ImeResult{ .preedit_text = "ga", .preedit_changed = true };
    const dirty = consumeImeResult(result, &ts.session, 10, mock_writer.writer(), null);

    try std.testing.expect(dirty);
    try std.testing.expect(ts.session.current_preedit != null);
    try std.testing.expectEqualSlices(u8, "ga", ts.session.current_preedit.?);
}

test "consumeImeResult: preedit cleared when preedit_text=null and preedit_changed=true" {
    var ts = makeTestSession();
    ts.session.setPreedit("old");
    var mock_writer = MockPtyWriter{};

    const result = ImeResult{ .preedit_text = null, .preedit_changed = true };
    const dirty = consumeImeResult(result, &ts.session, 10, mock_writer.writer(), null);

    try std.testing.expect(dirty);
    try std.testing.expect(ts.session.current_preedit == null);
}

test "consumeImeResult: preedit NOT updated when preedit_changed=false" {
    var ts = makeTestSession();
    ts.session.setPreedit("old");
    var mock_writer = MockPtyWriter{};

    const result = ImeResult{ .preedit_text = "new", .preedit_changed = false };
    const dirty = consumeImeResult(result, &ts.session, 10, mock_writer.writer(), null);

    try std.testing.expect(!dirty);
    // Preedit should still be "old"
    try std.testing.expectEqualSlices(u8, "old", ts.session.current_preedit.?);
}

test "consumeImeResult: forward_key encoded and written to PTY" {
    var ts = makeTestSession();
    var mock_writer = MockPtyWriter{};
    var mock_enc = MockKeyEncoder{ .result = "\x03" }; // Ctrl+C
    const key = KeyEvent{ .hid_keycode = 0x06, .modifiers = .{ .ctrl = true }, .shift = false, .action = .press };

    const result = ImeResult{ .forward_key = key };
    _ = consumeImeResult(result, &ts.session, 10, mock_writer.writer(), mock_enc.encoder());

    try std.testing.expectEqualSlices(u8, "\x03", mock_writer.written());
}

test "consumeImeResult: committed_text + forward_key both written in order" {
    var ts = makeTestSession();
    var mock_writer = MockPtyWriter{};
    var mock_enc = MockKeyEncoder{ .result = "\x03" };
    const key = KeyEvent{ .hid_keycode = 0x06, .modifiers = .{ .ctrl = true }, .shift = false, .action = .press };

    const result = ImeResult{
        .committed_text = "ha",
        .forward_key = key,
        .preedit_changed = true,
        .preedit_text = null,
    };
    const dirty = consumeImeResult(result, &ts.session, 10, mock_writer.writer(), mock_enc.encoder());

    // "ha" then "\x03"
    try std.testing.expectEqualSlices(u8, "ha\x03", mock_writer.written());
    try std.testing.expect(dirty);
    try std.testing.expect(ts.session.current_preedit == null);
}

test "consumeImeResult: empty result is no-op" {
    var ts = makeTestSession();
    var mock_writer = MockPtyWriter{};

    const result = ImeResult{};
    const dirty = consumeImeResult(result, &ts.session, 10, mock_writer.writer(), null);

    try std.testing.expect(!dirty);
    try std.testing.expectEqual(@as(usize, 0), mock_writer.written().len);
}
