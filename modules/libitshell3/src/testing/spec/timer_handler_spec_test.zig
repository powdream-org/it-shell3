//! Spec compliance tests for timer_handler.zig.
//!
//! Tests verify observable behavior: timer dispatch to correct handler
//! (handshake timeout, ready idle timeout, heartbeat tick), handshake
//! timeout disconnects HANDSHAKING client, ready idle timeout disconnects
//! READY client.

const std = @import("std");
const server = @import("itshell3_server");
const timer_handler_mod = server.handlers.timer_handler;
const TimerHandlerContext = timer_handler_mod.TimerHandlerContext;
const HANDSHAKE_TIMER_BASE = timer_handler_mod.HANDSHAKE_TIMER_BASE;
const READY_IDLE_TIMER_BASE = timer_handler_mod.READY_IDLE_TIMER_BASE;
const HEARTBEAT_TIMER_ID = timer_handler_mod.HEARTBEAT_TIMER_ID;
const client_manager_mod = server.connection.client_manager;
const ClientManager = client_manager_mod.ClientManager;
const heartbeat_manager_mod = server.connection.heartbeat_manager;
const HeartbeatManager = heartbeat_manager_mod.HeartbeatManager;
const interfaces = server.os.interfaces;
const Handler = server.handlers.event_loop.Handler;
const transport = @import("itshell3_transport");
const SocketConnection = transport.transport.SocketConnection;

// ── Test State ──────────────────────────────────────────────────────────────

const TestDisconnectState = struct {
    disconnect_count: u32 = 0,
    last_slot: u16 = 0,
};

var disconnect_state: TestDisconnectState = .{};

fn testDisconnect(client_slot: u16) void {
    disconnect_state.disconnect_count += 1;
    disconnect_state.last_slot = client_slot;
}

fn resetState() void {
    disconnect_state = .{};
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "spec: timer handler -- handshake timeout disconnects HANDSHAKING client" {
    resetState();

    var mgr = ClientManager{};
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(SocketConnection{ .fd = 100 });
    // Client starts in HANDSHAKING state

    var ctx = TimerHandlerContext{
        .client_manager = &mgr,
        .heartbeat_manager = &hb,
        .disconnect_fn = testDisconnect,
    };

    // Fire a handshake timer for this slot
    const timer_id = HANDSHAKE_TIMER_BASE + slot;
    const event = interfaces.Event{
        .fd = 0,
        .filter = .timer,
        .target = .{ .timer = .{ .timer_id = timer_id } },
    };
    timer_handler_mod.chainHandle(@ptrCast(&ctx), event, null);

    try std.testing.expectEqual(@as(u32, 1), disconnect_state.disconnect_count);
    try std.testing.expectEqual(slot, disconnect_state.last_slot);

    // Client should be in disconnecting state
    const client = mgr.getClient(slot).?;
    try std.testing.expectEqual(server.connection.connection_state.State.disconnecting, client.getState());
}

test "spec: timer handler -- handshake timeout ignores non-HANDSHAKING client" {
    resetState();

    var mgr = ClientManager{};
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(SocketConnection{ .fd = 101 });
    // Transition to READY -- handshake timeout should not apply
    _ = mgr.getClient(slot).?.connection.transitionTo(.ready);

    var ctx = TimerHandlerContext{
        .client_manager = &mgr,
        .heartbeat_manager = &hb,
        .disconnect_fn = testDisconnect,
    };

    const timer_id = HANDSHAKE_TIMER_BASE + slot;
    const event = interfaces.Event{
        .fd = 0,
        .filter = .timer,
        .target = .{ .timer = .{ .timer_id = timer_id } },
    };
    timer_handler_mod.chainHandle(@ptrCast(&ctx), event, null);

    try std.testing.expectEqual(@as(u32, 0), disconnect_state.disconnect_count);
}

test "spec: timer handler -- ready idle timeout disconnects READY client" {
    resetState();

    var mgr = ClientManager{};
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(SocketConnection{ .fd = 102 });
    _ = mgr.getClient(slot).?.connection.transitionTo(.ready);

    var ctx = TimerHandlerContext{
        .client_manager = &mgr,
        .heartbeat_manager = &hb,
        .disconnect_fn = testDisconnect,
    };

    const timer_id = READY_IDLE_TIMER_BASE + slot;
    const event = interfaces.Event{
        .fd = 0,
        .filter = .timer,
        .target = .{ .timer = .{ .timer_id = timer_id } },
    };
    timer_handler_mod.chainHandle(@ptrCast(&ctx), event, null);

    try std.testing.expectEqual(@as(u32, 1), disconnect_state.disconnect_count);
    try std.testing.expectEqual(slot, disconnect_state.last_slot);

    const client = mgr.getClient(slot).?;
    try std.testing.expectEqual(server.connection.connection_state.State.disconnecting, client.getState());
}

test "spec: timer handler -- ready idle timeout ignores OPERATING client" {
    resetState();

    var mgr = ClientManager{};
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(SocketConnection{ .fd = 103 });
    _ = mgr.getClient(slot).?.connection.transitionTo(.ready);
    _ = mgr.getClient(slot).?.connection.transitionTo(.operating);

    var ctx = TimerHandlerContext{
        .client_manager = &mgr,
        .heartbeat_manager = &hb,
        .disconnect_fn = testDisconnect,
    };

    const timer_id = READY_IDLE_TIMER_BASE + slot;
    const event = interfaces.Event{
        .fd = 0,
        .filter = .timer,
        .target = .{ .timer = .{ .timer_id = timer_id } },
    };
    timer_handler_mod.chainHandle(@ptrCast(&ctx), event, null);

    try std.testing.expectEqual(@as(u32, 0), disconnect_state.disconnect_count);
}

test "spec: timer handler -- heartbeat tick sends heartbeat to READY clients" {
    resetState();

    var mgr = ClientManager{};
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(SocketConnection{ .fd = 104 });
    const client = mgr.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);
    // Record activity so client is not timed out
    client.recordActivity();

    var ctx = TimerHandlerContext{
        .client_manager = &mgr,
        .heartbeat_manager = &hb,
        .disconnect_fn = testDisconnect,
    };

    const event = interfaces.Event{
        .fd = 0,
        .filter = .timer,
        .target = .{ .timer = .{ .timer_id = HEARTBEAT_TIMER_ID } },
    };
    timer_handler_mod.chainHandle(@ptrCast(&ctx), event, null);

    // Heartbeat should have been sent (ping_id assigned)
    try std.testing.expect(client.last_ping_id_sent > 0);
    // No disconnect for active client
    try std.testing.expectEqual(@as(u32, 0), disconnect_state.disconnect_count);
}

test "spec: timer handler -- heartbeat tick disconnects timed-out client" {
    resetState();

    var mgr = ClientManager{};
    var hb = HeartbeatManager{};
    const slot = try mgr.addClient(SocketConnection{ .fd = 105 });
    const client = mgr.getClient(slot).?;
    _ = client.connection.transitionTo(.ready);
    // Set last activity far in the past (beyond 90s timeout)
    client.last_activity_timestamp = std.time.milliTimestamp() - 100_000;

    var ctx = TimerHandlerContext{
        .client_manager = &mgr,
        .heartbeat_manager = &hb,
        .disconnect_fn = testDisconnect,
    };

    const event = interfaces.Event{
        .fd = 0,
        .filter = .timer,
        .target = .{ .timer = .{ .timer_id = HEARTBEAT_TIMER_ID } },
    };
    timer_handler_mod.chainHandle(@ptrCast(&ctx), event, null);

    try std.testing.expectEqual(@as(u32, 1), disconnect_state.disconnect_count);
    try std.testing.expectEqual(slot, disconnect_state.last_slot);
}

test "spec: timer handler -- heartbeat tick skips HANDSHAKING clients" {
    resetState();

    var mgr = ClientManager{};
    var hb = HeartbeatManager{};
    _ = try mgr.addClient(SocketConnection{ .fd = 106 });
    // Client stays in HANDSHAKING

    var ctx = TimerHandlerContext{
        .client_manager = &mgr,
        .heartbeat_manager = &hb,
        .disconnect_fn = testDisconnect,
    };

    const event = interfaces.Event{
        .fd = 0,
        .filter = .timer,
        .target = .{ .timer = .{ .timer_id = HEARTBEAT_TIMER_ID } },
    };
    timer_handler_mod.chainHandle(@ptrCast(&ctx), event, null);

    // Should be skipped entirely
    try std.testing.expectEqual(@as(u32, 0), disconnect_state.disconnect_count);
}

test "spec: timer handler -- non-timer event forwards to next handler" {
    resetState();

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
    const read_event = interfaces.Event{
        .fd = 42,
        .filter = .read,
        .target = .{ .client = .{ .client_idx = 0 } },
    };

    timer_handler_mod.chainHandle(@ptrCast(&dummy_ctx), read_event, &next_handler);
    try std.testing.expect(forwarded);
}

test "spec: timer handler -- timer event with non-timer target forwards to next" {
    resetState();

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
    // Timer filter but client target -- should forward
    const event = interfaces.Event{
        .fd = 42,
        .filter = .timer,
        .target = .{ .client = .{ .client_idx = 0 } },
    };

    timer_handler_mod.chainHandle(@ptrCast(&dummy_ctx), event, &next_handler);
    try std.testing.expect(forwarded);
}
