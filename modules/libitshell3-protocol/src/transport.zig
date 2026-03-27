const std = @import("std");
const builtin = @import("builtin");
const socket_path_mod = @import("socket_path.zig");

/// Transport provides a bidirectional byte stream.
/// Implemented by UnixTransport (real) and BufferTransport (testing).
pub const Transport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        read: *const fn (ptr: *anyopaque, buf: []u8) ReadError!usize,
        write: *const fn (ptr: *anyopaque, data: []const u8) WriteError!void,
        close: *const fn (ptr: *anyopaque) void,
    };

    pub const ReadError = error{ EndOfStream, ConnectionReset, Unexpected };
    pub const WriteError = error{ BrokenPipe, ConnectionReset, Unexpected };

    pub fn read(self: Transport, buf: []u8) ReadError!usize {
        return self.vtable.read(self.ptr, buf);
    }

    pub fn write(self: Transport, data: []const u8) WriteError!void {
        return self.vtable.write(self.ptr, data);
    }

    pub fn close(self: Transport) void {
        self.vtable.close(self.ptr);
    }
};

/// Real Unix socket transport.
pub const UnixTransport = struct {
    socket_fd: std.posix.socket_t,

    const vtable = Transport.VTable{
        .read = &readImpl,
        .write = &writeImpl,
        .close = &closeImpl,
    };

    pub fn transport(self: *UnixTransport) Transport {
        return .{ .ptr = @ptrCast(self), .vtable = &vtable };
    }

    pub fn reader(self: UnixTransport) std.net.Stream.Reader {
        return .{ .context = .{ .handle = self.socket_fd } };
    }

    pub fn writer(self: UnixTransport) std.net.Stream.Writer {
        return .{ .context = .{ .handle = self.socket_fd } };
    }

    fn readImpl(ptr: *anyopaque, buf: []u8) Transport.ReadError!usize {
        const self: *UnixTransport = @ptrCast(@alignCast(ptr));
        const stream = std.net.Stream{ .handle = self.socket_fd };
        return stream.read(buf) catch |err| switch (err) {
            error.ConnectionResetByPeer => return error.ConnectionReset,
            else => return error.Unexpected,
        };
    }

    fn writeImpl(ptr: *anyopaque, data: []const u8) Transport.WriteError!void {
        const self: *UnixTransport = @ptrCast(@alignCast(ptr));
        const stream = std.net.Stream{ .handle = self.socket_fd };
        stream.writeAll(data) catch |err| switch (err) {
            error.BrokenPipe => return error.BrokenPipe,
            error.ConnectionResetByPeer => return error.ConnectionReset,
            else => return error.Unexpected,
        };
    }

    fn closeImpl(ptr: *anyopaque) void {
        const self: *UnixTransport = @ptrCast(@alignCast(ptr));
        std.posix.close(self.socket_fd);
    }
};

/// Server-side listener: bind + listen + accept.
pub const Listener = struct {
    listen_fd: std.posix.socket_t,
    socket_path_storage: [socket_path_mod.MAX_SOCKET_PATH]u8,
    socket_path_length: usize,

    pub fn socketPath(self: *const Listener) []const u8 {
        return self.socket_path_storage[0..self.socket_path_length];
    }

    pub fn accept(self: *Listener) !UnixTransport {
        const fd = try std.posix.accept(self.listen_fd, null, null, 0);
        return .{ .socket_fd = fd };
    }

    pub fn deinit(self: *Listener) void {
        std.posix.close(self.listen_fd);
        // Unlink socket file
        const path = self.socketPath();
        std.posix.unlink(path) catch {};
    }
};

/// Bind and listen on a Unix domain socket.
pub fn listen(socket_path: []const u8) !Listener {
    // Probe for stale socket — try connecting; if it fails, unlink
    probeAndCleanStale(socket_path);

    const fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    errdefer std.posix.close(fd);

    // Set buffer sizes
    const buf_size: u32 = 256 * 1024;
    std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.SNDBUF, &std.mem.toBytes(buf_size)) catch {};
    std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVBUF, &std.mem.toBytes(buf_size)) catch {};

    var addr: std.posix.sockaddr.un = .{ .path = undefined };
    @memset(&addr.path, 0);
    if (socket_path.len >= addr.path.len) return error.NameTooLong;
    @memcpy(addr.path[0..socket_path.len], socket_path);

    try std.posix.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un));

    // chmod 0600 on socket file. The directory is 0700 which provides primary
    // access control; this is defense-in-depth. Use C function for null-terminated path.
    var path_buf: [socket_path_mod.MAX_SOCKET_PATH + 1]u8 = undefined;
    @memcpy(path_buf[0..socket_path.len], socket_path);
    path_buf[socket_path.len] = 0;
    _ = std.c.chmod(@ptrCast(&path_buf), 0o600);

    try std.posix.listen(fd, 16);

    var result = Listener{
        .listen_fd = fd,
        .socket_path_storage = undefined,
        .socket_path_length = socket_path.len,
    };
    @memcpy(result.socket_path_storage[0..socket_path.len], socket_path);
    return result;
}

fn probeAndCleanStale(socket_path: []const u8) void {
    // Try connecting to see if anyone is listening
    const fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0) catch return;
    defer std.posix.close(fd);

    var addr: std.posix.sockaddr.un = .{ .path = undefined };
    @memset(&addr.path, 0);
    if (socket_path.len >= addr.path.len) return;
    @memcpy(addr.path[0..socket_path.len], socket_path);

    std.posix.connect(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch {
        // Connection failed — socket is stale, remove it
        std.posix.unlink(socket_path) catch {};
        return;
    };
    // Connection succeeded — someone is already listening, don't remove
    // (caller will get EADDRINUSE on bind, which is correct)
}

/// Connect to an existing Unix domain socket.
pub fn connect(socket_path: []const u8) !UnixTransport {
    const fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
    errdefer std.posix.close(fd);

    var addr: std.posix.sockaddr.un = .{ .path = undefined };
    @memset(&addr.path, 0);
    if (socket_path.len >= addr.path.len) return error.NameTooLong;
    @memcpy(addr.path[0..socket_path.len], socket_path);

    try std.posix.connect(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un));
    return .{ .socket_fd = fd };
}

/// Mock transport for tests — backed by in-memory buffers.
pub const BufferTransport = struct {
    read_buf: []const u8,
    read_pos: usize = 0,
    write_buf: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    const vtable = Transport.VTable{
        .read = &readImpl,
        .write = &writeImpl,
        .close = &closeImpl,
    };

    pub fn init(allocator: std.mem.Allocator, read_data: []const u8) BufferTransport {
        return .{
            .read_buf = read_data,
            .write_buf = std.ArrayList(u8).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BufferTransport) void {
        self.write_buf.deinit(self.allocator);
    }

    pub fn transport(self: *BufferTransport) Transport {
        return .{ .ptr = @ptrCast(self), .vtable = &vtable };
    }

    pub fn writtenData(self: *const BufferTransport) []const u8 {
        return self.write_buf.items;
    }

    fn readImpl(ptr: *anyopaque, buf: []u8) Transport.ReadError!usize {
        const self: *BufferTransport = @ptrCast(@alignCast(ptr));
        if (self.read_pos >= self.read_buf.len) return 0; // EOF
        const available = self.read_buf[self.read_pos..];
        const n = @min(buf.len, available.len);
        @memcpy(buf[0..n], available[0..n]);
        self.read_pos += n;
        return n;
    }

    fn writeImpl(ptr: *anyopaque, data: []const u8) Transport.WriteError!void {
        const self: *BufferTransport = @ptrCast(@alignCast(ptr));
        self.write_buf.appendSlice(self.allocator, data) catch return error.Unexpected;
    }

    fn closeImpl(_: *anyopaque) void {}
};

// --- Tests ---

test "BufferTransport: write then read" {
    const allocator = std.testing.allocator;
    var bt = BufferTransport.init(allocator, "hello");
    defer bt.deinit();

    var t = bt.transport();

    // Read
    var buf: [10]u8 = undefined;
    const n = try t.read(&buf);
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqualSlices(u8, "hello", buf[0..n]);

    // Write
    try t.write("world");
    try std.testing.expectEqualSlices(u8, "world", bt.writtenData());
}

test "BufferTransport: returns 0 at EOF" {
    const allocator = std.testing.allocator;
    var bt = BufferTransport.init(allocator, "");
    defer bt.deinit();

    var t = bt.transport();
    var buf: [10]u8 = undefined;
    const n = try t.read(&buf);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "UnixTransport: via socketpair" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;

    var fds: [2]std.posix.socket_t = undefined;
    const rc = std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds);
    try std.testing.expectEqual(@as(c_int, 0), rc);

    var client = UnixTransport{ .socket_fd = fds[0] };
    var server = UnixTransport{ .socket_fd = fds[1] };

    // Write from client, read from server
    const ct = client.transport();
    const st = server.transport();

    try ct.write("test data");

    var buf: [64]u8 = undefined;
    const n = try st.read(&buf);
    try std.testing.expectEqualSlices(u8, "test data", buf[0..n]);

    ct.close();
    st.close();
}

test "listen/connect: real socket round-trip" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;

    const allocator = std.testing.allocator;
    _ = allocator;

    // Use a temp path
    const path = "/tmp/itshell3-test-transport.sock";
    std.posix.unlink(path) catch {};

    var listener = try listen(path);
    defer listener.deinit();

    // Connect client
    const client = try connect(path);
    defer std.posix.close(client.socket_fd);

    // Accept on server side
    const server = try listener.accept();
    defer std.posix.close(server.socket_fd);

    // Write from client, read from server
    const stream_c = std.net.Stream{ .handle = client.socket_fd };
    try stream_c.writeAll("hello from client");

    var buf: [64]u8 = undefined;
    const stream_s = std.net.Stream{ .handle = server.socket_fd };
    const n = try stream_s.read(&buf);
    try std.testing.expectEqualSlices(u8, "hello from client", buf[0..n]);
}
