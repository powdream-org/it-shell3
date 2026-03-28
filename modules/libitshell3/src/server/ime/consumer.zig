const std = @import("std");
const core = @import("itshell3_core");
const ImeResult = core.ImeResult;
const KeyEvent = core.KeyEvent;
const session_mod = core.session;
const interfaces = @import("../os/interfaces.zig");
const PtyOps = interfaces.PtyOps;

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
/// ImeResult MUST be consumed BEFORE any subsequent engine call
/// (see integration-boundaries critical runtime invariant).
///
/// Returns true if preedit state changed (caller should mark pane dirty).
pub fn consumeImeResult(
    result: ImeResult,
    session: *session_mod.Session,
    pty_fd: std.posix.fd_t,
    pty_ops: *const PtyOps,
    key_encoder: ?KeyEncoder,
) bool {
    var preedit_dirty = false;

    // 1. Write committed text to PTY
    if (result.committed_text) |text| {
        _ = pty_ops.write(pty_fd, text) catch {};
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
                _ = pty_ops.write(pty_fd, encoded) catch {};
            }
        }
    }

    return preedit_dirty;
}

// ── Tests ────────────────────────────────────────────────────────────────────

const test_mod = @import("itshell3_testing");
const mock_ime = test_mod.mock_ime_engine;
const MockPtyOps = test_mod.mock_os.MockPtyOps;

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
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    const result = ImeResult{ .committed_text = "han" };
    const dirty = consumeImeResult(result, &ts.session, 10, &pty_ops, null);

    try std.testing.expectEqualSlices(u8, "han", mock_pty.written());
    try std.testing.expect(!dirty);
}

test "consumeImeResult: preedit_text copied to session buffer when preedit_changed" {
    var ts = makeTestSession();
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    const result = ImeResult{ .preedit_text = "ga", .preedit_changed = true };
    const dirty = consumeImeResult(result, &ts.session, 10, &pty_ops, null);

    try std.testing.expect(dirty);
    try std.testing.expect(ts.session.current_preedit != null);
    try std.testing.expectEqualSlices(u8, "ga", ts.session.current_preedit.?);
}

test "consumeImeResult: preedit cleared when preedit_text=null and preedit_changed=true" {
    var ts = makeTestSession();
    ts.session.setPreedit("old");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    const result = ImeResult{ .preedit_text = null, .preedit_changed = true };
    const dirty = consumeImeResult(result, &ts.session, 10, &pty_ops, null);

    try std.testing.expect(dirty);
    try std.testing.expect(ts.session.current_preedit == null);
}

test "consumeImeResult: preedit NOT updated when preedit_changed=false" {
    var ts = makeTestSession();
    ts.session.setPreedit("old");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    const result = ImeResult{ .preedit_text = "new", .preedit_changed = false };
    const dirty = consumeImeResult(result, &ts.session, 10, &pty_ops, null);

    try std.testing.expect(!dirty);
    try std.testing.expectEqualSlices(u8, "old", ts.session.current_preedit.?);
}

test "consumeImeResult: forward_key encoded and written to PTY" {
    var ts = makeTestSession();
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    var mock_enc = MockKeyEncoder{ .result = "\x03" };
    const key = KeyEvent{ .hid_keycode = 0x06, .modifiers = .{ .ctrl = true }, .shift = false, .action = .press };

    const result = ImeResult{ .forward_key = key };
    _ = consumeImeResult(result, &ts.session, 10, &pty_ops, mock_enc.encoder());

    try std.testing.expectEqualSlices(u8, "\x03", mock_pty.written());
}

test "consumeImeResult: committed_text + forward_key both written in order" {
    var ts = makeTestSession();
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    var mock_enc = MockKeyEncoder{ .result = "\x03" };
    const key = KeyEvent{ .hid_keycode = 0x06, .modifiers = .{ .ctrl = true }, .shift = false, .action = .press };

    const result = ImeResult{
        .committed_text = "ha",
        .forward_key = key,
        .preedit_changed = true,
        .preedit_text = null,
    };
    const dirty = consumeImeResult(result, &ts.session, 10, &pty_ops, mock_enc.encoder());

    try std.testing.expectEqualSlices(u8, "ha\x03", mock_pty.written());
    try std.testing.expect(dirty);
    try std.testing.expect(ts.session.current_preedit == null);
}

test "consumeImeResult: empty result is no-op" {
    var ts = makeTestSession();
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    const result = ImeResult{};
    const dirty = consumeImeResult(result, &ts.session, 10, &pty_ops, null);

    try std.testing.expect(!dirty);
    try std.testing.expectEqual(@as(usize, 0), mock_pty.written().len);
}
