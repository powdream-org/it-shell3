const std = @import("std");
const libitshell3 = @import("libitshell3");

const Listener = libitshell3.listener.Listener;
const SessionManager = libitshell3.session_manager.SessionManager;
const KqueueContext = libitshell3.os_kqueue.KqueueContext;
const EventLoop = libitshell3.event_loop.EventLoop;
const real_socket_ops = libitshell3.os_socket.real_socket_ops;
const real_pty_ops = libitshell3.os_pty.real_pty_ops;
const real_signal_ops = libitshell3.os_signals.real_signal_ops;

// File-scope static — ~4.5 MB lives in .bss, not on main()'s stack.
var sm: SessionManager = SessionManager.init();

const usage =
    \\Usage: it-shell3-daemon --socket-path <path> [--foreground]
    \\
    \\Options:
    \\  --socket-path <path>   Unix domain socket path (required)
    \\  --foreground           Run in foreground (do not daemonize)
    \\  --help                 Print this help and exit
    \\
;

pub fn main() !void {
    // --- 1. Parse CLI arguments ---
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    var socket_path: ?[]const u8 = null;
    var foreground: bool = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--socket-path")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("error: --socket-path requires an argument\n", .{});
                std.process.exit(1);
            }
            socket_path = args[i];
        } else if (std.mem.eql(u8, arg, "--foreground")) {
            foreground = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            std.debug.print("{s}", .{usage});
            std.process.exit(0);
        } else {
            std.debug.print("error: unknown argument: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    const sock_path = socket_path orelse {
        std.debug.print("error: --socket-path is required\n", .{});
        std.debug.print("{s}", .{usage});
        std.process.exit(1);
    };

    // --- 2. Block signals (must happen before any FDs are created) ---
    // Signal blocking is now handled inside EventLoop.run() via signal_ops.
    // The binary delegates signal setup entirely to the library's SignalOps
    // interface as described in ADR 00048.

    // --- 3 & 4. Init listener (probes for stale socket, binds, listens) ---
    var listener = Listener.init(sock_path, &real_socket_ops) catch |err| switch (err) {
        error.DaemonAlreadyRunning => {
            std.debug.print(
                "error: daemon already running on socket: {s}\n",
                .{sock_path},
            );
            std.process.exit(1);
        },
        else => return err,
    };
    defer listener.deinit();

    // --- 5. Init session manager + create default session ---
    // sm is declared at file scope to keep ~4.5 MB off main()'s stack.
    const session_id = sm.createSession("default") catch |err| switch (err) {
        error.MaxSessionsReached => {
            std.debug.print("error: could not create default session\n", .{});
            std.process.exit(1);
        },
    };
    const session_entry = sm.getSession(session_id).?;

    // --- 6. Init kqueue ---
    var kq = KqueueContext.init() catch |err| switch (err) {
        error.KqueueError => {
            std.debug.print("error: failed to create kqueue\n", .{});
            std.process.exit(1);
        },
    };
    defer kq.deinit();
    const event_ops = kq.eventLoopOps();

    // --- 7. Init event loop ---
    var event_loop = EventLoop.init(
        &event_ops,
        @ptrCast(&kq),
        &real_pty_ops,
        &real_signal_ops,
        &listener,
        &sm,
    );

    // --- 8. Create initial pane (fork PTY) ---
    const fork_result = real_pty_ops.forkPty(80, 24) catch |err| switch (err) {
        error.ForkFailed, error.PtyOpenFailed, error.ExecFailed => {
            std.debug.print("error: failed to fork initial PTY: {}\n", .{err});
            std.process.exit(1);
        },
    };
    const pane_mod = libitshell3.pane;
    const initial_pane = pane_mod.Pane.init(
        1,
        0,
        fork_result.master_fd,
        fork_result.child_pid,
        80,
        24,
    );
    session_entry.setPaneAtSlot(0, initial_pane);
    if (!foreground) {
        // TODO: daemonize (fork+setsid) when running as LaunchAgent (Phase 1+)
    }

    // --- 9. Run event loop (blocks until SIGTERM/SIGINT/SIGHUP) ---
    try event_loop.run();

    // --- 10. Cleanup ---
    // listener.deinit() and kq.deinit() are called via defer above.
}
