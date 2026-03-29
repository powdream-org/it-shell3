//! Fixed-size session slot array manager. Creates, destroys, and looks up
//! sessions by ID or slot index. Statically allocated in .bss per ADR 00052.

const std = @import("std");
const core = @import("itshell3_core");
const types = core.types;
const session_mod = core.session;
const session_entry_mod = @import("session_entry.zig");

pub const SessionId = types.SessionId;
pub const PaneId = types.PaneId;
pub const MAX_SESSIONS = types.MAX_SESSIONS;
pub const SessionEntry = session_entry_mod.SessionEntry;
pub const Session = session_mod.Session;

/// Session metadata for list queries.
pub const SessionInfo = struct {
    session_id: SessionId,
    name_length: u8,
    name: [types.MAX_SESSION_NAME]u8,
    created_at: i64,
    pane_count: u8,

    pub fn getName(self: *const SessionInfo) []const u8 {
        return self.name[0..self.name_length];
    }
};

/// Fixed-size array of session slots with monotonic ID assignment.
pub const SessionManager = struct {
    sessions: [MAX_SESSIONS]?SessionEntry,
    next_session_id: SessionId,
    next_pane_id: PaneId,

    pub fn init() SessionManager {
        return SessionManager{
            .sessions = [_]?SessionEntry{null} ** MAX_SESSIONS,
            .next_session_id = 1,
            .next_pane_id = 1,
        };
    }

    pub fn createSession(
        self: *SessionManager,
        name: []const u8,
        ime_eng: session_mod.ImeEngine,
        creation_timestamp: i64,
    ) error{MaxSessionsReached}!SessionId {
        // Find a free slot.
        for (&self.sessions) |*slot| {
            if (slot.* == null) {
                const session_id = self.next_session_id;
                self.next_session_id += 1;

                // Allocate the initial pane slot (slot 0) for the session.
                // The Pane itself is NOT created here — caller fills it in later.
                const s = Session.init(session_id, name, 0, ime_eng, creation_timestamp);
                var entry = SessionEntry.init(s);
                // Reserve slot 0 (the initial pane slot) in free_mask.
                _ = entry.allocPaneSlot() catch unreachable; // slot 0 is always free at init

                slot.* = entry;
                return session_id;
            }
        }
        return error.MaxSessionsReached;
    }

    /// Finds a session by name. Returns a pointer to the matching entry or null.
    pub fn findSessionByName(self: *SessionManager, name: []const u8) ?*SessionEntry {
        for (&self.sessions) |*slot| {
            if (slot.*) |*entry| {
                if (std.mem.eql(u8, entry.session.getName(), name)) {
                    return entry;
                }
            }
        }
        return null;
    }

    /// Returns a list of session info for all active sessions.
    /// Populates the provided buffer and returns the number of entries written.
    pub fn getSessionList(self: *const SessionManager, out: []SessionInfo) u32 {
        var count: u32 = 0;
        for (self.sessions) |slot| {
            if (slot) |entry| {
                if (count >= out.len) break;
                out[count] = .{
                    .session_id = entry.session.session_id,
                    .name_length = entry.session.name_length,
                    .name = entry.session.name,
                    .created_at = entry.session.creation_timestamp,
                    .pane_count = entry.paneCount(),
                };
                count += 1;
            }
        }
        return count;
    }

    pub fn destroySession(self: *SessionManager, session_id: SessionId) ?SessionEntry {
        for (&self.sessions) |*slot| {
            if (slot.*) |entry| {
                if (entry.session.session_id == session_id) {
                    const old = entry;
                    slot.* = null;
                    return old;
                }
            }
        }
        return null;
    }

    pub fn getSession(self: *SessionManager, session_id: SessionId) ?*SessionEntry {
        for (&self.sessions) |*slot| {
            if (slot.*) |*entry| {
                if (entry.session.session_id == session_id) {
                    return entry;
                }
            }
        }
        return null;
    }

    pub fn sessionCount(self: *const SessionManager) u32 {
        var count: u32 = 0;
        for (self.sessions) |slot| {
            if (slot != null) count += 1;
        }
        return count;
    }

    /// Reset to initial state. Use between tests or for daemon restart.
    pub fn reset(self: *SessionManager) void {
        self.* = SessionManager.init();
    }

    pub fn allocPaneId(self: *SessionManager) PaneId {
        const id = self.next_pane_id;
        self.next_pane_id += 1;
        return id;
    }

    pub fn findSessionBySlot(self: *SessionManager, session_idx: usize) ?*SessionEntry {
        if (session_idx >= MAX_SESSIONS) return null;
        if (self.sessions[session_idx]) |*entry| {
            return entry;
        }
        return null;
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

const test_mod = @import("itshell3_testing");
const mock_ime = test_mod.mock_ime_engine;

var test_mock_engine = mock_ime.MockImeEngine{};

fn testImeEngine() session_mod.ImeEngine {
    return test_mock_engine.engine();
}

// File-scope static — placed in .bss segment, not on the stack.
// Each test calls test_sm.reset() to return to a clean initial state.
var test_sm = SessionManager.init();

test "SessionManager.init: has 0 sessions, next IDs start at 1" {
    test_sm.reset();
    try std.testing.expectEqual(@as(u32, 0), test_sm.sessionCount());
    try std.testing.expectEqual(@as(SessionId, 1), test_sm.next_session_id);
    try std.testing.expectEqual(@as(PaneId, 1), test_sm.next_pane_id);
}

test "SessionManager.createSession: returns valid ID, sessionCount = 1" {
    test_sm.reset();
    const id = try test_sm.createSession("main", testImeEngine(), 0);
    try std.testing.expectEqual(@as(SessionId, 1), id);
    try std.testing.expectEqual(@as(u32, 1), test_sm.sessionCount());
}

test "SessionManager.createSession: twice returns two different IDs" {
    test_sm.reset();
    const id1 = try test_sm.createSession("first", testImeEngine(), 0);
    const id2 = try test_sm.createSession("second", testImeEngine(), 0);
    try std.testing.expect(id1 != id2);
    try std.testing.expectEqual(@as(SessionId, 1), id1);
    try std.testing.expectEqual(@as(SessionId, 2), id2);
    try std.testing.expectEqual(@as(u32, 2), test_sm.sessionCount());
}

test "SessionManager.getSession: finds by ID" {
    test_sm.reset();
    const id = try test_sm.createSession("mysession", testImeEngine(), 0);
    const entry = test_sm.getSession(id);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(id, entry.?.session.session_id);
    try std.testing.expectEqualSlices(u8, "mysession", entry.?.session.getName());
}

test "SessionManager.getSession: returns null for nonexistent ID" {
    test_sm.reset();
    _ = try test_sm.createSession("x", testImeEngine(), 0);
    const entry = test_sm.getSession(999);
    try std.testing.expect(entry == null);
}

test "SessionManager.destroySession: removes and returns old entry" {
    test_sm.reset();
    const id = try test_sm.createSession("to-destroy", testImeEngine(), 0);
    try std.testing.expectEqual(@as(u32, 1), test_sm.sessionCount());

    const old = test_sm.destroySession(id);
    try std.testing.expect(old != null);
    try std.testing.expectEqual(id, old.?.session.session_id);
    try std.testing.expectEqual(@as(u32, 0), test_sm.sessionCount());
    try std.testing.expect(test_sm.getSession(id) == null);
}

test "SessionManager.destroySession: returns null for nonexistent ID" {
    test_sm.reset();
    const result = test_sm.destroySession(42);
    try std.testing.expect(result == null);
}

test "SessionManager.sessionCount: decrements after destroy" {
    test_sm.reset();
    const id1 = try test_sm.createSession("a", testImeEngine(), 0);
    _ = try test_sm.createSession("b", testImeEngine(), 0);
    try std.testing.expectEqual(@as(u32, 2), test_sm.sessionCount());
    _ = test_sm.destroySession(id1);
    try std.testing.expectEqual(@as(u32, 1), test_sm.sessionCount());
}

test "SessionManager.createSession: after destroy reuses the array slot" {
    test_sm.reset();
    const id1 = try test_sm.createSession("first", testImeEngine(), 0);
    _ = test_sm.destroySession(id1);
    try std.testing.expectEqual(@as(u32, 0), test_sm.sessionCount());

    const id2 = try test_sm.createSession("second", testImeEngine(), 0);
    try std.testing.expectEqual(@as(u32, 1), test_sm.sessionCount());
    try std.testing.expect(id2 != id1);
}

test "SessionManager.createSession: MAX_SESSIONS creates, next returns error.MaxSessionsReached" {
    test_sm.reset();
    var i: u32 = 0;
    while (i < MAX_SESSIONS) : (i += 1) {
        _ = try test_sm.createSession("s", testImeEngine(), 0);
    }
    try std.testing.expectEqual(@as(u32, MAX_SESSIONS), test_sm.sessionCount());
    const result = test_sm.createSession("overflow", testImeEngine(), 0);
    try std.testing.expectError(error.MaxSessionsReached, result);
}

test "SessionManager.allocPaneId: returns incrementing IDs" {
    test_sm.reset();
    const id1 = test_sm.allocPaneId();
    const id2 = test_sm.allocPaneId();
    const id3 = test_sm.allocPaneId();
    try std.testing.expectEqual(@as(PaneId, 1), id1);
    try std.testing.expectEqual(@as(PaneId, 2), id2);
    try std.testing.expectEqual(@as(PaneId, 3), id3);
}

test "SessionManager.findSessionBySlot: returns entry at valid occupied index" {
    test_sm.reset();
    _ = try test_sm.createSession("slot0", testImeEngine(), 0);
    const entry = test_sm.findSessionBySlot(0);
    try std.testing.expect(entry != null);
}

test "SessionManager.findSessionBySlot: returns null for empty slot" {
    test_sm.reset();
    _ = try test_sm.createSession("s", testImeEngine(), 0);
    const entry = test_sm.findSessionBySlot(1);
    try std.testing.expect(entry == null);
}

test "SessionManager.findSessionBySlot: returns null for out-of-bounds index" {
    test_sm.reset();
    const entry = test_sm.findSessionBySlot(MAX_SESSIONS);
    try std.testing.expect(entry == null);
}

test "SessionManager.findSessionByName: finds existing session" {
    test_sm.reset();
    _ = try test_sm.createSession("target", testImeEngine(), 0);
    _ = try test_sm.createSession("other", testImeEngine(), 0);
    const entry = test_sm.findSessionByName("target");
    try std.testing.expect(entry != null);
    try std.testing.expectEqualSlices(u8, "target", entry.?.session.getName());
}

test "SessionManager.findSessionByName: returns null for nonexistent name" {
    test_sm.reset();
    _ = try test_sm.createSession("exists", testImeEngine(), 0);
    try std.testing.expect(test_sm.findSessionByName("nope") == null);
}

test "SessionManager.getSessionList: returns all sessions" {
    test_sm.reset();
    _ = try test_sm.createSession("alpha", testImeEngine(), 100);
    _ = try test_sm.createSession("beta", testImeEngine(), 200);
    var buf: [MAX_SESSIONS]SessionInfo = undefined;
    const count = test_sm.getSessionList(&buf);
    try std.testing.expectEqual(@as(u32, 2), count);
    try std.testing.expectEqualSlices(u8, "alpha", buf[0].getName());
    try std.testing.expectEqual(@as(i64, 100), buf[0].created_at);
    try std.testing.expectEqualSlices(u8, "beta", buf[1].getName());
}

test "SessionManager.reset: returns to init state" {
    test_sm.reset();
    _ = try test_sm.createSession("temp", testImeEngine(), 0);
    try std.testing.expectEqual(@as(u32, 1), test_sm.sessionCount());
    test_sm.reset();
    try std.testing.expectEqual(@as(u32, 0), test_sm.sessionCount());
    try std.testing.expectEqual(@as(SessionId, 1), test_sm.next_session_id);
    try std.testing.expectEqual(@as(PaneId, 1), test_sm.next_pane_id);
}
