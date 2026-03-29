//! Timer chain handler. Dispatches timer events to handshake timeout,
//! READY idle timeout, or heartbeat tick handlers.
//!
//! Per daemon-behavior 02-event-handling (EVFILT_TIMER priority).

const std = @import("std");
const interfaces = @import("../os/interfaces.zig");
const event_loop_mod = @import("event_loop.zig");
const Handler = event_loop_mod.Handler;
const server = @import("itshell3_server");
const ClientManager = server.connection.client_manager.ClientManager;
const heartbeat_manager_mod = server.connection.heartbeat_manager;
const HeartbeatManager = heartbeat_manager_mod.HeartbeatManager;
const LivenessResult = heartbeat_manager_mod.LivenessResult;

const MAX_CLIENTS = server.connection.client_manager.MAX_CLIENTS;

/// Contiguous, non-overlapping timer ID ranges derived from MAX_CLIENTS.
pub const HANDSHAKE_TIMER_BASE: u16 = 0x0000;
pub const HANDSHAKE_TIMER_MAX: u16 = HANDSHAKE_TIMER_BASE + MAX_CLIENTS - 1;
pub const READY_IDLE_TIMER_BASE: u16 = HANDSHAKE_TIMER_MAX + 1;
pub const READY_IDLE_TIMER_MAX: u16 = READY_IDLE_TIMER_BASE + MAX_CLIENTS - 1;
pub const HEARTBEAT_TIMER_ID: u16 = READY_IDLE_TIMER_MAX + 1;
pub const TIMER_FDS_SIZE: u16 = HEARTBEAT_TIMER_ID + 1;

pub const ClientDisconnectFn = *const fn (client_slot: u16) void;

pub const TimerHandlerContext = struct {
    client_manager: *ClientManager,
    heartbeat_manager: *HeartbeatManager,
    disconnect_fn: ClientDisconnectFn,
};

/// Chain handler entry point for timer events.
pub fn chainHandle(context: *anyopaque, event: interfaces.Event, next: ?*const Handler) void {
    if (event.filter == .timer) {
        if (event.target) |target| {
            switch (target) {
                .timer => |t| {
                    const ctx: *TimerHandlerContext = @ptrCast(@alignCast(context));
                    handleTimer(ctx, t.timer_id);
                    return;
                },
                else => {},
            }
        }
    }
    if (next) |n| n.invoke(event);
}

fn handleTimer(ctx: *TimerHandlerContext, timer_id: u16) void {
    if (timer_id == HEARTBEAT_TIMER_ID) {
        handleHeartbeatTick(ctx);
    } else if (timer_id >= HANDSHAKE_TIMER_BASE and timer_id <= HANDSHAKE_TIMER_MAX) {
        // Handshake timeout for a specific client slot.
        const client_slot = timer_id - HANDSHAKE_TIMER_BASE;
        handleHandshakeTimeout(ctx, client_slot);
    } else if (timer_id >= READY_IDLE_TIMER_BASE and timer_id <= READY_IDLE_TIMER_MAX) {
        // READY idle timeout for a specific client slot.
        const client_slot = timer_id - READY_IDLE_TIMER_BASE;
        handleReadyIdleTimeout(ctx, client_slot);
    }
}

fn handleHeartbeatTick(ctx: *TimerHandlerContext) void {
    var i: u16 = 0;
    const now = std.time.milliTimestamp();
    while (i < server.connection.client_manager.MAX_CLIENTS) : (i += 1) {
        const client = ctx.client_manager.getClient(i) orelse continue;
        const result = ctx.heartbeat_manager.checkLiveness(client, now);
        switch (result) {
            .timed_out => ctx.disconnect_fn(i),
            .alive => {
                const ping_id = ctx.heartbeat_manager.nextPingId();
                client.last_ping_id_sent = ping_id;

                // TODO(Plan 7): Serialize with protocol header.
                var buf: [128]u8 = undefined;
                const json = std.fmt.bufPrint(&buf, "{{\"ping_id\":{d}}}", .{ping_id}) catch continue;
                client.enqueueDirect(json) catch {};
            },
            .unknown => {},
        }
    }
}

fn handleHandshakeTimeout(ctx: *TimerHandlerContext, client_slot: u16) void {
    const client = ctx.client_manager.getClient(client_slot) orelse return;
    if (client.getState() == .handshaking) {
        // Handshake timeout expired -- disconnect.
        _ = client.connection.transitionTo(.disconnecting);
        ctx.disconnect_fn(client_slot);
    }
}

fn handleReadyIdleTimeout(ctx: *TimerHandlerContext, client_slot: u16) void {
    const client = ctx.client_manager.getClient(client_slot) orelse return;
    if (client.getState() == .ready) {
        // READY idle timeout expired -- disconnect.
        _ = client.connection.transitionTo(.disconnecting);
        ctx.disconnect_fn(client_slot);
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "chainHandle: non-timer event forwards to next handler" {
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

    chainHandle(@ptrCast(&dummy_ctx), read_event, &next_handler);
    try std.testing.expect(forwarded);
}
