//! Server-side session wrapper. Bundles a core Session with pane-slot
//! allocation (bitmask-based), dirty tracking, and typed Pane references
//! that include ghostty pointers.

const std = @import("std");
const core = @import("itshell3_core");
const types = core.types;
const session_mod = core.session;
const pane_mod = @import("pane.zig");

pub const PaneSlot = types.PaneSlot;
pub const FreeMask = types.FreeMask;
pub const DirtyMask = types.DirtyMask;
pub const MAX_PANES = types.MAX_PANES;
pub const Pane = pane_mod.Pane;
pub const Session = session_mod.Session;

/// Narrow a PaneSlot (u8) to u4 for use as a bit-shift amount on u16 masks.
/// PaneSlot values are always in range 0..15; this is a safe cast.
inline fn slotShift(slot: PaneSlot) u4 {
    return @intCast(slot);
}

/// Server-side wrapper bundling a core Session with bitmask-based pane-slot
/// management and per-pane dirty tracking. Lives in server/ because Pane
/// has typed ghostty pointers not available in core/.
pub const SessionEntry = struct {
    session: Session,
    pane_slots: [MAX_PANES]?Pane, // null = empty slot
    free_mask: FreeMask, // 1 = available
    dirty_mask: DirtyMask, // 1 = dirty
    latest_client_id: u32, // client_id of most recently active client; 0 = no active client
    /// Zoom state: slot of the zoomed pane, or null if not zoomed.
    zoomed_pane: ?PaneSlot = null,

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
        // Find lowest set bit (lowest free slot) using @ctz.
        const slot_index: PaneSlot = @intCast(@ctz(self.free_mask));
        // Clear the bit in free_mask (slot is now occupied).
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

    pub fn paneCount(self: *const SessionEntry) u8 {
        return @intCast(@popCount(~self.free_mask));
    }

    /// Finds a pane slot by wire PaneId. Linear scan — cold path per spec.
    pub fn findPaneSlotByPaneId(self: *const SessionEntry, pane_id: types.PaneId) ?PaneSlot {
        var i: u32 = 0;
        while (i < MAX_PANES) : (i += 1) {
            const slot: PaneSlot = @intCast(i);
            if (self.pane_slots[slot]) |pane| {
                if (pane.pane_id == pane_id) return slot;
            }
        }
        return null;
    }

    /// Toggles zoom state. If already zoomed on this pane, unzooms.
    /// If zoomed on a different pane, switches zoom to the new pane.
    /// If not zoomed, zooms the specified pane.
    pub fn toggleZoom(self: *SessionEntry, pane_slot: PaneSlot) void {
        if (self.zoomed_pane) |current| {
            if (current == pane_slot) {
                // Unzoom.
                self.zoomed_pane = null;
            } else {
                // Switch zoom target.
                self.zoomed_pane = pane_slot;
            }
        } else {
            // Zoom in.
            self.zoomed_pane = pane_slot;
        }
    }

    /// Unzooms without toggle semantics. Clears zoom regardless of current state.
    pub fn unzoom(self: *SessionEntry) void {
        self.zoomed_pane = null;
    }

    /// Whether any pane is currently zoomed.
    pub fn isZoomed(self: *const SessionEntry) bool {
        return self.zoomed_pane != null;
    }

    /// Sentinel value for "no pane" in wire payloads.
    pub const NONE_PANE_ID_SENTINEL: types.PaneId = 0;

    /// Returns the PaneId for a given optional slot, or NONE_PANE_ID_SENTINEL
    /// if the slot is null or the slot has no pane.
    pub fn getPaneIdOrNone(self: *const SessionEntry, slot: ?types.PaneSlot) types.PaneId {
        const s = slot orelse return NONE_PANE_ID_SENTINEL;
        // Use array access directly since self is const.
        const pane = self.pane_slots[s] orelse return NONE_PANE_ID_SENTINEL;
        return pane.pane_id;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

fn testImeEngine() session_mod.ImeEngine {
    const test_mod = @import("itshell3_testing");
    const mock_ime = test_mod.mock_ime_engine;
    const S = struct {
        var engine = mock_ime.MockImeEngine{};
    };
    return S.engine.engine();
}

test "SessionEntry.init: has all null pane_slots, free_mask = 0xFFFF, dirty = 0, latest_client_id = 0" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    const entry = SessionEntry.init(s);
    try std.testing.expectEqual(@as(FreeMask, 0xFFFF), entry.free_mask);
    try std.testing.expectEqual(@as(DirtyMask, 0), entry.dirty_mask);
    try std.testing.expectEqual(@as(u32, 0), entry.latest_client_id);
    for (entry.pane_slots) |slot| {
        try std.testing.expect(slot == null);
    }
}

test "SessionEntry.allocPaneSlot: returns 0 first (lowest free bit)" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(PaneSlot, 0), slot);
}

test "SessionEntry.allocPaneSlot: second call returns 1" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    _ = try entry.allocPaneSlot();
    const slot = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(PaneSlot, 1), slot);
}

test "SessionEntry.allocPaneSlot: when all 16 occupied returns error.NoFreeSlots" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    var i: u32 = 0;
    while (i < MAX_PANES) : (i += 1) {
        _ = try entry.allocPaneSlot();
    }
    const alloc_result = entry.allocPaneSlot();
    try std.testing.expectError(error.NoFreeSlots, alloc_result);
}

test "SessionEntry.freePaneSlot: makes slot available again" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    const slot0 = try entry.allocPaneSlot();
    _ = try entry.allocPaneSlot();
    entry.freePaneSlot(slot0);
    const next = try entry.allocPaneSlot();
    try std.testing.expectEqual(@as(PaneSlot, 0), next);
}

test "SessionEntry.setPaneAtSlot: round-trip with getPaneAtSlot" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    const p = Pane.init(42, slot, 10, 200, 80, 24);
    entry.setPaneAtSlot(slot, p);
    const got = entry.getPaneAtSlot(slot);
    try std.testing.expect(got != null);
    try std.testing.expectEqual(@as(types.PaneId, 42), got.?.pane_id);
    try std.testing.expectEqual(slot, got.?.slot_index);
}

test "SessionEntry.getPaneAtSlot: returns null for unoccupied slot" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    const got = entry.getPaneAtSlot(3);
    try std.testing.expect(got == null);
}

test "SessionEntry.focusedPane: returns correct pane" {
    var s = Session.init(1, "s", 0, testImeEngine(), 0);
    s.focused_pane = 2;
    var entry = SessionEntry.init(s);
    const slot: PaneSlot = 2;
    entry.free_mask &= ~(@as(FreeMask, 1) << slotShift(slot));
    const p = Pane.init(99, slot, 10, 200, 80, 24);
    entry.setPaneAtSlot(slot, p);
    const fp = entry.focusedPane();
    try std.testing.expect(fp != null);
    try std.testing.expectEqual(@as(types.PaneId, 99), fp.?.pane_id);
}

test "SessionEntry.focusedPane: returns null when focused slot is empty" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    const fp = entry.focusedPane();
    try std.testing.expect(fp == null);
}

test "SessionEntry.focusedPane: returns null when focused_pane is null" {
    var s = Session.init(1, "s", 0, testImeEngine(), 0);
    s.focused_pane = null;
    var entry = SessionEntry.init(s);
    const fp = entry.focusedPane();
    try std.testing.expect(fp == null);
}

test "SessionEntry.dirtyMask: markDirty, isDirty, clearDirty, clearDirtySlot" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);

    try std.testing.expect(!entry.isDirty(0));
    try std.testing.expect(!entry.isDirty(5));

    entry.markDirty(3);
    try std.testing.expect(entry.isDirty(3));
    try std.testing.expect(!entry.isDirty(0));

    entry.markDirty(7);
    try std.testing.expect(entry.isDirty(7));

    entry.clearDirtySlot(3);
    try std.testing.expect(!entry.isDirty(3));
    try std.testing.expect(entry.isDirty(7));

    entry.markDirty(0);
    entry.markDirty(15);
    entry.clearDirty();
    try std.testing.expect(!entry.isDirty(0));
    try std.testing.expect(!entry.isDirty(7));
    try std.testing.expect(!entry.isDirty(15));
    try std.testing.expectEqual(@as(DirtyMask, 0), entry.dirty_mask);
}

test "SessionEntry.paneCount: returns correct count" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    try std.testing.expectEqual(@as(u8, 0), entry.paneCount());

    const slot0 = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot0, Pane.init(1, slot0, 10, 200, 80, 24));
    try std.testing.expectEqual(@as(u8, 1), entry.paneCount());

    const slot1 = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot1, Pane.init(2, slot1, 11, 201, 80, 24));
    try std.testing.expectEqual(@as(u8, 2), entry.paneCount());

    entry.freePaneSlot(slot0);
    try std.testing.expectEqual(@as(u8, 1), entry.paneCount());
}

test "SessionEntry.findPaneSlotByPaneId: finds existing pane" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, Pane.init(42, slot, 10, 200, 80, 24));
    const found = entry.findPaneSlotByPaneId(42);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(slot, found.?);
}

test "SessionEntry.findPaneSlotByPaneId: returns null for unknown id" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, Pane.init(1, slot, 10, 200, 80, 24));
    try std.testing.expect(entry.findPaneSlotByPaneId(999) == null);
}

test "SessionEntry.toggleZoom: zooms and unzooms" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    try std.testing.expect(!entry.isZoomed());

    entry.toggleZoom(3);
    try std.testing.expect(entry.isZoomed());
    try std.testing.expectEqual(@as(?PaneSlot, 3), entry.zoomed_pane);

    // Toggle same pane = unzoom.
    entry.toggleZoom(3);
    try std.testing.expect(!entry.isZoomed());
}

test "SessionEntry.toggleZoom: switches zoom target" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    entry.toggleZoom(1);
    try std.testing.expectEqual(@as(?PaneSlot, 1), entry.zoomed_pane);
    entry.toggleZoom(5);
    try std.testing.expectEqual(@as(?PaneSlot, 5), entry.zoomed_pane);
}

test "SessionEntry.unzoom: clears zoom state" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    entry.toggleZoom(2);
    try std.testing.expect(entry.isZoomed());
    entry.unzoom();
    try std.testing.expect(!entry.isZoomed());
}

test "SessionEntry.getPaneIdOrNone: returns pane_id for occupied slot" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, Pane.init(42, slot, 10, 200, 80, 24));
    try std.testing.expectEqual(@as(types.PaneId, 42), entry.getPaneIdOrNone(slot));
}

test "SessionEntry.getPaneIdOrNone: returns sentinel for null slot" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    const entry = SessionEntry.init(s);
    try std.testing.expectEqual(SessionEntry.NONE_PANE_ID_SENTINEL, entry.getPaneIdOrNone(null));
}

test "SessionEntry.getPaneIdOrNone: returns sentinel for empty slot" {
    const s = Session.init(1, "s", 0, testImeEngine(), 0);
    const entry = SessionEntry.init(s);
    try std.testing.expectEqual(SessionEntry.NONE_PANE_ID_SENTINEL, entry.getPaneIdOrNone(3));
}
