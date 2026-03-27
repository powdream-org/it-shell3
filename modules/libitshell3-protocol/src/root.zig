//! libitshell3-protocol: Wire protocol library for the it-shell3 daemon-client
//! communication. Defines message types, header encoding, JSON/binary
//! serialization, transport abstraction, and connection state management.

pub const header = @import("header.zig");
pub const message_type = @import("message_type.zig");
pub const err = @import("error.zig");
pub const capability = @import("capability.zig");
pub const json = @import("json.zig");
pub const handshake = @import("handshake.zig");
pub const session = @import("session.zig");
pub const pane = @import("pane.zig");
pub const input = @import("input.zig");
pub const preedit = @import("preedit.zig");
pub const auxiliary = @import("auxiliary.zig");
pub const cell = @import("cell.zig");
pub const frame_update = @import("frame_update.zig");
pub const reader = @import("reader.zig");
pub const writer = @import("writer.zig");
pub const socket_path = @import("socket_path.zig");
pub const transport = @import("transport.zig");
pub const connection = @import("connection.zig");
pub const auth = @import("auth.zig");
pub const handshake_io = @import("handshake_io.zig");
pub const testing_mod = @import("testing/root.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
