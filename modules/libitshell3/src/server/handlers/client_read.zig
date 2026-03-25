const std = @import("std");
const protocol = @import("itshell3_protocol");
const Connection = protocol.connection.Connection;

/// Handle client read event: stub that reads and discards.
/// Real message handling comes in Plan 3 (protocol).
pub fn handleClientRead(
    _: *Connection,
    _: []u8,
) void {
    // Stub: in the real implementation, we would:
    // 1. Read from client transport
    // 2. Parse protocol messages
    // 3. Dispatch to appropriate handler
    // For now: no-op (the event loop reads via the OS interface)
}

// --- Tests ---

const testing = std.testing;

test "handleClientRead: stub is callable" {
    const allocator = testing.allocator;
    var bt = protocol.transport.BufferTransport.init(allocator, "");
    defer bt.deinit();
    var conn = Connection.init(bt.transport());
    var buf: [256]u8 = undefined;
    handleClientRead(&conn, &buf);
    // No crash = success for a stub
    try testing.expectEqual(protocol.connection.ConnectionState.handshaking, conn.state);
}
