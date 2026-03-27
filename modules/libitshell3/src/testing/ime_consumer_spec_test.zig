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
const MockPtyWriter = test_mod.MockPtyWriter;
const PtyWriter = server.ime_consumer.PtyWriter;
const KeyEncoder = server.ime_consumer.KeyEncoder;

fn makeSession() struct { mock: MockImeEngine, session: Session } {
    var m = MockImeEngine{};
    return .{ .mock = m, .session = Session.init(1, "t", 0, m.engine()) };
}

test "ime_consumer: committed_text written to PTY" {
    var ts = makeSession();
    var pw = MockPtyWriter{};
    const dirty = consumeImeResult(.{ .committed_text = "han" }, &ts.session, 10, pw.writer(), null);
    try std.testing.expectEqualStrings("han", pw.written());
    try std.testing.expect(!dirty);
}

test "ime_consumer: preedit_text copied when preedit_changed=true" {
    var ts = makeSession();
    var pw = MockPtyWriter{};
    const dirty = consumeImeResult(.{ .preedit_text = "ga", .preedit_changed = true }, &ts.session, 10, pw.writer(), null);
    try std.testing.expect(dirty);
    try std.testing.expectEqualStrings("ga", ts.session.current_preedit.?);
}

test "ime_consumer: preedit NOT copied when preedit_changed=false" {
    var ts = makeSession();
    ts.session.setPreedit("old");
    var pw = MockPtyWriter{};
    _ = consumeImeResult(.{ .preedit_text = "new", .preedit_changed = false }, &ts.session, 10, pw.writer(), null);
    try std.testing.expectEqualStrings("old", ts.session.current_preedit.?);
}

test "ime_consumer: preedit cleared when preedit_text=null, preedit_changed=true" {
    var ts = makeSession();
    ts.session.setPreedit("old");
    var pw = MockPtyWriter{};
    const dirty = consumeImeResult(.{ .preedit_text = null, .preedit_changed = true }, &ts.session, 10, pw.writer(), null);
    try std.testing.expect(dirty);
    try std.testing.expect(ts.session.current_preedit == null);
}

test "ime_consumer: forward_key encoded and written to PTY" {
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
    var pw = MockPtyWriter{};
    var enc = MockKeyEncoder{ .result = "\x03" };
    _ = consumeImeResult(.{ .forward_key = .{ .hid_keycode = 0x06, .modifiers = .{ .ctrl = true }, .shift = false, .action = .press } }, &ts.session, 10, pw.writer(), enc.enc());
    try std.testing.expectEqualStrings("\x03", pw.written());
}

test "ime_consumer: empty ImeResult is no-op" {
    var ts = makeSession();
    var pw = MockPtyWriter{};
    const dirty = consumeImeResult(.{}, &ts.session, 10, pw.writer(), null);
    try std.testing.expect(!dirty);
    try std.testing.expectEqual(@as(usize, 0), pw.written().len);
}
