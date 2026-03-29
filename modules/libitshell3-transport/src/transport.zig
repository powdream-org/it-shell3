//! Core transport types: socket connection wrapper with non-blocking I/O
//! result types for the daemon-client communication layer.

const std = @import("std");
const posix = std.posix;

/// A single contiguous byte buffer for scatter/gather transport I/O.
pub const ImmutableIoVector = posix.iovec_const;

pub const FileDescriptor = posix.fd_t;

/// Unix socket connection with non-blocking-aware send/recv.
///
/// The `fd` field is public so callers can register it with kqueue/epoll.
pub const SocketConnection = struct {
    fd: FileDescriptor,

    /// Reads available bytes into `buf`, returning a tagged result to
    /// distinguish partial reads, would-block, and peer disconnection.
    pub fn recv(self: SocketConnection, buf: []u8) RecvResult {
        const n = posix.read(self.fd, buf) catch |err| switch (err) {
            error.WouldBlock => return .would_block,
            error.ConnectionResetByPeer => return .peer_closed,
            error.NotOpenForReading => return .peer_closed,
            else => return .{ .err = err },
        };
        if (n == 0) return .peer_closed;
        return .{ .bytes_read = n };
    }

    /// Writes `buf` to the socket, returning bytes written or a non-blocking/error status.
    pub fn send(self: SocketConnection, buf: []const u8) SendResult {
        const n = posix.write(self.fd, buf) catch |err| switch (err) {
            error.WouldBlock => return .would_block,
            error.BrokenPipe => return .peer_closed,
            error.ConnectionResetByPeer => return .peer_closed,
            error.NotOpenForWriting => return .peer_closed,
            else => return .{ .err = err },
        };
        return .{ .bytes_written = n };
    }

    /// Vectored write: sends multiple buffers in a single syscall.
    pub fn sendv(self: SocketConnection, iovecs: []const ImmutableIoVector) SendResult {
        const n = posix.writev(self.fd, iovecs) catch |err| switch (err) {
            error.WouldBlock => return .would_block,
            error.BrokenPipe => return .peer_closed,
            error.ConnectionResetByPeer => return .peer_closed,
            error.NotOpenForWriting => return .peer_closed,
            else => return .{ .err = err },
        };
        return .{ .bytes_written = n };
    }

    /// Closes the socket and poisons `fd` to -1 to catch use-after-close.
    pub fn close(self: *SocketConnection) void {
        posix.close(self.fd);
        self.fd = -1;
    }
};

/// Tagged result from a recv operation, distinguishing success from non-blocking and error states.
pub const RecvResult = union(enum) {
    bytes_read: usize,
    would_block: void,
    peer_closed: void,
    err: posix.ReadError,
};

/// Tagged result from a send/sendv operation.
pub const SendResult = union(enum) {
    bytes_written: usize,
    would_block: void,
    peer_closed: void,
    err: posix.WriteError,
};

// ── Tests ────────────────────────────────────────────────────────────────

test "SocketConnection.recv: round-trip with send" {
    const helpers = @import("testing/helpers.zig");
    const client_fd, const server_fd = try helpers.createSocketPair();
    var client = SocketConnection{ .fd = client_fd };
    var server = SocketConnection{ .fd = server_fd };
    defer client.close();
    defer server.close();

    const sent = client.send("hello");
    try std.testing.expectEqual(@as(usize, 5), sent.bytes_written);

    var buf: [64]u8 = undefined;
    const result = server.recv(&buf);
    try std.testing.expectEqualSlices(u8, "hello", buf[0..result.bytes_read]);
}

test "SocketConnection.recv: peer_closed on EOF" {
    const helpers = @import("testing/helpers.zig");
    const client_fd, const server_fd = try helpers.createSocketPair();
    var server = SocketConnection{ .fd = server_fd };

    posix.close(client_fd);

    var buf: [64]u8 = undefined;
    const result = server.recv(&buf);
    try std.testing.expectEqual(RecvResult.peer_closed, result);

    server.close();
}

test "SocketConnection.sendv: multiple segments" {
    const helpers = @import("testing/helpers.zig");
    const client_fd, const server_fd = try helpers.createSocketPair();
    var client = SocketConnection{ .fd = client_fd };
    var server = SocketConnection{ .fd = server_fd };
    defer client.close();
    defer server.close();

    const iovecs = [_]ImmutableIoVector{
        .{ .base = "hello", .len = 5 },
        .{ .base = ", world", .len = 7 },
    };
    const sent = client.sendv(&iovecs);
    try std.testing.expectEqual(@as(usize, 12), sent.bytes_written);

    var buf: [64]u8 = undefined;
    var total: usize = 0;
    while (total < 12) {
        const r = server.recv(buf[total..]);
        switch (r) {
            .bytes_read => |n| total += n,
            .peer_closed => break,
            else => break,
        }
    }
    try std.testing.expectEqualSlices(u8, "hello, world", buf[0..total]);
}

test "SocketConnection.send: peer_closed on broken pipe" {
    const helpers = @import("testing/helpers.zig");
    const client_fd, const server_fd = try helpers.createSocketPair();
    var client = SocketConnection{ .fd = client_fd };

    posix.close(server_fd);

    const result = client.send("data");
    try std.testing.expectEqual(SendResult.peer_closed, result);

    client.close();
}

test "SocketConnection.close: sets fd to -1" {
    const helpers = @import("testing/helpers.zig");
    const client_fd, _ = try helpers.createSocketPair();
    var conn = SocketConnection{ .fd = client_fd };

    conn.close();
    try std.testing.expectEqual(@as(FileDescriptor, -1), conn.fd);
}

test "SocketConnection: bidirectional communication" {
    const helpers = @import("testing/helpers.zig");
    const fd_a, const fd_b = try helpers.createSocketPair();
    var a = SocketConnection{ .fd = fd_a };
    var b = SocketConnection{ .fd = fd_b };
    defer a.close();
    defer b.close();

    _ = a.send("from A");
    var buf: [64]u8 = undefined;
    const r1 = b.recv(&buf);
    try std.testing.expectEqualSlices(u8, "from A", buf[0..r1.bytes_read]);

    _ = b.send("from B");
    const r2 = a.recv(&buf);
    try std.testing.expectEqualSlices(u8, "from B", buf[0..r2.bytes_read]);
}

const setNonBlock = @import("transport_helper.zig").setNonBlock;

fn setSmallSendBuffer(fd: posix.fd_t) void {
    // Set the smallest possible send buffer to make it easy to fill.
    const min_size: [4]u8 = @bitCast(@as(u32, 1));
    posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.SNDBUF, &min_size) catch {};
}

test "SocketConnection.recv: would_block on non-blocking socket with no data" {
    const helpers = @import("testing/helpers.zig");
    const fd_a, const fd_b = try helpers.createSocketPair();
    var a = SocketConnection{ .fd = fd_a };
    var b = SocketConnection{ .fd = fd_b };
    defer a.close();
    defer b.close();

    // Set receiver to non-blocking.
    setNonBlock(b.fd);

    // No data sent, so recv should return would_block.
    var buf: [64]u8 = undefined;
    const result = b.recv(&buf);
    try std.testing.expectEqual(RecvResult.would_block, result);
}

test "SocketConnection.send: would_block when send buffer is full" {
    const helpers = @import("testing/helpers.zig");
    const fd_a, const fd_b = try helpers.createSocketPair();
    var client = SocketConnection{ .fd = fd_a };
    var server = SocketConnection{ .fd = fd_b };
    defer client.close();
    defer server.close();

    // Set non-blocking and minimize send buffer to trigger would_block.
    setNonBlock(client.fd);
    setSmallSendBuffer(client.fd);

    // Fill the send buffer until would_block.
    const chunk = [_]u8{0xAA} ** 4096;
    var got_would_block = false;
    for (0..4096) |_| {
        const result = client.send(&chunk);
        switch (result) {
            .would_block => {
                got_would_block = true;
                break;
            },
            .bytes_written => {},
            else => break,
        }
    }
    try std.testing.expect(got_would_block);
}

test "SocketConnection.sendv: would_block when send buffer is full" {
    const helpers = @import("testing/helpers.zig");
    const fd_a, const fd_b = try helpers.createSocketPair();
    var client = SocketConnection{ .fd = fd_a };
    var server = SocketConnection{ .fd = fd_b };
    defer client.close();
    defer server.close();

    // Set non-blocking and minimize send buffer to trigger would_block.
    setNonBlock(client.fd);
    setSmallSendBuffer(client.fd);

    // Fill the send buffer until would_block.
    const chunk = [_]u8{0xBB} ** 4096;
    const iovecs = [_]ImmutableIoVector{
        .{ .base = &chunk, .len = chunk.len },
    };
    var got_would_block = false;
    for (0..4096) |_| {
        const result = client.sendv(&iovecs);
        switch (result) {
            .would_block => {
                got_would_block = true;
                break;
            },
            .bytes_written => {},
            else => break,
        }
    }
    try std.testing.expect(got_would_block);
}

test "SocketConnection.sendv: peer_closed on broken pipe" {
    const helpers = @import("testing/helpers.zig");
    const fd_a, const fd_b = try helpers.createSocketPair();
    var client = SocketConnection{ .fd = fd_a };

    // Close the peer end to trigger BrokenPipe on sendv.
    posix.close(fd_b);

    const iovecs = [_]ImmutableIoVector{
        .{ .base = "data", .len = 4 },
    };
    const result = client.sendv(&iovecs);
    try std.testing.expectEqual(SendResult.peer_closed, result);

    client.close();
}
