const std = @import("std");
const builtin = @import("builtin");
const helper = @import("../transport_helper.zig");

pub fn createSocketPair() ![2]std.posix.socket_t {
    comptime if (!builtin.os.tag.isBSD() and builtin.os.tag != .linux)
        @compileError("socketpair requires BSD or Linux");

    var fds: [2]std.posix.socket_t = undefined;
    const rc = std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds);
    if (rc != 0) return error.Unexpected;
    return fds;
}

var path_buf: [helper.MAX_SOCKET_PATH]u8 = undefined;

pub fn generateTestSocketPath() []const u8 {
    const timestamp = std.time.nanoTimestamp();
    const ts_unsigned: u128 = @bitCast(timestamp);
    return std.fmt.bufPrint(
        &path_buf,
        "/tmp/itshell3-test-{x}.sock",
        .{ts_unsigned},
    ) catch unreachable;
}
