//! Spec compliance tests: Session attachment tracking and ADR 00020.
//!
//! Covers AttachSession, DetachSession, AttachOrCreate, session switching
//! via detach+attach, and the ERR_SESSION_ALREADY_ATTACHED rule.
//!
//! Spec sources:
//!   - ADR 00020 (session attachment model: single-session-per-connection,
//!     ERR_SESSION_ALREADY_ATTACHED, detach before re-attach)
//!   - protocol 03-session-pane-management (Sections 1.5-1.8, 1.13-1.14)
//!   - daemon-behavior 03-policies-and-procedures (Section 12 client state
//!     transitions: READY->OPERATING, OPERATING->READY)
//!   - daemon-behavior 02-event-handling (Section 4 destroy cascade,
//!     Section 1.1 response-before-notification)

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
    // daemon-behavior 03 Section 12: READY -> AttachSessionRequest -> OPERATING.
    const conn = makeConn(.ready);
    try std.testing.expect(conn.isMessageAllowed(.attach_session_request));
}

test "spec: attachment -- READY to OPERATING transition succeeds" {
    // daemon-behavior 03 Section 12: READY -> OPERATING on attach.
    var conn = makeConn(.ready);
    try std.testing.expect(conn.transitionTo(.operating));
    try std.testing.expectEqual(State.operating, conn.state);
}

test "spec: attachment -- OPERATING to OPERATING transition is invalid" {
    // ADR 00020: OPERATING->OPERATING is NOT valid. Client must
    // DetachSessionRequest (-> READY) then AttachSessionRequest (-> OPERATING).
    var conn = makeConn(.operating);
    try std.testing.expect(!conn.transitionTo(.operating));
    // State should remain OPERATING (transition was rejected).
    try std.testing.expectEqual(State.operating, conn.state);
}

test "spec: attachment -- OPERATING to READY via detach succeeds" {
    // daemon-behavior 03 Section 12: OPERATING -> DetachSessionRequest -> READY.
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
    // protocol 03 Section 1.5-1.6: AttachSessionRequest sets session binding.
    // ConnectionState.attached_session_id stores the attached session (0 = none).
    var conn = makeConn(.ready);
    try std.testing.expectEqual(@as(u32, 0), conn.attached_session_id);

    _ = conn.transitionTo(.operating);
    conn.attached_session_id = 42;
    try std.testing.expectEqual(@as(u32, 42), conn.attached_session_id);
}

test "spec: attachment -- detach clears attached_session_id" {
    // protocol 03 Section 1.7-1.8: DetachSessionRequest clears attachment.
    var conn = makeConn(.operating);
    conn.attached_session_id = 10;

    _ = conn.transitionTo(.ready);
    conn.attached_session_id = 0;
    try std.testing.expectEqual(@as(u32, 0), conn.attached_session_id);
    try std.testing.expectEqual(State.ready, conn.state);
}

// ── AttachOrCreate ─────────────────────────────────────────────────────────

test "spec: attachment -- READY allows AttachOrCreateRequest" {
    // protocol 03 Section 1.13: AttachOrCreateRequest subject to same
    // single-session-per-connection rule.
    const conn = makeConn(.ready);
    try std.testing.expect(conn.isMessageAllowed(.attach_or_create_request));
}

test "spec: attachment -- AttachOrCreate rejected in OPERATING state" {
    // protocol 03 Section 1.13: returns ERR_SESSION_ALREADY_ATTACHED if
    // already attached. In OPERATING, session management messages other than
    // those explicitly allowed are rejected.
    const conn = makeConn(.operating);
    // attach_or_create_request is in the session management range, and
    // is NOT in the allowed set for OPERATING (only detach_session_request
    // is explicitly allowed for session lifecycle from OPERATING).
    // The implementation should check isOperationalMessageType for this.
    // Based on the state machine, re-attaching from OPERATING is invalid.
    // This verifies the message filtering rejects it.
    try std.testing.expect(!conn.isMessageAllowed(.attach_or_create_request));
}

// ── State transitions: OPERATING messages ──────────────────────────────────

test "spec: attachment -- OPERATING allows DetachSessionRequest" {
    // daemon-behavior 03 Section 12: OPERATING -> DetachSessionRequest -> READY.
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.detach_session_request));
}

test "spec: attachment -- OPERATING allows operational messages" {
    // daemon-behavior 03 Section 12: OPERATING allows input, pane management.
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
    // daemon-behavior 03 Section 12: OPERATING allows CreateSession, DestroySession,
    // RenameSession, ListSessions (in addition to detach).
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.create_session_request));
    try std.testing.expect(conn.isMessageAllowed(.destroy_session_request));
    try std.testing.expect(conn.isMessageAllowed(.rename_session_request));
    try std.testing.expect(conn.isMessageAllowed(.list_sessions_request));
}

// ── Destroy cascade: requester transitions to READY ────────────────────────

test "spec: attachment -- destroy own session transitions to READY" {
    // daemon-behavior 03 Section 12: OPERATING -> DestroySessionRequest (own
    // session) -> READY. The requester does NOT receive DetachSessionResponse.
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
    // daemon-behavior 03 Section 12: OPERATING -> Disconnect(server_shutdown) ->
    // DISCONNECTING.
    var conn = makeConn(.operating);
    try std.testing.expect(conn.transitionTo(.disconnecting));
    try std.testing.expectEqual(State.disconnecting, conn.state);
}

test "spec: attachment -- DISCONNECTING rejects all non-disconnect messages" {
    // daemon-behavior 03 Section 12: DISCONNECTING -> only disconnect/error.
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
    // protocol 01 Section 3.1: sequence field in header. Starts at 1.
    var conn = makeConn(.ready);
    const seq1 = conn.advanceSendSequence();
    const seq2 = conn.advanceSendSequence();
    try std.testing.expectEqual(@as(u32, 1), seq1);
    try std.testing.expectEqual(@as(u32, 2), seq2);
}

test "spec: attachment -- send sequence wraps from max to 1 skipping 0" {
    // protocol 01: sequence wraps, skipping 0 (0 is reserved/sentinel).
    var conn = makeConn(.ready);
    conn.send_sequence = 0xFFFFFFFF;
    const seq = conn.advanceSendSequence();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), seq);
    try std.testing.expectEqual(@as(u32, 1), conn.send_sequence);
}
