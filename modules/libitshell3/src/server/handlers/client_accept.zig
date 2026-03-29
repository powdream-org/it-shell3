//! Server-side handler for accepting new client connections on the listener
//! socket. Arms a handshake timeout timer after each successful accept.

const std = @import("std");
const interfaces = @import("../os/interfaces.zig");
const EventLoopOps = interfaces.EventLoopOps;
const EventTarget = interfaces.EventTarget;
const event_loop_mod = @import("event_loop.zig");
const transport = @import("itshell3_transport");
const Listener = transport.transport_server.Listener;
const SocketConnection = transport.transport.SocketConnection;
const timer_handler = @import("timer_handler.zig");
const server = @import("itshell3_server");
const ClientManager = server.connection.client_manager.ClientManager;

const Handler = event_loop_mod.Handler;

/// Callback type for adding a newly accepted client connection.
/// Returns the assigned client slot index on success.
pub const AddClientFn = *const fn (conn: SocketConnection) error{MaxClientsReached}!u16;

/// Duration for handshake stage 1 timer (accept to first byte).
/// Per daemon-behavior policies-and-procedures spec (Handshake Timeouts).
pub const HANDSHAKE_TIMEOUT_MS: u32 = 5000;

/// Context for the client accept chain handler.
pub const ClientAcceptContext = struct {
    listener: *Listener,
    add_client_fn: AddClientFn,
    client_manager: *ClientManager,
    event_loop_ops: *const EventLoopOps,
    event_loop_context: *anyopaque,
};

/// Chain handler entry point for client accept events.
/// Matches on event.target == .listener. If the event is not for the listener,
/// forwards to the next handler in the chain.
pub fn chainHandle(context: *anyopaque, event: interfaces.Event, next: ?*const Handler) void {
    if (event.target) |target| {
        switch (target) {
            .listener => {
                const ctx: *ClientAcceptContext = @ptrCast(@alignCast(context));
                handleClientAccept(ctx);
                return;
            },
            else => {},
        }
    }
    if (next) |n| n.invoke(event);
}

/// Accept a new client connection from the listener and pass it to the
/// add_client callback. Arms a 5s handshake timer per daemon-behavior spec
/// (Handshake Timeouts).
fn handleClientAccept(ctx: *ClientAcceptContext) void {
    const conn = ctx.listener.accept() catch {
        // Accept failed -- log and continue (non-fatal).
        return;
    };

    const client_slot = ctx.add_client_fn(conn) catch {
        // Max clients reached -- close the connection we just accepted.
        var mutable_conn = conn;
        mutable_conn.close();
        return;
    };

    // Arm the 5s handshake timer (stage 1: accept to first byte).
    const timer_id = timer_handler.HANDSHAKE_TIMER_BASE + client_slot;
    ctx.event_loop_ops.registerTimer(
        ctx.event_loop_context,
        timer_id,
        HANDSHAKE_TIMEOUT_MS,
        .{ .timer = .{ .timer_id = timer_id } },
    ) catch {
        // Timer registration failed -- non-fatal, handshake proceeds without timeout.
        return;
    };

    // Store the timer ID in the client state for later cancellation.
    if (ctx.client_manager.getClient(client_slot)) |client| {
        client.handshake_timer_id = timer_id;
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "chainHandle: non-listener event forwards to next handler" {
    var forwarded = false;
    const NextCtx = struct {
        flag: *bool,
        fn handle(context_ptr: *anyopaque, _: interfaces.Event, _: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context_ptr));
            self.flag.* = true;
        }
    };

    var next_ctx = NextCtx{ .flag = &forwarded };
    const next = Handler{
        .handleFn = NextCtx.handle,
        .context = @ptrCast(&next_ctx),
        .next = null,
    };

    // We do not need a valid ClientAcceptContext since the event is not .listener
    var dummy_ctx: u8 = 0;

    const pty_event = interfaces.Event{
        .fd = 42,
        .filter = .read,
        .target = .{ .pty = .{ .session_idx = 0, .pane_slot = 0 } },
    };

    chainHandle(@ptrCast(&dummy_ctx), pty_event, &next);
    try std.testing.expect(forwarded);
}
