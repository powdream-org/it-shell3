const std = @import("std");
const types = @import("types.zig");

pub const PaneSlot = types.PaneSlot;
pub const Orientation = types.Orientation;
pub const MAX_TREE_NODES = types.MAX_TREE_NODES;
pub const MAX_PANES = types.MAX_PANES;
pub const MAX_TREE_DEPTH = types.MAX_TREE_DEPTH;

pub const SplitNodeData = union(enum) {
    leaf: PaneSlot,
    split: struct {
        orientation: Orientation,
        ratio: f32,
        left: u5,
        right: u5,
    },
    empty: void,
};

pub const TreeFull = error{TreeFull};
pub const MaxDepthExceeded = error{MaxDepthExceeded};
pub const CannotRemoveRoot = error{CannotRemoveRoot};

/// Initialize a tree with a single leaf at root (index 0), all others empty.
pub fn initSingleLeaf(slot: PaneSlot) [MAX_TREE_NODES]SplitNodeData {
    var tree: [MAX_TREE_NODES]SplitNodeData = undefined;
    tree[0] = .{ .leaf = slot };
    var i: usize = 1;
    while (i < MAX_TREE_NODES) : (i += 1) {
        tree[i] = .empty;
    }
    return tree;
}

/// Find a free (empty) slot in the tree array. Returns null if full.
fn findFreeSlot(tree: *const [MAX_TREE_NODES]SplitNodeData) ?u5 {
    var i: u5 = 0;
    while (i < MAX_TREE_NODES) : (i += 1) {
        if (tree[i] == .empty) return i;
        if (i == MAX_TREE_NODES - 1) break;
    }
    return null;
}

/// Compute the depth of node_idx in the tree (root = 0).
pub fn depth(tree: *const [MAX_TREE_NODES]SplitNodeData, node_idx: u5) u5 {
    if (node_idx == 0) return 0;
    const parent_idx = findParent(tree, node_idx) orelse return 0;
    return 1 + depth(tree, parent_idx);
}

/// Find the parent of node_idx. Returns null for root (index 0).
pub fn findParent(tree: *const [MAX_TREE_NODES]SplitNodeData, child_idx: u5) ?u5 {
    if (child_idx == 0) return null;
    var i: u5 = 0;
    while (i < MAX_TREE_NODES) : (i += 1) {
        switch (tree[i]) {
            .split => |s| {
                if (s.left == child_idx or s.right == child_idx) return i;
            },
            else => {},
        }
        if (i == MAX_TREE_NODES - 1) break;
    }
    return null;
}

/// Split a leaf node into a split node with:
///   - original leaf as left child
///   - new_slot as right child
/// Enforces MAX_TREE_DEPTH and TreeFull.
pub fn splitLeaf(
    tree: *[MAX_TREE_NODES]SplitNodeData,
    node_idx: u5,
    orientation: Orientation,
    ratio: f32,
    new_slot: PaneSlot,
) (TreeFull || MaxDepthExceeded)!void {
    // Get the original leaf value before mutating
    const orig_leaf = switch (tree[node_idx]) {
        .leaf => |s| s,
        else => unreachable, // caller must pass a leaf index
    };

    // Depth check: after split, children will be at depth+1
    const current_depth = depth(tree, node_idx);
    if (current_depth + 1 > MAX_TREE_DEPTH) return error.MaxDepthExceeded;

    // Find two free slots for children
    const left_idx = findFreeSlot(tree) orelse return error.TreeFull;
    // Temporarily mark left slot as leaf to avoid finding it again
    tree[left_idx] = .{ .leaf = orig_leaf };
    const right_idx = findFreeSlot(tree) orelse {
        // Restore and propagate error
        tree[left_idx] = .empty;
        return error.TreeFull;
    };

    // Write children
    tree[left_idx] = .{ .leaf = orig_leaf };
    tree[right_idx] = .{ .leaf = new_slot };

    // Convert node_idx from leaf to split
    tree[node_idx] = .{ .split = .{
        .orientation = orientation,
        .ratio = ratio,
        .left = left_idx,
        .right = right_idx,
    } };
}

/// Remove a leaf node. Find its parent split, promote the sibling to replace
/// the parent's data. Returns error.CannotRemoveRoot if node_idx == 0 and root
/// is a leaf (single-pane tree has no parent to re-parent into).
pub fn removeLeaf(
    tree: *[MAX_TREE_NODES]SplitNodeData,
    node_idx: u5,
) CannotRemoveRoot!void {
    const parent_idx = findParent(tree, node_idx) orelse return error.CannotRemoveRoot;

    const parent_split = switch (tree[parent_idx]) {
        .split => |s| s,
        else => unreachable,
    };

    // Determine sibling
    const sibling_idx: u5 = if (parent_split.left == node_idx)
        parent_split.right
    else
        parent_split.left;

    // Copy sibling data into parent position
    tree[parent_idx] = tree[sibling_idx];

    // Clear removed nodes
    tree[node_idx] = .empty;
    tree[sibling_idx] = .empty;
}

/// Search for a leaf containing the given pane slot. Returns tree index or null.
pub fn findLeafBySlot(tree: *const [MAX_TREE_NODES]SplitNodeData, slot: PaneSlot) ?u5 {
    var i: u5 = 0;
    while (i < MAX_TREE_NODES) : (i += 1) {
        switch (tree[i]) {
            .leaf => |s| {
                if (s == slot) return i;
            },
            else => {},
        }
        if (i == MAX_TREE_NODES - 1) break;
    }
    return null;
}

/// Count the number of leaf nodes in the tree.
pub fn leafCount(tree: *const [MAX_TREE_NODES]SplitNodeData) u5 {
    var count: u5 = 0;
    var i: u5 = 0;
    while (i < MAX_TREE_NODES) : (i += 1) {
        switch (tree[i]) {
            .leaf => count += 1,
            else => {},
        }
        if (i == MAX_TREE_NODES - 1) break;
    }
    return count;
}

// ── Tests ──────────────────────────────────────────────────────────────────

test "initSingleLeaf creates tree with 1 leaf and 30 empty nodes" {
    const tree = initSingleLeaf(0);
    try std.testing.expectEqual(@as(u5, 1), leafCount(&tree));
    // Root is leaf
    try std.testing.expect(tree[0] == .leaf);
    // All others empty
    var i: usize = 1;
    while (i < MAX_TREE_NODES) : (i += 1) {
        try std.testing.expect(tree[i] == .empty);
    }
}

test "leafCount returns 1 for single leaf tree" {
    const tree = initSingleLeaf(5);
    try std.testing.expectEqual(@as(u5, 1), leafCount(&tree));
}

test "splitLeaf on root yields 1 split and 2 leaves, leafCount = 2" {
    var tree = initSingleLeaf(0);
    try splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    // Root should now be a split
    try std.testing.expect(tree[0] == .split);
    try std.testing.expectEqual(@as(u5, 2), leafCount(&tree));
}

test "splitLeaf twice yields 2 splits and 3 leaves" {
    var tree = initSingleLeaf(0);
    try splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    // Find one of the leaf children and split it again
    const left_idx = tree[0].split.left;
    try splitLeaf(&tree, left_idx, .vertical, 0.5, 2);
    try std.testing.expectEqual(@as(u5, 3), leafCount(&tree));
    // Count split nodes
    var split_count: usize = 0;
    var i: usize = 0;
    while (i < MAX_TREE_NODES) : (i += 1) {
        if (tree[i] == .split) split_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), split_count);
}

test "splitLeaf at max depth returns MaxDepthExceeded" {
    var tree = initSingleLeaf(0);
    // Build a chain of depth MAX_TREE_DEPTH (4) by always splitting the left child
    var slot: PaneSlot = 1;
    var current: u5 = 0;
    var d: u5 = 0;
    while (d < MAX_TREE_DEPTH) : (d += 1) {
        try splitLeaf(&tree, current, .horizontal, 0.5, slot);
        slot += 1;
        current = tree[current].split.left;
    }
    // Now current is at depth MAX_TREE_DEPTH; splitting it should fail
    const result = splitLeaf(&tree, current, .horizontal, 0.5, slot);
    try std.testing.expectError(error.MaxDepthExceeded, result);
}

test "splitLeaf when tree full returns TreeFull" {
    // MAX_TREE_NODES = 31. A full binary tree of 16 leaves has 31 nodes.
    // We need to fill the tree and then attempt one more split.
    // Fill: split until we have 16 leaves (15 internal + 16 leaves = 31 nodes).
    // Strategy: BFS-fill, splitting leaf nodes one by one.
    var tree = initSingleLeaf(0);
    var next_slot: PaneSlot = 1;

    // We'll do a BFS-like fill: always split the first available leaf
    var filled_leaves: usize = 1;
    while (filled_leaves < MAX_PANES) {
        // Find first leaf node
        var leaf_idx: u5 = 0;
        var found = false;
        var i: u5 = 0;
        while (i < MAX_TREE_NODES) : (i += 1) {
            if (tree[i] == .leaf) {
                // Only split if depth allows
                const d = depth(&tree, i);
                if (d < MAX_TREE_DEPTH) {
                    leaf_idx = i;
                    found = true;
                    break;
                }
            }
            if (i == MAX_TREE_NODES - 1) break;
        }
        if (!found) break;

        try splitLeaf(&tree, leaf_idx, .horizontal, 0.5, next_slot);
        next_slot +%= 1;
        filled_leaves += 1;
    }

    // Tree now has 16 leaves, all 31 slots used. Any further split should fail
    // (either TreeFull or MaxDepthExceeded depending on which leaf is picked).
    // Find a leaf at depth 4 and try to split it.
    var leaf_at_max: ?u5 = null;
    var i: u5 = 0;
    while (i < MAX_TREE_NODES) : (i += 1) {
        if (tree[i] == .leaf) {
            leaf_at_max = i;
            break;
        }
        if (i == MAX_TREE_NODES - 1) break;
    }
    if (leaf_at_max) |li| {
        const result = splitLeaf(&tree, li, .horizontal, 0.5, 0);
        // Either MaxDepthExceeded (if at depth 4) or TreeFull
        const is_expected_error = (result == error.MaxDepthExceeded or result == error.TreeFull);
        try std.testing.expect(is_expected_error);
    }
}

test "findLeafBySlot finds existing leaf" {
    var tree = initSingleLeaf(3);
    try splitLeaf(&tree, 0, .horizontal, 0.5, 7);
    const idx = findLeafBySlot(&tree, 3);
    try std.testing.expect(idx != null);
    try std.testing.expect(tree[idx.?] == .leaf);
    try std.testing.expectEqual(@as(PaneSlot, 3), tree[idx.?].leaf);
}

test "findLeafBySlot returns null for non-existent slot" {
    const tree = initSingleLeaf(0);
    const idx = findLeafBySlot(&tree, 5);
    try std.testing.expect(idx == null);
}

test "removeLeaf promotes sibling to parent position" {
    var tree = initSingleLeaf(0);
    try splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    // Root (0) is now split; left child has slot 0, right child has slot 1
    const left_idx = tree[0].split.left;
    const right_idx = tree[0].split.right;

    // Remove the right leaf → sibling (left, slot 0) should be promoted to root
    try removeLeaf(&tree, right_idx);

    // Root should now be a leaf again with slot 0
    try std.testing.expect(tree[0] == .leaf);
    try std.testing.expectEqual(@as(PaneSlot, 0), tree[0].leaf);
    // Old child slots should be empty
    try std.testing.expect(tree[left_idx] == .empty);
    try std.testing.expect(tree[right_idx] == .empty);
    try std.testing.expectEqual(@as(u5, 1), leafCount(&tree));
}

test "removeLeaf on single-pane root returns CannotRemoveRoot" {
    var tree = initSingleLeaf(0);
    const result = removeLeaf(&tree, 0);
    try std.testing.expectError(error.CannotRemoveRoot, result);
}

test "depth returns correct values" {
    var tree = initSingleLeaf(0);
    try std.testing.expectEqual(@as(u5, 0), depth(&tree, 0));

    try splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    const left = tree[0].split.left;
    const right = tree[0].split.right;
    try std.testing.expectEqual(@as(u5, 1), depth(&tree, left));
    try std.testing.expectEqual(@as(u5, 1), depth(&tree, right));

    // Split one of the children to go to depth 2
    try splitLeaf(&tree, left, .vertical, 0.5, 2);
    const grandchild_left = tree[left].split.left;
    try std.testing.expectEqual(@as(u5, 2), depth(&tree, grandchild_left));
}

test "round-trip: split then remove returns to original state" {
    var tree = initSingleLeaf(0);
    const orig_tree = tree;

    try splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    try std.testing.expectEqual(@as(u5, 2), leafCount(&tree));

    // Remove the right child (slot 1)
    const right_idx = tree[0].split.right;
    try removeLeaf(&tree, right_idx);

    // Tree should have 1 leaf again at root
    try std.testing.expectEqual(@as(u5, 1), leafCount(&tree));
    try std.testing.expect(tree[0] == .leaf);
    try std.testing.expectEqual(orig_tree[0].leaf, tree[0].leaf);
}
