const std = @import("std");
const types = @import("types.zig");
const split_tree = @import("split_tree.zig");

pub const SplitNodeData = split_tree.SplitNodeData;

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn right(self: Rect) f32 {
        return self.x + self.width;
    }

    pub fn bottom(self: Rect) f32 {
        return self.y + self.height;
    }
};

/// Compute bounding rectangles for all leaf panes, indexed by PaneSlot.
/// Returns an array of ?Rect with MAX_PANES entries. Slots not present in the
/// tree have null entries.
pub fn computeRects(
    tree: *const [types.MAX_TREE_NODES]SplitNodeData,
    total_cols: u16,
    total_rows: u16,
) [types.MAX_PANES]?Rect {
    var rects: [types.MAX_PANES]?Rect = .{null} ** types.MAX_PANES;
    const root_rect = Rect{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(total_cols),
        .height = @floatFromInt(total_rows),
    };
    computeRectsNode(tree, 0, root_rect, &rects);
    return rects;
}

fn computeRectsNode(
    tree: *const [types.MAX_TREE_NODES]SplitNodeData,
    node_idx: u5,
    rect: Rect,
    rects: *[types.MAX_PANES]?Rect,
) void {
    switch (tree[node_idx]) {
        .empty => {},
        .leaf => |slot| {
            rects[slot] = rect;
        },
        .split => |s| {
            // horizontal orientation: left/right split (side by side)
            // vertical orientation: top/bottom split (stacked)
            const left_rect: Rect = switch (s.orientation) {
                .horizontal => Rect{
                    .x = rect.x,
                    .y = rect.y,
                    .width = rect.width * s.ratio,
                    .height = rect.height,
                },
                .vertical => Rect{
                    .x = rect.x,
                    .y = rect.y,
                    .width = rect.width,
                    .height = rect.height * s.ratio,
                },
            };
            const right_rect: Rect = switch (s.orientation) {
                .horizontal => Rect{
                    .x = rect.x + rect.width * s.ratio,
                    .y = rect.y,
                    .width = rect.width * (1.0 - s.ratio),
                    .height = rect.height,
                },
                .vertical => Rect{
                    .x = rect.x,
                    .y = rect.y + rect.height * s.ratio,
                    .width = rect.width,
                    .height = rect.height * (1.0 - s.ratio),
                },
            };
            computeRectsNode(tree, s.left, left_rect, rects);
            computeRectsNode(tree, s.right, right_rect, rects);
        },
    }
}

/// Returns the length of the overlap between intervals [a0, a1) and [b0, b1).
/// Returns 0 if they do not overlap.
fn intervalOverlap(a0: f32, a1: f32, b0: f32, b1: f32) f32 {
    const lo = @max(a0, b0);
    const hi = @min(a1, b1);
    if (hi > lo) return hi - lo;
    return 0.0;
}

/// Find the adjacent pane in the given direction from focused_slot.
///
/// Algorithm:
/// 1. Compute bounding rects for all leaf panes.
/// 2. Find focused rect.
/// 3. Among other leaf panes, find candidates whose shared edge touches the
///    focused edge in the requested direction, with perpendicular overlap.
/// 4. Pick the candidate with greatest edge overlap; tie-break: lowest slot.
/// 5. If no direct neighbor found, wrap around to the furthest pane in the
///    opposite direction with perpendicular overlap.
/// 6. Return null only for single-pane sessions.
pub fn findPaneInDirection(
    tree: *const [types.MAX_TREE_NODES]SplitNodeData,
    total_cols: u16,
    total_rows: u16,
    focused_slot: types.PaneSlot,
    direction: types.Direction,
) ?types.PaneSlot {
    const epsilon: f32 = 0.5;

    const rects = computeRects(tree, total_cols, total_rows);
    const focused_rect = rects[focused_slot] orelse return null;

    var best_slot: ?types.PaneSlot = null;
    var best_overlap: f32 = -1.0;

    // Collect direct neighbors: edge touching in `direction` with overlap.
    var slot: u5 = 0;
    while (slot < types.MAX_PANES) : (slot += 1) {
        const candidate_slot: types.PaneSlot = @truncate(slot);
        if (candidate_slot == focused_slot) continue;
        const candidate_rect = rects[candidate_slot] orelse continue;

        const is_adjacent: bool = switch (direction) {
            .left => @abs(candidate_rect.right() - focused_rect.x) < epsilon,
            .right => @abs(candidate_rect.x - focused_rect.right()) < epsilon,
            .up => @abs(candidate_rect.bottom() - focused_rect.y) < epsilon,
            .down => @abs(candidate_rect.y - focused_rect.bottom()) < epsilon,
        };
        if (!is_adjacent) continue;

        // Compute perpendicular overlap.
        const overlap: f32 = switch (direction) {
            .left, .right => intervalOverlap(
                focused_rect.y,
                focused_rect.bottom(),
                candidate_rect.y,
                candidate_rect.bottom(),
            ),
            .up, .down => intervalOverlap(
                focused_rect.x,
                focused_rect.right(),
                candidate_rect.x,
                candidate_rect.right(),
            ),
        };
        if (overlap <= 0.0) continue;

        // Pick best: greatest overlap, tie-break: lowest slot index.
        const is_better = overlap > best_overlap or
            (overlap == best_overlap and (best_slot == null or candidate_slot < best_slot.?));
        if (is_better) {
            best_overlap = overlap;
            best_slot = candidate_slot;
        }
    }

    if (best_slot != null) return best_slot;

    // Step 5: wrap-around — search opposite direction for furthest pane with overlap.
    const opposite: types.Direction = switch (direction) {
        .left => .right,
        .right => .left,
        .up => .down,
        .down => .up,
    };

    // "Furthest" means the pane whose edge in `opposite` direction is as far as
    // possible from the focused edge in `direction`.
    var wrap_slot: ?types.PaneSlot = null;
    var wrap_extreme: f32 = -1.0; // sentinel

    var s2: u5 = 0;
    while (s2 < types.MAX_PANES) : (s2 += 1) {
        const candidate_slot: types.PaneSlot = @truncate(s2);
        if (candidate_slot == focused_slot) continue;
        const candidate_rect = rects[candidate_slot] orelse continue;

        // Must have perpendicular overlap with focused.
        const overlap: f32 = switch (direction) {
            .left, .right => intervalOverlap(
                focused_rect.y,
                focused_rect.bottom(),
                candidate_rect.y,
                candidate_rect.bottom(),
            ),
            .up, .down => intervalOverlap(
                focused_rect.x,
                focused_rect.right(),
                candidate_rect.x,
                candidate_rect.right(),
            ),
        };
        if (overlap <= 0.0) continue;

        // For wrap, pick furthest in the opposite direction.
        // For left wrap (going right): highest right edge (furthest right).
        // For right wrap (going left): lowest left edge (furthest left).
        // For up wrap (going down): highest bottom edge (furthest down).
        // For down wrap (going up): lowest top edge (furthest up).
        const metric: f32 = switch (opposite) {
            .right => candidate_rect.right(),
            .left => -candidate_rect.x,
            .down => candidate_rect.bottom(),
            .up => -candidate_rect.y,
        };

        const is_better = wrap_extreme < 0.0 or metric > wrap_extreme or
            (metric == wrap_extreme and (wrap_slot == null or candidate_slot < wrap_slot.?));
        if (is_better) {
            wrap_extreme = metric;
            wrap_slot = candidate_slot;
        }
    }

    return wrap_slot;
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "single pane: navigate any direction returns null" {
    const tree = split_tree.initSingleLeaf(0);
    try std.testing.expectEqual(
        @as(?types.PaneSlot, null),
        findPaneInDirection(&tree, 80, 24, 0, .left),
    );
    try std.testing.expectEqual(
        @as(?types.PaneSlot, null),
        findPaneInDirection(&tree, 80, 24, 0, .right),
    );
    try std.testing.expectEqual(
        @as(?types.PaneSlot, null),
        findPaneInDirection(&tree, 80, 24, 0, .up),
    );
    try std.testing.expectEqual(
        @as(?types.PaneSlot, null),
        findPaneInDirection(&tree, 80, 24, 0, .down),
    );
}

test "two panes horizontal split: navigate left/right" {
    // horizontal split: pane 0 on left, pane 1 on right
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);

    // right from pane 0 → pane 1
    try std.testing.expectEqual(
        @as(?types.PaneSlot, 1),
        findPaneInDirection(&tree, 80, 24, 0, .right),
    );
    // left from pane 1 → pane 0
    try std.testing.expectEqual(
        @as(?types.PaneSlot, 0),
        findPaneInDirection(&tree, 80, 24, 1, .left),
    );
}

test "two panes horizontal split: no vertical neighbor (direct) but wraps" {
    // horizontal split: pane 0 on left, pane 1 on right
    // up/down: no vertical neighbors; wrap-around yields the other pane with
    // perpendicular overlap only if the other pane has horizontal overlap.
    // Both panes span the full height so "up" wrap from pane 0 should find pane 1
    // (furthest down = pane with largest bottom, which is both equally — tie-break
    // lowest slot = pane 0, but that's ourselves; so pane 1 wins).
    // Actually: there are no direct up/down neighbors (no pane above or below).
    // Wrap looks for furthest in opposite direction with perpendicular overlap.
    // For .up from pane 0: opposite = .down, perpendicular = horizontal overlap.
    // Pane 1 is beside pane 0 — do they overlap horizontally? No, they are split
    // side by side, so their x ranges don't overlap.
    // → wrap should return null too (no pane with horizontal overlap in up direction).
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);

    // No vertical neighbors and no wrap possible (no perpendicular overlap)
    // because both panes share no horizontal range overlap (they are side by side).
    // Actually wait — pane 0 spans x=[0,40) and pane 1 spans x=[40,80).
    // For up/down navigation, perpendicular = horizontal ranges.
    // They don't overlap horizontally, so no wrap either.
    const result_up = findPaneInDirection(&tree, 80, 24, 0, .up);
    const result_down = findPaneInDirection(&tree, 80, 24, 0, .down);
    try std.testing.expectEqual(@as(?types.PaneSlot, null), result_up);
    try std.testing.expectEqual(@as(?types.PaneSlot, null), result_down);
}

test "two panes vertical split: navigate down/up" {
    // vertical split: pane 0 on top, pane 1 on bottom
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .vertical, 0.5, 1);

    // down from pane 0 → pane 1
    try std.testing.expectEqual(
        @as(?types.PaneSlot, 1),
        findPaneInDirection(&tree, 80, 24, 0, .down),
    );
    // up from pane 1 → pane 0
    try std.testing.expectEqual(
        @as(?types.PaneSlot, 0),
        findPaneInDirection(&tree, 80, 24, 1, .up),
    );
}

test "three panes: left half + right half split top/bottom" {
    // Layout:
    //   +--------+--------+
    //   |        | pane 1 |
    //   | pane 0 +--------+
    //   |        | pane 2 |
    //   +--------+--------+
    //
    // Build: split root horizontally → pane 0 (left), pane 1 (right).
    // Then split the right child vertically → pane 1 (top-right), pane 2 (bottom-right).
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    // Find the leaf for pane 1 and split it vertically
    const right_node = split_tree.findLeafBySlot(&tree, 1).?;
    try split_tree.splitLeaf(&tree, right_node, .vertical, 0.5, 2);

    // right from pane 0: pane 1 has more overlap than pane 2? Both share
    // equal right-edge with pane 0's right edge. Pane 1 and pane 2 each cover
    // half the height. Pane 0 covers full height. Each has 50% overlap.
    // Tie-break: lowest slot = pane 1.
    const right_from_0 = findPaneInDirection(&tree, 80, 24, 0, .right);
    try std.testing.expect(right_from_0 != null);
    // Both pane 1 and pane 2 have equal overlap (both half height), tie-break = slot 1
    try std.testing.expectEqual(@as(types.PaneSlot, 1), right_from_0.?);

    // down from top-right (pane 1) → bottom-right (pane 2)
    const down_from_1 = findPaneInDirection(&tree, 80, 24, 1, .down);
    try std.testing.expectEqual(@as(?types.PaneSlot, 2), down_from_1);
}

test "tie-break: equal overlap selects lowest slot index" {
    // Four-pane layout: 2x2 grid
    // pane 0 (top-left), pane 1 (top-right), pane 2 (bottom-left), pane 3 (bottom-right)
    // Build: root horizontal → left (pane 0) and right (pane 1).
    // Split left vertical → pane 0 (top) and pane 2 (bottom).
    // Split right vertical → pane 1 (top) and pane 3 (bottom).
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    const left_node = split_tree.findLeafBySlot(&tree, 0).?;
    try split_tree.splitLeaf(&tree, left_node, .vertical, 0.5, 2);
    const right_node = split_tree.findLeafBySlot(&tree, 1).?;
    try split_tree.splitLeaf(&tree, right_node, .vertical, 0.5, 3);

    // right from pane 0 (top-left): adjacent to both pane 1 (top-right) and
    // pane 3 (bottom-right)? No — pane 0 is only top half, pane 1 is top half,
    // pane 3 is bottom half. So only pane 1 has vertical overlap with pane 0.
    const right_from_0 = findPaneInDirection(&tree, 80, 24, 0, .right);
    try std.testing.expectEqual(@as(?types.PaneSlot, 1), right_from_0);

    // down from pane 0 (top-left) → pane 2 (bottom-left)
    const down_from_0 = findPaneInDirection(&tree, 80, 24, 0, .down);
    try std.testing.expectEqual(@as(?types.PaneSlot, 2), down_from_0);

    // right from pane 2 (bottom-left): adjacent to pane 3 (bottom-right), not pane 1
    const right_from_2 = findPaneInDirection(&tree, 80, 24, 2, .right);
    try std.testing.expectEqual(@as(?types.PaneSlot, 3), right_from_2);
}

test "wrap-around: navigating past edge wraps to opposite side" {
    // Two panes vertical split: pane 0 top, pane 1 bottom.
    // Navigating up from pane 0 → wraps to pane 1 (furthest bottom).
    // Navigating down from pane 1 → wraps to pane 0 (furthest top).
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .vertical, 0.5, 1);

    const up_from_0 = findPaneInDirection(&tree, 80, 24, 0, .up);
    try std.testing.expectEqual(@as(?types.PaneSlot, 1), up_from_0);

    const down_from_1 = findPaneInDirection(&tree, 80, 24, 1, .down);
    try std.testing.expectEqual(@as(?types.PaneSlot, 0), down_from_1);
}

test "non-adjacent panes: no shared edge returns null (or wraps)" {
    // Three panes: pane 0 left, pane 1 top-right, pane 2 bottom-right.
    // Navigating left from pane 2 has no direct left neighbor (pane 0 is to the
    // left but they do share the left-right edge across full height — pane 0's
    // right edge = pane 2's left edge, and they have vertical overlap).
    // So this test uses a layout where a pane truly has no neighbor in a direction.
    // For example, pane 1 (top-right): navigating right has no direct neighbor.
    // It should wrap to the furthest-left pane with vertical overlap = pane 0.
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    const right_node = split_tree.findLeafBySlot(&tree, 1).?;
    try split_tree.splitLeaf(&tree, right_node, .vertical, 0.5, 2);

    // Pane 1 is top-right: navigating right → no direct neighbor → wrap
    const right_from_1 = findPaneInDirection(&tree, 80, 24, 1, .right);
    // Wrap: furthest left with vertical overlap. Pane 0 spans full height,
    // pane 1 spans top half — they have vertical overlap. Pane 0 is the only
    // candidate → result = pane 0.
    try std.testing.expectEqual(@as(?types.PaneSlot, 0), right_from_1);
}

test "computeRects: two pane horizontal split geometry" {
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);

    const rects = computeRects(&tree, 80, 24);
    const r0 = rects[0].?;
    const r1 = rects[1].?;

    // Pane 0: left half
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), r0.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), r0.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), r0.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), r0.height, 0.01);

    // Pane 1: right half
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), r1.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), r1.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), r1.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), r1.height, 0.01);
}

test "computeRects: two pane vertical split geometry" {
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .vertical, 0.5, 1);

    const rects = computeRects(&tree, 80, 24);
    const r0 = rects[0].?;
    const r1 = rects[1].?;

    // Pane 0: top half
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), r0.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), r0.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), r0.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), r0.height, 0.01);

    // Pane 1: bottom half
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), r1.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), r1.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), r1.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), r1.height, 0.01);
}
