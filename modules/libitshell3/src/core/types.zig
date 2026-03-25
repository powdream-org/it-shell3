const std = @import("std");

// Identifier types
pub const PaneId = u32; // Monotonically increasing, assigned at pane creation
pub const PaneSlot = u4; // 0..15 index into pane_slots array
pub const SessionId = u32; // Monotonically increasing
pub const ClientId = u32; // Monotonically increasing, assigned at accept()

// Capacity constants
pub const MAX_PANES: u5 = 16;
pub const MAX_TREE_NODES: u5 = 31;
pub const MAX_TREE_DEPTH: u3 = 4;
pub const MAX_SESSIONS: u8 = 64;
pub const MAX_CLIENTS: u8 = 64;

// Layout enums
pub const Orientation = enum { horizontal, vertical };
pub const Direction = enum { up, down, left, right };

// Bitmask types (one bit per pane slot, 16 slots total)
pub const FreeMask = u16; // Bitfield: 1 = slot available
pub const DirtyMask = u16; // Bitfield: 1 = pane is dirty

test "constants have expected values" {
    try std.testing.expectEqual(@as(u5, 16), MAX_PANES);
    try std.testing.expectEqual(@as(u5, 31), MAX_TREE_NODES);
    try std.testing.expectEqual(@as(u3, 4), MAX_TREE_DEPTH);
    try std.testing.expectEqual(@as(u8, 64), MAX_SESSIONS);
    try std.testing.expectEqual(@as(u8, 64), MAX_CLIENTS);
}

test "PaneSlot fits values 0..15" {
    const min_slot: PaneSlot = 0;
    const max_slot: PaneSlot = 15;
    try std.testing.expectEqual(@as(PaneSlot, 0), min_slot);
    try std.testing.expectEqual(@as(PaneSlot, 15), max_slot);
    // u4 max is 15, which matches MAX_PANES - 1
    try std.testing.expectEqual(@as(u5, 16), MAX_PANES);
}

test "FreeMask and DirtyMask can represent all 16 pane slots" {
    // A u16 has 16 bits, one per pane slot
    const all_set: FreeMask = 0xFFFF;
    const none_set: FreeMask = 0x0000;
    try std.testing.expectEqual(@as(FreeMask, 0xFFFF), all_set);
    try std.testing.expectEqual(@as(FreeMask, 0x0000), none_set);

    // Each bit corresponds to one slot
    var mask: DirtyMask = 0;
    var i: u5 = 0;
    while (i < MAX_PANES) : (i += 1) {
        mask |= @as(DirtyMask, 1) << @as(u4, @truncate(i));
    }
    try std.testing.expectEqual(@as(DirtyMask, 0xFFFF), mask);
}

test "Orientation enum works as expected" {
    const h = Orientation.horizontal;
    const v = Orientation.vertical;
    try std.testing.expect(h != v);
    try std.testing.expectEqual(Orientation.horizontal, h);
    try std.testing.expectEqual(Orientation.vertical, v);
}

test "Direction enum works as expected" {
    try std.testing.expect(Direction.up != Direction.down);
    try std.testing.expect(Direction.left != Direction.right);
    const dirs = [_]Direction{ .up, .down, .left, .right };
    try std.testing.expectEqual(@as(usize, 4), dirs.len);
}
