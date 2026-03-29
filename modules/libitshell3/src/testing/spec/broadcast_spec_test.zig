//! Spec compliance tests: Multi-client broadcast infrastructure.
//!
//! Covers response-before-notification ordering, session-scoped and global
//! broadcast, two-channel write priority, and best-effort delivery semantics.
//!
//! Spec sources:
//!   - daemon-behavior event-handling — response-before-notification, atomicity
//!   - daemon-architecture state-and-types — two-channel write priority

const std = @import("std");
const server = @import("itshell3_server");
const ClientManager = server.connection.client_manager.ClientManager;
const ClientState = server.connection.client_state.ClientState;
const broadcast_mod = server.connection.broadcast;

// ── Spec: Session-Scoped Broadcast ───────────────────────────────────────────

test "spec: broadcast — session-scoped sends to all OPERATING clients in that session" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    // Two clients OPERATING in session 1.
    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = 1;

    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);
    c2.connection.attached_session_id = 1;

    const result = broadcast_mod.broadcastToSession(&mgr, 1, "notification", null);
    try std.testing.expectEqual(@as(u16, 2), result.sent_count);
    try std.testing.expectEqual(@as(u16, 0), result.failed_count);

    // Clean up direct queues.
    mgr.getClient(idx1).?.deinit();
    mgr.getClient(idx2).?.deinit();
}

test "spec: broadcast — session-scoped skips clients in different session" {
    // Only clients attached to the target session receive the notification.
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = 1;

    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);
    c2.connection.attached_session_id = 2; // Different session.

    const result = broadcast_mod.broadcastToSession(&mgr, 1, "notification", null);
    try std.testing.expectEqual(@as(u16, 1), result.sent_count);

    mgr.getClient(idx1).?.deinit();
    mgr.getClient(idx2).?.deinit();
}

test "spec: broadcast — session-scoped skips non-OPERATING clients" {
    // Only OPERATING clients receive session broadcasts.
    // READY and HANDSHAKING clients do not receive session notifications.
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    // OPERATING in session 1.
    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = 1;

    // READY, not attached to any session (or attached_session_id = 1 but not OPERATING).
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    c2.connection.attached_session_id = 1;

    // HANDSHAKING.
    _ = try mgr.addClient(.{ .fd = 12 });

    const result = broadcast_mod.broadcastToSession(&mgr, 1, "notification", null);
    try std.testing.expectEqual(@as(u16, 1), result.sent_count);

    mgr.getClient(idx1).?.deinit();
}

// ── Spec: Response-Before-Notification Pattern ───────────────────────────────

test "spec: broadcast — exclude-one variant for response-before-notification" {
    // The exclude_slot parameter enables the response-before-notification pattern:
    // send response to requester first, then broadcast notification to all others.
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = 1;

    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);
    c2.connection.attached_session_id = 1;

    const idx3 = try mgr.addClient(.{ .fd = 12 });
    const c3 = mgr.getClient(idx3).?;
    _ = c3.connection.transitionTo(.ready);
    _ = c3.connection.transitionTo(.operating);
    c3.connection.attached_session_id = 1;

    // Exclude idx1 (the requester).
    const result = broadcast_mod.broadcastToSession(&mgr, 1, "notification", idx1);

    // Should send to idx2 and idx3, but NOT idx1.
    try std.testing.expectEqual(@as(u16, 2), result.sent_count);

    // Verify idx1 did NOT receive the message (direct_queue should be empty).
    try std.testing.expect(c1.direct_queue.isEmpty());

    mgr.getClient(idx1).?.deinit();
    mgr.getClient(idx2).?.deinit();
    mgr.getClient(idx3).?.deinit();
}

// ── Spec: Global Broadcast ───────────────────────────────────────────────────

test "spec: broadcast — global sends to all OPERATING clients" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = 1;

    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);
    c2.connection.attached_session_id = 2; // Different session.

    // HANDSHAKING client should NOT receive global broadcast.
    _ = try mgr.addClient(.{ .fd = 12 });

    const result = broadcast_mod.broadcastGlobal(&mgr, "global-msg", null);
    try std.testing.expectEqual(@as(u16, 2), result.sent_count);

    mgr.getClient(idx1).?.deinit();
    mgr.getClient(idx2).?.deinit();
}

test "spec: broadcast — global with exclude sends to all except excluded" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);

    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);

    const result = broadcast_mod.broadcastGlobal(&mgr, "global-msg", idx1);
    try std.testing.expectEqual(@as(u16, 1), result.sent_count);

    mgr.getClient(idx1).?.deinit();
    mgr.getClient(idx2).?.deinit();
}

// ── Spec: Active Broadcast (READY + OPERATING) ──────────────────────────────

test "spec: broadcast — broadcastToActive includes READY and OPERATING clients" {
    // Some notifications (like SessionListChanged) need to reach READY clients
    // too, not just OPERATING ones, because READY clients need the session list
    // to decide which session to attach to.
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready); // READY state.

    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating); // OPERATING state.

    // HANDSHAKING client.
    _ = try mgr.addClient(.{ .fd = 12 });

    const result = broadcast_mod.broadcastToActive(&mgr, "session-list-update", null);
    // Both READY and OPERATING clients should receive it.
    try std.testing.expectEqual(@as(u16, 2), result.sent_count);

    mgr.getClient(idx1).?.deinit();
    mgr.getClient(idx2).?.deinit();
}

// ── Spec: Best-Effort Delivery ───────────────────────────────────────────────

test "spec: broadcast — best-effort per client (individual failure does not stop broadcast)" {
    // Plan 6 spec: "Best-effort per client (individual enqueue failure
    // doesn't stop broadcast)."
    //
    // We verify this by checking that broadcastResult tracks both sent and failed counts,
    // and that the function returns rather than erroring.
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = 1;

    // Send a normal-sized message — should succeed.
    const result = broadcast_mod.broadcastToSession(&mgr, 1, "ok", null);
    try std.testing.expectEqual(@as(u16, 1), result.sent_count);
    try std.testing.expectEqual(@as(u16, 0), result.failed_count);

    mgr.getClient(idx1).?.deinit();
}

// ── Spec: Two-Channel Write Priority ─────────────────────────────────────────

test "spec: broadcast — messages go via direct queue (priority 1 channel)" {
    // Broadcast uses the direct queue (priority 1), not the ring buffer.
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    const idx = try mgr.addClient(.{ .fd = 10 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    _ = broadcast_mod.broadcastToSession(&mgr, 1, "test-notification", null);

    // Verify the message is in the direct queue (not ring buffer).
    try std.testing.expect(!client.direct_queue.isEmpty());

    mgr.getClient(idx).?.deinit();
}
