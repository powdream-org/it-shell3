//! libitshell3-ime: Native IME engine for Korean Hangul composition + English direct passthrough.
//! Wraps libhangul (C) via Zig @cImport.

pub const types = @import("types.zig");
pub const KeyEvent = types.KeyEvent;
pub const ImeResult = types.ImeResult;

pub const engine = @import("engine.zig");
pub const ImeEngine = engine.ImeEngine;

pub const HangulImeEngine = @import("hangul_engine.zig").HangulImeEngine;
pub const MockImeEngine = @import("mock_engine.zig").MockImeEngine;

test {
    // Force test runner to discover tests in all submodules.
    _ = @import("types.zig");
    _ = @import("hid_to_ascii.zig");
    _ = @import("ucs4.zig");
    _ = @import("engine.zig");
    _ = @import("mock_engine.zig");
    _ = @import("hangul_engine.zig");
    _ = @import("hangul_engine_test.zig");
}
