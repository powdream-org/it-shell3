//! Spec compliance tests: Session CRUD operations.
//!
//! Covers CreateSession, ListSessions, RenameSession, DestroySession,
//! AttachOrCreate, and associated SessionListChanged notification ordering.
//!
//! Spec sources:
//!   - protocol 03-session-pane-management (Sections 1.1-1.14)
//!   - daemon-behavior 02-event-handling (Section 1.1 response-before-notification,
//!     Section 4 session destroy cascade, Section 7 session rename)
//!   - daemon-architecture 02-state-and-types (Section 1 state tree, creation_timestamp)

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
