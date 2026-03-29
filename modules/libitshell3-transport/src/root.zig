//! libitshell3-transport: Transport and connection management for it-shell3.
//! Socket lifecycle, byte IO, connection state machine, sequence tracking,
//! capability negotiation, and authentication.

pub const transport = @import("transport.zig");
pub const transport_client = @import("transport_client.zig");
pub const transport_helper = @import("transport_helper.zig");
pub const transport_server = @import("transport_server.zig");
pub const socket_path = @import("socket_path.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
