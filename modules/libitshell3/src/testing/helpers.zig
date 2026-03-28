const std = @import("std");
const builtin = @import("builtin");
const mock_os = @import("mocks/mock_os.zig");
const mock_ime = @import("mocks/mock_ime_engine.zig");
const server_os = @import("itshell3_server").os;
const interfaces = server_os.interfaces;
const core = @import("itshell3_core");
const session_mod = core.session;
const server = @import("itshell3_server");
const session_manager_mod = server.session_manager;
const protocol = @import("itshell3_protocol");
const Listener = protocol.transport.Listener;
const UnixTransport = protocol.transport.UnixTransport;

// File-scope static mock engine. Persists across tests so the vtable pointer
// stored in sessions remains valid. Exported for use by other test files.
pub var test_mock_engine = mock_ime.MockImeEngine{};

pub fn testImeEngine() session_mod.ImeEngine {
    return test_mock_engine.engine();
}

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

/// Create a pipe pair for testing. Returns .{read_fd, write_fd}.
pub fn createPipe() ![2]std.posix.fd_t {
    return std.posix.pipe() catch return error.EventLoopError;
}

test "createPipe: returns valid file descriptors" {
    const pipe_fds = try createPipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    // Write to write end, read from read end
    _ = try std.posix.write(pipe_fds[1], "test");
    var buf: [4]u8 = undefined;
    const n = try std.posix.read(pipe_fds[0], &buf);
    try std.testing.expectEqual(@as(usize, 4), n);
    try std.testing.expectEqualSlices(u8, "test", buf[0..n]);
}

test "tempSocketPath: generates valid unique paths" {
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

// Integration test: EventLoop with handler chain using mock OS ops.
test "spec: daemon lifecycle — EventLoop with handler chain and mock OS ops" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;

    // 1. Create mock OS ops
    var mock_event = mock_os.MockEventLoopOps{};
    var mock_pty = mock_os.MockPtyOps{
        .fork_result = .{ .master_fd = 42, .child_pid = 1234 },
    };

    _ = mock_pty.ops();

    // Configure mock to return a SIGTERM event that will stop the loop.
    const events_to_return = [_]interfaces.Event{
        .{
            .fd = std.posix.SIG.TERM,
            .filter = .signal,
            .target = .{ .listener = {} },
        },
    };
    mock_event.events_to_return = &events_to_return;
    const event_ops = mock_event.ops();

    // 2. Create SessionManager and create a session
    var sm = session_manager_mod.SessionManager.init();
    const session_id = try sm.createSession("integration-test", testImeEngine());
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());

    // Verify the session exists
    const entry = sm.getSession(session_id);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(session_id, entry.?.session.session_id);

    // 3. Build a simple handler chain that stops the loop on signal events.
    const StopOnSignal = struct {
        event_loop: ?*server.EventLoop = null,

        fn handle(context: *anyopaque, event: interfaces.Event, next: ?*const server.Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (event.filter == .signal) {
                if (self.event_loop) |el| el.stop();
            }
            if (next) |n| n.invoke(event);
        }
    };

    var stop_ctx = StopOnSignal{};
    var event_ctx: u8 = 0;
    const handler = server.Handler{
        .handleFn = StopOnSignal.handle,
        .context = @ptrCast(&stop_ctx),
        .next = null,
    };
    var el = server.EventLoop.init(
        &event_ops,
        @ptrCast(&event_ctx),
        &handler,
    );
    stop_ctx.event_loop = &el;

    try std.testing.expect(el.running);

    // 4. Run the event loop — should process the SIGTERM and stop.
    try el.run();

    try std.testing.expect(!el.running);
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());
}

const c_pty = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
    if (builtin.os.tag == .macos) {
        @cInclude("util.h"); // macOS openpty
    } else {
        @cInclude("pty.h"); // Linux openpty
    }
    @cInclude("sys/wait.h");
    @cInclude("poll.h");
});

// Integration test: real PTY fork and read using /bin/echo.
// Uses /bin/echo (not a shell) so the child exits immediately.
// Uses poll() with a timeout to prevent hanging.
test "spec: PTY integration — real PTY fork and read with echo" {
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
