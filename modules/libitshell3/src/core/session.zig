const std = @import("std");
const types = @import("types.zig");
const split_tree = @import("split_tree.zig");
const preedit_state = @import("preedit_state.zig");
const pane_mod = @import("pane.zig");

pub const SessionId = types.SessionId;
pub const PaneSlot = types.PaneSlot;
pub const FreeMask = types.FreeMask;
pub const DirtyMask = types.DirtyMask;
pub const MAX_PANES = types.MAX_PANES;
pub const MAX_TREE_NODES = types.MAX_TREE_NODES;
pub const SplitNodeData = split_tree.SplitNodeData;
pub const PreeditState = preedit_state.PreeditState;
pub const Pane = pane_mod.Pane;

pub const Session = struct {
    session_id: SessionId,
    name: [64]u8,
    name_len: u8,
    active_input_method: [32]u8, // default: "direct"
    aim_len: u8,
    keyboard_layout: [32]u8, // default: "us"
    kl_len: u8,
    tree_nodes: [MAX_TREE_NODES]SplitNodeData,
    focused_pane: PaneSlot,
    preedit: PreeditState,

    pub fn init(session_id: SessionId, name: []const u8, initial_pane_slot: PaneSlot) Session {
        var s: Session = undefined;
        s.session_id = session_id;
        s.focused_pane = initial_pane_slot;
        s.preedit = PreeditState.init();

        // Copy name (truncate to 64)
        const name_len = @min(name.len, s.name.len);
        @memcpy(s.name[0..name_len], name[0..name_len]);
        s.name_len = @intCast(name_len);

        // Default input method: "direct"
        const aim = "direct";
        @memcpy(s.active_input_method[0..aim.len], aim);
        s.aim_len = aim.len;

        // Default keyboard layout: "us"
        const kl = "us";
        @memcpy(s.keyboard_layout[0..kl.len], kl);
        s.kl_len = kl.len;

        // Initialize tree with initial pane at root
        s.tree_nodes = split_tree.initSingleLeaf(initial_pane_slot);

        return s;
    }

    pub fn getName(self: *const Session) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getActiveInputMethod(self: *const Session) []const u8 {
        return self.active_input_method[0..self.aim_len];
    }

    pub fn getKeyboardLayout(self: *const Session) []const u8 {
        return self.keyboard_layout[0..self.kl_len];
    }
};

pub const SessionEntry = struct {
    session: Session,
    pane_slots: [MAX_PANES]?Pane, // null = empty slot
    free_mask: FreeMask, // 1 = available
    dirty_mask: DirtyMask, // 1 = dirty

    pub fn init(session: Session) SessionEntry {
        return SessionEntry{
            .session = session,
            .pane_slots = [_]?Pane{null} ** MAX_PANES,
            .free_mask = 0xFFFF, // all 16 slots free
            .dirty_mask = 0,
        };
    }

    pub fn allocPaneSlot(self: *SessionEntry) error{NoFreeSlots}!PaneSlot {
        if (self.free_mask == 0) return error.NoFreeSlots;
        // Find lowest set bit (lowest free slot) using @ctz
        const slot_index: u4 = @intCast(@ctz(self.free_mask));
        // Clear the bit in free_mask (slot is now occupied)
        self.free_mask &= ~(@as(FreeMask, 1) << slot_index);
        return slot_index;
    }

    pub fn freePaneSlot(self: *SessionEntry, slot: PaneSlot) void {
        const bit = @as(FreeMask, 1) << slot;
        self.free_mask |= bit;
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
        return self.getPaneAtSlot(self.session.focused_pane);
    }

    pub fn markDirty(self: *SessionEntry, slot: PaneSlot) void {
        self.dirty_mask |= @as(DirtyMask, 1) << slot;
    }

    pub fn clearDirty(self: *SessionEntry) void {
        self.dirty_mask = 0;
    }

    pub fn clearDirtySlot(self: *SessionEntry, slot: PaneSlot) void {
        self.dirty_mask &= ~(@as(DirtyMask, 1) << slot);
    }

    pub fn isDirty(self: *const SessionEntry, slot: PaneSlot) bool {
        return (self.dirty_mask & (@as(DirtyMask, 1) << slot)) != 0;
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

test "Session.init sets correct defaults" {
    const s = Session.init(1, "myterm", 0);
    try std.testing.expectEqual(@as(SessionId, 1), s.session_id);
    try std.testing.expectEqualSlices(u8, "myterm", s.getName());
    try std.testing.expectEqualSlices(u8, "direct", s.getActiveInputMethod());
    try std.testing.expectEqualSlices(u8, "us", s.getKeyboardLayout());
    try std.testing.expectEqual(@as(PaneSlot, 0), s.focused_pane);
}

test "Session.init with initial_pane_slot sets focused_pane" {
    const s = Session.init(2, "test", 5);
    try std.testing.expectEqual(@as(PaneSlot, 5), s.focused_pane);
}

test "Session.getName returns the name" {
    const s = Session.init(1, "hello", 0);
    try std.testing.expectEqualSlices(u8, "hello", s.getName());
}

test "Session.init truncates name longer than 64 bytes" {
    const long_name = "a" ** 100;
    const s = Session.init(1, long_name, 0);
    try std.testing.expectEqual(@as(u8, 64), s.name_len);
    try std.testing.expectEqualSlices(u8, long_name[0..64], s.getName());
}

test "Session.preedit initialized to null owner and session_id 0" {
    const s = Session.init(1, "s", 0);
    try std.testing.expectEqual(@as(?types.ClientId, null), s.preedit.owner);
    try std.testing.expectEqual(@as(u32, 0), s.preedit.session_id);
}

test "SessionEntry.init has all null pane_slots, free_mask = 0xFFFF, dirty = 0" {
    const s = Session.init(1, "s", 0);
    const entry = SessionEntry.init(s);
    try std.testing.expectEqual(@as(FreeMask, 0xFFFF), entry.free_mask);
    try std.testing.expectEqual(@as(DirtyMask, 0), entry.dirty_mask);
    for (entry.pane_slots) |slot| {
        try std.testing.expect(slot == null);
    }
}

test "allocPaneSlot returns 0 first (lowest free bit)" {
    const s = Session.init(1, "s", 0);
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(PaneSlot, 0), slot);
}

test "allocPaneSlot second call returns 1" {
    const s = Session.init(1, "s", 0);
    var entry = SessionEntry.init(s);
    _ = try entry.allocPaneSlot();
    const slot = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(PaneSlot, 1), slot);
}

test "allocPaneSlot when all 16 occupied returns error.NoFreeSlots" {
    const s = Session.init(1, "s", 0);
    var entry = SessionEntry.init(s);
    var i: usize = 0;
    while (i < MAX_PANES) : (i += 1) {
        _ = try entry.allocPaneSlot();
    }
    const result = entry.allocPaneSlot();
    try std.testing.expectError(error.NoFreeSlots, result);
}

test "freePaneSlot makes slot available again" {
    const s = Session.init(1, "s", 0);
    var entry = SessionEntry.init(s);
    const slot0 = try entry.allocPaneSlot(); // alloc slot 0
    const slot1 = try entry.allocPaneSlot(); // alloc slot 1
    _ = slot1;
    entry.freePaneSlot(slot0); // free slot 0
    // Next alloc should return slot 0 again (lowest free bit)
    const next = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(PaneSlot, 0), next);
}

test "setPaneAtSlot + getPaneAtSlot round-trip" {
    const s = Session.init(1, "s", 0);
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    const p = Pane.init(42, slot, 10, 200, 80, 24);
    entry.setPaneAtSlot(slot, p);
    const got = entry.getPaneAtSlot(slot);
    try std.testing.expect(got != null);
    try std.testing.expectEqual(@as(types.PaneId, 42), got.?.pane_id);
    try std.testing.expectEqual(slot, got.?.slot_index);
}

test "getPaneAtSlot returns null for unoccupied slot" {
    const s = Session.init(1, "s", 0);
    var entry = SessionEntry.init(s);
    const got = entry.getPaneAtSlot(3);
    try std.testing.expect(got == null);
}

test "focusedPane returns correct pane" {
    var s = Session.init(1, "s", 0);
    s.focused_pane = 2;
    var entry = SessionEntry.init(s);
    const slot = 2;
    // Manually clear free bit for slot 2 and set a pane
    entry.free_mask &= ~(@as(FreeMask, 1) << @as(u4, slot));
    const p = Pane.init(99, slot, 10, 200, 80, 24);
    entry.setPaneAtSlot(slot, p);
    const fp = entry.focusedPane();
    try std.testing.expect(fp != null);
    try std.testing.expectEqual(@as(types.PaneId, 99), fp.?.pane_id);
}

test "focusedPane returns null when focused slot is empty" {
    const s = Session.init(1, "s", 0);
    var entry = SessionEntry.init(s);
    // focused_pane = 0, but slot 0 has no pane set
    const fp = entry.focusedPane();
    try std.testing.expect(fp == null);
}

test "dirty mask: markDirty, isDirty, clearDirty, clearDirtySlot" {
    const s = Session.init(1, "s", 0);
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

test "paneCount returns correct count" {
    const s = Session.init(1, "s", 0);
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
