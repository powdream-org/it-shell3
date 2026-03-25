//! Re-exports of ghostty types needed by server/ and other modules.
//! This is the single point where libitshell3 code references ghostty types.
const ghostty = @import("ghostty");

pub const Terminal = ghostty.Terminal;
pub const RenderState = ghostty.RenderState;
pub const CellCountInt = ghostty.size.CellCountInt;

// Input types
pub const Key = ghostty.input.Key;
pub const KeyAction = ghostty.input.KeyAction;
pub const KeyEvent = ghostty.input.KeyEvent;
pub const KeyMods = ghostty.input.KeyMods;
pub const KeyEncodeOptions = ghostty.input.KeyEncodeOptions;
pub const MouseAction = ghostty.input.MouseAction;
pub const MouseButton = ghostty.input.MouseButton;
pub const MouseEncodeOptions = ghostty.input.MouseEncodeOptions;
pub const MouseEncodeEvent = ghostty.input.MouseEncodeEvent;

// --- Tests ---

const std = @import("std");

test "ghostty types are importable" {
    // Verify the key types resolve without errors
    try std.testing.expect(@sizeOf(Terminal) > 0);
    try std.testing.expect(@sizeOf(RenderState) > 0);
    try std.testing.expect(@sizeOf(CellCountInt) == 2); // u16
    try std.testing.expect(@sizeOf(Key) > 0);
}
