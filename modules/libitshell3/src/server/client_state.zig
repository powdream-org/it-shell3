const std = @import("std");
const protocol = @import("itshell3_protocol");
const Connection = protocol.connection.Connection;
const UnixTransport = protocol.transport.UnixTransport;
const client_writer_mod = @import("client_writer.zig");

/// Holds a protocol Connection plus the raw socket fd needed for kqueue.
/// `unix_transport` must remain stable in memory because `conn.transport.ptr`
/// points to it — do not copy a ClientEntry after init.
pub const ClientEntry = struct {
    unix_transport: UnixTransport,
    conn: Connection,
    socket_fd: std.posix.socket_t,
    writer: client_writer_mod.ClientWriter,
};
