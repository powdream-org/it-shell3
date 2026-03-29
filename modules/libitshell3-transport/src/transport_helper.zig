const std = @import("std");

pub const socket_t = std.posix.socket_t;
pub const MAX_SOCKET_PATH: usize = @as(std.posix.sockaddr.un, undefined).path.len;

/// Creates a new Unix domain stream socket.
pub fn newFd() !socket_t {
    return std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
}

/// Builds a sockaddr_un from a socket path.
pub fn makeAddr(socket_path: []const u8) std.posix.sockaddr.un {
    std.debug.assert(socket_path.len < MAX_SOCKET_PATH);
    var addr: std.posix.sockaddr.un = .{ .path = undefined };
    @memset(&addr.path, 0);
    @memcpy(addr.path[0..socket_path.len], socket_path);
    return addr;
}

/// Sets O_NONBLOCK on a file descriptor.
pub fn setNonBlock(fd: std.posix.fd_t) void {
    const flags = std.posix.fcntl(fd, std.posix.F.GETFL, 0) catch return;
    _ = std.posix.fcntl(fd, std.posix.F.SETFL, flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true }))) catch {};
}
