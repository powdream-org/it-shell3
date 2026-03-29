//! libitshell3-protocol: Wire protocol library for it-shell3.
//! Defines message types, header encoding, JSON/binary serialization,
//! and frame reader/writer.

// Imports are in lexicographical order. Keep sorted when adding new entries.
pub const auxiliary = @import("auxiliary.zig");
pub const capability = @import("capability.zig");
pub const cell = @import("cell.zig");
pub const err = @import("error.zig");
pub const frame_update = @import("frame_update.zig");
pub const handshake = @import("handshake.zig");
pub const header = @import("header.zig");
pub const input = @import("input.zig");
pub const message_type = @import("message_type.zig");
pub const pane = @import("pane.zig");
pub const preedit = @import("preedit.zig");
pub const reader = @import("reader.zig");
pub const session = @import("session.zig");
pub const writer = @import("writer.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
