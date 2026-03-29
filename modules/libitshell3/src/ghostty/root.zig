//! Ghostty integration helpers. Thin free-function wrappers around ghostty's
//! Terminal, RenderState, key encoding, preedit overlay, and bulk export APIs.

const std = @import("std");

pub const types = @import("types.zig");
pub const terminal = @import("terminal.zig");
pub const render_state = @import("render_state.zig");
pub const key_encoder = @import("key_encoder.zig");
pub const render_export = @import("render_export.zig");
pub const preedit_overlay = @import("preedit_overlay.zig");

test {
    std.testing.refAllDecls(@This());
}
