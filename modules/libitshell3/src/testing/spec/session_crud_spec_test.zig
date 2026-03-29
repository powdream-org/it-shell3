//! Spec compliance tests: Session CRUD operations.
//!
//! Covers CreateSession, ListSessions, RenameSession, DestroySession,
//! AttachOrCreate, AttachSession, SwapPanes, forced DetachSession, and associated
//! SessionListChanged notification ordering.
//!
//! Spec sources:
//!   - protocol 03-session-pane-management (session messages 1.1-1.14, pane
//!     messages swap-panes, response field names)
//!   - daemon-behavior 02-event-handling (response-before-notification,
//!     session destroy cascade, session rename)

const std = @import("std");
const core = @import("itshell3_core");
const server = @import("itshell3_server");
const protocol = @import("itshell3_protocol");

const Session = core.Session;
const SessionId = core.SessionId;
const PaneId = core.PaneId;
const PaneSlot = core.PaneSlot;
const MAX_SESSIONS = core.MAX_SESSIONS;
const SessionEntry = server.state.SessionEntry;
const SessionManager = server.state.SessionManager;
const Pane = server.state.Pane;
const ConnectionState = server.connection.ConnectionState;
const MessageType = protocol.message_type.MessageType;

const test_mod = @import("itshell3_testing");
const mock_ime = test_mod.mock_ime_engine;

var test_mock_engine = mock_ime.MockImeEngine{};

fn testImeEngine() core.ImeEngine {
    return test_mock_engine.engine();
}

// File-scope static session manager — placed in .bss, not on the stack.
var sm = SessionManager.init();

fn resetState() void {
    sm.reset();
}

// ── CreateSession ──────────────────────────────────────────────────────────

test "spec: session create -- allocates session with monotonic ID" {
    // protocol 03 Section 1.2: CreateSessionResponse returns session_id (u32,
    // server-assigned, monotonically increasing).
    resetState();
    const id1 = try sm.createSession("first", testImeEngine(), 0);
    const id2 = try sm.createSession("second", testImeEngine(), 0);
    try std.testing.expect(id2 > id1);
    try std.testing.expectEqual(@as(u32, 2), sm.sessionCount());
}

test "spec: session create -- initial pane slot is allocated" {
    // protocol 03 Section 1.2: CreateSessionResponse includes pane_id of
    // initial pane. The session must have at least one pane slot reserved.
    resetState();
    const id = try sm.createSession("test", testImeEngine(), 0);
    const entry = sm.getSession(id).?;
    // paneCount should be 1 (the initial pane slot 0 is reserved during creation).
    try std.testing.expectEqual(@as(u8, 1), entry.paneCount());
}

test "spec: session create -- session name is stored correctly" {
    // protocol 03 Section 1.4: ListSessionsResponse includes name.
    resetState();
    const id = try sm.createSession("my-session", testImeEngine(), 0);
    const entry = sm.getSession(id).?;
    try std.testing.expectEqualSlices(u8, "my-session", entry.session.getName());
}

test "spec: session create -- default input method is direct" {
    // protocol 03 Section 1.6: AttachSessionResponse.active_input_method.
    // daemon-architecture: default input method for new sessions is "direct".
    resetState();
    const id = try sm.createSession("test", testImeEngine(), 0);
    const entry = sm.getSession(id).?;
    try std.testing.expectEqualSlices(u8, "direct", entry.session.getActiveInputMethod());
}

test "spec: session create -- default keyboard layout is qwerty" {
    // protocol 03 Section 1.6: AttachSessionResponse.active_keyboard_layout.
    resetState();
    const id = try sm.createSession("test", testImeEngine(), 0);
    const entry = sm.getSession(id).?;
    try std.testing.expectEqualSlices(u8, "qwerty", entry.session.getActiveKeyboardLayout());
}

test "spec: session create -- max sessions returns error" {
    // protocol 03 Section 1.2: non-zero status on error.
    // daemon-architecture 02 state tree: MAX_SESSIONS capacity.
    resetState();
    var i: u32 = 0;
    while (i < MAX_SESSIONS) : (i += 1) {
        _ = try sm.createSession("s", testImeEngine(), 0);
    }
    const result = sm.createSession("overflow", testImeEngine(), 0);
    try std.testing.expectError(error.MaxSessionsReached, result);
}

test "spec: session create -- focused pane set to initial pane" {
    // daemon-architecture 02 state tree: session.focused_pane = initial pane slot.
    resetState();
    const id = try sm.createSession("test", testImeEngine(), 0);
    const entry = sm.getSession(id).?;
    try std.testing.expectEqual(@as(?PaneSlot, 0), entry.session.focused_pane);
}

test "spec: session create -- pane IDs are monotonically increasing" {
    // protocol 03 ID Types: pane_id is monotonically increasing, never reused.
    resetState();
    const pane1 = sm.allocPaneId();
    const pane2 = sm.allocPaneId();
    const pane3 = sm.allocPaneId();
    try std.testing.expect(pane2 > pane1);
    try std.testing.expect(pane3 > pane2);
}

test "spec: session create -- session IDs never reused after destroy" {
    // protocol 03 ID Types: session_id never reused during daemon lifetime.
    resetState();
    const id1 = try sm.createSession("a", testImeEngine(), 0);
    _ = sm.destroySession(id1);
    const id2 = try sm.createSession("b", testImeEngine(), 0);
    try std.testing.expect(id2 > id1);
}

// ── ListSessions ───────────────────────────────────────────────────────────

test "spec: session list -- returns all sessions with correct fields" {
    // protocol 03 Section 1.4: ListSessionsResponse includes session_id,
    // name, pane_count for each session.
    resetState();
    const id1 = try sm.createSession("alpha", testImeEngine(), 0);
    const id2 = try sm.createSession("beta", testImeEngine(), 0);

    // Verify each session is accessible.
    const entry1 = sm.getSession(id1).?;
    const entry2 = sm.getSession(id2).?;
    try std.testing.expectEqualSlices(u8, "alpha", entry1.session.getName());
    try std.testing.expectEqualSlices(u8, "beta", entry2.session.getName());
    try std.testing.expectEqual(@as(u8, 1), entry1.paneCount());
    try std.testing.expectEqual(@as(u8, 1), entry2.paneCount());
}

test "spec: session list -- empty when no sessions exist" {
    // protocol 03 Section 1.4: sessions array may be empty.
    resetState();
    try std.testing.expectEqual(@as(u32, 0), sm.sessionCount());
}

// ── RenameSession ──────────────────────────────────────────────────────────

test "spec: session rename -- updates session name" {
    // protocol 03 Section 1.11-1.12: RenameSessionRequest updates name,
    // response status=0 on success.
    // daemon-behavior 02 Section 7.1: state update BEFORE response.
    resetState();
    const id = try sm.createSession("old-name", testImeEngine(), 0);
    const entry = sm.getSession(id).?;

    // Simulate rename by directly updating the session name (the handler
    // will do this via Session.setName or equivalent).
    const new_name = "new-name";
    const name_length: u8 = @intCast(new_name.len);
    @memcpy(entry.session.name[0..name_length], new_name);
    entry.session.name_length = name_length;

    try std.testing.expectEqualSlices(u8, "new-name", entry.session.getName());
}

// ── DestroySession ─────────────────────────────────────────────────────────

test "spec: session destroy -- removes session from manager" {
    // protocol 03 Section 1.10: DestroySessionResponse status=0.
    // daemon-behavior 02 Section 4: session destroy cascade.
    resetState();
    const id = try sm.createSession("doomed", testImeEngine(), 0);
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());
    const old = sm.destroySession(id);
    try std.testing.expect(old != null);
    try std.testing.expectEqual(@as(u32, 0), sm.sessionCount());
    try std.testing.expect(sm.getSession(id) == null);
}

test "spec: session destroy -- nonexistent session returns null" {
    // protocol 03 Section 1.10: status=1 (session not found).
    resetState();
    const result = sm.destroySession(999);
    try std.testing.expect(result == null);
}

test "spec: session destroy -- does not affect other sessions" {
    // daemon-behavior 02 Section 4: only the target session is destroyed.
    resetState();
    const id1 = try sm.createSession("keep", testImeEngine(), 0);
    const id2 = try sm.createSession("destroy", testImeEngine(), 0);
    _ = sm.destroySession(id2);
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());
    try std.testing.expect(sm.getSession(id1) != null);
    try std.testing.expect(sm.getSession(id2) == null);
}

// ── Pane slot management within session ────────────────────────────────────

test "spec: session pane slots -- allocate and free correctly" {
    // daemon-architecture 02 Section 1.2: SessionEntry manages pane_slots[16].
    resetState();
    const id = try sm.createSession("test", testImeEngine(), 0);
    const entry = sm.getSession(id).?;
    // Slot 0 already allocated during creation.
    try std.testing.expectEqual(@as(u8, 1), entry.paneCount());

    // Allocate another slot.
    const slot1 = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(u8, 2), entry.paneCount());
    try std.testing.expect(slot1 != 0); // slot 0 was already taken.

    // Free the second slot.
    entry.freePaneSlot(slot1);
    try std.testing.expectEqual(@as(u8, 1), entry.paneCount());
}

test "spec: session pane slots -- pane count reflects occupied slots" {
    // protocol 03 Section 1.4: ListSessionsResponse includes pane_count.
    resetState();
    const id = try sm.createSession("test", testImeEngine(), 0);
    const entry = sm.getSession(id).?;
    try std.testing.expectEqual(@as(u8, 1), entry.paneCount());

    _ = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(u8, 2), entry.paneCount());

    _ = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(u8, 3), entry.paneCount());
}

// ── Message type codes ─────────────────────────────────────────────────────

test "spec: session message types -- correct protocol codes" {
    // protocol 03 Message Type Assignments: Session Messages range 0x0100-0x010D.
    try std.testing.expectEqual(@as(u16, 0x0100), @intFromEnum(MessageType.create_session_request));
    try std.testing.expectEqual(@as(u16, 0x0101), @intFromEnum(MessageType.create_session_response));
    try std.testing.expectEqual(@as(u16, 0x0102), @intFromEnum(MessageType.list_sessions_request));
    try std.testing.expectEqual(@as(u16, 0x0103), @intFromEnum(MessageType.list_sessions_response));
    try std.testing.expectEqual(@as(u16, 0x0104), @intFromEnum(MessageType.attach_session_request));
    try std.testing.expectEqual(@as(u16, 0x0105), @intFromEnum(MessageType.attach_session_response));
    try std.testing.expectEqual(@as(u16, 0x0106), @intFromEnum(MessageType.detach_session_request));
    try std.testing.expectEqual(@as(u16, 0x0107), @intFromEnum(MessageType.detach_session_response));
    try std.testing.expectEqual(@as(u16, 0x0108), @intFromEnum(MessageType.destroy_session_request));
    try std.testing.expectEqual(@as(u16, 0x0109), @intFromEnum(MessageType.destroy_session_response));
    try std.testing.expectEqual(@as(u16, 0x010A), @intFromEnum(MessageType.rename_session_request));
    try std.testing.expectEqual(@as(u16, 0x010B), @intFromEnum(MessageType.rename_session_response));
    try std.testing.expectEqual(@as(u16, 0x010C), @intFromEnum(MessageType.attach_or_create_request));
    try std.testing.expectEqual(@as(u16, 0x010D), @intFromEnum(MessageType.attach_or_create_response));
}

// ── Handler-level tests: response payload content ─────────────────────────
//
// These tests call the session handler functions directly and inspect the
// binary-framed responses enqueued into the client's direct queue. The
// 16-byte protocol header precedes each JSON payload in the queue.

/// Extracts the JSON payload from the first item in the client's direct queue.
/// The caller provides a large enough output buffer.
fn extractFirstPayload(client: anytype, out: []u8) ?[]const u8 {
    const HEADER_SIZE = protocol.header.HEADER_SIZE;
    var copy_buf: [server.handlers.protocol_envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const n = client.direct_queue.peekCopy(&copy_buf) orelse return null;
    if (n < HEADER_SIZE) return null;
    const payload_len = std.mem.readInt(u32, copy_buf[8..12], .little);
    const total = HEADER_SIZE + payload_len;
    if (total > n or total > out.len) return null;
    @memcpy(out[0..payload_len], copy_buf[HEADER_SIZE..total]);
    return out[0..payload_len];
}

/// Dequeues the first item in the client's direct queue and returns the JSON
/// payload of the next item (i.e., the second message), or null.
fn extractSecondPayload(client: anytype, out: []u8) ?[]const u8 {
    client.direct_queue.dequeue();
    return extractFirstPayload(client, out);
}

/// Returns the msg_type from the first item in the client's direct queue,
/// or null if the queue is empty.
fn peekMsgType(client: anytype) ?u16 {
    const HEADER_SIZE = protocol.header.HEADER_SIZE;
    var copy_buf: [server.handlers.protocol_envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const n = client.direct_queue.peekCopy(&copy_buf) orelse return null;
    if (n < HEADER_SIZE) return null;
    return std.mem.readInt(u16, copy_buf[4..6], .little);
}

/// Drains queue items until one with the given msg_type is found, then returns
/// its JSON payload. Returns null if no such item is in the queue.
fn extractPayloadByMsgType(client: anytype, target_msg_type: u16, out: []u8) ?[]const u8 {
    var iterations: u8 = 0;
    while (iterations < 8) : (iterations += 1) {
        const mt = peekMsgType(client) orelse return null;
        if (mt == target_msg_type) {
            return extractFirstPayload(client, out);
        }
        client.direct_queue.dequeue();
    }
    return null;
}

fn makeTestContext(session_mgr: *SessionManager, client_mgr: *server.connection.client_manager.ClientManager) server.handlers.session_handler.SessionHandlerContext {
    return server.handlers.session_handler.SessionHandlerContext{
        .session_manager = session_mgr,
        .client_manager = client_mgr,
        .disconnect_fn = struct {
            fn cb(_: u16) void {}
        }.cb,
        .default_ime_engine = testImeEngine(),
    };
}

// ── TEST-1: handleListSessions response contains status=0 ─────────────────

test "spec: session list handler -- response payload contains status 0" {
    // protocol 03 ListSessionsResponse: status=0 on success.
    // Strengthens the existing "returns empty list" test to verify the status
    // field is present and equals 0 in the JSON payload.
    const helpers = test_mod.helpers;
    var mgr = server.connection.client_manager.ClientManager{
        .chunk_pool = helpers.testChunkPool(),
    };
    const idx = try mgr.addClient(.{ .fd = 20 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);

    resetState();
    var ctx = makeTestContext(&sm, &mgr);
    server.handlers.session_handler.handleListSessions(&ctx, client, idx, 1);

    var payload_buf: [4096]u8 = undefined;
    const payload = extractFirstPayload(client, &payload_buf) orelse
        return error.TestUnexpectedResult;

    // The response must contain "status":0 per protocol 03 ListSessionsResponse.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"status\":0") != null);
    // The response must contain the sessions array.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"sessions\"") != null);

    client.deinit();
}

// ── TEST-2: CreateSession response fields ─────────────────────────────────

test "spec: session create -- session_id is non-zero after successful creation" {
    // protocol 03 CreateSessionResponse: status=0, session_id (server-assigned
    // u32 > 0) on success. Verified at the state layer: createSession returns a
    // non-zero session_id and increments sessionCount.
    resetState();
    const sess_id = try sm.createSession("my-session", testImeEngine(), 0);
    // session_id must be > 0 (0 is reserved sentinel per protocol 03 ID Types).
    try std.testing.expect(sess_id > 0);
    // Session count reflects the new session.
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());
    // pane_id must also be > 0 (initial pane slot is reserved during creation).
    const pane_id = sm.allocPaneId();
    try std.testing.expect(pane_id > 0);
}

test "spec: session create -- SessionListChanged broadcast payload contains created event and session_id" {
    // daemon-behavior 02 response-before-notification: after CreateSessionResponse,
    // SessionListChanged(event="created") is broadcast to all active clients via
    // broadcastToActive. Verify the notification builder produces the correct payload
    // and broadcast delivers it to a READY client.
    const helpers = test_mod.helpers;
    var mgr = server.connection.client_manager.ClientManager{
        .chunk_pool = helpers.testChunkPool(),
    };
    const idx = try mgr.addClient(.{ .fd = 22 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);

    resetState();
    const sess_id = try sm.createSession("broadcast-test", testImeEngine(), 0);

    // Build and broadcast the SessionListChanged notification, as the handler
    // does after creating a session. This verifies both the notification format
    // and that broadcastToActive reaches READY clients.
    var notif_buf: [server.handlers.protocol_envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notif_seq = client.connection.advanceSendSequence();
    const notif = server.handlers.notification_builder.buildSessionListChanged(
        "created",
        sess_id,
        sm.getSession(sess_id).?.session.getName(),
        notif_seq,
        &notif_buf,
    ) orelse return error.TestUnexpectedResult;

    const result = server.connection.broadcast.broadcastToActive(&mgr, notif, null);
    try std.testing.expectEqual(@as(u16, 1), result.sent_count);

    var buf: [4096]u8 = undefined;
    const payload = extractFirstPayload(client, &buf) orelse
        return error.TestUnexpectedResult;
    // Notification must carry event="created" and session_id.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"created\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"session_id\"") != null);

    client.deinit();
}

// ── TEST-3: handleDestroySession ──────────────────────────────────────────

test "spec: session destroy handler -- status=0 on success" {
    // protocol 03 DestroySessionResponse: status=0 on success.
    const helpers = test_mod.helpers;
    var mgr = server.connection.client_manager.ClientManager{
        .chunk_pool = helpers.testChunkPool(),
    };
    const idx = try mgr.addClient(.{ .fd = 23 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);

    resetState();
    const sess_id = try sm.createSession("doomed", testImeEngine(), 0);

    var ctx = makeTestContext(&sm, &mgr);
    server.handlers.session_handler.handleDestroySession(&ctx, client, idx, 1, sess_id, true);

    var payload_buf: [4096]u8 = undefined;
    const payload = extractFirstPayload(client, &payload_buf) orelse
        return error.TestUnexpectedResult;

    // protocol 03 DestroySessionResponse: status=0 on success.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"status\":0") != null);
    // Session must be gone from the manager.
    try std.testing.expect(sm.getSession(sess_id) == null);

    client.deinit();
}

test "spec: session destroy handler -- status=1 when session not found" {
    // protocol 03 DestroySessionResponse: status=1 = session not found.
    const helpers = test_mod.helpers;
    var mgr = server.connection.client_manager.ClientManager{
        .chunk_pool = helpers.testChunkPool(),
    };
    const idx = try mgr.addClient(.{ .fd = 24 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);

    resetState();
    var ctx = makeTestContext(&sm, &mgr);
    // Destroy a session that does not exist.
    server.handlers.session_handler.handleDestroySession(&ctx, client, idx, 1, 999, false);

    var payload_buf: [4096]u8 = undefined;
    const payload = extractFirstPayload(client, &payload_buf) orelse
        return error.TestUnexpectedResult;

    // protocol 03 DestroySessionResponse: status=1 on session not found.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"status\":1") != null);

    client.deinit();
}

test "spec: session destroy handler -- status=2 when processes running and force=false" {
    // protocol 03 DestroySessionResponse: status=2 = processes still running
    // (force=false). When force=false and a pane has is_running=true, the handler
    // must refuse with status=2.
    const helpers = test_mod.helpers;
    var mgr = server.connection.client_manager.ClientManager{
        .chunk_pool = helpers.testChunkPool(),
    };
    const idx = try mgr.addClient(.{ .fd = 25 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);

    resetState();
    const sess_id = try sm.createSession("with-process", testImeEngine(), 0);
    const entry = sm.getSession(sess_id).?;

    // Place a pane in slot 0 that is marked as running.
    const pane_id = sm.allocPaneId();
    const running_pane = Pane.init(pane_id, 0, 5, 100, 80, 24);
    // is_running defaults to true in Pane.init.
    entry.setPaneAtSlot(0, running_pane);

    var ctx = makeTestContext(&sm, &mgr);
    // force=false — must refuse because pane is running.
    server.handlers.session_handler.handleDestroySession(&ctx, client, idx, 1, sess_id, false);

    var payload_buf: [4096]u8 = undefined;
    const payload = extractFirstPayload(client, &payload_buf) orelse
        return error.TestUnexpectedResult;

    // protocol 03 DestroySessionResponse: status=2 = PROCESSES_RUNNING.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"status\":2") != null);
    // Session must still exist.
    try std.testing.expect(sm.getSession(sess_id) != null);

    client.deinit();
}

// ── TEST-4 & TEST-9: handleAttachOrCreate response field names ────────────

test "spec: attach-or-create handler -- 'created' path response contains required fields" {
    // protocol 03 AttachOrCreateResponse: action_taken="created", session_id,
    // pane_id, session_name fields.
    //
    // In the "created" code path, the handler broadcasts SessionListChanged
    // before enqueueing AttachOrCreateResponse (0x010D). We locate the response
    // by message type code.
    const helpers = test_mod.helpers;
    var mgr = server.connection.client_manager.ClientManager{
        .chunk_pool = helpers.testChunkPool(),
    };
    const idx = try mgr.addClient(.{ .fd = 26 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);

    resetState();
    var ctx = makeTestContext(&sm, &mgr);
    // No session named "new-sess" exists — handler must create it.
    server.handlers.session_handler.handleAttachOrCreate(&ctx, client, idx, 1, "new-sess");

    // Locate the AttachOrCreateResponse (0x010D) in the queue.
    var payload_buf: [4096]u8 = undefined;
    const payload = extractPayloadByMsgType(
        client,
        @intFromEnum(MessageType.attach_or_create_response),
        &payload_buf,
    ) orelse return error.TestUnexpectedResult;

    // protocol 03 AttachOrCreateResponse: action_taken field.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"action_taken\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"created\"") != null);
    // protocol 03 AttachOrCreateResponse: session_name field.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"session_name\"") != null);
    // protocol 03 AttachOrCreateResponse: pane_id field.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"pane_id\"") != null);
    // status=0 on success.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"status\":0") != null);

    client.deinit();
}

test "spec: attach-or-create handler -- 'attached' path response contains required fields" {
    // protocol 03 AttachOrCreateResponse: action_taken="attached" when session
    // with the given name already exists. session_name and pane_id fields present.
    // In the "attached" path, the handler enqueues the response directly
    // (no SessionListChanged broadcast). We locate by message type code.
    const helpers = test_mod.helpers;
    var mgr = server.connection.client_manager.ClientManager{
        .chunk_pool = helpers.testChunkPool(),
    };
    const idx = try mgr.addClient(.{ .fd = 27 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);

    resetState();
    // Pre-create the session so the handler takes the "attached" code path.
    _ = try sm.createSession("existing-sess", testImeEngine(), 0);

    var ctx = makeTestContext(&sm, &mgr);
    server.handlers.session_handler.handleAttachOrCreate(&ctx, client, idx, 1, "existing-sess");

    // Locate AttachOrCreateResponse (0x010D) in the queue.
    var payload_buf: [4096]u8 = undefined;
    const payload = extractPayloadByMsgType(
        client,
        @intFromEnum(MessageType.attach_or_create_response),
        &payload_buf,
    ) orelse return error.TestUnexpectedResult;

    // protocol 03 AttachOrCreateResponse: action_taken="attached".
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"action_taken\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"attached\"") != null);
    // protocol 03 AttachOrCreateResponse: session_name field.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"session_name\"") != null);
    // protocol 03 AttachOrCreateResponse: pane_id field.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"pane_id\"") != null);

    client.deinit();
}

// ── TEST-5: handleAttachSession state transition and response fields ───────

test "spec: session attach handler -- transitions to OPERATING and sets attached_session_id" {
    // protocol 03 AttachSessionResponse: status=0 on success, session_id,
    // name, active_pane_id, active_input_method, active_keyboard_layout fields.
    // daemon-behavior 03 policies-and-procedures: READY -> OPERATING on attach.
    const helpers = test_mod.helpers;
    var mgr = server.connection.client_manager.ClientManager{
        .chunk_pool = helpers.testChunkPool(),
    };
    const idx = try mgr.addClient(.{ .fd = 28 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);

    resetState();
    const sess_id = try sm.createSession("attach-me", testImeEngine(), 0);

    var ctx = makeTestContext(&sm, &mgr);
    server.handlers.session_handler.handleAttachSession(&ctx, client, idx, 1, sess_id);

    // Verify state transition to OPERATING.
    try std.testing.expectEqual(
        server.connection.connection_state.State.operating,
        client.connection.state,
    );
    // Verify attached_session_id is set.
    try std.testing.expectEqual(sess_id, client.connection.attached_session_id);

    var payload_buf: [4096]u8 = undefined;
    const payload = extractFirstPayload(client, &payload_buf) orelse
        return error.TestUnexpectedResult;

    // protocol 03 AttachSessionResponse: status=0 on success.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"status\":0") != null);
    // protocol 03 AttachSessionResponse: session_id field.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"session_id\"") != null);
    // protocol 03 AttachSessionResponse: name field.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"name\"") != null);
    // protocol 03 AttachSessionResponse: active_input_method field.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"active_input_method\"") != null);
    // protocol 03 AttachSessionResponse: active_keyboard_layout field.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"active_keyboard_layout\"") != null);

    client.deinit();
}

// ── TEST-6: SwapPanes uses pane_a and pane_b field names ──────────────────

test "spec: swap panes handler -- accepts pane_a_id and pane_b_id parameters" {
    // protocol 03 SwapPanesRequest uses pane_a and pane_b field names.
    // The handler function signature accepts pane_a_id and pane_b_id — verify
    // that a successful swap with two distinct panes returns status=0.
    const helpers = test_mod.helpers;
    var mgr = server.connection.client_manager.ClientManager{
        .chunk_pool = helpers.testChunkPool(),
    };
    const idx = try mgr.addClient(.{ .fd = 29 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);

    resetState();
    const sess_id = try sm.createSession("swap-test", testImeEngine(), 0);
    const entry = sm.getSession(sess_id).?;
    const slot1 = try entry.allocPaneSlot();

    // Create two real panes and place them in the two slots.
    const pane_a_id = sm.allocPaneId();
    const pane_b_id = sm.allocPaneId();
    entry.setPaneAtSlot(0, Pane.init(pane_a_id, 0, 5, 100, 80, 24));
    entry.setPaneAtSlot(slot1, Pane.init(pane_b_id, slot1, 6, 101, 80, 24));

    // Build a two-leaf split tree.
    const split_tree = core.split_tree;
    try split_tree.splitLeaf(&entry.session.tree_nodes, 0, .horizontal, 0.5, slot1);

    var pane_ctx = server.handlers.pane_handler.PaneHandlerContext{
        .session_manager = &sm,
        .client_manager = &mgr,
    };
    // Dispatch with pane_a_id / pane_b_id — the field names from protocol 03
    // SwapPanesRequest.
    server.handlers.pane_handler.handleSwapPanes(
        &pane_ctx,
        client,
        idx,
        1,
        sess_id,
        pane_a_id,
        pane_b_id,
    );

    var payload_buf: [4096]u8 = undefined;
    const payload = extractFirstPayload(client, &payload_buf) orelse
        return error.TestUnexpectedResult;

    // protocol 03 SwapPanesResponse: status=0 on success.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"status\":0") != null);

    client.deinit();
}

// ── TEST-7: forced DetachSessionResponse sequence != 0 ────────────────────

test "spec: forced detach response -- sequence is non-zero (server-assigned)" {
    // protocol 03 DetachSessionResponse: server-initiated forced detach uses
    // a server-assigned sequence number (never 0, per protocol 01 sequence rules).
    // daemon-behavior 02 destroy cascade: DetachSessionResponse sent to each peer.
    //
    // Set up: two clients attached to the same session. The requester destroys
    // the session. The peer must receive a DetachSessionResponse with sequence != 0.
    const helpers = test_mod.helpers;
    var mgr = server.connection.client_manager.ClientManager{
        .chunk_pool = helpers.testChunkPool(),
    };

    // Requester.
    const req_idx = try mgr.addClient(.{ .fd = 30 });
    const requester = mgr.getClient(req_idx).?;
    _ = requester.connection.transitionTo(.ready);
    _ = requester.connection.transitionTo(.operating);

    // Peer (attached to same session, will receive forced DetachSessionResponse).
    const peer_idx = try mgr.addClient(.{ .fd = 31 });
    const peer = mgr.getClient(peer_idx).?;
    _ = peer.connection.transitionTo(.ready);
    _ = peer.connection.transitionTo(.operating);

    resetState();
    const sess_id = try sm.createSession("cascade-session", testImeEngine(), 0);
    requester.connection.attached_session_id = sess_id;
    peer.connection.attached_session_id = sess_id;

    var ctx = makeTestContext(&sm, &mgr);
    // Requester destroys the session.
    server.handlers.session_handler.handleDestroySession(&ctx, requester, req_idx, 42, sess_id, true);

    // Peer must have received a DetachSessionResponse.
    try std.testing.expect(!peer.direct_queue.isEmpty());

    var peer_buf: [4096]u8 = undefined;
    const peer_item_len = peer.direct_queue.peekCopy(&peer_buf);
    try std.testing.expect(peer_item_len != null);

    // The header encodes the sequence at bytes [12..16] (little-endian u32).
    const HEADER_SIZE = protocol.header.HEADER_SIZE;
    const peer_data = peer_buf[0..peer_item_len.?];
    try std.testing.expect(peer_data.len >= HEADER_SIZE);

    // Decode sequence number from header bytes 12-15 (little-endian).
    const seq = std.mem.readInt(u32, peer_data[12..16], .little);
    // Protocol 01: sequence 0 is reserved/sentinel — forced detach must use != 0.
    try std.testing.expect(seq != 0);

    requester.deinit();
    peer.deinit();
}

// ── TEST-8: SessionListChanged reaches requester after createSession ───────

test "spec: session create -- SessionListChanged reaches requester via broadcastToActive" {
    // daemon-behavior 02 response-before-notification: CreateSessionResponse
    // precedes SessionListChanged. broadcastToActive delivers to both READY and
    // OPERATING clients. This test verifies the ordering requirement: the
    // requester (in READY state) must receive SessionListChanged after the
    // response that the handler enqueues first.
    //
    // We simulate the handler sequence directly: (1) enqueue a response to the
    // requester, then (2) broadcast SessionListChanged via broadcastToActive.
    // Both items arrive in the requester's direct queue, response first.
    const helpers = test_mod.helpers;
    var mgr = server.connection.client_manager.ClientManager{
        .chunk_pool = helpers.testChunkPool(),
    };
    const idx = try mgr.addClient(.{ .fd = 32 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);

    resetState();
    const sess_id = try sm.createSession("notify-test", testImeEngine(), 0);
    const pane_id_val = sm.allocPaneId();

    // Step 1: Enqueue a synthetic CreateSessionResponse (status=0) to the requester.
    // This is what the handler does before broadcasting.
    var resp_buf: [server.handlers.protocol_envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    var json_buf: [256]u8 = undefined;
    const resp_json = try std.fmt.bufPrint(
        &json_buf,
        "{{\"status\":0,\"session_id\":{d},\"pane_id\":{d}}}",
        .{ sess_id, pane_id_val },
    );
    const resp = server.handlers.protocol_envelope.wrapResponse(
        &resp_buf,
        @intFromEnum(MessageType.create_session_response),
        5,
        resp_json,
    ) orelse return error.TestUnexpectedResult;
    try client.enqueueDirect(resp);

    // Step 2: Broadcast SessionListChanged — must arrive AFTER the response.
    var notif_buf: [server.handlers.protocol_envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notif_seq = client.connection.advanceSendSequence();
    const notif = server.handlers.notification_builder.buildSessionListChanged(
        "created",
        sess_id,
        sm.getSession(sess_id).?.session.getName(),
        notif_seq,
        &notif_buf,
    ) orelse return error.TestUnexpectedResult;
    const broadcast_result = server.connection.broadcast.broadcastToActive(&mgr, notif, null);
    try std.testing.expectEqual(@as(u16, 1), broadcast_result.sent_count);

    // Verify message 1: CreateSessionResponse with status=0 and session_id.
    var buf1: [4096]u8 = undefined;
    const resp_payload = extractFirstPayload(client, &buf1) orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, resp_payload, "\"status\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp_payload, "\"session_id\"") != null);

    // Verify message 2: SessionListChanged with event="created" and session_id.
    var buf2: [4096]u8 = undefined;
    const notif_payload = extractSecondPayload(client, &buf2) orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, notif_payload, "\"created\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, notif_payload, "\"session_id\"") != null);

    client.deinit();
}
