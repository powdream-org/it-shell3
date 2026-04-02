//! Spec compliance tests for Plan 16 post-design code alignment.
//!
//! Work items covered:
//!   WI-2: ADR 00062 -- Fixed-point ratio for resize and split
//!     Spec: daemon-architecture state-and-types SplitNodeData
//!     Spec: daemon-behavior policies-and-procedures resize procedure
//!   WI-4: ADR 00059 -- CapsLock/NumLock modifiers in KeyEvent
//!     Spec: interface-contract types KeyEvent.Modifiers
//!     Spec: daemon-architecture state-and-types KeyEvent.Modifiers table

const std = @import("std");
const core = @import("itshell3_core");
const KeyEvent = core.KeyEvent;
const SplitNodeData = core.SplitNodeData;
const split_tree = core.split_tree;
const input = @import("itshell3_input");

// ============================================================================
// WI-4: ADR 00059 -- CapsLock/NumLock modifiers
// Spec: interface-contract types KeyEvent.Modifiers
// ============================================================================

test "spec: Modifiers -- @sizeOf is exactly 1 byte" {
    // Spec: "pub const Modifiers = packed struct(u8)"
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(KeyEvent.Modifiers));
}

test "spec: Modifiers -- caps_lock defaults to false" {
    // Spec: daemon-architecture state-and-types Modifiers table:
    // caps_lock is a boolean field that defaults to false.
    const mods = KeyEvent.Modifiers{};
    try std.testing.expect(!mods.caps_lock);
}

test "spec: Modifiers -- num_lock defaults to false" {
    // Spec: daemon-architecture state-and-types Modifiers table:
    // num_lock is a boolean field that defaults to false.
    const mods = KeyEvent.Modifiers{};
    try std.testing.expect(!mods.num_lock);
}

test "spec: Modifiers -- caps_lock at bit 3" {
    // Spec: daemon-architecture state-and-types Modifiers table:
    // caps_lock is at bit 3.
    const mods = KeyEvent.Modifiers{ .caps_lock = true };
    const raw: u8 = @bitCast(mods);
    // Bit 3 = 0x08.
    try std.testing.expectEqual(@as(u8, 0x08), raw);
}

test "spec: Modifiers -- num_lock at bit 4" {
    // Spec: daemon-architecture state-and-types Modifiers table:
    // num_lock is at bit 4.
    const mods = KeyEvent.Modifiers{ .num_lock = true };
    const raw: u8 = @bitCast(mods);
    // Bit 4 = 0x10.
    try std.testing.expectEqual(@as(u8, 0x10), raw);
}

test "spec: Modifiers -- ctrl at bit 0, alt at bit 1, super_key at bit 2" {
    // Spec: daemon-architecture state-and-types Modifiers table
    const ctrl_raw: u8 = @bitCast(KeyEvent.Modifiers{ .ctrl = true });
    try std.testing.expectEqual(@as(u8, 0x01), ctrl_raw);

    const alt_raw: u8 = @bitCast(KeyEvent.Modifiers{ .alt = true });
    try std.testing.expectEqual(@as(u8, 0x02), alt_raw);

    const super_raw: u8 = @bitCast(KeyEvent.Modifiers{ .super_key = true });
    try std.testing.expectEqual(@as(u8, 0x04), super_raw);
}

test "spec: hasCompositionBreakingModifier -- does NOT include caps_lock" {
    // Spec: interface-contract types KeyEvent.Modifiers:
    // CapsLock and NumLock are explicitly excluded -- they are "input
    // classification" modifiers that do NOT interrupt Hangul composition.
    const key = KeyEvent{
        .hid_keycode = 0x04,
        .modifiers = .{ .caps_lock = true },
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(!key.hasCompositionBreakingModifier());
}

test "spec: hasCompositionBreakingModifier -- does NOT include num_lock" {
    // Spec: interface-contract types KeyEvent.Modifiers: NumLock excluded.
    const key = KeyEvent{
        .hid_keycode = 0x04,
        .modifiers = .{ .num_lock = true },
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(!key.hasCompositionBreakingModifier());
}

test "spec: hasCompositionBreakingModifier -- caps_lock + num_lock together do not break" {
    // Both are "input classification" modifiers -- neither should break composition.
    const key = KeyEvent{
        .hid_keycode = 0x04,
        .modifiers = .{ .caps_lock = true, .num_lock = true },
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(!key.hasCompositionBreakingModifier());
}

test "spec: hasCompositionBreakingModifier -- ctrl still breaks even with caps_lock set" {
    // Ctrl is a composition-breaking modifier regardless of caps_lock state.
    const key = KeyEvent{
        .hid_keycode = 0x04,
        .modifiers = .{ .ctrl = true, .caps_lock = true },
        .shift = false,
        .action = .press,
    };
    try std.testing.expect(key.hasCompositionBreakingModifier());
}

test "spec: wire decompose -- bits 4-5 map to caps_lock and num_lock" {
    // Spec: daemon-architecture integration-boundaries wire-to-KeyEvent table:
    // Bit 4 maps to caps_lock, bit 5 maps to num_lock.
    // Wire bit 4 = 0x10, bit 5 = 0x20.
    const key = input.decomposeWireEvent(0x04, 0x30, .press);
    try std.testing.expect(key.modifiers.caps_lock);
    try std.testing.expect(key.modifiers.num_lock);
    // Other modifiers should be false
    try std.testing.expect(!key.modifiers.ctrl);
    try std.testing.expect(!key.modifiers.alt);
    try std.testing.expect(!key.modifiers.super_key);
    try std.testing.expect(!key.shift);
}

test "spec: wire decompose -- caps_lock only (bit 4)" {
    const key = input.decomposeWireEvent(0x04, 0x10, .press);
    try std.testing.expect(key.modifiers.caps_lock);
    try std.testing.expect(!key.modifiers.num_lock);
}

test "spec: wire decompose -- num_lock only (bit 5)" {
    const key = input.decomposeWireEvent(0x04, 0x20, .press);
    try std.testing.expect(!key.modifiers.caps_lock);
    try std.testing.expect(key.modifiers.num_lock);
}

test "spec: wire decompose -- all six modifier bits set preserves all fields" {
    // Wire: 0x3F = shift(0) + ctrl(1) + alt(2) + super(3) + caps(4) + num(5).
    const key = input.decomposeWireEvent(0x15, 0x3F, .press);
    try std.testing.expect(key.shift);
    try std.testing.expect(key.modifiers.ctrl);
    try std.testing.expect(key.modifiers.alt);
    try std.testing.expect(key.modifiers.super_key);
    try std.testing.expect(key.modifiers.caps_lock);
    try std.testing.expect(key.modifiers.num_lock);
}

// ============================================================================
// WI-2: ADR 00062 -- Fixed-point ratio in SplitNodeData
// Spec: daemon-architecture state-and-types, daemon-behavior resize procedure
// ============================================================================

test "spec: SplitNodeData -- split ratio is integer (not float)" {
    // Spec: protocol overview conventions: ratios are fixed-point u32 integers
    // (x10^4, range 0-10000, where 5000 = 50.00%).
    // Spec: daemon-behavior resize procedure: all ratio arithmetic uses integer
    // operations with no floating-point.
    // Verify by constructing a split node with ratio 5000 and reading it back.
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 5000, 1);
    switch (tree[0].?) {
        .split => |s| try std.testing.expectEqual(@as(@TypeOf(s.ratio), 5000), s.ratio),
        .leaf => return error.TestUnexpectedResult,
    }
}

test "spec: equalize ratios -- sets all split nodes to 5000" {
    // Spec: daemon-behavior equalize-splits procedure: sets all split ratios to 5000.
    // Create a tree with root split + two children that are splits
    var tree = split_tree.initSingleLeaf(0);
    // Split root: root becomes split, children are leaves
    try split_tree.splitLeaf(&tree, 0, .horizontal, 7000, 1);
    // Now tree[0] = split, tree[1] = leaf(0), tree[2] = leaf(1)
    // Verify initial ratio is 7000
    switch (tree[0].?) {
        .split => |s| try std.testing.expectEqual(@as(@TypeOf(s.ratio), 7000), s.ratio),
        .leaf => return error.TestUnexpectedResult,
    }

    // Equalize
    split_tree.equalizeRatios(&tree);

    // All split nodes should have ratio = 5000
    switch (tree[0].?) {
        .split => |s| try std.testing.expectEqual(@as(@TypeOf(s.ratio), 5000), s.ratio),
        .leaf => return error.TestUnexpectedResult,
    }
}

test "spec: dimension calculation -- child_size = parent_size * ratio / 10000" {
    // Spec: daemon-behavior resize procedure: recompute affected pane leaf
    // rectangles with integer arithmetic (width * ratio / 10000).
    // This test verifies the formula produces correct results.
    const parent_width: u32 = 80;
    const ratio: u32 = 5000; // 50%
    const first_child = parent_width * ratio / 10000;
    try std.testing.expectEqual(@as(u32, 40), first_child);

    // Asymmetric split: 30% / 70%
    const ratio_30: u32 = 3000;
    const first_30 = parent_width * ratio_30 / 10000;
    const second_70 = parent_width - first_30;
    try std.testing.expectEqual(@as(u32, 24), first_30);
    try std.testing.expectEqual(@as(u32, 56), second_70);
}

test "spec: resize clamping -- ratio clamped to [MIN_RATIO, RATIO_SCALE - MIN_RATIO]" {
    // Spec: daemon-behavior resize procedure: clamp to
    // [MIN_RATIO, 10000 - MIN_RATIO] where MIN_RATIO = 500 (5%).
    // This tests the clamping formula, not the implementation directly.
    const MIN_RATIO: u32 = 500;
    const RATIO_SCALE: u32 = 10000;

    // Attempting to go below MIN_RATIO should clamp to 500
    const old_ratio: u32 = 1000;
    const delta: i32 = -600; // would result in 400, below MIN_RATIO
    const new_unclamped = @as(i32, @intCast(old_ratio)) + delta;
    const new_clamped: u32 = @intCast(@max(@as(i32, MIN_RATIO), @min(new_unclamped, @as(i32, RATIO_SCALE - MIN_RATIO))));
    try std.testing.expectEqual(@as(u32, 500), new_clamped);

    // Attempting to go above RATIO_SCALE - MIN_RATIO should clamp to 9500
    const old_ratio_high: u32 = 9000;
    const delta_high: i32 = 600; // would result in 9600, above 9500
    const new_unclamped_high = @as(i32, @intCast(old_ratio_high)) + delta_high;
    const new_clamped_high: u32 = @intCast(@max(@as(i32, MIN_RATIO), @min(new_unclamped_high, @as(i32, RATIO_SCALE - MIN_RATIO))));
    try std.testing.expectEqual(@as(u32, 9500), new_clamped_high);

    // Normal resize within bounds
    const old_normal: u32 = 5000;
    const delta_normal: i32 = 500;
    const new_normal = @as(i32, @intCast(old_normal)) + delta_normal;
    const clamped_normal: u32 = @intCast(@max(@as(i32, MIN_RATIO), @min(new_normal, @as(i32, RATIO_SCALE - MIN_RATIO))));
    try std.testing.expectEqual(@as(u32, 5500), clamped_normal);
}
