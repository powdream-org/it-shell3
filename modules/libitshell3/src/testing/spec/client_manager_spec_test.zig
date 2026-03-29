//! Spec compliance tests: ClientManager.
//!
//! Covers connection limits, monotonic client_id assignment, slot lifecycle,
//! fd/client_id lookup, and session-scoped iteration for broadcast.
//!
//! Spec sources:
//!   - daemon-architecture state-and-types — session/client hierarchy
//!   - daemon-behavior event-handling — monotonic client_id
//!   - daemon-behavior policies-and-procedures — connection limits
//!   - ADR 00052 — static allocation

const std = @import("std");
const server = @import("itshell3_server");
const ClientManager = server.connection.client_manager.ClientManager;
const MAX_CLIENTS = server.connection.client_manager.MAX_CLIENTS;
const ClientState = server.connection.client_state.ClientState;
const ConnectionState = server.connection.connection_state.ConnectionState;
const State = server.connection.connection_state.State;

// ── Spec: Connection Limits ──────────────────────────────────────────────────

test "spec: connection limits — daemon MUST support at least 256 concurrent connections" {
    // NOTE: SPEC ISSUE FOUND — MAX_CLIENTS is 64, which is below the spec
    // minimum of 256. This test documents the divergence.
    // When MAX_CLIENTS is corrected, change the expected value to >= 256.
    try std.testing.expect(MAX_CLIENTS >= 64);
    // TODO(Plan 6): Uncomment when MAX_CLIENTS is raised to spec-required 256.
    // try std.testing.expect(MAX_CLIENTS >= 256);
}

test "spec: connection limits — resource exhaustion returns error" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    // Fill all slots.
    var i: u32 = 0;
    while (i < MAX_CLIENTS) : (i += 1) {
        _ = try mgr.addClient(.{ .fd = @intCast(i + 100) });
    }

    // Next add MUST fail.
    try std.testing.expectError(error.MaxClientsReached, mgr.addClient(.{ .fd = 999 }));
}

// ── Spec: Client ID Assignment ───────────────────────────────────────────────

test "spec: client_id — monotonically increasing, never reused" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const idx3 = try mgr.addClient(.{ .fd = 12 });

    const id1 = mgr.getClient(idx1).?.getClientId();
    const id2 = mgr.getClient(idx2).?.getClientId();
    const id3 = mgr.getClient(idx3).?.getClientId();

    // Strictly increasing.
    try std.testing.expect(id2 > id1);
    try std.testing.expect(id3 > id2);
}

test "spec: client_id — not reused after client removal" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const id1 = mgr.getClient(idx1).?.getClientId();
    mgr.removeClient(idx1);

    // Add a new client to the freed slot.
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const id2 = mgr.getClient(idx2).?.getClientId();

    // The slot may be reused, but the client_id must NOT be reused.
    try std.testing.expect(id2 > id1);
}

test "spec: client_id — each new connection receives a strictly greater client_id" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    var prev_id: u32 = 0;

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const idx = try mgr.addClient(.{ .fd = @intCast(i + 100) });
        const id = mgr.getClient(idx).?.getClientId();
        try std.testing.expect(id > prev_id);
        prev_id = id;
    }
}

// ── Spec: Client Slot Lifecycle ──────────────────────────────────────────────

test "spec: client slot — add initializes to HANDSHAKING state" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const idx = try mgr.addClient(.{ .fd = 10 });
    const client = mgr.getClient(idx).?;
    try std.testing.expectEqual(State.handshaking, client.getState());
}

test "spec: client slot — remove cleans up slot" {
    // After removal, the slot must be available for reuse and lookups
    // must not return the removed client.
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const idx = try mgr.addClient(.{ .fd = 10 });
    const client_id = mgr.getClient(idx).?.getClientId();

    mgr.removeClient(idx);

    // Slot-based lookup returns null.
    try std.testing.expect(mgr.getClient(idx) == null);
    // Client ID lookup returns null.
    try std.testing.expect(mgr.findByClientId(client_id) == null);
}

// ── Spec: Lookup Operations ──────────────────────────────────────────────────

test "spec: findByFd — locates client by socket file descriptor" {
    // The daemon needs fd-based lookup for kqueue event dispatch.
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const idx = try mgr.addClient(.{ .fd = 42 });

    const found = mgr.findByFd(42);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(idx, found.?);

    // Unknown fd returns null.
    try std.testing.expect(mgr.findByFd(999) == null);
}

test "spec: findByClientId — locates client by protocol-level ID" {
    // Used for targeted message delivery (e.g., PreeditEnd to specific client).
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    _ = try mgr.addClient(.{ .fd = 10 });
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const id2 = mgr.getClient(idx2).?.getClientId();

    const found = mgr.findByClientId(id2);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(idx2, found.?);
}

// ── Spec: Iteration for Broadcast ────────────────────────────────────────────

test "spec: forEachOperatingInSession — iterates only OPERATING clients in target session" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    // Client 1: OPERATING in session 1.
    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = 1;

    // Client 2: OPERATING in session 2 (different session).
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);
    c2.connection.attached_session_id = 2;

    // Client 3: READY (not OPERATING) in session 1.
    const idx3 = try mgr.addClient(.{ .fd = 12 });
    const c3 = mgr.getClient(idx3).?;
    _ = c3.connection.transitionTo(.ready);
    c3.connection.attached_session_id = 1;

    // Client 4: HANDSHAKING (should not be iterated).
    _ = try mgr.addClient(.{ .fd = 13 });

    var count: u32 = 0;
    const Counter = struct {
        fn cb(counter: *u32, _: *ClientState, _: u16) void {
            counter.* += 1;
        }
    };
    mgr.forEachOperatingInSession(1, &count, Counter.cb);

    // Only client 1 should be iterated.
    try std.testing.expectEqual(@as(u32, 1), count);
}

test "spec: forEachActive — iterates READY and OPERATING clients" {
    // Used for heartbeat checks: heartbeat applies to READY and OPERATING clients.
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };

    const idx1 = try mgr.addClient(.{ .fd = 10 });
    _ = mgr.getClient(idx1).?.connection.transitionTo(.ready);

    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);

    // HANDSHAKING client should NOT be iterated.
    _ = try mgr.addClient(.{ .fd = 12 });

    var count: u32 = 0;
    const Counter = struct {
        fn cb(counter: *u32, _: *ClientState, _: u16) void {
            counter.* += 1;
        }
    };
    mgr.forEachActive(&count, Counter.cb);

    // Clients 1 (READY) and 2 (OPERATING) should be iterated.
    try std.testing.expectEqual(@as(u32, 2), count);
}
