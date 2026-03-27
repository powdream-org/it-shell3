const std = @import("std");
const types = @import("types.zig");
const split_tree = @import("split_tree.zig");
const preedit_state = @import("preedit_state.zig");
const pane_mod = @import("pane.zig");
const ime_engine_mod = @import("ime_engine.zig");

pub const SessionId = types.SessionId;
pub const PaneSlot = types.PaneSlot;
pub const FreeMask = types.FreeMask;
pub const DirtyMask = types.DirtyMask;
pub const MAX_PANES = types.MAX_PANES;
pub const MAX_TREE_NODES = types.MAX_TREE_NODES;
pub const SplitNodeData = split_tree.SplitNodeData;
pub const PreeditState = preedit_state.PreeditState;
pub const Pane = pane_mod.Pane;
pub const ImeEngine = ime_engine_mod.ImeEngine;

/// Narrow a PaneSlot (u8) to u4 for use as a bit-shift amount on u16 masks.
/// PaneSlot values are always in range 0..15; this is a safe cast.
inline fn slotShift(slot: PaneSlot) u4 {
    return @intCast(slot);
}

pub const Session = struct {
    session_id: SessionId,
    name: [types.MAX_SESSION_NAME]u8,
    name_length: u8,
    active_input_method: [types.MAX_INPUT_METHOD_NAME]u8,
    active_input_method_length: u8,
    active_keyboard_layout: [types.MAX_KEYBOARD_LAYOUT_NAME]u8,
    active_keyboard_layout_length: u8,
    tree_nodes: [MAX_TREE_NODES]SplitNodeData,
    focused_pane: ?PaneSlot,
    creation_timestamp: i64,
    ime_engine: ImeEngine,
    current_preedit: ?[]const u8,
    preedit_buf: [types.MAX_PREEDIT_BUF]u8,
    last_preedit_row: ?u16,
    preedit: PreeditState,

    pub fn init(
        session_id: SessionId,
        name: []const u8,
        initial_pane_slot: PaneSlot,
        ime_eng: ImeEngine,
    ) Session {
        // Copy name (truncate to MAX_SESSION_NAME)
        const name_len: u8 = @intCast(@min(name.len, types.MAX_SESSION_NAME));
        var name_buf: [types.MAX_SESSION_NAME]u8 = @splat(0);
        @memcpy(name_buf[0..name_len], name[0..name_len]);

        // Default input method: "direct"
        const aim = "direct";
        var aim_buf: [types.MAX_INPUT_METHOD_NAME]u8 = @splat(0);
        @memcpy(aim_buf[0..aim.len], aim);

        // Default keyboard layout: "qwerty" (per spec)
        const kl = "qwerty";
        var kl_buf: [types.MAX_KEYBOARD_LAYOUT_NAME]u8 = @splat(0);
        @memcpy(kl_buf[0..kl.len], kl);

        return Session{
            .session_id = session_id,
            .name = name_buf,
            .name_length = name_len,
            .active_input_method = aim_buf,
            .active_input_method_length = aim.len,
            .active_keyboard_layout = kl_buf,
            .active_keyboard_layout_length = kl.len,
            .tree_nodes = split_tree.initSingleLeaf(initial_pane_slot),
            .focused_pane = initial_pane_slot,
            .creation_timestamp = 0,
            .ime_engine = ime_eng,
            .current_preedit = null,
            .preedit_buf = @splat(0),
            .last_preedit_row = null,
            .preedit = PreeditState.init(),
        };
    }

    pub fn getName(self: *const Session) []const u8 {
        return self.name[0..self.name_length];
    }

    pub fn getActiveInputMethod(self: *const Session) []const u8 {
        return self.active_input_method[0..self.active_input_method_length];
    }

    pub fn getActiveKeyboardLayout(self: *const Session) []const u8 {
        return self.active_keyboard_layout[0..self.active_keyboard_layout_length];
    }

    /// Copy preedit text into session.preedit_buf and update current_preedit slice.
    /// If text is null, clears current_preedit.
    pub fn setPreedit(self: *Session, text: ?[]const u8) void {
        if (text) |t| {
            const len = @min(t.len, self.preedit_buf.len);
            @memcpy(self.preedit_buf[0..len], t[0..len]);
            self.current_preedit = self.preedit_buf[0..len];
        } else {
            self.current_preedit = null;
        }
    }
};

pub const SessionEntry = struct {
    session: Session,
    pane_slots: [MAX_PANES]?Pane, // null = empty slot
    free_mask: FreeMask, // 1 = available
    dirty_mask: DirtyMask, // 1 = dirty
    latest_client_id: u32, // client_id of most recently active client; 0 = no active client

    pub fn init(session: Session) SessionEntry {
        return SessionEntry{
            .session = session,
            .pane_slots = [_]?Pane{null} ** MAX_PANES,
            .free_mask = 0xFFFF, // all 16 slots free
            .dirty_mask = 0,
            .latest_client_id = 0,
        };
    }

    pub fn allocPaneSlot(self: *SessionEntry) error{NoFreeSlots}!PaneSlot {
        if (self.free_mask == 0) return error.NoFreeSlots;
        // Find lowest set bit (lowest free slot) using @ctz
        const slot_index: PaneSlot = @intCast(@ctz(self.free_mask));
        // Clear the bit in free_mask (slot is now occupied)
        self.free_mask &= ~(@as(FreeMask, 1) << slotShift(slot_index));
        return slot_index;
    }

    pub fn freePaneSlot(self: *SessionEntry, slot: PaneSlot) void {
        self.free_mask |= @as(FreeMask, 1) << slotShift(slot);
        self.pane_slots[slot] = null;
    }

    pub fn setPaneAtSlot(self: *SessionEntry, slot: PaneSlot, p: Pane) void {
        self.pane_slots[slot] = p;
    }

    pub fn getPaneAtSlot(self: *SessionEntry, slot: PaneSlot) ?*Pane {
        if (self.pane_slots[slot]) |*p| {
            return p;
        }
        return null;
    }

    pub fn focusedPane(self: *SessionEntry) ?*Pane {
        if (self.session.focused_pane) |fp| {
            return self.getPaneAtSlot(fp);
        }
        return null;
    }

    pub fn markDirty(self: *SessionEntry, slot: PaneSlot) void {
        self.dirty_mask |= @as(DirtyMask, 1) << slotShift(slot);
    }

    pub fn clearDirty(self: *SessionEntry) void {
        self.dirty_mask = 0;
    }

    pub fn clearDirtySlot(self: *SessionEntry, slot: PaneSlot) void {
        self.dirty_mask &= ~(@as(DirtyMask, 1) << slotShift(slot));
    }

    pub fn isDirty(self: *const SessionEntry, slot: PaneSlot) bool {
        return (self.dirty_mask & (@as(DirtyMask, 1) << slotShift(slot))) != 0;
    }

    pub fn paneCount(self: *const SessionEntry) u5 {
        var count: u5 = 0;
        var i: u5 = 0;
        while (i < MAX_PANES) : (i += 1) {
            if (self.pane_slots[i] != null) count += 1;
        }
        return count;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

const mock_ime = @import("itshell3_testing").mock_ime_engine;

// File-scope static mock engine. Persists across tests so the vtable pointer
// stored in sessions remains valid.
var test_mock_engine = mock_ime.MockImeEngine{};

fn testImeEngine() ImeEngine {
    return test_mock_engine.engine();
}

test "Session.init: sets correct defaults" {
    const s = Session.init(1, "myterm", 0, testImeEngine());
    try std.testing.expectEqual(@as(SessionId, 1), s.session_id);
    try std.testing.expectEqualSlices(u8, "myterm", s.getName());
    try std.testing.expectEqualSlices(u8, "direct", s.getActiveInputMethod());
    try std.testing.expectEqualSlices(u8, "qwerty", s.getActiveKeyboardLayout());
    try std.testing.expectEqual(@as(?PaneSlot, 0), s.focused_pane);
    try std.testing.expect(s.current_preedit == null);
    try std.testing.expect(s.last_preedit_row == null);
    try std.testing.expectEqual(@as(i64, 0), s.creation_timestamp);
}

test "Session.init: with initial_pane_slot sets focused_pane" {
    const s = Session.init(2, "test", 5, testImeEngine());
    try std.testing.expectEqual(@as(?PaneSlot, 5), s.focused_pane);
}

test "Session.getName: returns the name" {
    const s = Session.init(1, "hello", 0, testImeEngine());
    try std.testing.expectEqualSlices(u8, "hello", s.getName());
}

test "Session.init: truncates name longer than 64 bytes" {
    const long_name = "a" ** 100;
    const s = Session.init(1, long_name, 0, testImeEngine());
    try std.testing.expectEqual(@as(u8, 64), s.name_length);
    try std.testing.expectEqualSlices(u8, long_name[0..64], s.getName());
}

test "Session.preedit: initialized to null owner and session_id 0" {
    const s = Session.init(1, "s", 0, testImeEngine());
    try std.testing.expectEqual(@as(?types.ClientId, null), s.preedit.owner);
    try std.testing.expectEqual(@as(u32, 0), s.preedit.session_id);
}

test "Session.setPreedit: sets and clears preedit" {
    var s = Session.init(1, "s", 0, testImeEngine());

    // Set preedit
    s.setPreedit("hello");
    try std.testing.expect(s.current_preedit != null);
    try std.testing.expectEqualSlices(u8, "hello", s.current_preedit.?);

    // Clear preedit
    s.setPreedit(null);
    try std.testing.expect(s.current_preedit == null);
}

test "Session.setPreedit: truncates to MAX_PREEDIT_BUF" {
    var s = Session.init(1, "s", 0, testImeEngine());
    const long_text = "x" ** 100;
    s.setPreedit(long_text);
    try std.testing.expect(s.current_preedit != null);
    try std.testing.expectEqual(@as(usize, types.MAX_PREEDIT_BUF), s.current_preedit.?.len);
}

test "SessionEntry.init: has all null pane_slots, free_mask = 0xFFFF, dirty = 0, latest_client_id = 0" {
    const s = Session.init(1, "s", 0, testImeEngine());
    const entry = SessionEntry.init(s);
    try std.testing.expectEqual(@as(FreeMask, 0xFFFF), entry.free_mask);
    try std.testing.expectEqual(@as(DirtyMask, 0), entry.dirty_mask);
    try std.testing.expectEqual(@as(u32, 0), entry.latest_client_id);
    for (entry.pane_slots) |slot| {
        try std.testing.expect(slot == null);
    }
}

test "allocPaneSlot: returns 0 first (lowest free bit)" {
    const s = Session.init(1, "s", 0, testImeEngine());
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(PaneSlot, 0), slot);
}

test "allocPaneSlot: second call returns 1" {
    const s = Session.init(1, "s", 0, testImeEngine());
    var entry = SessionEntry.init(s);
    _ = try entry.allocPaneSlot();
    const slot = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(PaneSlot, 1), slot);
}

test "allocPaneSlot: when all 16 occupied returns error.NoFreeSlots" {
    const s = Session.init(1, "s", 0, testImeEngine());
    var entry = SessionEntry.init(s);
    var i: usize = 0;
    while (i < MAX_PANES) : (i += 1) {
        _ = try entry.allocPaneSlot();
    }
    const alloc_result = entry.allocPaneSlot();
    try std.testing.expectError(error.NoFreeSlots, alloc_result);
}

test "freePaneSlot: makes slot available again" {
    const s = Session.init(1, "s", 0, testImeEngine());
    var entry = SessionEntry.init(s);
    const slot0 = try entry.allocPaneSlot(); // alloc slot 0
    const slot1 = try entry.allocPaneSlot(); // alloc slot 1
    _ = slot1;
    entry.freePaneSlot(slot0); // free slot 0
    // Next alloc should return slot 0 again (lowest free bit)
    const next = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(PaneSlot, 0), next);
}

test "setPaneAtSlot + getPaneAtSlot: round-trip" {
    const s = Session.init(1, "s", 0, testImeEngine());
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    const p = Pane.init(42, slot, 10, 200, 80, 24);
    entry.setPaneAtSlot(slot, p);
    const got = entry.getPaneAtSlot(slot);
    try std.testing.expect(got != null);
    try std.testing.expectEqual(@as(types.PaneId, 42), got.?.pane_id);
    try std.testing.expectEqual(slot, got.?.slot_index);
}

test "getPaneAtSlot: returns null for unoccupied slot" {
    const s = Session.init(1, "s", 0, testImeEngine());
    var entry = SessionEntry.init(s);
    const got = entry.getPaneAtSlot(3);
    try std.testing.expect(got == null);
}

test "focusedPane: returns correct pane" {
    var s = Session.init(1, "s", 0, testImeEngine());
    s.focused_pane = 2;
    var entry = SessionEntry.init(s);
    const slot: PaneSlot = 2;
    // Manually clear free bit for slot 2 and set a pane
    entry.free_mask &= ~(@as(FreeMask, 1) << slotShift(slot));
    const p = Pane.init(99, slot, 10, 200, 80, 24);
    entry.setPaneAtSlot(slot, p);
    const fp = entry.focusedPane();
    try std.testing.expect(fp != null);
    try std.testing.expectEqual(@as(types.PaneId, 99), fp.?.pane_id);
}

test "focusedPane: returns null when focused slot is empty" {
    const s = Session.init(1, "s", 0, testImeEngine());
    var entry = SessionEntry.init(s);
    // focused_pane = 0, but slot 0 has no pane set
    const fp = entry.focusedPane();
    try std.testing.expect(fp == null);
}

test "focusedPane: returns null when focused_pane is null" {
    var s = Session.init(1, "s", 0, testImeEngine());
    s.focused_pane = null;
    var entry = SessionEntry.init(s);
    const fp = entry.focusedPane();
    try std.testing.expect(fp == null);
}

test "dirty mask: markDirty, isDirty, clearDirty, clearDirtySlot" {
    const s = Session.init(1, "s", 0, testImeEngine());
    var entry = SessionEntry.init(s);

    // Initially no dirty bits
    try std.testing.expect(!entry.isDirty(0));
    try std.testing.expect(!entry.isDirty(5));

    // Mark slot 3 dirty
    entry.markDirty(3);
    try std.testing.expect(entry.isDirty(3));
    try std.testing.expect(!entry.isDirty(0));

    // Mark slot 7 dirty
    entry.markDirty(7);
    try std.testing.expect(entry.isDirty(7));

    // clearDirtySlot only clears slot 3
    entry.clearDirtySlot(3);
    try std.testing.expect(!entry.isDirty(3));
    try std.testing.expect(entry.isDirty(7));

    // clearDirty clears all
    entry.markDirty(0);
    entry.markDirty(15);
    entry.clearDirty();
    try std.testing.expect(!entry.isDirty(0));
    try std.testing.expect(!entry.isDirty(7));
    try std.testing.expect(!entry.isDirty(15));
    try std.testing.expectEqual(@as(DirtyMask, 0), entry.dirty_mask);
}

test "paneCount: returns correct count" {
    const s = Session.init(1, "s", 0, testImeEngine());
    var entry = SessionEntry.init(s);
    try std.testing.expectEqual(@as(u5, 0), entry.paneCount());

    const slot0 = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot0, Pane.init(1, slot0, 10, 200, 80, 24));
    try std.testing.expectEqual(@as(u5, 1), entry.paneCount());

    const slot1 = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot1, Pane.init(2, slot1, 11, 201, 80, 24));
    try std.testing.expectEqual(@as(u5, 2), entry.paneCount());

    entry.freePaneSlot(slot0);
    try std.testing.expectEqual(@as(u5, 1), entry.paneCount());
}
