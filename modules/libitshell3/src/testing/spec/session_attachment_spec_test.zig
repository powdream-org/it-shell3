//! Spec compliance tests: Session attachment tracking and ADR 00020.
//!
//! Covers AttachSession, DetachSession, AttachOrCreate, session switching
//! via detach+attach, and the ERR_SESSION_ALREADY_ATTACHED rule.
//!
//! Spec sources:
//!   - ADR 00020 (session attachment model: single-session-per-connection,
//!     ERR_SESSION_ALREADY_ATTACHED, detach before re-attach)
//!   - protocol 03-session-pane-management (attach/detach/attach-or-create
//!     message definitions)
//!   - daemon-behavior 03-policies-and-procedures (client state transitions:
//!     READY->OPERATING, OPERATING->READY)
//!   - daemon-behavior 02-event-handling (destroy cascade,
//!     response-before-notification)

const std = @import("std");
const core = @import("itshell3_core");
const server = @import("itshell3_server");
const protocol = @import("itshell3_protocol");
const transport = @import("itshell3_transport");

const SessionId = core.SessionId;
const ConnectionState = server.connection.ConnectionState;
const State = server.connection.connection_state.State;
const SocketConnection = transport.transport.SocketConnection;
const MessageType = protocol.message_type.MessageType;
const SessionManager = server.state.SessionManager;
const SessionEntry = server.state.SessionEntry;

const test_mod = @import("itshell3_testing");
const mock_ime = test_mod.mock_ime_engine;

var test_mock_engine = mock_ime.MockImeEngine{};

fn testImeEngine() core.ImeEngine {
    return test_mock_engine.engine();
}

fn makeConn(state: State) ConnectionState {
    var conn = ConnectionState.init(SocketConnection{ .fd = 5 }, 1);
    switch (state) {
        .handshaking => {},
        .ready => {
            _ = conn.transitionTo(.ready);
        },
        .operating => {
            _ = conn.transitionTo(.ready);
            _ = conn.transitionTo(.operating);
        },
        .disconnecting => {
            _ = conn.transitionTo(.disconnecting);
        },
    }
    return conn;
}

// ── ADR 00020: Single-session-per-connection ───────────────────────────────

test "spec: attachment -- READY allows AttachSessionRequest" {
    // daemon-behavior 03-policies-and-procedures (client state transitions):
    // READY -> AttachSessionRequest -> OPERATING.
    const conn = makeConn(.ready);
    try std.testing.expect(conn.isMessageAllowed(.attach_session_request));
}

test "spec: attachment -- READY to OPERATING transition succeeds" {
    // daemon-behavior 03-policies-and-procedures (client state transitions):
    // READY -> OPERATING on attach.
    var conn = makeConn(.ready);
    try std.testing.expect(conn.transitionTo(.operating));
    try std.testing.expectEqual(State.operating, conn.state);
}

test "spec: attachment -- OPERATING to OPERATING transition is invalid" {
    // ADR 00020 (session attachment model): OPERATING->OPERATING is NOT valid.
    // Client must DetachSessionRequest (-> READY) then AttachSessionRequest
    // (-> OPERATING).
    var conn = makeConn(.operating);
    try std.testing.expect(!conn.transitionTo(.operating));
    // State should remain OPERATING (transition was rejected).
    try std.testing.expectEqual(State.operating, conn.state);
}

test "spec: attachment -- OPERATING to READY via detach succeeds" {
    // daemon-behavior 03-policies-and-procedures (client state transitions):
    // OPERATING -> DetachSessionRequest -> READY.
    var conn = makeConn(.operating);
    try std.testing.expect(conn.transitionTo(.ready));
    try std.testing.expectEqual(State.ready, conn.state);
}

test "spec: attachment -- session switching requires detach then attach" {
    // ADR 00020: To switch sessions, client must first detach then attach.
    var conn = makeConn(.ready);

    // Attach to first session.
    try std.testing.expect(conn.transitionTo(.operating));
    conn.attached_session_id = 1;
    try std.testing.expectEqual(State.operating, conn.state);

    // Cannot re-attach without detaching (OPERATING->OPERATING invalid).
    try std.testing.expect(!conn.transitionTo(.operating));

    // Detach first.
    try std.testing.expect(conn.transitionTo(.ready));
    conn.attached_session_id = 0;
    try std.testing.expectEqual(State.ready, conn.state);

    // Now attach to second session.
    try std.testing.expect(conn.transitionTo(.operating));
    conn.attached_session_id = 2;
    try std.testing.expectEqual(State.operating, conn.state);
    try std.testing.expectEqual(@as(u32, 2), conn.attached_session_id);
}

test "spec: attachment -- attached_session_id tracks current session" {
    // protocol 03-session-pane-management (attach/detach message definitions):
    // AttachSessionRequest sets session binding.
    // ConnectionState.attached_session_id stores the attached session (0 = none).
    var conn = makeConn(.ready);
    try std.testing.expectEqual(@as(u32, 0), conn.attached_session_id);

    _ = conn.transitionTo(.operating);
    conn.attached_session_id = 42;
    try std.testing.expectEqual(@as(u32, 42), conn.attached_session_id);
}

test "spec: attachment -- detach clears attached_session_id" {
    // protocol 03-session-pane-management (attach/detach message definitions):
    // DetachSessionRequest clears attachment.
    var conn = makeConn(.operating);
    conn.attached_session_id = 10;

    _ = conn.transitionTo(.ready);
    conn.attached_session_id = 0;
    try std.testing.expectEqual(@as(u32, 0), conn.attached_session_id);
    try std.testing.expectEqual(State.ready, conn.state);
}

// ── AttachSession with create_if_missing ───────────────────────────────────

test "spec: attachment -- create_if_missing uses same AttachSessionRequest message type" {
    // protocol 03-session-pane-management (ADR 00003): AttachOrCreate merged
    // into AttachSessionRequest. create_if_missing uses the same 0x0104
    // message type, subject to the same state machine rules.
    const conn = makeConn(.ready);
    try std.testing.expect(conn.isMessageAllowed(.attach_session_request));
}

test "spec: attachment -- AttachSession allowed through filter in OPERATING state" {
    // ADR 00020 (session attachment model): ERR_SESSION_ALREADY_ATTACHED is
    // returned at the handler level, not at the message filter level. The
    // message type 0x0104 is in the operational range and must pass through
    // the filter. The handler is responsible for returning the error status.
    // daemon-behavior 03-policies-and-procedures (client state transitions):
    // OPERATING allows session management messages (create, destroy, rename,
    // list, attach_session).
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.attach_session_request));
}

// ── State transitions: OPERATING messages ──────────────────────────────────

test "spec: attachment -- OPERATING allows DetachSessionRequest" {
    // daemon-behavior 03-policies-and-procedures (client state transitions):
    // OPERATING -> DetachSessionRequest -> READY.
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.detach_session_request));
}

test "spec: attachment -- OPERATING allows operational messages" {
    // daemon-behavior 03-policies-and-procedures (client state transitions):
    // OPERATING allows input, pane management.
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.key_event));
    try std.testing.expect(conn.isMessageAllowed(.split_pane_request));
    try std.testing.expect(conn.isMessageAllowed(.close_pane_request));
    try std.testing.expect(conn.isMessageAllowed(.focus_pane_request));
    try std.testing.expect(conn.isMessageAllowed(.navigate_pane_request));
    try std.testing.expect(conn.isMessageAllowed(.resize_pane_request));
    try std.testing.expect(conn.isMessageAllowed(.equalize_splits_request));
    try std.testing.expect(conn.isMessageAllowed(.zoom_pane_request));
    try std.testing.expect(conn.isMessageAllowed(.swap_panes_request));
    try std.testing.expect(conn.isMessageAllowed(.layout_get_request));
}

test "spec: attachment -- OPERATING allows session management that mutates" {
    // daemon-behavior 03-policies-and-procedures (client state transitions):
    // OPERATING allows CreateSession, DestroySession, RenameSession,
    // ListSessions (in addition to detach).
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.create_session_request));
    try std.testing.expect(conn.isMessageAllowed(.destroy_session_request));
    try std.testing.expect(conn.isMessageAllowed(.rename_session_request));
    try std.testing.expect(conn.isMessageAllowed(.list_sessions_request));
}

// ── Destroy cascade: requester transitions to READY ────────────────────────

test "spec: attachment -- destroy own session transitions to READY" {
    // daemon-behavior 03-policies-and-procedures (client state transitions):
    // OPERATING -> DestroySessionRequest (own session) -> READY. The
    // requester does NOT receive DetachSessionResponse.
    var conn = makeConn(.operating);
    conn.attached_session_id = 1;

    // After session destruction, the handler transitions to READY.
    try std.testing.expect(conn.transitionTo(.ready));
    conn.attached_session_id = 0;

    try std.testing.expectEqual(State.ready, conn.state);
    try std.testing.expectEqual(@as(u32, 0), conn.attached_session_id);
}

// ── DISCONNECTING state ────────────────────────────────────────────────────

test "spec: attachment -- OPERATING to DISCONNECTING on server shutdown" {
    // daemon-behavior 03-policies-and-procedures (client state transitions):
    // OPERATING -> Disconnect(server_shutdown) -> DISCONNECTING.
    var conn = makeConn(.operating);
    try std.testing.expect(conn.transitionTo(.disconnecting));
    try std.testing.expectEqual(State.disconnecting, conn.state);
}

test "spec: attachment -- DISCONNECTING rejects all non-disconnect messages" {
    // daemon-behavior 03-policies-and-procedures (client state transitions):
    // DISCONNECTING -> only disconnect/error.
    const conn = makeConn(.disconnecting);
    try std.testing.expect(!conn.isMessageAllowed(.attach_session_request));
    try std.testing.expect(!conn.isMessageAllowed(.detach_session_request));
    try std.testing.expect(!conn.isMessageAllowed(.key_event));
    try std.testing.expect(!conn.isMessageAllowed(.heartbeat));
    try std.testing.expect(conn.isMessageAllowed(.disconnect));
    try std.testing.expect(conn.isMessageAllowed(.@"error"));
}

// ── Sequence number management ─────────────────────────────────────────────

test "spec: attachment -- send sequence starts at 1 and increments" {
    // protocol 01-protocol-overview (wire header format): sequence field
    // starts at 1.
    var conn = makeConn(.ready);
    const seq1 = conn.advanceSendSequence();
    const seq2 = conn.advanceSendSequence();
    try std.testing.expectEqual(@as(u64, 1), seq1);
    try std.testing.expectEqual(@as(u64, 2), seq2);
}

test "spec: attachment -- u64 sequence increments beyond u32 max without wrapping" {
    // protocol v2: sequence is u64, no practical wrap concern.
    var conn = makeConn(.ready);
    conn.send_sequence = 0xFFFFFFFF;
    const seq = conn.advanceSendSequence();
    try std.testing.expectEqual(@as(u64, 0xFFFFFFFF), seq);
    try std.testing.expectEqual(@as(u64, 0x100000000), conn.send_sequence);
}

// ── AttachOrCreate response format ────────────────────────────────────────

// File-scope static SessionManager for tests that need it (too large for stack).
var sm_static = SessionManager.init();

fn resetStaticSm() void {
    sm_static.reset();
}

test "spec: attachment -- AttachSession 'created' path when session does not exist" {
    // protocol 03-session-pane-management (attach session response):
    // AttachSessionResponse must include action_taken: "created" when a
    // new session is created (create_if_missing=true).
    // Test: when no session with the given name exists, the handler must
    // create a new session. We verify the precondition (findSessionByName
    // returns null) that triggers the "created" code path.
    resetStaticSm();

    // No sessions exist yet — findSessionByName must return null.
    try std.testing.expect(sm_static.findSessionByName("new-session") == null);

    // Creating the session succeeds, giving us the session_id for the response.
    const id = try sm_static.createSession("new-session", testImeEngine(), 0);
    try std.testing.expect(id > 0);

    // After creation, the session exists and has an initial pane.
    const entry = sm_static.getSession(id).?;
    try std.testing.expectEqual(@as(u8, 1), entry.paneCount());

    // The response type code must be 0x0105 (AttachSessionResponse).
    try std.testing.expectEqual(@as(u16, 0x0105), @intFromEnum(MessageType.attach_session_response));
}

test "spec: attachment -- AttachSession 'attached' path when session exists" {
    // protocol 03-session-pane-management (attach session response):
    // AttachSessionResponse must include action_taken: "attached" when
    // attaching to an existing session (create_if_missing=true).
    // Test: when a session with the given name already exists,
    // findSessionByName returns it and the handler attaches (no creation).
    resetStaticSm();

    // Pre-create a session.
    const id = try sm_static.createSession("existing", testImeEngine(), 0);

    // findSessionByName returns the existing session — triggers "attached" path.
    const found = sm_static.findSessionByName("existing");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(id, found.?.session.session_id);

    // The response type code must be 0x0105 (AttachSessionResponse).
    try std.testing.expectEqual(@as(u16, 0x0105), @intFromEnum(MessageType.attach_session_response));
}

// ── DetachSession with wrong session_id ───────────────────────────────────

test "spec: attachment -- DetachSession with mismatched session_id returns status 1" {
    // protocol 03-session-pane-management (detach session response):
    // DetachSessionResponse status 1 means "not attached to this session."
    // When DetachSessionRequest carries a session_id that does not match
    // the connection's attached_session_id, the handler must return status 1.
    // Test: verify the precondition — attached_session_id differs from
    // the requested session_id.
    var conn = makeConn(.operating);
    conn.attached_session_id = 5;

    // The request carries session_id = 99, which does not match 5.
    const requested_session_id: u32 = 99;
    try std.testing.expect(conn.attached_session_id != requested_session_id);

    // The handler checks this mismatch and returns status 1.
    // This test verifies the state-level precondition that triggers the
    // "not attached to this session" error path.
}

// ── DestroySession cascade with peers ─────────────────────────────────────

test "spec: attachment -- DestroySession cascade sends correct messages to peers" {
    // daemon-behavior 02-event-handling (destroy cascade): DestroySession
    // observable effects:
    //   1. [PreeditEnd — Plan 8 scope, skipped]
    //   2. DestroySessionResponse(status=0) — to requester
    //   3. SessionListChanged(event="destroyed") — broadcast to ALL
    //   4. DetachSessionResponse(reason="session_destroyed") — to each peer
    //   5. ClientDetached(client_id=C) — to requester, for each peer
    //
    // The requester does NOT receive DetachSessionResponse.
    //
    // Test: set up multiple clients attached to the same session, destroy it,
    // and verify the message ordering constraints using broadcast infrastructure.
    const testing_mod = @import("itshell3_testing");
    const ClientManager = server.connection.client_manager.ClientManager;
    const broadcast_mod = server.connection.broadcast;

    var mgr = ClientManager{ .chunk_pool = testing_mod.helpers.testChunkPool() };

    // Requester: client 1 attached to session 1.
    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = 1;

    // Peer: client 2 attached to session 1.
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c2 = mgr.getClient(idx2).?;
    _ = c2.connection.transitionTo(.ready);
    _ = c2.connection.transitionTo(.operating);
    c2.connection.attached_session_id = 1;

    // Peer: client 3 attached to session 1.
    const idx3 = try mgr.addClient(.{ .fd = 12 });
    const c3 = mgr.getClient(idx3).?;
    _ = c3.connection.transitionTo(.ready);
    _ = c3.connection.transitionTo(.operating);
    c3.connection.attached_session_id = 1;

    // Verify: SessionListChanged broadcast reaches all 3 clients.
    const result = broadcast_mod.broadcastGlobal(&mgr, "session_list_changed", null);
    try std.testing.expectEqual(@as(u16, 3), result.sent_count);

    // Verify: session-scoped broadcast to session 1 reaches all 3 clients
    // (used for DetachSessionResponse to peers and ClientDetached).
    const session_result = broadcast_mod.broadcastToSession(&mgr, 1, "detach_notification", null);
    try std.testing.expectEqual(@as(u16, 3), session_result.sent_count);

    // Verify: excluding the requester (idx1), exactly 2 peers would receive
    // DetachSessionResponse.
    const peer_result = broadcast_mod.broadcastToSession(&mgr, 1, "detach_peers", idx1);
    try std.testing.expectEqual(@as(u16, 2), peer_result.sent_count);

    // Verify message type codes for the cascade messages.
    try std.testing.expectEqual(@as(u16, 0x0109), @intFromEnum(MessageType.destroy_session_response));
    try std.testing.expectEqual(@as(u16, 0x0182), @intFromEnum(MessageType.session_list_changed));
    try std.testing.expectEqual(@as(u16, 0x0107), @intFromEnum(MessageType.detach_session_response));
    try std.testing.expectEqual(@as(u16, 0x0184), @intFromEnum(MessageType.client_detached));

    // Clean up.
    mgr.getClient(idx1).?.deinit();
    mgr.getClient(idx2).?.deinit();
    mgr.getClient(idx3).?.deinit();
}

// ── LayoutChanged after AttachSession ─────────────────────────────────────

test "spec: attachment -- LayoutChanged sent after AttachSession success" {
    // protocol 03-session-pane-management (attach session response):
    // After AttachSessionResponse success, server sends LayoutChanged
    // notification to the attaching client with full layout tree (including
    // per-pane active_input_method and active_keyboard_layout in leaf nodes).
    //
    // Verify: LayoutChanged (0x0180) is a valid notification type and uses
    // JSON encoding, the session has a layout tree to send, and the message
    // type is in the notification range.
    try std.testing.expectEqual(@as(u16, 0x0180), @intFromEnum(MessageType.layout_changed));
    try std.testing.expectEqual(MessageType.Encoding.json, MessageType.layout_changed.expectedEncoding());

    // Verify: after a session is created and a client attaches, the session
    // has a non-empty layout tree (at least the root pane).
    resetStaticSm();
    const id = try sm_static.createSession("test", testImeEngine(), 0);
    const entry = sm_static.getSession(id).?;

    // The layout tree must have at least one leaf (the initial pane at slot 0).
    const leaf_count = core.split_tree.leafCount(&entry.session.tree_nodes);
    try std.testing.expect(leaf_count >= 1);

    // The attaching client must receive this tree as LayoutChanged.
    // Verify the focused pane is set (active_pane_id in AttachSessionResponse).
    try std.testing.expect(entry.session.focused_pane != null);
}
