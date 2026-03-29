//! libitshell3-ime: Native IME engine for Korean Hangul composition + English direct passthrough.
//! Wraps libhangul (C) via Zig @cImport.

pub const types = @import("types.zig");
pub const KeyEvent = types.KeyEvent;
pub const ImeResult = types.ImeResult;

pub const engine = @import("engine.zig");
pub const ImeEngine = engine.ImeEngine;

pub const HangulImeEngine = @import("hangul_engine.zig").HangulImeEngine;
pub const MockImeEngine = @import("testing/mocks/mock_engine.zig").MockImeEngine;

pub const hid_to_ascii = @import("hid_to_ascii.zig");
pub const ucs4 = @import("ucs4.zig");
pub const testing_mod = @import("testing/root.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
