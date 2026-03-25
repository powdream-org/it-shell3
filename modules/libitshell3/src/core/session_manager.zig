const std = @import("std");
const types = @import("types.zig");
const session_mod = @import("session.zig");

pub const SessionId = types.SessionId;
pub const PaneId = types.PaneId;
pub const MAX_SESSIONS = types.MAX_SESSIONS;
pub const SessionEntry = session_mod.SessionEntry;
pub const Session = session_mod.Session;

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

    pub fn createSession(self: *SessionManager, name: []const u8) error{MaxSessionsReached}!SessionId {
        // Find a free slot
        for (&self.sessions) |*slot| {
            if (slot.* == null) {
                const session_id = self.next_session_id;
                self.next_session_id += 1;

                // Allocate the initial pane slot (slot 0) for the session.
                // The Pane itself is NOT created here — caller fills it in later.
                const s = Session.init(session_id, name, 0);
                var entry = SessionEntry.init(s);
                // Reserve slot 0 (the initial pane slot) in free_mask.
                _ = entry.allocPaneSlot() catch unreachable; // slot 0 is always free at init

                slot.* = entry;
                return session_id;
            }
        }
        return error.MaxSessionsReached;
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

test "init has 0 sessions, next IDs start at 1" {
    const sm = SessionManager.init();
    try std.testing.expectEqual(@as(u32, 0), sm.sessionCount());
    try std.testing.expectEqual(@as(SessionId, 1), sm.next_session_id);
    try std.testing.expectEqual(@as(PaneId, 1), sm.next_pane_id);
}

test "createSession returns valid ID, sessionCount = 1" {
    var sm = SessionManager.init();
    const id = try sm.createSession("main");
    try std.testing.expectEqual(@as(SessionId, 1), id);
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());
}

test "createSession twice returns two different IDs" {
    var sm = SessionManager.init();
    const id1 = try sm.createSession("first");
    const id2 = try sm.createSession("second");
    try std.testing.expect(id1 != id2);
    try std.testing.expectEqual(@as(SessionId, 1), id1);
    try std.testing.expectEqual(@as(SessionId, 2), id2);
    try std.testing.expectEqual(@as(u32, 2), sm.sessionCount());
}

test "getSession finds by ID" {
    var sm = SessionManager.init();
    const id = try sm.createSession("mysession");
    const entry = sm.getSession(id);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(id, entry.?.session.session_id);
    try std.testing.expectEqualSlices(u8, "mysession", entry.?.session.getName());
}

test "getSession returns null for nonexistent ID" {
    var sm = SessionManager.init();
    _ = try sm.createSession("x");
    const entry = sm.getSession(999);
    try std.testing.expect(entry == null);
}

test "destroySession removes and returns old entry" {
    var sm = SessionManager.init();
    const id = try sm.createSession("to-destroy");
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());

    const old = sm.destroySession(id);
    try std.testing.expect(old != null);
    try std.testing.expectEqual(id, old.?.session.session_id);
    try std.testing.expectEqual(@as(u32, 0), sm.sessionCount());
    // Should not be findable anymore
    try std.testing.expect(sm.getSession(id) == null);
}

test "destroySession returns null for nonexistent ID" {
    var sm = SessionManager.init();
    const result = sm.destroySession(42);
    try std.testing.expect(result == null);
}

test "sessionCount decrements after destroy" {
    var sm = SessionManager.init();
    const id1 = try sm.createSession("a");
    const id2 = try sm.createSession("b");
    _ = id2;
    try std.testing.expectEqual(@as(u32, 2), sm.sessionCount());
    _ = sm.destroySession(id1);
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());
}

test "createSession after destroy reuses the array slot" {
    var sm = SessionManager.init();
    const id1 = try sm.createSession("first");
    _ = sm.destroySession(id1);
    try std.testing.expectEqual(@as(u32, 0), sm.sessionCount());

    // Should succeed — the slot is free again
    const id2 = try sm.createSession("second");
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());
    try std.testing.expect(id2 != id1); // IDs are still monotonically increasing
}

test "MAX_SESSIONS creates, next returns error.MaxSessionsReached" {
    var sm = SessionManager.init();
    var i: usize = 0;
    while (i < MAX_SESSIONS) : (i += 1) {
        _ = try sm.createSession("s");
    }
    try std.testing.expectEqual(@as(u32, MAX_SESSIONS), sm.sessionCount());
    const result = sm.createSession("overflow");
    try std.testing.expectError(error.MaxSessionsReached, result);
}

test "allocPaneId returns incrementing IDs" {
    var sm = SessionManager.init();
    const id1 = sm.allocPaneId();
    const id2 = sm.allocPaneId();
    const id3 = sm.allocPaneId();
    try std.testing.expectEqual(@as(PaneId, 1), id1);
    try std.testing.expectEqual(@as(PaneId, 2), id2);
    try std.testing.expectEqual(@as(PaneId, 3), id3);
}

test "findSessionBySlot returns entry at valid occupied index" {
    var sm = SessionManager.init();
    _ = try sm.createSession("slot0");
    // The session was placed in the first free slot (index 0)
    const entry = sm.findSessionBySlot(0);
    try std.testing.expect(entry != null);
}

test "findSessionBySlot returns null for empty slot" {
    var sm = SessionManager.init();
    _ = try sm.createSession("s");
    // Slot 1 is still empty
    const entry = sm.findSessionBySlot(1);
    try std.testing.expect(entry == null);
}

test "findSessionBySlot returns null for out-of-bounds index" {
    var sm = SessionManager.init();
    const entry = sm.findSessionBySlot(MAX_SESSIONS);
    try std.testing.expect(entry == null);
}
