//! libitshell3-transport-v2: Transport and connection management for it-shell3.
//! Socket lifecycle, byte IO, connection state machine, sequence tracking,
//! capability negotiation, and authentication.

pub const transport = @import("transport.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
