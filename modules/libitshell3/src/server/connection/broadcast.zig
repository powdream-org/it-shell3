//! Multi-client notification delivery. Session-scoped and global broadcast,
//! with exclude-one variant for the response-before-notification pattern.
//!
//! Per daemon-behavior 02-event-handling (response-before-notification invariant)
//! and daemon-architecture 02-state-and-types (two-channel write priority).

const std = @import("std");
const client_state_mod = @import("client_state.zig");
const ClientState = client_state_mod.ClientState;
const client_manager_mod = @import("client_manager.zig");
const ClientManager = client_manager_mod.ClientManager;

/// Result of a broadcast operation.
pub const BroadcastResult = struct {
    /// Number of clients the message was successfully enqueued to.
    sent_count: u16 = 0,
    /// Number of clients where enqueue failed (queue full).
    failed_count: u16 = 0,
};

/// Context passed through ClientManager iterator callbacks.
const BroadcastContext = struct {
    result: BroadcastResult = .{},
    message: []const u8,
    exclude_slot: ?u16,
};

/// Broadcast a message to all OPERATING clients attached to a session.
/// Uses the direct queue (priority 1 channel).
/// Best-effort: individual enqueue failure does not stop broadcast.
pub fn broadcastToSession(
    manager: *ClientManager,
    session_id: u32,
    message: []const u8,
    exclude_slot: ?u16,
) BroadcastResult {
    var ctx = BroadcastContext{ .message = message, .exclude_slot = exclude_slot };
    manager.forEachOperatingInSession(session_id, &ctx, enqueueCallback);
    return ctx.result;
}

/// Broadcast a message to all OPERATING clients (global broadcast).
/// Uses the direct queue (priority 1 channel).
pub fn broadcastGlobal(
    manager: *ClientManager,
    message: []const u8,
    exclude_slot: ?u16,
) BroadcastResult {
    var ctx = BroadcastContext{ .message = message, .exclude_slot = exclude_slot };
    var i: u32 = 0;
    while (i < client_manager_mod.MAX_CLIENTS) : (i += 1) {
        const idx: u16 = @intCast(i);
        const slot = manager.getClient(idx) orelse continue;
        if (slot.connection.state != .operating) continue;
        enqueueCallback(&ctx, slot, idx);
    }
    return ctx.result;
}

/// Broadcast to all READY or OPERATING clients (for session list notifications).
pub fn broadcastToActive(
    manager: *ClientManager,
    message: []const u8,
    exclude_slot: ?u16,
) BroadcastResult {
    var ctx = BroadcastContext{ .message = message, .exclude_slot = exclude_slot };
    manager.forEachActive(&ctx, enqueueCallback);
    return ctx.result;
}

fn enqueueCallback(ctx: *BroadcastContext, slot: *ClientState, idx: u16) void {
    if (ctx.exclude_slot) |excl| {
        if (idx == excl) return;
    }
    slot.enqueueDirect(ctx.message) catch {
        ctx.result.failed_count += 1;
        return;
    };
    ctx.result.sent_count += 1;
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "broadcastToSession: sends to operating clients in session" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    // Add two clients, both operating in session 1
    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    // Transition both to OPERATING in session 1
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = 1;
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);
    c2.connection.attached_session_id = 1;

    const result = broadcastToSession(&mgr, 1, "notification", null);
    try std.testing.expectEqual(@as(u16, 2), result.sent_count);
    try std.testing.expectEqual(@as(u16, 0), result.failed_count);

    // Clean up
    mgr.getClient(idx1).?.deinit();
    mgr.getClient(idx2).?.deinit();
}

test "broadcastToSession: excludes specified slot" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = 1;
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);
    c2.connection.attached_session_id = 1;

    const result = broadcastToSession(&mgr, 1, "notification", idx1);
    try std.testing.expectEqual(@as(u16, 1), result.sent_count);

    mgr.getClient(idx1).?.deinit();
    mgr.getClient(idx2).?.deinit();
}

test "broadcastGlobal: sends to all operating clients" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    _ = try mgr.addClient(.{ .fd = 12 }); // stays in handshaking

    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);

    const result = broadcastGlobal(&mgr, "global-msg", null);
    try std.testing.expectEqual(@as(u16, 2), result.sent_count);

    mgr.getClient(idx1).?.deinit();
    mgr.getClient(idx2).?.deinit();
}

test "broadcastToSession: skips clients in different session" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = 1;
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);
    c2.connection.attached_session_id = 2; // Different session

    const result = broadcastToSession(&mgr, 1, "notification", null);
    try std.testing.expectEqual(@as(u16, 1), result.sent_count);

    mgr.getClient(idx1).?.deinit();
    mgr.getClient(idx2).?.deinit();
}
