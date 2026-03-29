//! Shared domain types and capacity constants for the it-shell3 daemon.
//! All identifier types, limits, and layout enums live here to avoid
//! circular imports between core modules.

const std = @import("std");

// ── Identifier types ────────────────────────────────────────────────────────

/// Monotonically increasing pane identifier, assigned at pane creation.
pub const PaneId = u32;

/// Index into the fixed-size pane_slots array (0..MAX_PANES-1).
pub const PaneSlot = u8;

/// Monotonically increasing session identifier.
pub const SessionId = u32;

/// Monotonically increasing client identifier, assigned at accept().
pub const ClientId = u32;

// ── Capacity constants ──────────────────────────────────────────────────────

/// Maximum number of panes per session.
pub const MAX_PANES: u8 = 16;

/// Maximum number of nodes in the binary split tree (2*MAX_PANES - 1).
pub const MAX_TREE_NODES: u8 = MAX_PANES * 2 - 1;

/// Maximum depth of the binary split tree (log2 of MAX_PANES).
pub const MAX_TREE_DEPTH: u8 = std.math.log2_int(u8, MAX_PANES);

/// Maximum number of concurrent sessions.
pub const MAX_SESSIONS: u8 = 64;

/// Maximum number of concurrent client connections.
pub const MAX_CLIENTS: u8 = 64;

// ── Fixed-size inline buffer sizes (per ADR 00058) ──────────────────────────

/// Maximum length of a session name in bytes.
pub const MAX_SESSION_NAME: u8 = 64;

/// Maximum length of an input method identifier in bytes.
pub const MAX_INPUT_METHOD_NAME: u8 = 32;

/// Maximum length of a keyboard layout identifier in bytes.
pub const MAX_KEYBOARD_LAYOUT_NAME: u8 = 32;

/// Maximum length of preedit text in bytes.
pub const MAX_PREEDIT_BUF: u8 = 64;

/// Maximum length of a pane title in bytes.
pub const MAX_PANE_TITLE: u16 = 256;

/// Maximum length of a pane current working directory path in bytes.
pub const MAX_PANE_CWD: u16 = 4096;

// ── Layout enums ────────────────────────────────────────────────────────────

/// Split orientation for the binary pane tree.
pub const Orientation = enum { horizontal, vertical };

/// Directional navigation. Integer tags match protocol wire format
/// and ghostty's GHOSTTY_SPLIT_DIRECTION: 0=right, 1=down, 2=left, 3=up.
pub const Direction = enum(u8) { right = 0, down = 1, left = 2, up = 3 };

// ── Bitmask types ───────────────────────────────────────────────────────────

/// One bit per pane slot (16 slots). Bit set = slot available.
pub const FreeMask = u16;

/// One bit per pane slot (16 slots). Bit set = pane is dirty.
pub const DirtyMask = u16;

// ── Tests ────────────────────────────────────────────────────────────────────

test "constants: have expected values" {
    try std.testing.expectEqual(@as(u8, 16), MAX_PANES);
    try std.testing.expectEqual(@as(u8, 31), MAX_TREE_NODES);
    try std.testing.expectEqual(@as(u8, 4), MAX_TREE_DEPTH);
    try std.testing.expectEqual(@as(u8, 64), MAX_SESSIONS);
    try std.testing.expectEqual(@as(u8, 64), MAX_CLIENTS);
}

test "constants: derived values match source" {
    try std.testing.expectEqual(MAX_PANES * 2 - 1, MAX_TREE_NODES);
    try std.testing.expectEqual(std.math.log2_int(u8, MAX_PANES), MAX_TREE_DEPTH);
}

test "constants: buffer size constants have expected values" {
    try std.testing.expectEqual(@as(u8, 64), MAX_SESSION_NAME);
    try std.testing.expectEqual(@as(u8, 32), MAX_INPUT_METHOD_NAME);
    try std.testing.expectEqual(@as(u8, 32), MAX_KEYBOARD_LAYOUT_NAME);
    try std.testing.expectEqual(@as(u8, 64), MAX_PREEDIT_BUF);
    try std.testing.expectEqual(@as(u16, 256), MAX_PANE_TITLE);
    try std.testing.expectEqual(@as(u16, 4096), MAX_PANE_CWD);
}

test "PaneSlot: fits values 0..15" {
    const min_slot: PaneSlot = 0;
    const max_slot: PaneSlot = 15;
    try std.testing.expectEqual(@as(PaneSlot, 0), min_slot);
    try std.testing.expectEqual(@as(PaneSlot, 15), max_slot);
    // u8 can hold 0..15 which matches MAX_PANES - 1.
    try std.testing.expectEqual(@as(u8, 16), MAX_PANES);
}

test "FreeMask and DirtyMask: can represent all 16 pane slots" {
    // A u16 has 16 bits, one per pane slot.
    const all_set: FreeMask = 0xFFFF;
    const none_set: FreeMask = 0x0000;
    try std.testing.expectEqual(@as(FreeMask, 0xFFFF), all_set);
    try std.testing.expectEqual(@as(FreeMask, 0x0000), none_set);

    // Each bit corresponds to one slot.
    var mask: DirtyMask = 0;
    var i: u32 = 0;
    while (i < MAX_PANES) : (i += 1) {
        mask |= @as(DirtyMask, 1) << @as(u4, @truncate(i));
    }
    try std.testing.expectEqual(@as(DirtyMask, 0xFFFF), mask);
}

test "Orientation: enum works as expected" {
    const h = Orientation.horizontal;
    const v = Orientation.vertical;
    try std.testing.expect(h != v);
    try std.testing.expectEqual(Orientation.horizontal, h);
    try std.testing.expectEqual(Orientation.vertical, v);
}

test "Direction: has explicit integer tags per protocol spec" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Direction.right));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Direction.down));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(Direction.left));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(Direction.up));
    const dirs = [_]Direction{ .right, .down, .left, .up };
    try std.testing.expectEqual(@as(usize, 4), dirs.len);
}
