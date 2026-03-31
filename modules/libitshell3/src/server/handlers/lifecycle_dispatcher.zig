//! Dispatches lifecycle messages (0x00xx range): handshake, heartbeat,
//! disconnect, and error handling.
//!
//! Per protocol 01-protocol-overview (Handshake & Lifecycle range 0x0001-0x00FF)
//! and daemon-behavior 03-policies-and-procedures (connection state machine,
//! heartbeat policy).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const server = @import("itshell3_server");
const ClientState = server.connection.client_state.ClientState;
const handshake_handler = server.connection.handshake_handler;
const HeartbeatManager = server.connection.heartbeat_manager.HeartbeatManager;
const disconnect_handler = server.connection.disconnect_handler;
const timer_handler = server.handlers.timer_handler;
const message_dispatcher = @import("message_dispatcher.zig");
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;
const DispatcherContext = message_dispatcher.DispatcherContext;
const ready_idle_timeout_ms = message_dispatcher.ready_idle_timeout_ms;

/// Dispatches a lifecycle-category message to the appropriate handler.
pub fn dispatch(params: CategoryDispatchParams) void {
    switch (params.msg_type) {
        .client_hello => handleClientHello(params.context, params.client, params.client_slot, params.payload),
        .heartbeat => handleHeartbeat(params.client, params.payload),
        .heartbeat_ack => handleHeartbeatAck(params.client, params.payload),
        .disconnect => handleDisconnect(params.context, params.client_slot),
        .@"error" => {
            // Received an error from client -- transition to disconnecting.
            _ = params.client.connection.transitionTo(.disconnecting);
            params.context.disconnect_fn(params.client_slot);
        },
        else => {},
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
        ctx.allocator,
        payload,
        client.connection.client_id,
        ctx.server_pid,
    );

    // Cancel the handshake timer regardless of outcome.
    cancelHandshakeTimer(ctx, client, client_slot);

    switch (result) {
        .success => |data| {
            // Transition to READY.
            _ = client.connection.transitionTo(.ready);
            // Enqueue the ServerHello response via direct queue with protocol header.
            const envelope_mod = @import("protocol_envelope.zig");
            var hello_buf: [envelope_mod.MAX_ENVELOPE_SIZE]u8 = undefined;
            const hello_payload = data.getPayload();
            const seq = client.connection.advanceSendSequence();
            if (envelope_mod.wrapResponse(&hello_buf, @intFromEnum(MessageType.server_hello), seq, hello_payload)) |wrapped| {
                client.enqueueDirect(wrapped) catch {};
            } else {
                // Fallback: send without header if wrapping fails.
                client.enqueueDirect(hello_payload) catch {};
            }

            // Arm the 60s READY idle timer.
            const ready_timer_id = timer_handler.READY_IDLE_TIMER_BASE + client_slot;
            ctx.event_loop_ops.registerTimer(
                ctx.event_loop_context,
                ready_timer_id,
                ready_idle_timeout_ms,
                .{ .timer = .{ .timer_id = ready_timer_id } },
            ) catch {};
            client.ready_idle_timer_id = ready_timer_id;
        },
        .version_mismatch, .capability_required, .malformed_payload => |_| {
            // Send error, transition to disconnecting.
            _ = client.connection.transitionTo(.disconnecting);
            ctx.disconnect_fn(client_slot);
        },
    }
}

/// Cancels the handshake timeout timer for a client slot.
fn cancelHandshakeTimer(ctx: *DispatcherContext, client: *ClientState, client_slot: u16) void {
    const timer_id = timer_handler.HANDSHAKE_TIMER_BASE + client_slot;
    ctx.event_loop_ops.cancelTimer(ctx.event_loop_context, timer_id);
    client.handshake_timer_id = null;
}

fn handleHeartbeat(client: *ClientState, payload: []const u8) void {
    var parse_buf: [256]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&parse_buf);
    const parsed = std.json.parseFromSlice(protocol.handshake.Heartbeat, fixed_buffer_allocator.allocator(), payload, .{
        .ignore_unknown_fields = true,
    }) catch return;
    defer parsed.deinit();

    const echo_id = HeartbeatManager.processHeartbeat(client, parsed.value.ping_id);
    var ack_json_buf: [128]u8 = undefined;
    const ack_json = std.fmt.bufPrint(&ack_json_buf, "{{\"ping_id\":{d}}}", .{echo_id}) catch return;
    const envelope_mod = @import("protocol_envelope.zig");
    var ack_buf: [envelope_mod.MAX_ENVELOPE_SIZE]u8 = undefined;
    const seq = client.connection.advanceSendSequence();
    if (envelope_mod.wrapResponse(&ack_buf, @intFromEnum(MessageType.heartbeat_ack), seq, ack_json)) |wrapped| {
        client.enqueueDirect(wrapped) catch {};
    } else {
        client.enqueueDirect(ack_json) catch {};
    }
}

fn handleHeartbeatAck(client: *ClientState, payload: []const u8) void {
    var parse_buf: [256]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&parse_buf);
    const parsed = std.json.parseFromSlice(protocol.handshake.HeartbeatAck, fixed_buffer_allocator.allocator(), payload, .{
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

test "dispatch: unknown lifecycle message type does not crash" {
    const Header = protocol.header.Header;
    // server_hello is S->C; the server-side lifecycle dispatcher should ignore it.
    const params = CategoryDispatchParams{
        .context = undefined,
        .client = undefined,
        .client_slot = 0,
        .msg_type = .server_hello,
        .header = Header{
            .msg_type = @intFromEnum(MessageType.server_hello),
            .flags = .{},
            .payload_length = 0,
            .sequence = 1,
        },
        .payload = "",
    };
    dispatch(params);
    // No crash = success.
}

test "dispatch: error message transitions to disconnecting" {
    const ClientManager = server.connection.client_manager.ClientManager;
    const Header = protocol.header.Header;
    const noop_event_loop_ops = @import("itshell3_testing").helpers.noop_event_loop_ops;

    var client_manager = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const idx = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);

    var heartbeat_manager = HeartbeatManager{};
    var disconnect_called = false;
    const disconnect_ctx_ns = struct {
        var flag: *bool = undefined;
        fn cb(_: u16) void {
            flag.* = true;
        }
    };
    disconnect_ctx_ns.flag = &disconnect_called;

    var dummy_el_ctx: u8 = 0;
    var ctx = DispatcherContext{
        .client_manager = &client_manager,
        .heartbeat_manager = &heartbeat_manager,
        .server_pid = 1234,
        .disconnect_fn = disconnect_ctx_ns.cb,
        .event_loop_ops = &noop_event_loop_ops,
        .event_loop_context = @ptrCast(&dummy_el_ctx),
        .allocator = std.testing.allocator,
    };

    const params = CategoryDispatchParams{
        .context = &ctx,
        .client = client,
        .client_slot = idx,
        .msg_type = .@"error",
        .header = Header{
            .msg_type = @intFromEnum(MessageType.@"error"),
            .flags = .{},
            .payload_length = 0,
            .sequence = 1,
        },
        .payload = "",
    };
    dispatch(params);
    try std.testing.expectEqual(.disconnecting, client.connection.state);
    try std.testing.expect(disconnect_called);

    client.deinit();
}
