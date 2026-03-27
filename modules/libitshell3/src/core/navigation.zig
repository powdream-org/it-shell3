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
    tree: *const [types.MAX_TREE_NODES]?SplitNodeData,
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
    tree: *const [types.MAX_TREE_NODES]?SplitNodeData,
    node_idx: u8,
    rect: Rect,
    rects: *[types.MAX_PANES]?Rect,
) void {
    if (node_idx >= types.MAX_TREE_NODES) return;
    const node = tree[node_idx] orelse return;

    switch (node) {
        .leaf => |slot| {
            rects[slot] = rect;
        },
        .split => |s| {
            const left_idx = split_tree.leftChild(node_idx);
            const right_idx = split_tree.rightChild(node_idx);

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
            computeRectsNode(tree, left_idx, left_rect, rects);
            computeRectsNode(tree, right_idx, right_rect, rects);
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

/// Find the adjacent pane in the given direction from focused.
///
/// Algorithm (per daemon-architecture state-and-types spec):
/// 1. Compute bounding rects for all leaf panes.
/// 2. Find focused rect.
/// 3. Among other leaf panes, find candidates whose shared edge touches the
///    focused edge in the requested direction, with perpendicular overlap.
/// 4. Pick the candidate with shortest edge distance; tie-break: lowest slot.
/// 5. If no direct neighbor found, wrap around to the furthest pane in the
///    opposite direction with perpendicular overlap.
/// 6. Return null only for single-pane sessions.
pub fn findPaneInDirection(
    tree: *const [types.MAX_TREE_NODES]?SplitNodeData,
    total_cols: u16,
    total_rows: u16,
    focused: types.PaneSlot,
    direction: types.Direction,
) ?types.PaneSlot {
    const epsilon: f32 = 0.5;

    const rects = computeRects(tree, total_cols, total_rows);
    const focused_rect = rects[focused] orelse return null;

    var best_slot: ?types.PaneSlot = null;
    var best_distance: f32 = std.math.inf(f32);

    // Collect direct neighbors: edge adjacent in `direction` with perpendicular overlap.
    var slot: u32 = 0;
    while (slot < types.MAX_PANES) : (slot += 1) {
        const candidate_slot: types.PaneSlot = @intCast(slot);
        if (candidate_slot == focused) continue;
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

        // Compute edge distance (distance between focused edge and candidate's adjacent edge).
        const edge_distance: f32 = switch (direction) {
            .left => @abs(focused_rect.x - candidate_rect.right()),
            .right => @abs(candidate_rect.x - focused_rect.right()),
            .up => @abs(focused_rect.y - candidate_rect.bottom()),
            .down => @abs(candidate_rect.y - focused_rect.bottom()),
        };

        // Pick best: shortest edge distance, tie-break: lowest slot index.
        const is_better = edge_distance < best_distance or
            (edge_distance == best_distance and (best_slot == null or candidate_slot < best_slot.?));
        if (is_better) {
            best_distance = edge_distance;
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

    var wrap_slot: ?types.PaneSlot = null;
    var wrap_extreme: f32 = -1.0; // sentinel

    var s2: u32 = 0;
    while (s2 < types.MAX_PANES) : (s2 += 1) {
        const candidate_slot: types.PaneSlot = @intCast(s2);
        if (candidate_slot == focused) continue;
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

test "findPaneInDirection: single pane navigate any direction returns null" {
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

test "findPaneInDirection: two panes horizontal split navigate left/right" {
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);

    try std.testing.expectEqual(
        @as(?types.PaneSlot, 1),
        findPaneInDirection(&tree, 80, 24, 0, .right),
    );
    try std.testing.expectEqual(
        @as(?types.PaneSlot, 0),
        findPaneInDirection(&tree, 80, 24, 1, .left),
    );
}

test "findPaneInDirection: two panes horizontal split no vertical neighbor wraps to null" {
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);

    const result_up = findPaneInDirection(&tree, 80, 24, 0, .up);
    const result_down = findPaneInDirection(&tree, 80, 24, 0, .down);
    try std.testing.expectEqual(@as(?types.PaneSlot, null), result_up);
    try std.testing.expectEqual(@as(?types.PaneSlot, null), result_down);
}

test "findPaneInDirection: two panes vertical split navigate down/up" {
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .vertical, 0.5, 1);

    try std.testing.expectEqual(
        @as(?types.PaneSlot, 1),
        findPaneInDirection(&tree, 80, 24, 0, .down),
    );
    try std.testing.expectEqual(
        @as(?types.PaneSlot, 0),
        findPaneInDirection(&tree, 80, 24, 1, .up),
    );
}

test "findPaneInDirection: three panes left half + right half split top/bottom" {
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    const right_node = split_tree.findLeafBySlot(&tree, 1).?;
    try split_tree.splitLeaf(&tree, right_node, .vertical, 0.5, 2);

    const right_from_0 = findPaneInDirection(&tree, 80, 24, 0, .right);
    try std.testing.expect(right_from_0 != null);
    // Both pane 1 and pane 2 have equal edge distance (0), tie-break = slot 1.
    try std.testing.expectEqual(@as(types.PaneSlot, 1), right_from_0.?);

    const down_from_1 = findPaneInDirection(&tree, 80, 24, 1, .down);
    try std.testing.expectEqual(@as(?types.PaneSlot, 2), down_from_1);
}

test "findPaneInDirection: tie-break equal distance selects lowest slot index" {
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    const left_node = split_tree.findLeafBySlot(&tree, 0).?;
    try split_tree.splitLeaf(&tree, left_node, .vertical, 0.5, 2);
    const right_node = split_tree.findLeafBySlot(&tree, 1).?;
    try split_tree.splitLeaf(&tree, right_node, .vertical, 0.5, 3);

    const right_from_0 = findPaneInDirection(&tree, 80, 24, 0, .right);
    try std.testing.expectEqual(@as(?types.PaneSlot, 1), right_from_0);

    const down_from_0 = findPaneInDirection(&tree, 80, 24, 0, .down);
    try std.testing.expectEqual(@as(?types.PaneSlot, 2), down_from_0);

    const right_from_2 = findPaneInDirection(&tree, 80, 24, 2, .right);
    try std.testing.expectEqual(@as(?types.PaneSlot, 3), right_from_2);
}

test "findPaneInDirection: wrap-around navigating past edge" {
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .vertical, 0.5, 1);

    const up_from_0 = findPaneInDirection(&tree, 80, 24, 0, .up);
    try std.testing.expectEqual(@as(?types.PaneSlot, 1), up_from_0);

    const down_from_1 = findPaneInDirection(&tree, 80, 24, 1, .down);
    try std.testing.expectEqual(@as(?types.PaneSlot, 0), down_from_1);
}

test "findPaneInDirection: non-adjacent pane wraps" {
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    const right_node = split_tree.findLeafBySlot(&tree, 1).?;
    try split_tree.splitLeaf(&tree, right_node, .vertical, 0.5, 2);

    const right_from_1 = findPaneInDirection(&tree, 80, 24, 1, .right);
    try std.testing.expectEqual(@as(?types.PaneSlot, 0), right_from_1);
}

test "findPaneInDirection: shortest edge distance wins over greatest overlap" {
    // Layout (80x24):
    //   Pane 0: left half, full height (0,0 40x24)
    //   Pane 1: right-top, 25% height  (40,0 40x6)
    //   Pane 2: right-bottom, 75% height (40,6 40x18)
    //
    // From pane 0, navigating right: both pane 1 and pane 2 are edge-adjacent
    // (edge distance ~0). Pane 2 has greater perpendicular overlap (18 rows vs
    // 6 rows). Under a "greatest overlap" algorithm, pane 2 would be selected.
    // Under the correct "shortest edge distance" algorithm, both have equal
    // edge distance, so tie-break by lowest slot index selects pane 1.
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    const right_node = split_tree.findLeafBySlot(&tree, 1).?;
    try split_tree.splitLeaf(&tree, right_node, .vertical, 0.25, 2);

    // Verify geometry: pane 2 has greater overlap with pane 0 than pane 1.
    const rects = computeRects(&tree, 80, 24);
    const r0 = rects[0].?;
    const r1 = rects[1].?;
    const r2 = rects[2].?;

    // Pane 1 overlap with pane 0 (vertical): 6 rows
    const overlap_1 = intervalOverlap(r0.y, r0.bottom(), r1.y, r1.bottom());
    // Pane 2 overlap with pane 0 (vertical): 18 rows
    const overlap_2 = intervalOverlap(r0.y, r0.bottom(), r2.y, r2.bottom());
    try std.testing.expect(overlap_2 > overlap_1);

    // Algorithm picks pane 1 (shortest edge distance tie-broken by lowest slot),
    // NOT pane 2 (which has greater overlap).
    const result = findPaneInDirection(&tree, 80, 24, 0, .right);
    try std.testing.expectEqual(@as(?types.PaneSlot, 1), result);
}

test "computeRects: two pane horizontal split geometry" {
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);

    const rects = computeRects(&tree, 80, 24);
    const r0 = rects[0].?;
    const r1 = rects[1].?;

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), r0.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), r0.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), r0.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), r0.height, 0.01);

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

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), r0.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), r0.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), r0.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), r0.height, 0.01);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), r1.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), r1.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), r1.width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), r1.height, 0.01);
}
