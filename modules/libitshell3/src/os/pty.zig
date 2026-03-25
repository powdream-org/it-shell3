const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const interfaces = @import("interfaces.zig");

const c = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
    if (builtin.os.tag == .macos) {
        @cInclude("util.h");
    } else if (builtin.os.tag == .linux) {
        @cInclude("pty.h");
    }
});

/// Winsize struct matching the POSIX definition.
const Winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16 = 0,
    ws_ypixel: u16 = 0,
};

/// Real PTY operations using POSIX openpty/fork/ioctl.
pub const real_pty_ops: interfaces.PtyOps = .{
    .forkPty = realForkPty,
    .resize = realResize,
    .close = realClose,
    .read = realRead,
};

fn realForkPty(cols: u16, rows: u16) interfaces.PtyOps.ForkPtyError!interfaces.PtyOps.ForkPtyResult {
    var master_fd: posix.fd_t = undefined;
    var slave_fd: posix.fd_t = undefined;

    var ws = Winsize{ .ws_row = rows, .ws_col = cols };

    // Open a PTY pair
    if (c.openpty(&master_fd, &slave_fd, null, null, @ptrCast(&ws)) < 0) {
        return error.PtyOpenFailed;
    }
    errdefer {
        _ = c.close(master_fd);
        _ = c.close(slave_fd);
    }

    // Set CLOEXEC on master fd
    cloexec: {
        const flags = posix.fcntl(master_fd, posix.F.GETFD, 0) catch break :cloexec;
        _ = posix.fcntl(master_fd, posix.F.SETFD, flags | posix.FD_CLOEXEC) catch break :cloexec;
    }

    // Fork
    const pid = c.fork();
    if (pid < 0) {
        return error.ForkFailed;
    }

    if (pid == 0) {
        // Child process
        _ = c.close(master_fd);

        // Create new session
        _ = c.setsid();

        // Set controlling terminal
        _ = c.ioctl(slave_fd, c.TIOCSCTTY, @as(c_ulong, 0));

        // Dup slave to stdin/stdout/stderr
        _ = c.dup2(slave_fd, 0);
        _ = c.dup2(slave_fd, 1);
        _ = c.dup2(slave_fd, 2);
        if (slave_fd > 2) {
            _ = c.close(slave_fd);
        }

        // Reset signal handlers to default
        var sa: posix.Sigaction = .{
            .handler = .{ .handler = posix.SIG.DFL },
            .mask = posix.sigemptyset(),
            .flags = 0,
        };
        posix.sigaction(posix.SIG.HUP, &sa, null);
        posix.sigaction(posix.SIG.INT, &sa, null);
        posix.sigaction(posix.SIG.QUIT, &sa, null);
        posix.sigaction(posix.SIG.TERM, &sa, null);
        posix.sigaction(posix.SIG.CHLD, &sa, null);
        posix.sigaction(posix.SIG.PIPE, &sa, null);

        // Exec the user's shell via C execl (simpler in child context)
        const shell: [*:0]const u8 = std.posix.getenv("SHELL") orelse "/bin/sh";
        _ = c.execl(shell, shell, @as(?[*:0]const u8, null));

        // If exec fails, exit
        c._exit(1);
    }

    // Parent: close slave, return master + child pid
    _ = c.close(slave_fd);
    return .{
        .master_fd = master_fd,
        .child_pid = pid,
    };
}

fn realResize(master_fd: posix.fd_t, cols: u16, rows: u16) interfaces.PtyOps.ResizeError!void {
    var ws = Winsize{ .ws_row = rows, .ws_col = cols };
    if (c.ioctl(master_fd, c.TIOCSWINSZ, @intFromPtr(&ws)) < 0) {
        return error.IoctlFailed;
    }
}

fn realClose(master_fd: posix.fd_t) void {
    _ = c.close(master_fd);
}

fn realRead(master_fd: posix.fd_t, buf: []u8) interfaces.PtyOps.ReadError!usize {
    return posix.read(master_fd, buf);
}

// Real PTY integration tests (fork+exec) are deferred to the dedicated
// integration test suite (Task 14) to avoid fork-related hangs in the
// unit test runner. The vtable contract is verified via mock tests in
// testing/mock_os.zig.

test "real_pty_ops vtable has all required function pointers" {
    try std.testing.expect(real_pty_ops.forkPty == realForkPty);
    try std.testing.expect(real_pty_ops.resize == realResize);
    try std.testing.expect(real_pty_ops.close == realClose);
    try std.testing.expect(real_pty_ops.read == realRead);
}
