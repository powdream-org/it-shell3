const std = @import("std");
const client_mod = @import("../client.zig");

/// Handle client read event: stub that reads and discards.
/// Real message handling comes in Plan 3 (protocol).
pub fn handleClientRead(
    _: *client_mod.ClientState,
    _: []u8,
) void {
    // Stub: in the real implementation, we would:
    // 1. Read from client conn_fd
    // 2. Parse protocol messages
    // 3. Dispatch to appropriate handler
    // For now: no-op (the event loop reads via the OS interface)
}

// --- Tests ---

const testing = std.testing;

test "handleClientRead: stub is callable" {
    var cs = client_mod.ClientState.init(1, 5);
    var buf: [256]u8 = undefined;
    handleClientRead(&cs, &buf);
    // No crash = success for a stub
    try testing.expectEqual(client_mod.ClientState.State.handshaking, cs.state);
}
