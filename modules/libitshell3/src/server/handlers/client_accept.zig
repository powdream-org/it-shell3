const std = @import("std");
const event_loop_mod = @import("../event_loop.zig");

/// Handle a new client connection: accept from listener and add to event loop.
pub fn handleClientAccept(
    ev: *event_loop_mod.EventLoop,
) void {
    const new_fd = ev.listener.accept() catch {
        // Accept failed — log and continue (non-fatal)
        return;
    };
    ev.addClient(new_fd) catch {
        // Max clients reached — close the fd we just accepted
        ev.listener.socket_ops.close(new_fd);
        return;
    };
}

// --- Tests ---

const testing = std.testing;
const mock_os = @import("../../testing/mock_os.zig");
const interfaces = @import("../../os/interfaces.zig");
const session_manager_mod = @import("../../core/session_manager.zig");
const Listener = @import("../listener.zig").Listener;

test "handleClientAccept: successful accept adds client" {
    // Setup mock socket ops
    var mock_socket = mock_os.MockSocketOps{
        .probe_result = .no_socket,
        .bind_fd = 10,
        .accept_fd = 50,
    };
    const socket_ops = mock_socket.ops();

    var listener = try Listener.init("/tmp/test-accept.sock", &socket_ops);
    defer listener.deinit();

    // Setup mock event loop ops
    var mock_event = mock_os.MockEventLoopOps{};
    const event_ops = mock_event.ops();
    var event_ctx: u8 = 0;

    // Setup mock pty/signal ops
    var mock_pty = mock_os.MockPtyOps{};
    const pty_ops = mock_pty.ops();
    var mock_signal = mock_os.MockSignalOps{};
    const signal_ops = mock_signal.ops();

    var sm = session_manager_mod.SessionManager.init();

    var ev = event_loop_mod.EventLoop.init(
        &event_ops,
        @ptrCast(&event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    // Initially no clients
    try testing.expect(ev.findClientByFd(50) == null);

    handleClientAccept(&ev);

    // Now should have one client
    try testing.expect(ev.findClientByFd(50) != null);
}

test "handleClientAccept: accept error does not crash" {
    var mock_socket = mock_os.MockSocketOps{
        .probe_result = .no_socket,
        .bind_fd = 10,
        .accept_error = error.AcceptFailed,
    };
    const socket_ops = mock_socket.ops();

    var listener = try Listener.init("/tmp/test-accept-err.sock", &socket_ops);
    defer listener.deinit();

    var mock_event = mock_os.MockEventLoopOps{};
    const event_ops = mock_event.ops();
    var event_ctx: u8 = 0;

    var mock_pty = mock_os.MockPtyOps{};
    const pty_ops = mock_pty.ops();
    var mock_signal = mock_os.MockSignalOps{};
    const signal_ops = mock_signal.ops();

    var sm = session_manager_mod.SessionManager.init();

    var ev = event_loop_mod.EventLoop.init(
        &event_ops,
        @ptrCast(&event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    // Should not crash
    handleClientAccept(&ev);

    // No clients added
    try testing.expectEqual(@as(usize, 0), ev.clientCount());
}
