//! Routes decoded protocol messages by msg_type to the appropriate handler.
//! Handshake, heartbeat, disconnect, and error messages are handled directly.
//! Session/pane/input/render messages are forwarded (stubs for future plans).
//!
//! Per daemon-architecture 01-module-structure (server/ component responsibilities)
//! and protocol 01-protocol-overview (message type ranges).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const Header = protocol.header.Header;
const server = @import("itshell3_server");
const interfaces = server.os.interfaces;
const EventLoopOps = interfaces.EventLoopOps;
const ClientManager = server.connection.client_manager.ClientManager;
const ClientState = server.connection.client_state.ClientState;
const handshake_handler = server.connection.handshake_handler;
const heartbeat_manager_mod = server.connection.heartbeat_manager;
const HeartbeatManager = heartbeat_manager_mod.HeartbeatManager;
const disconnect_handler = server.connection.disconnect_handler;
const timer_handler = server.handlers.timer_handler;

/// Duration for READY idle timer (READY to AttachSession).
/// Per daemon-behavior policies-and-procedures spec (Handshake Timeouts).
pub const READY_IDLE_TIMEOUT_MS: u32 = 60_000;

/// Context for the message dispatcher.
pub const DispatcherContext = struct {
    client_manager: *ClientManager,
    heartbeat_manager: *HeartbeatManager,
    server_pid: u32,
    /// Callback for initiating client disconnect.
    disconnect_fn: *const fn (client_slot: u16) void,
    /// Event loop operations for timer management.
    event_loop_ops: *const EventLoopOps,
    event_loop_context: *anyopaque,
};

/// Dispatch a decoded message to the appropriate handler.
pub fn dispatch(
    ctx: *DispatcherContext,
    client_slot: u16,
    msg_type: MessageType,
    header: Header,
    payload: []const u8,
) void {
    _ = header;
    const client = ctx.client_manager.getClient(client_slot) orelse return;

    switch (msg_type) {
        .client_hello => handleClientHello(ctx, client, client_slot, payload),
        .heartbeat => handleHeartbeat(client, payload),
        .heartbeat_ack => handleHeartbeatAck(client, payload),
        .disconnect => handleDisconnect(ctx, client_slot),
        .@"error" => {
            // Received an error from client -- transition to disconnecting.
            _ = client.connection.transitionTo(.disconnecting);
            ctx.disconnect_fn(client_slot);
        },
        else => {
            // All other message types are stubs for future plans (session, pane,
            // input, render, IME, flow control, etc.).
        },
    }
}

fn handleClientHello(
    ctx: *DispatcherContext,
    client: *ClientState,
    client_slot: u16,
    payload: []const u8,
) void {
    if (client.connection.state != .handshaking) return;

    const result = handshake_handler.processClientHello(
        std.heap.page_allocator,
        payload,
        client.connection.client_id,
        ctx.server_pid,
    );

    switch (result) {
        .success => |data| {
            // Transition to READY.
            _ = client.connection.transitionTo(.ready);
            // Enqueue the ServerHello response via direct queue.
            // TODO(Plan 7): Wrap with protocol header before sending.
            client.enqueueDirect(data.getPayload()) catch {};

            // Cancel the 5s handshake timer.
            const handshake_timer_id = timer_handler.HANDSHAKE_TIMER_BASE + client_slot;
            ctx.event_loop_ops.cancelTimer(ctx.event_loop_context, handshake_timer_id);
            client.handshake_timer_id = null;

            // Arm the 60s READY idle timer.
            const ready_timer_id = timer_handler.READY_IDLE_TIMER_BASE + client_slot;
            ctx.event_loop_ops.registerTimer(
                ctx.event_loop_context,
                ready_timer_id,
                READY_IDLE_TIMEOUT_MS,
                .{ .timer = .{ .timer_id = ready_timer_id } },
            ) catch {};
            client.ready_idle_timer_id = ready_timer_id;
        },
        .version_mismatch, .capability_required, .malformed_payload => |err_data| {
            // Send error, transition to disconnecting.
            _ = err_data;
            // Cancel the handshake timer on failure too.
            const handshake_timer_id = timer_handler.HANDSHAKE_TIMER_BASE + client_slot;
            ctx.event_loop_ops.cancelTimer(ctx.event_loop_context, handshake_timer_id);
            client.handshake_timer_id = null;

            _ = client.connection.transitionTo(.disconnecting);
            ctx.disconnect_fn(client_slot);
        },
    }
}

fn handleHeartbeat(client: *ClientState, payload: []const u8) void {
    var parse_buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&parse_buf);
    const parsed = std.json.parseFromSlice(protocol.handshake.Heartbeat, fba.allocator(), payload, .{
        .ignore_unknown_fields = true,
    }) catch return;
    defer parsed.deinit();

    const echo_id = HeartbeatManager.processHeartbeat(client, parsed.value.ping_id);
    // TODO(Plan 7): Wrap with protocol header before sending.
    var ack_buf: [128]u8 = undefined;
    const ack_json = std.fmt.bufPrint(&ack_buf, "{{\"ping_id\":{d}}}", .{echo_id}) catch return;
    client.enqueueDirect(ack_json) catch {};
}

fn handleHeartbeatAck(client: *ClientState, payload: []const u8) void {
    var parse_buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&parse_buf);
    const parsed = std.json.parseFromSlice(protocol.handshake.HeartbeatAck, fba.allocator(), payload, .{
        .ignore_unknown_fields = true,
    }) catch return;
    defer parsed.deinit();

    HeartbeatManager.processAck(client, parsed.value.ping_id);
}

fn handleDisconnect(ctx: *DispatcherContext, client_slot: u16) void {
    const client = ctx.client_manager.getClient(client_slot) orelse return;
    disconnect_handler.processIncomingDisconnect(client);
    ctx.disconnect_fn(client_slot);
}

// ── Tests ────────────────────────────────────────────────────────────────────

/// No-op event loop ops for tests.
const noop_event_loop_ops = EventLoopOps{
    .registerRead = struct {
        fn f(_: *anyopaque, _: std.posix.fd_t, _: ?interfaces.EventTarget) EventLoopOps.RegisterError!void {}
    }.f,
    .registerWrite = struct {
        fn f(_: *anyopaque, _: std.posix.fd_t, _: ?interfaces.EventTarget) EventLoopOps.RegisterError!void {}
    }.f,
    .unregister = struct {
        fn f(_: *anyopaque, _: std.posix.fd_t) void {}
    }.f,
    .registerTimer = struct {
        fn f(_: *anyopaque, _: u16, _: u32, _: ?interfaces.EventTarget) EventLoopOps.RegisterError!void {}
    }.f,
    .cancelTimer = struct {
        fn f(_: *anyopaque, _: u16) void {}
    }.f,
    .wait = struct {
        fn f(_: *anyopaque, _: ?u32) EventLoopOps.WaitError!server.os.PriorityEventBuffer.Iterator {
            // Not used in these tests; provide a dummy empty buffer.
            const empty = &server.os.PriorityEventBuffer{};
            return empty.iterator();
        }
    }.f,
};

test "dispatch: unknown message type does not crash" {
    var mgr = ClientManager{};
    const idx = try mgr.addClient(.{ .fd = 10 });
    const c = mgr.getClient(idx).?;
    _ = c.connection.transitionTo(.ready);
    _ = c.connection.transitionTo(.operating);

    var hb_mgr = HeartbeatManager{};
    var disconnect_called = false;
    const disconnect_ctx = struct {
        var flag: *bool = undefined;
        fn cb(_: u16) void {
            flag.* = true;
        }
    };
    disconnect_ctx.flag = &disconnect_called;

    var dummy_el_ctx: u8 = 0;
    var ctx = DispatcherContext{
        .client_manager = &mgr,
        .heartbeat_manager = &hb_mgr,
        .server_pid = 1234,
        .disconnect_fn = disconnect_ctx.cb,
        .event_loop_ops = &noop_event_loop_ops,
        .event_loop_context = @ptrCast(&dummy_el_ctx),
    };

    // Dispatch an operational message type (stub, should not crash).
    const hdr = Header{
        .msg_type = @intFromEnum(MessageType.key_event),
        .flags = .{},
        .payload_length = 0,
        .sequence = 1,
    };
    dispatch(&ctx, idx, .key_event, hdr, "");
    // No crash = success.
    try std.testing.expect(!disconnect_called);

    mgr.getClient(idx).?.deinit();
}
