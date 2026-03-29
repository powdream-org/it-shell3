//! Server-side pane state. Wraps a PTY master fd, child process, ghostty
//! terminal/render-state pointers, and two-phase exit tracking (SIGCHLD + EOF).

const std = @import("std");
const core = @import("itshell3_core");
const types = core.types;
const ghostty = @import("itshell3_ghostty");
const terminal_mod = ghostty.terminal;
const render_state_mod = ghostty.render_state;

/// A single terminal pane within a session. Owns the PTY fd and child PID,
/// holds optional ghostty terminal/render-state pointers, and tracks
/// two-phase exit (SIGCHLD + PTY EOF must both arrive before cleanup).
pub const Pane = struct {
    pane_id: types.PaneId,
    slot_index: types.PaneSlot,
    pty_fd: std.posix.fd_t,
    child_pid: std.posix.pid_t,

    /// Typed ghostty pointers — null until server/ initializes these.
    terminal: ?*terminal_mod.Terminal = null,
    render_state: ?*render_state_mod.RenderState = null,
    /// Persistent ghostty VT parser stream. Held for the pane's lifetime so
    /// that split escape sequences spanning multiple PTY reads are parsed
    /// correctly. Creating a new vtStream per feedTerminal call would lose
    /// mid-sequence parser state. (See implementation-learnings.md G3.)
    /// Code-only addition not present in the spec type definition.
    vt_stream: ?*terminal_mod.ReadonlyStream = null,

    // Dimensions
    cols: u16,
    rows: u16,

    // Metadata (updated via OSC sequences)
    title: [types.MAX_PANE_TITLE]u8 = [_]u8{0} ** types.MAX_PANE_TITLE,
    title_length: u16 = 0,
    cwd: [types.MAX_PANE_CWD]u8 = [_]u8{0} ** types.MAX_PANE_CWD,
    cwd_length: u16 = 0,

    // Foreground process metadata — population site (process monitor) not
    // yet implemented; fields and accessors are functional.
    foreground_process: [types.MAX_FOREGROUND_PROCESS]u8 = [_]u8{0} ** types.MAX_FOREGROUND_PROCESS,
    foreground_process_length: u16 = 0,
    foreground_pid: std.posix.pid_t = 0,

    // Process state
    is_running: bool = true,
    exit_status: ?u8 = null,

    // TODO(Plan 17+): Add silence_subscriptions: BoundedArray(SilenceSubscription, MAX),
    //                 silence_deadline: ?i64 — requires SilenceSubscription type definition

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

    /// Copies up to MAX_PANE_TITLE bytes from title into the internal buffer.
    pub fn setTitle(self: *Pane, title: []const u8) void {
        const len = @min(title.len, self.title.len);
        @memcpy(self.title[0..len], title[0..len]);
        self.title_length = @intCast(len);
    }

    /// Copies up to MAX_PANE_CWD bytes from cwd into the internal buffer.
    pub fn setCwd(self: *Pane, cwd: []const u8) void {
        const len = @min(cwd.len, self.cwd.len);
        @memcpy(self.cwd[0..len], cwd[0..len]);
        self.cwd_length = @intCast(len);
    }

    /// Copies up to MAX_FOREGROUND_PROCESS bytes into the internal buffer.
    pub fn setForegroundProcess(self: *Pane, name: []const u8) void {
        const len = @min(name.len, self.foreground_process.len);
        @memcpy(self.foreground_process[0..len], name[0..len]);
        self.foreground_process_length = @intCast(len);
    }

    /// Slice into the title buffer.
    pub fn getTitle(self: *const Pane) []const u8 {
        return self.title[0..self.title_length];
    }

    /// Slice into the cwd buffer.
    pub fn getCwd(self: *const Pane) []const u8 {
        return self.cwd[0..self.cwd_length];
    }

    /// Slice into the foreground process name buffer.
    pub fn getForegroundProcess(self: *const Pane) []const u8 {
        return self.foreground_process[0..self.foreground_process_length];
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

test "Pane.init: creates pane with correct fields and default flags" {
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
    try std.testing.expect(p.vt_stream == null);
}

test "Pane.isFullyDead: returns false when neither flag set" {
    const p = Pane.init(1, 0, 5, 100, 80, 24);
    try std.testing.expect(!p.isFullyDead());
}

test "Pane.isFullyDead: returns false when only pane_exited set" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.markExited(0);
    try std.testing.expect(!p.isFullyDead());
}

test "Pane.isFullyDead: returns false when only pty_eof set" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.markPtyEof();
    try std.testing.expect(!p.isFullyDead());
}

test "Pane.isFullyDead: returns true when both flags set" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.markExited(0);
    p.markPtyEof();
    try std.testing.expect(p.isFullyDead());
}

test "Pane.markExited: sets pane_exited, exit_status, and clears is_running" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    try std.testing.expect(p.is_running);
    p.markExited(42);
    try std.testing.expect(p.pane_exited);
    try std.testing.expectEqual(@as(?u8, 42), p.exit_status);
    try std.testing.expect(!p.is_running);
}

test "Pane.markPtyEof: sets pty_eof but does not change is_running" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.markPtyEof();
    try std.testing.expect(p.pty_eof);
    try std.testing.expect(p.is_running);
}

test "Pane.setTitle: copies bytes and updates title_length" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    const title = "my terminal";
    p.setTitle(title);
    try std.testing.expectEqual(@as(u16, title.len), p.title_length);
    try std.testing.expectEqualSlices(u8, title, p.title[0..p.title_length]);
}

test "Pane.setTitle: truncates if longer than MAX_PANE_TITLE" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    const long_title = "a" ** 300;
    p.setTitle(long_title);
    try std.testing.expectEqual(@as(u16, types.MAX_PANE_TITLE), p.title_length);
    try std.testing.expectEqualSlices(u8, long_title[0..types.MAX_PANE_TITLE], p.title[0..types.MAX_PANE_TITLE]);
}

test "Pane.init: foreground fields default to empty/zero" {
    const p = Pane.init(1, 0, 5, 100, 80, 24);
    try std.testing.expectEqual(@as(u16, 0), p.foreground_process_length);
    try std.testing.expectEqual(@as(std.posix.pid_t, 0), p.foreground_pid);
    try std.testing.expectEqualSlices(u8, "", p.getForegroundProcess());
}

test "Pane.setForegroundProcess: copies bytes and updates length" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.setForegroundProcess("vim");
    try std.testing.expectEqualSlices(u8, "vim", p.getForegroundProcess());
}

test "Pane.getTitle: returns title slice" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.setTitle("my terminal");
    try std.testing.expectEqualSlices(u8, "my terminal", p.getTitle());
}

test "Pane.getCwd: returns cwd slice" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.setCwd("/home/user");
    try std.testing.expectEqualSlices(u8, "/home/user", p.getCwd());
}

test "Pane.setCwd: copies bytes and updates cwd_length" {
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    const cwd = "/home/user/project";
    p.setCwd(cwd);
    try std.testing.expectEqual(@as(u16, cwd.len), p.cwd_length);
    try std.testing.expectEqualSlices(u8, cwd, p.cwd[0..p.cwd_length]);
}
