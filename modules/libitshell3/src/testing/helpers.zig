const std = @import("std");
const mock_os = @import("mock_os.zig");
const interfaces = @import("../os/interfaces.zig");
const session_manager_mod = @import("../core/session_manager.zig");
const pane_mod = @import("../core/pane.zig");
const Listener = @import("../server/listener.zig").Listener;
const EventLoop = @import("../server/event_loop.zig").EventLoop;

/// Generate a unique temporary socket path for testing.
/// Caller owns the returned slice and must free it with the provided allocator.
pub fn tempSocketPath(allocator: std.mem.Allocator) ![]u8 {
    var buf: [8]u8 = undefined;
    std.crypto.random.bytes(&buf);
    const hex = std.fmt.bytesToHex(buf, .lower);
    return std.fmt.allocPrint(
        allocator,
        "/tmp/itshell3-test-{s}.sock",
        .{&hex},
    );
}

test "tempSocketPath generates valid unique paths" {
    const allocator = std.testing.allocator;
    const path1 = try tempSocketPath(allocator);
    defer allocator.free(path1);
    const path2 = try tempSocketPath(allocator);
    defer allocator.free(path2);

    // Both start with the expected prefix
    try std.testing.expect(std.mem.startsWith(u8, path1, "/tmp/itshell3-test-"));
    try std.testing.expect(std.mem.endsWith(u8, path1, ".sock"));

    // Paths are unique
    try std.testing.expect(!std.mem.eql(u8, path1, path2));
}

// ── Integration Tests ─────────────────────────────────────────────────────────

// Integration test: full daemon lifecycle using mock OS resources only.
// No real files, sockets, or PTYs are touched.
test "integration: daemon lifecycle with mocks" {
    // 1. Create mock OS ops
    var mock_socket = mock_os.MockSocketOps{
        .probe_result = .no_socket,
        .bind_fd = 10,
        .accept_fd = 50,
    };
    var mock_event = mock_os.MockEventLoopOps{};
    var mock_pty = mock_os.MockPtyOps{
        .fork_result = .{ .master_fd = 42, .child_pid = 1234 },
    };
    var mock_signal = mock_os.MockSignalOps{};

    const socket_ops = mock_socket.ops();
    const event_ops = mock_event.ops();
    const pty_ops = mock_pty.ops();
    const signal_ops = mock_signal.ops();

    // 2. Create SessionManager and create a session
    var sm = session_manager_mod.SessionManager.init();
    const session_id = try sm.createSession("integration-test");
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());

    // Verify the session exists
    const entry = sm.getSession(session_id);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(session_id, entry.?.session.session_id);

    // 3. Create Listener with MockSocketOps
    var listener = try Listener.init("/tmp/itshell3-integration-test.sock", &socket_ops);
    defer listener.deinit();

    try std.testing.expectEqual(@as(std.posix.fd_t, 10), listener.listen_fd);

    // 4. Create EventLoop with all mock ops
    var event_ctx: u8 = 0;
    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    try std.testing.expect(!ev.shutdown_requested);
    try std.testing.expectEqual(@as(usize, 0), ev.clientCount());

    // 5. Add a mock client (addClient with a fake fd)
    try ev.addClient(50);

    // 6. Verify: session exists, client exists
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());
    try std.testing.expectEqual(@as(usize, 1), ev.clientCount());

    const client_idx = ev.findClientByFd(50);
    try std.testing.expect(client_idx != null);

    // 7. Set shutdown_requested = true
    ev.shutdown_requested = true;

    // 8. Verify: clean state (shutdown flag set, session and client intact)
    try std.testing.expect(ev.shutdown_requested);
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());
    try std.testing.expectEqual(@as(usize, 1), ev.clientCount());
}

const c_pty = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
    @cInclude("util.h"); // macOS openpty
    @cInclude("sys/wait.h");
    @cInclude("poll.h");
});

// Integration test: real PTY fork and read using /bin/echo.
// Uses /bin/echo (not a shell) so the child exits immediately.
// Uses poll() with a timeout to prevent hanging.
test "integration: real PTY fork and read" {
    var master_fd: std.posix.fd_t = undefined;
    var slave_fd: std.posix.fd_t = undefined;

    // 1. Open a PTY pair
    if (c_pty.openpty(&master_fd, &slave_fd, null, null, null) < 0) {
        return error.SkipZigTest; // PTY not available in this environment
    }
    defer _ = c_pty.close(master_fd);

    // 2. Fork /bin/echo "hello" — exits immediately after writing
    const pid = c_pty.fork();
    if (pid < 0) {
        _ = c_pty.close(slave_fd);
        return error.SkipZigTest;
    }

    if (pid == 0) {
        // Child process: set slave as controlling terminal and exec echo
        _ = c_pty.close(master_fd);
        _ = c_pty.setsid();
        _ = c_pty.ioctl(slave_fd, c_pty.TIOCSCTTY, @as(c_ulong, 0));
        _ = c_pty.dup2(slave_fd, 0);
        _ = c_pty.dup2(slave_fd, 1);
        _ = c_pty.dup2(slave_fd, 2);
        if (slave_fd > 2) _ = c_pty.close(slave_fd);
        _ = c_pty.execl("/bin/echo", "echo", "hello", @as(?[*:0]const u8, null));
        c_pty._exit(1);
    }

    // Parent: close slave fd
    _ = c_pty.close(slave_fd);

    // 3. Read from master fd with a poll timeout (2 seconds max)
    var pfd = c_pty.struct_pollfd{
        .fd = master_fd,
        .events = c_pty.POLLIN,
        .revents = 0,
    };

    var total_bytes: usize = 0;
    var buf: [256]u8 = undefined;

    // Poll up to 2000ms
    const poll_ret = c_pty.poll(&pfd, 1, 2000);
    if (poll_ret > 0 and (pfd.revents & c_pty.POLLIN) != 0) {
        const n = c_pty.read(master_fd, &buf, buf.len);
        if (n > 0) {
            total_bytes += @intCast(n);
        }
    }

    // 4. waitpid the child
    var status: c_int = 0;
    _ = c_pty.waitpid(pid, &status, 0);

    // 5. Verify we got some output (echo "hello" produces at least "hello\r\n")
    try std.testing.expect(total_bytes > 0);
}
