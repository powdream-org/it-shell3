//! Binary split tree for pane layout. Uses a heap-indexed flat array
//! (left = 2*i+1, right = 2*i+2) so the tree requires no heap allocation.

const std = @import("std");
const types = @import("types.zig");

pub const PaneSlot = types.PaneSlot;
pub const Orientation = types.Orientation;
pub const MAX_TREE_NODES = types.MAX_TREE_NODES;
pub const MAX_PANES = types.MAX_PANES;
pub const MAX_TREE_DEPTH = types.MAX_TREE_DEPTH;

/// A node in the binary split tree. Leaf nodes hold a PaneSlot;
/// split nodes hold orientation and ratio. Children are located via
/// heap-index arithmetic: left = 2*i+1, right = 2*i+2.
pub const SplitNodeData = union(enum) {
    leaf: PaneSlot,
    split: struct {
        orientation: Orientation,
        ratio: f32,
    },
};

/// Child indices would exceed the flat array bounds.
pub const TreeFull = error{TreeFull};

/// Splitting would exceed the configured maximum tree depth.
pub const MaxDepthExceeded = error{MaxDepthExceeded};

/// Cannot remove the root when it is the only leaf (single-pane session).
pub const CannotRemoveRoot = error{CannotRemoveRoot};

/// Left child index in heap-indexed layout.
pub fn leftChild(i: u8) u8 {
    return i * 2 + 1;
}

/// Right child index in heap-indexed layout.
pub fn rightChild(i: u8) u8 {
    return i * 2 + 2;
}

/// Parent index, or null for the root node (index 0).
pub fn parentIndex(i: u8) ?u8 {
    if (i == 0) return null;
    return (i - 1) / 2;
}

/// Depth of a node in the heap-indexed tree. Root has depth 0.
pub fn depth(node_idx: u8) u8 {
    if (node_idx == 0) return 0;
    // depth = floor(log2(i+1))
    var idx = @as(u32, node_idx) + 1;
    var d: u8 = 0;
    while (idx > 1) : (idx >>= 1) {
        d += 1;
    }
    return d;
}

/// Initialize a tree with a single leaf at root (index 0), all others null.
pub fn initSingleLeaf(slot: PaneSlot) [MAX_TREE_NODES]?SplitNodeData {
    var tree: [MAX_TREE_NODES]?SplitNodeData = .{null} ** MAX_TREE_NODES;
    tree[0] = .{ .leaf = slot };
    return tree;
}

/// Count the number of leaf nodes in the tree.
pub fn leafCount(tree: *const [MAX_TREE_NODES]?SplitNodeData) u8 {
    var count: u8 = 0;
    var i: u32 = 0;
    while (i < MAX_TREE_NODES) : (i += 1) {
        if (tree[i]) |node| {
            switch (node) {
                .leaf => count += 1,
                .split => {},
            }
        }
    }
    return count;
}

/// Search for a leaf containing the given pane slot. Returns tree index or null.
pub fn findLeafBySlot(tree: *const [MAX_TREE_NODES]?SplitNodeData, slot: PaneSlot) ?u8 {
    var i: u32 = 0;
    while (i < MAX_TREE_NODES) : (i += 1) {
        if (tree[i]) |node| {
            switch (node) {
                .leaf => |s| {
                    if (s == slot) return @intCast(i);
                },
                .split => {},
            }
        }
    }
    return null;
}

// Copy a subtree rooted at src_idx to dst_idx within the tree.
fn copySubtree(
    tree: *[MAX_TREE_NODES]?SplitNodeData,
    dst_idx: u8,
    src_idx: u8,
) void {
    if (src_idx >= MAX_TREE_NODES or dst_idx >= MAX_TREE_NODES) return;
    tree[dst_idx] = tree[src_idx];
    tree[src_idx] = null;

    if (tree[dst_idx]) |node| {
        switch (node) {
            .split => {
                copySubtree(tree, leftChild(dst_idx), leftChild(src_idx));
                copySubtree(tree, rightChild(dst_idx), rightChild(src_idx));
            },
            .leaf => {},
        }
    }
}

// Clear a subtree rooted at idx (set all nodes to null).
fn clearSubtree(tree: *[MAX_TREE_NODES]?SplitNodeData, idx: u8) void {
    if (idx >= MAX_TREE_NODES) return;
    if (tree[idx]) |node| {
        switch (node) {
            .split => {
                clearSubtree(tree, leftChild(idx));
                clearSubtree(tree, rightChild(idx));
            },
            .leaf => {},
        }
        tree[idx] = null;
    }
}

/// Split a leaf node into a split node with:
///   - original leaf as left child (at 2*node_idx+1)
///   - new_slot as right child (at 2*node_idx+2)
/// Enforces MAX_TREE_DEPTH and TreeFull.
pub fn splitLeaf(
    tree: *[MAX_TREE_NODES]?SplitNodeData,
    node_idx: u8,
    orientation: Orientation,
    ratio: f32,
    new_slot: PaneSlot,
) (TreeFull || MaxDepthExceeded)!void {
    // Get the original leaf value before mutating.
    const orig_leaf = switch (tree[node_idx].?) {
        .leaf => |s| s,
        .split => unreachable, // Caller must pass a leaf index.
    };

    // Depth check: after split, children will be at depth+1.
    const current_depth = depth(node_idx);
    if (current_depth + 1 > MAX_TREE_DEPTH) return error.MaxDepthExceeded;

    // Check that child indices fit within the tree array.
    const left_idx = leftChild(node_idx);
    const right_idx = rightChild(node_idx);
    if (right_idx >= MAX_TREE_NODES) return error.TreeFull;

    // Children must be empty (heap property).
    if (tree[left_idx] != null or tree[right_idx] != null) return error.TreeFull;

    // Write children.
    tree[left_idx] = .{ .leaf = orig_leaf };
    tree[right_idx] = .{ .leaf = new_slot };

    // Convert node_idx from leaf to split.
    tree[node_idx] = .{ .split = .{
        .orientation = orientation,
        .ratio = ratio,
    } };
}

/// Remove a leaf node. Find its parent split via heap-index arithmetic,
/// promote the sibling subtree to replace the parent's position.
/// Returns error.CannotRemoveRoot if node_idx == 0 and root is a leaf.
pub fn removeLeaf(
    tree: *[MAX_TREE_NODES]?SplitNodeData,
    node_idx: u8,
) CannotRemoveRoot!void {
    const par_idx = parentIndex(node_idx) orelse return error.CannotRemoveRoot;

    // Determine sibling index.
    const sibling_idx: u8 = if (leftChild(par_idx) == node_idx)
        rightChild(par_idx)
    else
        leftChild(par_idx);

    // Clear the removed leaf.
    tree[node_idx] = null;

    // Copy sibling subtree into parent position.
    // First clear the parent, then copy the sibling subtree there.
    tree[par_idx] = null;
    copySubtree(tree, par_idx, sibling_idx);
}

// ── Tests ──────────────────────────────────────────────────────────────────

test "initSingleLeaf: creates tree with 1 leaf and 30 null nodes" {
    const tree = initSingleLeaf(0);
    try std.testing.expectEqual(@as(u8, 1), leafCount(&tree));
    // Root is leaf.
    try std.testing.expect(tree[0] != null);
    try std.testing.expect(tree[0].? == .leaf);
    // All others null.
    var i: u32 = 1;
    while (i < MAX_TREE_NODES) : (i += 1) {
        try std.testing.expect(tree[i] == null);
    }
}

test "leafCount: returns 1 for single leaf tree" {
    const tree = initSingleLeaf(5);
    try std.testing.expectEqual(@as(u8, 1), leafCount(&tree));
}

test "splitLeaf: on root yields 1 split and 2 leaves, leafCount = 2" {
    var tree = initSingleLeaf(0);
    try splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    // Root should now be a split.
    try std.testing.expect(tree[0].? == .split);
    try std.testing.expectEqual(@as(u8, 2), leafCount(&tree));
    // Children at heap positions 1 and 2.
    try std.testing.expect(tree[1] != null);
    try std.testing.expect(tree[1].? == .leaf);
    try std.testing.expectEqual(@as(PaneSlot, 0), tree[1].?.leaf);
    try std.testing.expect(tree[2] != null);
    try std.testing.expect(tree[2].? == .leaf);
    try std.testing.expectEqual(@as(PaneSlot, 1), tree[2].?.leaf);
}

test "splitLeaf: twice yields 2 splits and 3 leaves" {
    var tree = initSingleLeaf(0);
    try splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    // Split the left child (index 1).
    try splitLeaf(&tree, 1, .vertical, 0.5, 2);
    try std.testing.expectEqual(@as(u8, 3), leafCount(&tree));
    // Count split nodes.
    var split_count: u32 = 0;
    var i: u32 = 0;
    while (i < MAX_TREE_NODES) : (i += 1) {
        if (tree[i]) |node| {
            if (node == .split) split_count += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 2), split_count);
}

test "splitLeaf: at max depth returns MaxDepthExceeded" {
    var tree = initSingleLeaf(0);
    // Build a chain of depth MAX_TREE_DEPTH by always splitting the left child.
    var slot: PaneSlot = 1;
    var current: u8 = 0;
    var d: u32 = 0;
    while (d < MAX_TREE_DEPTH) : (d += 1) {
        try splitLeaf(&tree, current, .horizontal, 0.5, slot);
        slot += 1;
        current = leftChild(current);
    }
    // Now current is at depth MAX_TREE_DEPTH; splitting it should fail.
    const result = splitLeaf(&tree, current, .horizontal, 0.5, slot);
    try std.testing.expectError(error.MaxDepthExceeded, result);
}

test "findLeafBySlot: finds existing leaf" {
    var tree = initSingleLeaf(3);
    try splitLeaf(&tree, 0, .horizontal, 0.5, 7);
    const idx = findLeafBySlot(&tree, 3);
    try std.testing.expect(idx != null);
    try std.testing.expect(tree[idx.?].? == .leaf);
    try std.testing.expectEqual(@as(PaneSlot, 3), tree[idx.?].?.leaf);
}

test "findLeafBySlot: returns null for non-existent slot" {
    const tree = initSingleLeaf(0);
    const idx = findLeafBySlot(&tree, 5);
    try std.testing.expect(idx == null);
}

test "removeLeaf: promotes sibling to parent position" {
    var tree = initSingleLeaf(0);
    try splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    // Root (0) is split; left child (1) has slot 0, right child (2) has slot 1.

    // Remove the right leaf (index 2) -> sibling (left, slot 0) promoted to root.
    try removeLeaf(&tree, 2);

    // Root should now be a leaf again with slot 0.
    try std.testing.expect(tree[0] != null);
    try std.testing.expect(tree[0].? == .leaf);
    try std.testing.expectEqual(@as(PaneSlot, 0), tree[0].?.leaf);
    // Old child slots should be null.
    try std.testing.expect(tree[1] == null);
    try std.testing.expect(tree[2] == null);
    try std.testing.expectEqual(@as(u8, 1), leafCount(&tree));
}

test "removeLeaf: on single-pane root returns CannotRemoveRoot" {
    var tree = initSingleLeaf(0);
    const result = removeLeaf(&tree, 0);
    try std.testing.expectError(error.CannotRemoveRoot, result);
}

test "depth: returns correct values via heap-index arithmetic" {
    try std.testing.expectEqual(@as(u8, 0), depth(0));
    try std.testing.expectEqual(@as(u8, 1), depth(1));
    try std.testing.expectEqual(@as(u8, 1), depth(2));
    try std.testing.expectEqual(@as(u8, 2), depth(3));
    try std.testing.expectEqual(@as(u8, 2), depth(4));
    try std.testing.expectEqual(@as(u8, 2), depth(5));
    try std.testing.expectEqual(@as(u8, 2), depth(6));
    try std.testing.expectEqual(@as(u8, 3), depth(7));
    try std.testing.expectEqual(@as(u8, 4), depth(15));
}

test "parentIndex: returns correct parent via heap-index arithmetic" {
    try std.testing.expect(parentIndex(0) == null);
    try std.testing.expectEqual(@as(u8, 0), parentIndex(1).?);
    try std.testing.expectEqual(@as(u8, 0), parentIndex(2).?);
    try std.testing.expectEqual(@as(u8, 1), parentIndex(3).?);
    try std.testing.expectEqual(@as(u8, 1), parentIndex(4).?);
    try std.testing.expectEqual(@as(u8, 2), parentIndex(5).?);
    try std.testing.expectEqual(@as(u8, 2), parentIndex(6).?);
}

test "leftChild and rightChild: heap-index arithmetic" {
    try std.testing.expectEqual(@as(u8, 1), leftChild(0));
    try std.testing.expectEqual(@as(u8, 2), rightChild(0));
    try std.testing.expectEqual(@as(u8, 3), leftChild(1));
    try std.testing.expectEqual(@as(u8, 4), rightChild(1));
    try std.testing.expectEqual(@as(u8, 5), leftChild(2));
    try std.testing.expectEqual(@as(u8, 6), rightChild(2));
}

test "round-trip: split then remove returns to original state" {
    var tree = initSingleLeaf(0);

    try splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    try std.testing.expectEqual(@as(u8, 2), leafCount(&tree));

    // Remove the right child (slot 1).
    try removeLeaf(&tree, rightChild(0));

    // Tree should have 1 leaf again at root.
    try std.testing.expectEqual(@as(u8, 1), leafCount(&tree));
    try std.testing.expect(tree[0] != null);
    try std.testing.expect(tree[0].? == .leaf);
    try std.testing.expectEqual(@as(PaneSlot, 0), tree[0].?.leaf);
}

test "removeLeaf: with subtree sibling promotes entire subtree" {
    var tree = initSingleLeaf(0);
    // Split root: left=1(slot0), right=2(slot1).
    try splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    // Split right child: left=5(slot1), right=6(slot2).
    try splitLeaf(&tree, 2, .vertical, 0.5, 2);
    try std.testing.expectEqual(@as(u8, 3), leafCount(&tree));

    // Remove left child of root (index 1, slot 0).
    // Sibling is right child of root (index 2, which is a split with children at 5, 6).
    try removeLeaf(&tree, 1);

    // Root should now be the split that was at index 2.
    try std.testing.expect(tree[0] != null);
    try std.testing.expect(tree[0].? == .split);
    // Its children should now be at heap positions 1 and 2.
    try std.testing.expect(tree[1] != null);
    try std.testing.expect(tree[1].? == .leaf);
    try std.testing.expect(tree[2] != null);
    try std.testing.expect(tree[2].? == .leaf);
    try std.testing.expectEqual(@as(u8, 2), leafCount(&tree));
}
