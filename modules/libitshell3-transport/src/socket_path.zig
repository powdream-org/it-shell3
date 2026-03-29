const std = @import("std");
const helper = @import("transport_helper.zig");

// TODO(Plan 12): Implement proper socket path resolution per ADR 00054.
// Discovery strategy: find running it-shell3-daemon via ps, locate its
// per-instance socket directory by PID.
pub fn resolveByPid(buf: *[helper.MAX_SOCKET_PATH]u8, pid: std.posix.pid_t) []const u8 {
    const tmpdir = std.posix.getenv("TMPDIR") orelse "/tmp";
    return std.fmt.bufPrint(buf, "{s}/itshell3/temp-{d}.sock", .{ tmpdir, pid }) catch
        unreachable;
}
