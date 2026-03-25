const std = @import("std");
const builtin = @import("builtin");

pub const AuthError = error{
    UidMismatch,
    GetPeerCredFailed,
};

/// Verify that the peer on `fd` has the same UID as this process.
/// Uses getpeereid() on macOS/BSD, SO_PEERCRED on Linux.
pub fn verifyPeerUid(fd: std.posix.socket_t) AuthError!u32 {
    if (comptime builtin.os.tag == .macos or builtin.os.tag == .freebsd) {
        return verifyPeerUidBsd(fd);
    } else if (comptime builtin.os.tag == .linux) {
        return verifyPeerUidLinux(fd);
    } else {
        // Unsupported platform — fail closed
        return error.GetPeerCredFailed;
    }
}

fn verifyPeerUidBsd(fd: std.posix.socket_t) AuthError!u32 {
    var euid: std.posix.uid_t = undefined;
    var egid: std.posix.gid_t = undefined;
    const rc = std.c.getpeereid(fd, &euid, &egid);
    if (rc != 0) return error.GetPeerCredFailed;
    const my_uid = std.c.getuid();
    if (euid != my_uid) return error.UidMismatch;
    return euid;
}

fn verifyPeerUidLinux(fd: std.posix.socket_t) AuthError!u32 {
    // SO_PEERCRED returns struct ucred { pid_t pid; uid_t uid; gid_t gid; }
    const SOL_SOCKET = 1;
    const SO_PEERCRED = 17;
    var ucred: extern struct { pid: i32, uid: u32, gid: u32 } = undefined;
    var len: u32 = @sizeOf(@TypeOf(ucred));
    const rc = std.c.getsockopt(fd, SOL_SOCKET, SO_PEERCRED, @ptrCast(&ucred), &len);
    if (rc != 0) return error.GetPeerCredFailed;
    const my_uid = std.os.linux.getuid();
    if (ucred.uid != my_uid) return error.UidMismatch;
    return ucred.uid;
}

// --- Tests ---

test "verifyPeerUid on socketpair (same UID)" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;

    var fds: [2]std.posix.socket_t = undefined;
    const rc = std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds);
    try std.testing.expectEqual(@as(c_int, 0), rc);
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    // Both ends of a socketpair have the same UID
    const uid = try verifyPeerUid(fds[0]);
    try std.testing.expect(uid > 0 or uid == 0); // valid UID (root is 0)
}
