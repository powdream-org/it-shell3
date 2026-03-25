const std = @import("std");
const interfaces = @import("../os/interfaces.zig");
const types = @import("../core/types.zig");
const session_manager_mod = @import("../core/session_manager.zig");
const pane_mod = @import("../core/pane.zig");
const Listener = @import("listener.zig").Listener;
const ClientState = @import("client.zig").ClientState;
const signal_handler = @import("signal_handler.zig");
const pty_read = @import("handlers/pty_read.zig");
const client_accept = @import("handlers/client_accept.zig");

/// udata conventions for event dispatch:
/// - 0: listener socket
/// - Signal events: udata = signal number (set by SignalOps.registerSignals)
/// - UDATA_CLIENT_BASE + client_idx: client connections
/// - UDATA_PTY_BASE + encoded: PTY fds (session_idx * MAX_PANES + pane_slot)
const UDATA_LISTENER: usize = 0;
const UDATA_CLIENT_BASE: usize = 100;
const UDATA_PTY_BASE: usize = 1;

pub const EventLoop = struct {
    // OS interfaces (injected for testability)
    event_ops: *const interfaces.EventLoopOps,
    event_ctx: *anyopaque,
    pty_ops: *const interfaces.PtyOps,
    signal_ops: *const interfaces.SignalOps,

    // State
    listener: *Listener,
    session_manager: *session_manager_mod.SessionManager,
    clients: [types.MAX_CLIENTS]?ClientState,
    next_client_id: types.ClientId,
    shutdown_requested: bool,

    pub fn init(
        event_ops: *const interfaces.EventLoopOps,
        event_ctx: *anyopaque,
        pty_ops: *const interfaces.PtyOps,
        signal_ops: *const interfaces.SignalOps,
        listener: *Listener,
        session_manager: *session_manager_mod.SessionManager,
    ) EventLoop {
        return .{
            .event_ops = event_ops,
            .event_ctx = event_ctx,
            .pty_ops = pty_ops,
            .signal_ops = signal_ops,
            .listener = listener,
            .session_manager = session_manager,
            .clients = [_]?ClientState{null} ** types.MAX_CLIENTS,
            .next_client_id = 1,
            .shutdown_requested = false,
        };
    }

    pub const RunError = error{KqueueError} || interfaces.SignalOps.SignalError;

    /// Main event loop. Blocks until shutdown_requested is set.
    pub fn run(self: *EventLoop) RunError!void {
        // Register listener fd for read events
        try self.event_ops.registerRead(self.event_ctx, self.listener.listen_fd, UDATA_LISTENER);

        // Register all existing PTY fds
        self.registerAllPtyFds() catch |err| return err;

        // Block signals and register signal filters
        try self.signal_ops.blockSignals();
        try self.signal_ops.registerSignals(self.event_ctx, self.event_ops);

        var events: [64]interfaces.EventLoopOps.Event = undefined;

        while (!self.shutdown_requested) {
            const n = self.event_ops.wait(self.event_ctx, &events, 1000) catch |err| return err;
            if (n == 0) continue;

            for (events[0..n]) |event| {
                self.dispatch(event);
            }
        }
    }

    /// Dispatch a single event based on filter type and udata.
    fn dispatch(self: *EventLoop, event: interfaces.EventLoopOps.Event) void {
        switch (event.filter) {
            .signal => {
                signal_handler.handleSignalEvent(
                    event,
                    self.signal_ops,
                    self.session_manager,
                    &self.shutdown_requested,
                );
            },
            .read => {
                if (event.udata == UDATA_LISTENER) {
                    client_accept.handleClientAccept(self);
                } else if (event.udata >= UDATA_CLIENT_BASE) {
                    self.dispatchClientRead(event);
                } else {
                    self.dispatchPtyRead(event);
                }
            },
            .write, .timer => {},
        }
    }

    fn dispatchClientRead(self: *EventLoop, event: interfaces.EventLoopOps.Event) void {
        const client_idx = event.udata - UDATA_CLIENT_BASE;
        if (client_idx >= types.MAX_CLIENTS) return;
        if (self.clients[client_idx] != null) {
            // Stub: read from client fd and discard
            // Real protocol handling in Plan 3
        }
    }

    fn dispatchPtyRead(self: *EventLoop, event: interfaces.EventLoopOps.Event) void {
        // Decode: udata = UDATA_PTY_BASE + session_idx * MAX_PANES + pane_slot
        const encoded = event.udata - UDATA_PTY_BASE;
        const session_idx = encoded / types.MAX_PANES;
        const pane_slot: types.PaneSlot = @intCast(encoded % types.MAX_PANES);

        if (self.session_manager.findSessionBySlot(session_idx)) |entry| {
            if (entry.getPaneAtSlot(pane_slot)) |pane| {
                pty_read.handlePtyRead(
                    self.pty_ops,
                    pane,
                    &self.clients,
                    entry.session.session_id,
                );
            }
        }
    }

    fn registerAllPtyFds(self: *EventLoop) interfaces.EventLoopOps.RegisterError!void {
        for (&self.session_manager.sessions, 0..) |*slot, session_idx| {
            if (slot.*) |*entry| {
                var i: u5 = 0;
                while (i < types.MAX_PANES) : (i += 1) {
                    const pane_slot: types.PaneSlot = @intCast(i);
                    if (entry.getPaneAtSlot(pane_slot)) |pane| {
                        if (pane.is_running) {
                            const udata = UDATA_PTY_BASE + session_idx * types.MAX_PANES + pane_slot;
                            try self.event_ops.registerRead(self.event_ctx, pane.pty_fd, udata);
                        }
                    }
                }
            }
        }
    }

    pub fn addClient(self: *EventLoop, conn_fd: std.posix.fd_t) error{MaxClientsReached}!void {
        for (&self.clients, 0..) |*slot, idx| {
            if (slot.* == null) {
                const client_id = self.next_client_id;
                self.next_client_id += 1;
                slot.* = ClientState.init(client_id, conn_fd);
                // Register for read events
                self.event_ops.registerRead(
                    self.event_ctx,
                    conn_fd,
                    UDATA_CLIENT_BASE + idx,
                ) catch {};
                return;
            }
        }
        return error.MaxClientsReached;
    }

    pub fn removeClient(self: *EventLoop, client_idx: usize) void {
        if (client_idx >= types.MAX_CLIENTS) return;
        if (self.clients[client_idx]) |cs| {
            self.event_ops.unregister(self.event_ctx, cs.conn_fd);
            self.listener.socket_ops.close(cs.conn_fd);
            self.clients[client_idx] = null;
        }
    }

    pub fn findClientByFd(self: *EventLoop, fd: std.posix.fd_t) ?usize {
        for (self.clients, 0..) |slot, idx| {
            if (slot) |cs| {
                if (cs.conn_fd == fd) return idx;
            }
        }
        return null;
    }

    pub fn clientCount(self: *const EventLoop) usize {
        var count: usize = 0;
        for (self.clients) |slot| {
            if (slot != null) count += 1;
        }
        return count;
    }
};

// --- Tests ---

const testing = std.testing;
const mock_os = @import("../testing/mock_os.zig");

fn makeTestEventLoop() struct {
    mock_socket: mock_os.MockSocketOps,
    mock_event: mock_os.MockEventLoopOps,
    mock_pty: mock_os.MockPtyOps,
    mock_signal: mock_os.MockSignalOps,
    event_ctx: u8,
} {
    return .{
        .mock_socket = mock_os.MockSocketOps{
            .probe_result = .no_socket,
            .bind_fd = 10,
            .accept_fd = 50,
        },
        .mock_event = mock_os.MockEventLoopOps{},
        .mock_pty = mock_os.MockPtyOps{},
        .mock_signal = mock_os.MockSignalOps{},
        .event_ctx = 0,
    };
}

test "init: clients all null, shutdown_requested = false" {
    var ctx = makeTestEventLoop();
    const socket_ops = ctx.mock_socket.ops();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try Listener.init("/tmp/test-ev-init.sock", &socket_ops);
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();

    const ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    try testing.expect(!ev.shutdown_requested);
    try testing.expectEqual(@as(types.ClientId, 1), ev.next_client_id);
    try testing.expectEqual(@as(usize, 0), ev.clientCount());
    // All client slots should be null
    for (ev.clients) |slot| {
        try testing.expect(slot == null);
    }
}

test "addClient: stores ClientState, increments next_client_id" {
    var ctx = makeTestEventLoop();
    const socket_ops = ctx.mock_socket.ops();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try Listener.init("/tmp/test-ev-add.sock", &socket_ops);
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    try ev.addClient(20);
    try testing.expectEqual(@as(usize, 1), ev.clientCount());
    try testing.expectEqual(@as(types.ClientId, 2), ev.next_client_id);

    // Check the stored client
    const idx = ev.findClientByFd(20).?;
    const cs = ev.clients[idx].?;
    try testing.expectEqual(@as(types.ClientId, 1), cs.client_id);
    try testing.expectEqual(@as(std.posix.fd_t, 20), cs.conn_fd);
}

test "addClient: second client gets next ID" {
    var ctx = makeTestEventLoop();
    const socket_ops = ctx.mock_socket.ops();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try Listener.init("/tmp/test-ev-add2.sock", &socket_ops);
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    try ev.addClient(20);
    try ev.addClient(21);
    try testing.expectEqual(@as(usize, 2), ev.clientCount());
    try testing.expectEqual(@as(types.ClientId, 3), ev.next_client_id);
}

test "addClient when full: error.MaxClientsReached" {
    var ctx = makeTestEventLoop();
    const socket_ops = ctx.mock_socket.ops();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try Listener.init("/tmp/test-ev-full.sock", &socket_ops);
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    // Fill all client slots
    var i: usize = 0;
    while (i < types.MAX_CLIENTS) : (i += 1) {
        try ev.addClient(@intCast(100 + i));
    }

    // Next should fail
    try testing.expectError(error.MaxClientsReached, ev.addClient(999));
}

test "removeClient: nulls slot, calls close" {
    var ctx = makeTestEventLoop();
    const socket_ops = ctx.mock_socket.ops();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try Listener.init("/tmp/test-ev-rm.sock", &socket_ops);
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    try ev.addClient(30);
    const idx = ev.findClientByFd(30).?;
    try testing.expectEqual(@as(usize, 1), ev.clientCount());

    ev.removeClient(idx);
    try testing.expectEqual(@as(usize, 0), ev.clientCount());
    try testing.expect(ev.clients[idx] == null);
    try testing.expect(ctx.mock_socket.close_called);
}

test "findClientByFd: finds correct index" {
    var ctx = makeTestEventLoop();
    const socket_ops = ctx.mock_socket.ops();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try Listener.init("/tmp/test-ev-find.sock", &socket_ops);
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    try ev.addClient(40);
    try ev.addClient(41);

    const idx0 = ev.findClientByFd(40);
    const idx1 = ev.findClientByFd(41);
    try testing.expect(idx0 != null);
    try testing.expect(idx1 != null);
    try testing.expect(idx0.? != idx1.?);
}

test "findClientByFd: unknown fd returns null" {
    var ctx = makeTestEventLoop();
    const socket_ops = ctx.mock_socket.ops();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try Listener.init("/tmp/test-ev-notfound.sock", &socket_ops);
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    try testing.expect(ev.findClientByFd(999) == null);
}

test "dispatch: signal event sets shutdown_requested" {
    var ctx = makeTestEventLoop();
    const socket_ops = ctx.mock_socket.ops();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try Listener.init("/tmp/test-ev-sig.sock", &socket_ops);
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    const event = interfaces.EventLoopOps.Event{
        .fd = std.posix.SIG.TERM,
        .filter = .signal,
        .udata = std.posix.SIG.TERM,
    };

    ev.dispatch(event);
    try testing.expect(ev.shutdown_requested);
}

test "dispatch: read event on listener fd adds client" {
    var ctx = makeTestEventLoop();
    ctx.mock_socket.accept_fd = 60;
    const socket_ops = ctx.mock_socket.ops();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try Listener.init("/tmp/test-ev-listen.sock", &socket_ops);
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    const event = interfaces.EventLoopOps.Event{
        .fd = listener.listen_fd,
        .filter = .read,
        .udata = UDATA_LISTENER,
    };

    ev.dispatch(event);
    try testing.expectEqual(@as(usize, 1), ev.clientCount());
}

test "dispatch: read event on PTY fd triggers pty read" {
    var ctx = makeTestEventLoop();
    ctx.mock_pty.read_data = "test output";
    const socket_ops = ctx.mock_socket.ops();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try Listener.init("/tmp/test-ev-pty.sock", &socket_ops);
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();
    const session_id = try sm.createSession("test");
    const entry = sm.getSession(session_id).?;

    const pane = pane_mod.Pane.init(1, 0, 42, 1234, 80, 24);
    entry.setPaneAtSlot(0, pane);

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    // Session at slot 0, pane at slot 0 → udata = UDATA_PTY_BASE + 0*16 + 0 = 1
    const event = interfaces.EventLoopOps.Event{
        .fd = 42,
        .filter = .read,
        .udata = UDATA_PTY_BASE + 0,
    };

    ev.dispatch(event);
    // The pane should NOT be marked EOF since mock has data
    const updated_pane = entry.getPaneAtSlot(0).?;
    try testing.expect(!updated_pane.pty_eof);
}

test "run: single event then shutdown" {
    var ctx = makeTestEventLoop();

    // Configure mock to return a SIGTERM event
    const events_to_return = [_]interfaces.EventLoopOps.Event{
        .{
            .fd = std.posix.SIG.TERM,
            .filter = .signal,
            .udata = std.posix.SIG.TERM,
        },
    };
    ctx.mock_event.events_to_return = &events_to_return;

    const socket_ops = ctx.mock_socket.ops();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try Listener.init("/tmp/test-ev-run.sock", &socket_ops);
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    // run() should process the SIGTERM and exit
    try ev.run();
    try testing.expect(ev.shutdown_requested);
}
