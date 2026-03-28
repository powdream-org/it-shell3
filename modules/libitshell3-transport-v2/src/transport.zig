/// A single contiguous byte buffer for transport I/O.
pub const IoVector = []const u8;

/// Bidirectional byte stream interface.
pub const Transport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        read: *const fn (ptr: *anyopaque, buf: []u8) ReadError!usize,
        writeSingle: *const fn (ptr: *anyopaque, data: IoVector) WriteError!void,
        writeBulk: *const fn (ptr: *anyopaque, dataVector: []const IoVector) WriteError!void,
        close: *const fn (ptr: *anyopaque) void,
    };

    pub const ReadError = error{ EndOfStream, ConnectionReset, Unexpected };
    pub const WriteError = error{ BrokenPipe, ConnectionReset, Unexpected };

    /// The number of bytes read, or 0 on peer close.
    pub fn read(self: *Transport, buf: []u8) ReadError!usize {
        return self.vtable.read(self.ptr, buf);
    }

    /// Sends one or more byte buffers. Empty `dataVector` is a no-op.
    pub fn write(self: *Transport, dataVector: []const IoVector) WriteError!void {
        if (dataVector.len == 0) {
            return; // no-op for empty vector
        } else if (dataVector.len == 1) {
            return self.vtable.writeSingle(self.ptr, dataVector[0]);
        } else {
            return self.vtable.writeBulk(self.ptr, dataVector);
        }
    }

    pub fn close(self: *Transport) void {
        self.vtable.close(self.ptr);
    }
};

const std = @import("std");
const socket_t = std.posix.socket_t;
const iovec_const = std.posix.iovec_const;
const Stream = std.net.Stream;

/// Unix socket connection.
pub const SocketConnection = struct {
    socket_fd: socket_t,

    const vtable = Transport.VTable{
        .read = &readImpl,
        .writeSingle = &writeImpl,
        .writeBulk = &writevImpl,
        .close = &closeImpl,
    };

    /// The SocketConnection must outlive the returned Transport.
    pub fn asTransport(self: *SocketConnection) Transport {
        return .{ .ptr = @ptrCast(self), .vtable = &vtable };
    }

    fn readImpl(ptr: *anyopaque, buf: []u8) Transport.ReadError!usize {
        const stream = Stream{ .handle = cast(ptr).socket_fd };
        return stream.read(buf) catch |err| switch (err) {
            error.ConnectionResetByPeer => return error.ConnectionReset,
            else => return error.Unexpected,
        };
    }

    fn writeImpl(ptr: *anyopaque, data: IoVector) Transport.WriteError!void {
        const stream = Stream{ .handle = cast(ptr).socket_fd };
        stream.writeAll(data) catch |err| switch (err) {
            error.BrokenPipe => return error.BrokenPipe,
            error.ConnectionResetByPeer => return error.ConnectionReset,
            else => return error.Unexpected,
        };
    }

    // []const u8 and iovec_const have identical memory layout (ptr + len).
    // This allows zero-copy reinterpretation via @ptrCast.
    comptime {
        std.debug.assert(@sizeOf(IoVector) == @sizeOf(iovec_const));
        std.debug.assert(@alignOf(IoVector) == @alignOf(iovec_const));
    }

    fn writevImpl(ptr: *anyopaque, dataVector: []const IoVector) Transport.WriteError!void {
        const fd = cast(ptr).socket_fd;
        const iovecs: [*]const iovec_const = @ptrCast(dataVector.ptr);
        _ = std.posix.writev(fd, iovecs[0..dataVector.len]) catch |err| switch (err) {
            error.BrokenPipe => return error.BrokenPipe,
            error.ConnectionResetByPeer => return error.ConnectionReset,
            else => return error.Unexpected,
        };
    }

    fn closeImpl(ptr: *anyopaque) void {
        std.posix.close(cast(ptr).socket_fd);
    }

    inline fn cast(ptr: *anyopaque) *SocketConnection {
        return @ptrCast(@alignCast(ptr));
    }
};

// ── Tests ────────────────────────────────────────────────────────────────

test "SocketConnection: read and writeSingle round-trip via socketpair" {
    const helpers = @import("testing/helpers.zig");
    const client_fd, const server_fd = try helpers.createSocketPair();
    var client = SocketConnection{ .socket_fd = client_fd };
    var server = SocketConnection{ .socket_fd = server_fd };
    var ct = client.asTransport();
    var st = server.asTransport();
    defer ct.close();
    defer st.close();

    try ct.write(&.{"hello"});

    var buf: [64]u8 = undefined;
    const n = try st.read(&buf);
    try std.testing.expectEqualSlices(u8, "hello", buf[0..n]);
}

test "SocketConnection: writeBulk sends multiple segments in order" {
    const helpers = @import("testing/helpers.zig");
    const client_fd, const server_fd = try helpers.createSocketPair();
    var client = SocketConnection{ .socket_fd = client_fd };
    var server = SocketConnection{ .socket_fd = server_fd };
    var ct = client.asTransport();
    var st = server.asTransport();
    defer ct.close();
    defer st.close();

    try ct.write(&.{ "hello", ", ", "world" });

    var buf: [64]u8 = undefined;
    var total: usize = 0;
    while (total < 12) {
        const n = try st.read(buf[total..]);
        if (n == 0) break;
        total += n;
    }
    try std.testing.expectEqualSlices(u8, "hello, world", buf[0..total]);
}

test "Transport.write: empty dataVector is no-op" {
    const helpers = @import("testing/helpers.zig");
    const client_fd, const server_fd = try helpers.createSocketPair();
    const client = SocketConnection{ .socket_fd = client_fd };
    var ct = @constCast(&client).asTransport();
    defer ct.close();
    std.posix.close(server_fd);

    // Should not error or crash
    try ct.write(&.{});
}

test "SocketConnection: read returns 0 on peer close" {
    const helpers = @import("testing/helpers.zig");
    const client_fd, const server_fd = try helpers.createSocketPair();
    var server = SocketConnection{ .socket_fd = server_fd };
    var st = server.asTransport();

    // Close client side
    std.posix.close(client_fd);

    var buf: [64]u8 = undefined;
    const n = try st.read(&buf);
    try std.testing.expectEqual(@as(usize, 0), n);

    st.close();
}

test "SocketConnection: bidirectional communication" {
    const helpers = @import("testing/helpers.zig");
    const fd_a, const fd_b = try helpers.createSocketPair();
    var a = SocketConnection{ .socket_fd = fd_a };
    var b = SocketConnection{ .socket_fd = fd_b };
    var ta = a.asTransport();
    var tb = b.asTransport();
    defer ta.close();
    defer tb.close();

    // A -> B
    try ta.write(&.{"from A"});
    var buf: [64]u8 = undefined;
    const n1 = try tb.read(&buf);
    try std.testing.expectEqualSlices(u8, "from A", buf[0..n1]);

    // B -> A
    try tb.write(&.{"from B"});
    const n2 = try ta.read(&buf);
    try std.testing.expectEqualSlices(u8, "from B", buf[0..n2]);
}

test "SocketConnection: writeBulk single segment dispatches to writeSingle path" {
    const helpers = @import("testing/helpers.zig");
    const client_fd, const server_fd = try helpers.createSocketPair();
    var client = SocketConnection{ .socket_fd = client_fd };
    var server = SocketConnection{ .socket_fd = server_fd };
    var ct = client.asTransport();
    var st = server.asTransport();
    defer ct.close();
    defer st.close();

    // Single-element dataVector goes through writeSingle path in Transport.write
    try ct.write(&.{"single"});

    var buf: [64]u8 = undefined;
    const n = try st.read(&buf);
    try std.testing.expectEqualSlices(u8, "single", buf[0..n]);
}
