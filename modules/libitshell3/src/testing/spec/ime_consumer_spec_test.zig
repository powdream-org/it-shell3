//! Spec compliance tests: Phase 2 ImeResult Consumer.
//!
//! Spec sources:
//!   - daemon-architecture integration-boundaries ImeResult-to-ghostty mapping
//!   - daemon-architecture integration-boundaries critical runtime invariant

const std = @import("std");
const core = @import("itshell3_core");
const server = @import("itshell3_server");
const test_mod = @import("itshell3_testing");
const ImeResult = core.ImeResult;
const KeyEvent = core.KeyEvent;
const Session = core.Session;
const consumeImeResult = server.ime_consumer.consumeImeResult;
const MockImeEngine = test_mod.MockImeEngine;
const MockPtyOps = test_mod.MockPtyOps;
const KeyEncoder = server.ime_consumer.KeyEncoder;

fn makeSession() struct { mock: MockImeEngine, session: Session } {
    var m = MockImeEngine{};
    return .{ .mock = m, .session = Session.init(1, "t", 0, m.engine()) };
}

test "spec: IME consumer — committed_text written to PTY" {
    var ts = makeSession();
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    const dirty = consumeImeResult(.{ .committed_text = "han" }, &ts.session, 10, &pty_ops, null);
    try std.testing.expectEqualStrings("han", mock_pty.written());
    try std.testing.expect(!dirty);
}

test "spec: IME consumer — preedit_text copied when preedit_changed is true" {
    var ts = makeSession();
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    const dirty = consumeImeResult(.{ .preedit_text = "ga", .preedit_changed = true }, &ts.session, 10, &pty_ops, null);
    try std.testing.expect(dirty);
    try std.testing.expectEqualStrings("ga", ts.session.current_preedit.?);
}

test "spec: IME consumer — preedit not copied when preedit_changed is false" {
    var ts = makeSession();
    ts.session.setPreedit("old");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    _ = consumeImeResult(.{ .preedit_text = "new", .preedit_changed = false }, &ts.session, 10, &pty_ops, null);
    try std.testing.expectEqualStrings("old", ts.session.current_preedit.?);
}

test "spec: IME consumer — preedit cleared when preedit_text is null and preedit_changed" {
    var ts = makeSession();
    ts.session.setPreedit("old");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    const dirty = consumeImeResult(.{ .preedit_text = null, .preedit_changed = true }, &ts.session, 10, &pty_ops, null);
    try std.testing.expect(dirty);
    try std.testing.expect(ts.session.current_preedit == null);
}

test "spec: IME consumer — forward_key encoded and written to PTY" {
    const MockKeyEncoder = struct {
        result: ?[]const u8 = null,
        fn enc(self: *@This()) KeyEncoder {
            return .{ .ptr = @ptrCast(self), .vtable = &vtable };
        }
        const vtable = KeyEncoder.VTable{ .encode = encodeImpl };
        fn encodeImpl(ptr: *anyopaque, _: KeyEvent) ?[]const u8 {
            const s: *@This() = @ptrCast(@alignCast(ptr));
            return s.result;
        }
    };

    var ts = makeSession();
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    var enc = MockKeyEncoder{ .result = "\x03" };
    _ = consumeImeResult(.{ .forward_key = .{ .hid_keycode = 0x06, .modifiers = .{ .ctrl = true }, .shift = false, .action = .press } }, &ts.session, 10, &pty_ops, enc.enc());
    try std.testing.expectEqualStrings("\x03", mock_pty.written());
}

test "spec: IME consumer — empty ImeResult is no-op" {
    var ts = makeSession();
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();
    const dirty = consumeImeResult(.{}, &ts.session, 10, &pty_ops, null);
    try std.testing.expect(!dirty);
    try std.testing.expectEqual(@as(usize, 0), mock_pty.written().len);
}
