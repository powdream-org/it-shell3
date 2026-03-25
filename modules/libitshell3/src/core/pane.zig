const std = @import("std");
const types = @import("types.zig");

pub const Pane = struct {
    pane_id: types.PaneId,
    slot_index: types.PaneSlot,
    pty_fd: std.posix.fd_t,
    child_pid: std.posix.pid_t,

    // ghostty pointers — opaque, null until Plan 2 fills these
    terminal: ?*anyopaque = null,
    render_state: ?*anyopaque = null,

    // Dimensions
    cols: u16,
    rows: u16,

    // Metadata (updated via OSC sequences)
    title: [256]u8 = [_]u8{0} ** 256,
    title_len: u16 = 0,
    cwd: [4096]u8 = [_]u8{0} ** 4096,
    cwd_len: u16 = 0,

    // Process state
    is_running: bool = true,
    exit_status: ?u8 = null,

    // Two-phase exit flags
    pane_exited: bool = false, // set by SIGCHLD handler after waitpid()
    pty_eof: bool = false, // set by PTY read handler on EV_EOF

    pub fn init(
        pane_id: types.PaneId,
        slot_index: types.PaneSlot,
        pty_fd: std.posix.fd_t,
        child_pid: std.posix.pid_t,
        cols: u16,
        rows: u16,
    ) Pane {
        return Pane{
            .pane_id = pane_id,
            .slot_index = slot_index,
            .pty_fd = pty_fd,
            .child_pid = child_pid,
            .cols = cols,
            .rows = rows,
        };
    }

    /// Returns true only when both two-phase exit flags are set.
    pub fn isFullyDead(self: *const Pane) bool {
        return self.pane_exited and self.pty_eof;
    }

    /// Called when SIGCHLD is received and waitpid() has reaped the child.
    pub fn markExited(self: *Pane, exit_status: u8) void {
        self.pane_exited = true;
        self.exit_status = exit_status;
        self.is_running = false;
    }

    /// Called when the PTY master fd returns EOF.
    pub fn markPtyEof(self: *Pane) void {
        self.pty_eof = true;
    }

    /// Copies up to 256 bytes from title into the internal buffer.
    pub fn setTitle(self: *Pane, title: []const u8) void {
        const len = @min(title.len, self.title.len);
        @memcpy(self.title[0..len], title[0..len]);
        self.title_len = @intCast(len);
    }

    /// Copies up to 4096 bytes from cwd into the internal buffer.
    pub fn setCwd(self: *Pane, cwd: []const u8) void {
        const len = @min(cwd.len, self.cwd.len);
        @memcpy(self.cwd[0..len], cwd[0..len]);
        self.cwd_len = @intCast(len);
    }
};

// --- Tests ---

test "init creates pane with correct fields and default flags" {
    const p = Pane.init(1, 3, 5, 100, 80, 24);
    try std.testing.expectEqual(@as(types.PaneId, 1), p.pane_id);
    try std.testing.expectEqual(@as(types.PaneSlot, 3), p.slot_index);
    try std.testing.expectEqual(@as(std.posix.fd_t, 5), p.pty_fd);
    try std.testing.expectEqual(@as(std.posix.pid_t, 100), p.child_pid);
    try std.testing.expectEqual(@as(u16, 80), p.cols);
    try std.testing.expectEqual(@as(u16, 24), p.rows);
    try std.testing.expect(p.is_running);
    try std.testing.expect(p.exit_status == null);
    try std.testing.expect(!p.pane_exited);
    try std.testing.expect(!p.pty_eof);
    try std.testing.expect(p.terminal == null);
    try std.testing.expect(p.render_state == null);
}

test "isFullyDead returns false when neither flag set" {
    const p = Pane.init(1, 0, 5, 100, 80, 24);
    try std.testing.expect(!p.isFullyDead());
}

test "isFullyDead returns false when only pane_exited set" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.markExited(0);
    try std.testing.expect(!p.isFullyDead());
}

test "isFullyDead returns false when only pty_eof set" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.markPtyEof();
    try std.testing.expect(!p.isFullyDead());
}

test "isFullyDead returns true when both flags set" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.markExited(0);
    p.markPtyEof();
    try std.testing.expect(p.isFullyDead());
}

test "markExited sets pane_exited, exit_status, and clears is_running" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    try std.testing.expect(p.is_running);
    p.markExited(42);
    try std.testing.expect(p.pane_exited);
    try std.testing.expectEqual(@as(?u8, 42), p.exit_status);
    try std.testing.expect(!p.is_running);
}

test "markPtyEof sets pty_eof but does not change is_running" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.markPtyEof();
    try std.testing.expect(p.pty_eof);
    try std.testing.expect(p.is_running); // unchanged
}

test "two-phase: markExited then markPtyEof -> isFullyDead true" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.markExited(0);
    try std.testing.expect(!p.isFullyDead());
    p.markPtyEof();
    try std.testing.expect(p.isFullyDead());
}

test "two-phase: markPtyEof then markExited -> isFullyDead true (reverse order)" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.markPtyEof();
    try std.testing.expect(!p.isFullyDead());
    p.markExited(0);
    try std.testing.expect(p.isFullyDead());
}

test "setTitle copies bytes and updates title_len" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    const title = "my terminal";
    p.setTitle(title);
    try std.testing.expectEqual(@as(u16, title.len), p.title_len);
    try std.testing.expectEqualSlices(u8, title, p.title[0..p.title_len]);
}

test "setTitle truncates if longer than 256" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    const long_title = "a" ** 300;
    p.setTitle(long_title);
    try std.testing.expectEqual(@as(u16, 256), p.title_len);
    try std.testing.expectEqualSlices(u8, long_title[0..256], p.title[0..256]);
}

test "setCwd copies bytes and updates cwd_len" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    const cwd = "/home/user/project";
    p.setCwd(cwd);
    try std.testing.expectEqual(@as(u16, cwd.len), p.cwd_len);
    try std.testing.expectEqualSlices(u8, cwd, p.cwd[0..p.cwd_len]);
}
