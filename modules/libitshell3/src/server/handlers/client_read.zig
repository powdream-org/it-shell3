//! Client read chain handler. Receives data from SocketConnection, feeds to
//! protocol MessageReader for framing, validates message type against connection
//! state, and dispatches to the appropriate handler.
//!
//! Per protocol spec 01-protocol-overview (16-byte header, message framing).

const std = @import("std");
const interfaces = @import("../os/interfaces.zig");
const event_loop_mod = @import("event_loop.zig");
const Handler = event_loop_mod.Handler;
const transport = @import("itshell3_transport");
const SocketConnection = transport.transport.SocketConnection;
const RecvResult = transport.transport.RecvResult;
const protocol = @import("itshell3_protocol");
const Header = protocol.header.Header;
const MessageType = protocol.message_type.MessageType;
const server = @import("itshell3_server");
const client_manager_mod = server.connection.client_manager;
const ClientManager = client_manager_mod.ClientManager;
const ClientState = server.connection.client_state.ClientState;

/// Callback for dispatching decoded messages.
pub const MessageDispatchFn = *const fn (
    client_slot: u16,
    msg_type: MessageType,
    header: Header,
    payload: []const u8,
) void;

/// Callback for handling client disconnect (peer close or error).
pub const ClientDisconnectFn = *const fn (client_slot: u16) void;

/// Context for the client read chain handler.
pub const ClientReadContext = struct {
    client_manager: *ClientManager,
    dispatch_fn: MessageDispatchFn,
    disconnect_fn: ClientDisconnectFn,
    /// Shared receive buffer for all client reads.
    recv_buffer: [RECV_BUFFER_SIZE]u8 = [_]u8{0} ** RECV_BUFFER_SIZE,
};

/// Size of the shared receive buffer.
pub const RECV_BUFFER_SIZE: usize = 64 * 1024;

/// Chain handler entry point for client read events.
pub fn chainHandle(context: *anyopaque, event: interfaces.Event, next: ?*const Handler) void {
    if (event.target) |target| {
        switch (target) {
            .client => |c| {
                const ctx: *ClientReadContext = @ptrCast(@alignCast(context));
                handleClientRead(ctx, c.client_idx);
                return;
            },
            else => {},
        }
    }
    if (next) |n| n.invoke(event);
}

fn handleClientRead(ctx: *ClientReadContext, client_idx: u16) void {
    const client = ctx.client_manager.getClient(client_idx) orelse return;

    const result = client.connection.socket.recv(&ctx.recv_buffer);

    switch (result) {
        .bytes_read => |n| {
            client.recordActivity();
            // Feed received bytes into the per-client MessageReader, which
            // handles partial frame accumulation across recv() calls.
            _ = client.message_reader.feed(ctx.recv_buffer[0..n]);
            processMessages(ctx, client_idx, client);
        },
        .would_block => {
            // Nothing to read right now, re-arm will happen automatically.
        },
        .peer_closed => {
            ctx.disconnect_fn(client_idx);
        },
        .err => {
            ctx.disconnect_fn(client_idx);
        },
    }
}

fn processMessages(
    ctx: *ClientReadContext,
    client_idx: u16,
    client: *ClientState,
) void {
    while (client.message_reader.nextMessage()) |msg| {
        const msg_type: MessageType = @enumFromInt(msg.header.msg_type);

        // Validate message type against connection state.
        if (!client.connection.isMessageAllowed(msg_type)) {
            // Invalid message for current state -- skip.
            continue;
        }

        // Update last received sequence.
        client.connection.recv_sequence_last = msg.header.sequence;

        // Dispatch the decoded message.
        ctx.dispatch_fn(client_idx, msg_type, msg.header, msg.payload);
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "chainHandle: non-client event forwards to next handler" {
    var forwarded = false;
    const NextCtx = struct {
        flag: *bool,
        fn handle(context_ptr: *anyopaque, _: interfaces.Event, _: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context_ptr));
            self.flag.* = true;
        }
    };
    var next_ctx = NextCtx{ .flag = &forwarded };
    const next_handler = Handler{
        .handleFn = NextCtx.handle,
        .context = @ptrCast(&next_ctx),
        .next = null,
    };

    var dummy_ctx: u8 = 0;
    const pty_event = interfaces.Event{
        .fd = 42,
        .filter = .read,
        .target = .{ .pty = .{ .session_idx = 0, .pane_slot = 0 } },
    };

    chainHandle(@ptrCast(&dummy_ctx), pty_event, &next_handler);
    try std.testing.expect(forwarded);
}
