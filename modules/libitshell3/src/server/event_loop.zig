const std = @import("std");
const os = @import("itshell3_os");
const interfaces = os.interfaces;
const core = @import("itshell3_core");
const types = core.types;
const protocol = @import("itshell3_protocol");
const Listener = protocol.transport.Listener;
const Connection = protocol.connection.Connection;
const UnixTransport = protocol.transport.UnixTransport;
const signal_handler = @import("signal_handler.zig");
const pty_read = @import("handlers/pty_read.zig");
const client_accept = @import("handlers/client_accept.zig");
const client_writer_mod = @import("client_writer.zig");
const client_state_mod = @import("client_state.zig");
const session_manager_mod = @import("session_manager.zig");
const pane_mod = @import("pane.zig");

pub const ClientEntry = client_state_mod.ClientEntry;

/// udata conventions for event dispatch:
/// - 0: listener socket
/// - Signal events: udata = signal number (set by SignalOps.registerSignals)
/// - UDATA_PTY_BASE + encoded: PTY fds (session_idx * MAX_PANES + pane_slot)
///   Range: [1, MAX_SESSIONS * MAX_PANES] = [1, 1024]
/// - UDATA_CLIENT_BASE + client_idx: client connections
///   Range: [1025, 1025 + MAX_CLIENTS - 1] = [1025, 1088]
const UDATA_LISTENER: usize = 0;
const UDATA_PTY_BASE: usize = 1;
const UDATA_CLIENT_BASE: usize = UDATA_PTY_BASE + @as(usize, types.MAX_SESSIONS) * @as(usize, types.MAX_PANES);

pub const EventLoop = struct {
    // OS interfaces (injected for testability)
    event_ops: *const interfaces.EventLoopOps,
    event_ctx: *anyopaque,
    pty_ops: *const interfaces.PtyOps,
    signal_ops: *const interfaces.SignalOps,

    // State
    listener: *Listener,
    session_manager: *session_manager_mod.SessionManager,
    clients: [types.MAX_CLIENTS]?ClientEntry,
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
            .clients = [_]?ClientEntry{null} ** types.MAX_CLIENTS,
            .next_client_id = 1,
            .shutdown_requested = false,
        };
    }

    pub const RunError = error{EventLoopError} || interfaces.SignalOps.SignalError;

    /// Main event loop. Blocks until shutdown_requested is set.
    pub fn run(self: *EventLoop) RunError!void {
        // Register listener fd for read events.
        try self.event_ops.registerRead(self.event_ctx, self.listener.listen_fd, UDATA_LISTENER);

        // Register all existing PTY fds.
        self.registerAllPtyFds() catch |err| return err;

        // Block signals and register signal filters.
        try self.signal_ops.blockSignals();
        try self.signal_ops.registerSignals(self.event_ctx, self.event_ops);

        var events: [64]interfaces.EventLoopOps.Event = undefined;

        while (!self.shutdown_requested) {
            const n = self.event_ops.wait(self.event_ctx, &events, 1000) catch |err| return err;
            if (n == 0) continue;

            // Two-pass dispatch: signal events first, then all others.
            // Per daemon-behavior event-handling spec, EVFILT_SIGNAL MUST be
            // processed before EVFILT_READ in the same kevent64() batch.
            for (events[0..n]) |event| {
                if (event.filter == .signal) {
                    self.dispatch(event);
                }
            }
            for (events[0..n]) |event| {
                if (event.filter != .signal) {
                    self.dispatch(event);
                }
            }
        }
    }

    /// Dispatch a single event based on filter type and udata.
    // TODO(Plan 6): Implement 5-tier client message priority ordering per
    // daemon-behavior policies-and-procedures spec. The current dispatch
    // handles signal-first ordering (Task 17) but does not yet prioritize
    // among different client message types.
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
            .write => {
                if (event.udata >= UDATA_CLIENT_BASE) {
                    self.dispatchClientWrite(event);
                }
            },
            .timer => {
                self.dispatchTimer(event);
            },
        }
    }

    fn dispatchClientRead(self: *EventLoop, event: interfaces.EventLoopOps.Event) void {
        const client_idx = event.udata - UDATA_CLIENT_BASE;
        if (client_idx >= types.MAX_CLIENTS) return;
        if (self.clients[client_idx] != null) {
            // Stub: read from client fd and discard.
            // Real protocol handling in Plan 3.
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
                    entry,
                    &self.clients,
                    entry.session.session_id,
                );
            }
        }
    }

    fn dispatchClientWrite(self: *EventLoop, event: interfaces.EventLoopOps.Event) void {
        const client_idx = event.udata - UDATA_CLIENT_BASE;
        if (client_idx >= types.MAX_CLIENTS) return;
        _ = self;
        // Stub: full write delivery in Plan 6 (requires session attachment tracking).
    }

    fn dispatchTimer(self: *EventLoop, event: interfaces.EventLoopOps.Event) void {
        _ = self;
        _ = event;
        // Stub: frame export timer (Plan 6: adaptive coalescing).
    }

    fn registerAllPtyFds(self: *EventLoop) interfaces.EventLoopOps.RegisterError!void {
        for (&self.session_manager.sessions, 0..) |*slot, session_idx| {
            if (slot.*) |*entry| {
                var i: u32 = 0;
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

    pub fn addClientTransport(self: *EventLoop, ut: UnixTransport) error{MaxClientsReached}!void {
        for (&self.clients, 0..) |*slot, idx| {
            if (slot.* == null) {
                const client_id = self.next_client_id;
                self.next_client_id += 1;
                // Store UnixTransport in the slot first; then take its address
                // for the Transport vtable pointer.
                slot.* = ClientEntry{
                    .unix_transport = ut,
                    .conn = undefined, // patched below
                    .socket_fd = ut.socket_fd,
                    .writer = client_writer_mod.ClientWriter.init(),
                };
                slot.*.?.conn = Connection.init(slot.*.?.unix_transport.transport());
                slot.*.?.conn.client_id = client_id;
                // Register for read events.
                self.event_ops.registerRead(
                    self.event_ctx,
                    ut.socket_fd,
                    UDATA_CLIENT_BASE + idx,
                ) catch {};
                return;
            }
        }
        return error.MaxClientsReached;
    }

    pub fn removeClient(self: *EventLoop, client_idx: usize) void {
        if (client_idx >= types.MAX_CLIENTS) return;
        if (self.clients[client_idx]) |*entry| {
            self.event_ops.unregister(self.event_ctx, entry.socket_fd);
            entry.conn.transport.close();
            entry.writer.deinit();
            self.clients[client_idx] = null;
        }
    }

    pub fn findClientByFd(self: *EventLoop, fd: std.posix.socket_t) ?usize {
        for (self.clients, 0..) |slot, idx| {
            if (slot) |entry| {
                if (entry.socket_fd == fd) return idx;
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

// ── Tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;
const builtin = @import("builtin");
const test_mod = @import("itshell3_testing");
const mock_os = test_mod.mock_os;
const test_helpers = test_mod.helpers;
const protocol_transport = protocol.transport;

const testImeEngine = test_helpers.testImeEngine;

/// Build a fake protocol Listener backed by a real socket for tests.
fn makeTestListener(socket_path: []const u8) !Listener {
    std.posix.unlink(socket_path) catch {};
    return protocol_transport.listen(socket_path);
}

/// Create a socketpair and return both ends as UnixTransport.
fn makeSocketPair() ![2]UnixTransport {
    var fds: [2]std.posix.socket_t = undefined;
    const rc = std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds);
    if (rc != 0) return error.SocketPairFailed;
    return .{
        UnixTransport{ .socket_fd = fds[0] },
        UnixTransport{ .socket_fd = fds[1] },
    };
}

fn makeTestMocks() struct {
    mock_event: mock_os.MockEventLoopOps,
    mock_pty: mock_os.MockPtyOps,
    mock_signal: mock_os.MockSignalOps,
    event_ctx: u8,
} {
    return .{
        .mock_event = mock_os.MockEventLoopOps{},
        .mock_pty = mock_os.MockPtyOps{},
        .mock_signal = mock_os.MockSignalOps{},
        .event_ctx = 0,
    };
}

test "EventLoop.init: clients all null, shutdown_requested = false" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;
    var ctx = makeTestMocks();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try makeTestListener("/tmp/itshell3-ev-init.sock");
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
    for (ev.clients) |slot| {
        try testing.expect(slot == null);
    }
}

test "EventLoop.addClientTransport: stores Connection, increments next_client_id" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;
    var ctx = makeTestMocks();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try makeTestListener("/tmp/itshell3-ev-add.sock");
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

    const pair = try makeSocketPair();
    defer std.posix.close(pair[1].socket_fd);

    try ev.addClientTransport(pair[0]);
    try testing.expectEqual(@as(usize, 1), ev.clientCount());
    try testing.expectEqual(@as(types.ClientId, 2), ev.next_client_id);

    const idx = ev.findClientByFd(pair[0].socket_fd).?;
    const entry = ev.clients[idx].?;
    try testing.expectEqual(pair[0].socket_fd, entry.socket_fd);
}

test "EventLoop.addClientTransport: second client gets next ID" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;
    var ctx = makeTestMocks();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try makeTestListener("/tmp/itshell3-ev-add2.sock");
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

    const p1 = try makeSocketPair();
    defer std.posix.close(p1[1].socket_fd);
    const p2 = try makeSocketPair();
    defer std.posix.close(p2[1].socket_fd);

    try ev.addClientTransport(p1[0]);
    try ev.addClientTransport(p2[0]);
    try testing.expectEqual(@as(usize, 2), ev.clientCount());
    try testing.expectEqual(@as(types.ClientId, 3), ev.next_client_id);
}

test "EventLoop.addClientTransport: when full returns error.MaxClientsReached" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;
    var ctx = makeTestMocks();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try makeTestListener("/tmp/itshell3-ev-full.sock");
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

    var pairs: [types.MAX_CLIENTS][2]UnixTransport = undefined;
    for (0..types.MAX_CLIENTS) |i| {
        pairs[i] = try makeSocketPair();
        defer std.posix.close(pairs[i][1].socket_fd);
        try ev.addClientTransport(pairs[i][0]);
    }

    const extra = try makeSocketPair();
    std.posix.close(extra[0].socket_fd);
    std.posix.close(extra[1].socket_fd);
    try testing.expectError(error.MaxClientsReached, ev.addClientTransport(
        UnixTransport{ .socket_fd = extra[0].socket_fd },
    ));
}

test "EventLoop.removeClient: nulls slot" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;
    var ctx = makeTestMocks();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try makeTestListener("/tmp/itshell3-ev-rm.sock");
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

    const pair = try makeSocketPair();
    defer std.posix.close(pair[1].socket_fd);
    const fd = pair[0].socket_fd;

    try ev.addClientTransport(pair[0]);
    const idx = ev.findClientByFd(fd).?;
    try testing.expectEqual(@as(usize, 1), ev.clientCount());

    ev.removeClient(idx);
    try testing.expectEqual(@as(usize, 0), ev.clientCount());
    try testing.expect(ev.clients[idx] == null);
    try testing.expect(ev.findClientByFd(fd) == null);
}

test "EventLoop.findClientByFd: finds correct index" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;
    var ctx = makeTestMocks();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try makeTestListener("/tmp/itshell3-ev-find.sock");
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

    const p1 = try makeSocketPair();
    defer std.posix.close(p1[1].socket_fd);
    const p2 = try makeSocketPair();
    defer std.posix.close(p2[1].socket_fd);

    try ev.addClientTransport(p1[0]);
    try ev.addClientTransport(p2[0]);

    const idx0 = ev.findClientByFd(p1[0].socket_fd);
    const idx1 = ev.findClientByFd(p2[0].socket_fd);
    try testing.expect(idx0 != null);
    try testing.expect(idx1 != null);
    try testing.expect(idx0.? != idx1.?);
}

test "EventLoop.findClientByFd: unknown fd returns null" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;
    var ctx = makeTestMocks();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try makeTestListener("/tmp/itshell3-ev-notfound.sock");
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

    try testing.expect(ev.findClientByFd(99999) == null);
}

test "EventLoop.dispatch: signal-first ordering in mixed batch" {
    // Construct a batch with a read event followed by a signal event.
    // The two-pass loop must process the signal first (setting shutdown_requested)
    // before handling the read event. We verify by checking that after dispatching
    // the batch in two-pass order, shutdown_requested is true — which means the
    // signal was processed regardless of its position in the array.
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;
    var ctx = makeTestMocks();
    ctx.mock_pty.read_data = "data";
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try makeTestListener("/tmp/itshell3-ev-sigfirst.sock");
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();
    const session_id = try sm.createSession("test", testImeEngine());
    const entry = sm.getSession(session_id).?;
    const pane_inst = pane_mod.Pane.init(1, 0, 42, 1234, 80, 24);
    entry.setPaneAtSlot(0, pane_inst);

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    // Batch: read event at index 0, signal event at index 1.
    // Two-pass loop should process signal (index 1) before read (index 0).
    var events = [_]interfaces.EventLoopOps.Event{
        .{ .fd = 42, .filter = .read, .udata = UDATA_PTY_BASE + 0 },
        .{ .fd = std.posix.SIG.TERM, .filter = .signal, .udata = std.posix.SIG.TERM },
    };

    // Simulate the two-pass dispatch from run():
    // Pass 1: signal events only
    for (&events) |event| {
        if (event.filter == .signal) {
            ev.dispatch(event);
        }
    }
    // After pass 1, shutdown_requested must already be true.
    try testing.expect(ev.shutdown_requested);

    // Pass 2: non-signal events
    for (&events) |event| {
        if (event.filter != .signal) {
            ev.dispatch(event);
        }
    }
    // State remains consistent — read dispatch ran after signal state was set.
    try testing.expect(ev.shutdown_requested);
}

test "udata ranges: PTY and client ranges do not overlap" {
    // Compile-time assertion that UDATA_CLIENT_BASE is beyond the PTY range.
    // PTY range: [UDATA_PTY_BASE, UDATA_PTY_BASE + MAX_SESSIONS * MAX_PANES - 1]
    // Client range: [UDATA_CLIENT_BASE, UDATA_CLIENT_BASE + MAX_CLIENTS - 1]
    const pty_range_end = UDATA_PTY_BASE + @as(usize, types.MAX_SESSIONS) * @as(usize, types.MAX_PANES) - 1;
    comptime {
        if (UDATA_CLIENT_BASE <= pty_range_end) {
            @compileError("UDATA_CLIENT_BASE overlaps with PTY udata range");
        }
    }
    // Runtime check for documentation clarity.
    try testing.expect(UDATA_CLIENT_BASE > pty_range_end);
}

test "EventLoop.dispatch: signal event sets shutdown_requested" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;
    var ctx = makeTestMocks();
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try makeTestListener("/tmp/itshell3-ev-sig.sock");
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

test "EventLoop.dispatch: read event on PTY fd triggers pty read" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;
    var ctx = makeTestMocks();
    ctx.mock_pty.read_data = "test output";
    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try makeTestListener("/tmp/itshell3-ev-pty.sock");
    defer listener.deinit();

    var sm = session_manager_mod.SessionManager.init();
    const session_id = try sm.createSession("test", testImeEngine());
    const entry = sm.getSession(session_id).?;

    const pane_inst = pane_mod.Pane.init(1, 0, 42, 1234, 80, 24);
    entry.setPaneAtSlot(0, pane_inst);

    var ev = EventLoop.init(
        &event_ops,
        @ptrCast(&ctx.event_ctx),
        &pty_ops,
        &signal_ops,
        &listener,
        &sm,
    );

    const event = interfaces.EventLoopOps.Event{
        .fd = 42,
        .filter = .read,
        .udata = UDATA_PTY_BASE + 0,
    };

    ev.dispatch(event);
    const updated_pane = entry.getPaneAtSlot(0).?;
    try testing.expect(!updated_pane.pty_eof);
}

test "EventLoop.run: single event then shutdown" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;
    var ctx = makeTestMocks();

    const events_to_return = [_]interfaces.EventLoopOps.Event{
        .{
            .fd = std.posix.SIG.TERM,
            .filter = .signal,
            .udata = std.posix.SIG.TERM,
        },
    };
    ctx.mock_event.events_to_return = &events_to_return;

    const event_ops = ctx.mock_event.ops();
    const pty_ops = ctx.mock_pty.ops();
    const signal_ops = ctx.mock_signal.ops();

    var listener = try makeTestListener("/tmp/itshell3-ev-run.sock");
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

    try ev.run();
    try testing.expect(ev.shutdown_requested);
}
