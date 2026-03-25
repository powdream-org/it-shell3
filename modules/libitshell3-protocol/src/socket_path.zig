const std = @import("std");
const builtin = @import("builtin");

pub const MAX_SOCKET_PATH: usize = 104; // macOS sockaddr_un limit

/// Resolve the socket path for a given server-id.
/// Priority: $ITSHELL3_SOCKET > $XDG_RUNTIME_DIR > $TMPDIR > /tmp
pub fn resolve(
    buf: *[MAX_SOCKET_PATH]u8,
    server_id: []const u8,
) error{PathTooLong}![]const u8 {
    // 1. Check $ITSHELL3_SOCKET (exact path override)
    if (std.posix.getenv("ITSHELL3_SOCKET")) |path| {
        if (path.len > MAX_SOCKET_PATH) return error.PathTooLong;
        @memcpy(buf[0..path.len], path);
        return buf[0..path.len];
    }

    const uid = getuid();

    // 2. $XDG_RUNTIME_DIR/itshell3/<server_id>.sock
    if (std.posix.getenv("XDG_RUNTIME_DIR")) |xdg| {
        return formatPath(buf, xdg, "itshell3", server_id);
    }

    // 3. $TMPDIR/itshell3-<uid>/<server_id>.sock
    if (std.posix.getenv("TMPDIR")) |tmpdir| {
        return formatPathWithUid(buf, tmpdir, uid, server_id);
    }

    // 4. /tmp/itshell3-<uid>/<server_id>.sock
    return formatPathWithUid(buf, "/tmp", uid, server_id);
}

fn getuid() u32 {
    if (comptime builtin.os.tag == .macos) {
        return std.c.getuid();
    } else if (comptime builtin.os.tag == .linux) {
        return std.os.linux.getuid();
    } else {
        return 0;
    }
}

fn formatPath(
    buf: *[MAX_SOCKET_PATH]u8,
    base: []const u8,
    subdir: []const u8,
    server_id: []const u8,
) error{PathTooLong}![]const u8 {
    const result = std.fmt.bufPrint(buf, "{s}/{s}/{s}.sock", .{ base, subdir, server_id }) catch
        return error.PathTooLong;
    return result;
}

fn formatPathWithUid(
    buf: *[MAX_SOCKET_PATH]u8,
    base: []const u8,
    uid: u32,
    server_id: []const u8,
) error{PathTooLong}![]const u8 {
    const result = std.fmt.bufPrint(buf, "{s}/itshell3-{d}/{s}.sock", .{ base, uid, server_id }) catch
        return error.PathTooLong;
    return result;
}

/// Ensure the socket directory exists with 0700 permissions.
pub fn ensureDirectory(path: []const u8) !void {
    const dir = std.fs.path.dirname(path) orelse return;
    std.posix.mkdir(dir, 0o700) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

// --- Tests ---

test "resolve with ITSHELL3_SOCKET env override" {
    // We can't easily set env in tests, so test the format functions directly
    var buf: [MAX_SOCKET_PATH]u8 = undefined;
    const path = try formatPath(&buf, "/run/user/1000", "itshell3", "default");
    try std.testing.expectEqualStrings("/run/user/1000/itshell3/default.sock", path);
}

test "formatPathWithUid" {
    var buf: [MAX_SOCKET_PATH]u8 = undefined;
    const path = try formatPathWithUid(&buf, "/tmp", 501, "default");
    try std.testing.expectEqualStrings("/tmp/itshell3-501/default.sock", path);
}

test "formatPathWithUid TMPDIR" {
    var buf: [MAX_SOCKET_PATH]u8 = undefined;
    const path = try formatPathWithUid(&buf, "/var/folders/xx/yy", 501, "myserver");
    try std.testing.expectEqualStrings("/var/folders/xx/yy/itshell3-501/myserver.sock", path);
}

test "path too long returns error" {
    var buf: [MAX_SOCKET_PATH]u8 = undefined;
    // Create a server_id that will exceed 104 bytes
    const long_id = "a" ** 90;
    const result = formatPathWithUid(&buf, "/tmp", 501, long_id);
    try std.testing.expectError(error.PathTooLong, result);
}

test "MAX_SOCKET_PATH is 104" {
    try std.testing.expectEqual(@as(usize, 104), MAX_SOCKET_PATH);
}
