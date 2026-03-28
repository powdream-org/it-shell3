const std = @import("std");
const builtin = @import("builtin");

pub fn createSocketPair() ![2]std.posix.socket_t {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("socketpair requires BSD or Linux");

    var fds: [2]std.posix.socket_t = undefined;
    const rc = std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds);
    if (rc != 0) return error.Unexpected;
    return fds;
}
