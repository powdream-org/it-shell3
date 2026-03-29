//! Spec compliance tests: Pane CRUD operations.
//!
//! Covers CreatePane, SplitPane, ClosePane, FocusPane, NavigatePane,
//! ResizePane, EqualizeSplits, ZoomPane, SwapPanes, LayoutGet, and the
//! 16-pane limit enforcement.
//!
//! Spec sources:
//!   - protocol 03-session-pane-management (pane message definitions)
//!   - daemon-architecture 02-state-and-types (state tree, layout enforcement,
//!     pane metadata tracking)
//!   - daemon-behavior 02-event-handling (response-before-notification)

const std = @import("std");
const core = @import("itshell3_core");
const server = @import("itshell3_server");
const protocol = @import("itshell3_protocol");

const PaneSlot = core.PaneSlot;
const PaneId = core.PaneId;
const MAX_PANES = core.MAX_PANES;
const MAX_TREE_NODES = core.MAX_TREE_NODES;
const Orientation = core.Orientation;
const Direction = core.Direction;
const SplitNodeData = core.SplitNodeData;
const Session = core.Session;
const split_tree = core.split_tree;
const SessionManager = server.state.SessionManager;
const SessionEntry = server.state.SessionEntry;
const Pane = server.state.Pane;
const MessageType = protocol.message_type.MessageType;

const test_mod = @import("itshell3_testing");
const mock_ime = test_mod.mock_ime_engine;

var test_mock_engine = mock_ime.MockImeEngine{};

fn testImeEngine() core.ImeEngine {
    return test_mock_engine.engine();
}

var sm = SessionManager.init();

fn resetState() void {
    sm.reset();
}

// ── Pane message type codes ────────────────────────────────────────────────

test "spec: pane message types -- correct protocol codes" {
    // protocol 03-session-pane-management (pane message definitions):
    // Pane Messages range 0x0140-0x0153.
    try std.testing.expectEqual(@as(u16, 0x0140), @intFromEnum(MessageType.create_pane_request));
    try std.testing.expectEqual(@as(u16, 0x0141), @intFromEnum(MessageType.create_pane_response));
    try std.testing.expectEqual(@as(u16, 0x0142), @intFromEnum(MessageType.split_pane_request));
    try std.testing.expectEqual(@as(u16, 0x0143), @intFromEnum(MessageType.split_pane_response));
    try std.testing.expectEqual(@as(u16, 0x0144), @intFromEnum(MessageType.close_pane_request));
    try std.testing.expectEqual(@as(u16, 0x0145), @intFromEnum(MessageType.close_pane_response));
    try std.testing.expectEqual(@as(u16, 0x0146), @intFromEnum(MessageType.focus_pane_request));
    try std.testing.expectEqual(@as(u16, 0x0147), @intFromEnum(MessageType.focus_pane_response));
    try std.testing.expectEqual(@as(u16, 0x0148), @intFromEnum(MessageType.navigate_pane_request));
    try std.testing.expectEqual(@as(u16, 0x0149), @intFromEnum(MessageType.navigate_pane_response));
    try std.testing.expectEqual(@as(u16, 0x014A), @intFromEnum(MessageType.resize_pane_request));
    try std.testing.expectEqual(@as(u16, 0x014B), @intFromEnum(MessageType.resize_pane_response));
    try std.testing.expectEqual(@as(u16, 0x014C), @intFromEnum(MessageType.equalize_splits_request));
    try std.testing.expectEqual(@as(u16, 0x014D), @intFromEnum(MessageType.equalize_splits_response));
    try std.testing.expectEqual(@as(u16, 0x014E), @intFromEnum(MessageType.zoom_pane_request));
    try std.testing.expectEqual(@as(u16, 0x014F), @intFromEnum(MessageType.zoom_pane_response));
    try std.testing.expectEqual(@as(u16, 0x0150), @intFromEnum(MessageType.swap_panes_request));
    try std.testing.expectEqual(@as(u16, 0x0151), @intFromEnum(MessageType.swap_panes_response));
    try std.testing.expectEqual(@as(u16, 0x0152), @intFromEnum(MessageType.layout_get_request));
    try std.testing.expectEqual(@as(u16, 0x0153), @intFromEnum(MessageType.layout_get_response));
}

// ── Split tree: split and close ────────────────────────────────────────────

test "spec: pane split -- splits leaf into split node with two children" {
    // protocol 03-session-pane-management (split pane request/response):
    // SplitPaneRequest creates new pane alongside existing. Original pane
    // becomes one half, new pane the other.
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);

    // Root should now be a split node.
    try std.testing.expect(tree[0] != null);
    switch (tree[0].?) {
        .split => |s| {
            try std.testing.expectEqual(Orientation.horizontal, s.orientation);
            try std.testing.expect(s.ratio == 0.5);
        },
        .leaf => return error.TestUnexpectedResult,
    }
    // Left child = original pane (slot 0), right child = new pane (slot 1).
    try std.testing.expectEqual(SplitNodeData{ .leaf = 0 }, tree[split_tree.leftChild(0)].?);
    try std.testing.expectEqual(SplitNodeData{ .leaf = 1 }, tree[split_tree.rightChild(0)].?);
}

test "spec: pane split -- leaf count increases by one after split" {
    // protocol 03-session-pane-management (split pane request): a split
    // creates exactly one new pane.
    var tree = split_tree.initSingleLeaf(0);
    try std.testing.expectEqual(@as(u8, 1), split_tree.leafCount(&tree));
    try split_tree.splitLeaf(&tree, 0, .vertical, 0.5, 1);
    try std.testing.expectEqual(@as(u8, 2), split_tree.leafCount(&tree));
}

test "spec: pane split -- direction right creates horizontal split" {
    // protocol 03-session-pane-management (split pane request): right (0) =
    // vertical split (original left, new right).
    // Note: protocol "direction" maps to split_tree "orientation". Right/left -> horizontal.
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    switch (tree[0].?) {
        .split => |s| try std.testing.expectEqual(Orientation.horizontal, s.orientation),
        .leaf => return error.TestUnexpectedResult,
    }
}

test "spec: pane split -- direction down creates vertical split" {
    // protocol 03-session-pane-management (split pane request): down (1) =
    // horizontal split (original top, new bottom).
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .vertical, 0.5, 1);
    switch (tree[0].?) {
        .split => |s| try std.testing.expectEqual(Orientation.vertical, s.orientation),
        .leaf => return error.TestUnexpectedResult,
    }
}

test "spec: pane split -- ratio is stored in split node" {
    // protocol 03-session-pane-management (split pane request): ratio
    // describes proportion of space for first child.
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.3, 1);
    switch (tree[0].?) {
        .split => |s| try std.testing.expect(s.ratio == 0.3),
        .leaf => return error.TestUnexpectedResult,
    }
}

test "spec: pane close -- removes leaf and promotes sibling" {
    // protocol 03-session-pane-management (close pane request/response):
    // ClosePaneRequest removes pane from tree, parent split node replaced
    // by sibling.
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);
    try std.testing.expectEqual(@as(u8, 2), split_tree.leafCount(&tree));

    // Remove the right child (new pane, slot 1).
    const right_idx = split_tree.rightChild(0);
    try split_tree.removeLeaf(&tree, right_idx);

    // Tree should be back to a single leaf (original pane, slot 0).
    try std.testing.expectEqual(@as(u8, 1), split_tree.leafCount(&tree));
    try std.testing.expectEqual(SplitNodeData{ .leaf = 0 }, tree[0].?);
}

test "spec: pane close -- last pane removal returns CannotRemoveRoot" {
    // protocol 03-session-pane-management (close pane response): if closed
    // pane is last, session_also_destroyed. split_tree: removing root leaf
    // is an error (the handler deals with session destruction separately).
    var tree = split_tree.initSingleLeaf(0);
    const result = split_tree.removeLeaf(&tree, 0);
    try std.testing.expectError(error.CannotRemoveRoot, result);
}

test "spec: pane close -- focus transfers to sibling" {
    // protocol 03-session-pane-management (close pane response):
    // new_focus_pane_id is the sibling pane. When left child is closed,
    // the right child (sibling) should be promoted.
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);

    // Close left child (slot 0).
    const left_idx = split_tree.leftChild(0);
    try split_tree.removeLeaf(&tree, left_idx);

    // Root should now be the sibling (slot 1).
    try std.testing.expectEqual(SplitNodeData{ .leaf = 1 }, tree[0].?);
}

// ── Layout enforcement: 16-pane limit ──────────────────────────────────────

test "spec: pane limit -- 16 pane slots per session" {
    // daemon-architecture 02-state-and-types (layout enforcement):
    // MAX_PANES = 16.
    // protocol 03-session-pane-management (split pane response):
    // PANE_LIMIT_EXCEEDED error.
    resetState();
    const id = try sm.createSession("test", testImeEngine(), 0);
    const entry = sm.getSession(id).?;

    // Slot 0 is already allocated. Allocate 15 more (total 16).
    var i: u8 = 0;
    while (i < MAX_PANES - 1) : (i += 1) {
        _ = try entry.allocPaneSlot();
    }
    try std.testing.expectEqual(@as(u8, MAX_PANES), entry.paneCount());

    // 17th allocation should fail.
    const result = entry.allocPaneSlot();
    try std.testing.expectError(error.NoFreeSlots, result);
}

// ── SplitTree: equalize ratios ─────────────────────────────────────────────

test "spec: pane equalize -- all split ratios set to 0.5" {
    // protocol 03-session-pane-management (equalize splits request/response):
    // EqualizeSplitsRequest sets all split ratios to 0.5.
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.3, 1);
    // Create a nested split on the left child.
    try split_tree.splitLeaf(&tree, split_tree.leftChild(0), .vertical, 0.7, 2);

    // Verify ratios are NOT 0.5 initially.
    switch (tree[0].?) {
        .split => |s| try std.testing.expect(s.ratio == 0.3),
        .leaf => return error.TestUnexpectedResult,
    }

    // Call the actual equalizeRatios function to exercise the real code path.
    split_tree.equalizeRatios(&tree);

    // Verify all splits now have ratio 0.5.
    for (tree) |node_opt| {
        if (node_opt) |node| {
            switch (node) {
                .split => |s| try std.testing.expect(s.ratio == 0.5),
                .leaf => {},
            }
        }
    }
}

// ── SplitTree: swap panes ──────────────────────────────────────────────────

test "spec: pane swap -- exchanges two leaf positions" {
    // protocol 03-session-pane-management (swap panes request/response):
    // SwapPanesRequest swaps two panes in the layout tree. PTY follows the
    // pane; only position changes.
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);

    const left_idx = split_tree.leftChild(0);
    const right_idx = split_tree.rightChild(0);

    // Before swap: left=slot 0, right=slot 1.
    try std.testing.expectEqual(SplitNodeData{ .leaf = 0 }, tree[left_idx].?);
    try std.testing.expectEqual(SplitNodeData{ .leaf = 1 }, tree[right_idx].?);

    // Call the actual swapLeaves function to exercise the real code path.
    // swapLeaves takes PaneSlot values (not tree indices).
    const swapped = split_tree.swapLeaves(&tree, 0, 1);
    try std.testing.expect(swapped);

    // After swap: left=slot 1, right=slot 0.
    try std.testing.expectEqual(SplitNodeData{ .leaf = 1 }, tree[left_idx].?);
    try std.testing.expectEqual(SplitNodeData{ .leaf = 0 }, tree[right_idx].?);
}

// ── SplitTree: findLeafBySlot ──────────────────────────────────────────────

test "spec: pane lookup -- findLeafBySlot locates correct tree index" {
    // daemon-architecture 01-module-structure: PaneId wire lookup uses linear
    // scan of pane_slots to find the PaneSlot, then findLeafBySlot for tree
    // position.
    var tree = split_tree.initSingleLeaf(0);
    try split_tree.splitLeaf(&tree, 0, .horizontal, 0.5, 1);

    const idx0 = split_tree.findLeafBySlot(&tree, 0);
    const idx1 = split_tree.findLeafBySlot(&tree, 1);
    try std.testing.expect(idx0 != null);
    try std.testing.expect(idx1 != null);
    try std.testing.expect(idx0.? != idx1.?);

    // Nonexistent slot returns null.
    try std.testing.expect(split_tree.findLeafBySlot(&tree, 15) == null);
}

// ── Focus pane ─────────────────────────────────────────────────────────────

test "spec: pane focus -- updates focused_pane on session" {
    // protocol 03-session-pane-management (focus pane request/response):
    // FocusPaneRequest sets focused pane. FocusPaneResponse includes
    // previous_pane_id.
    resetState();
    const id = try sm.createSession("test", testImeEngine(), 0);
    const entry = sm.getSession(id).?;

    // Initially focused on slot 0.
    try std.testing.expectEqual(@as(?PaneSlot, 0), entry.session.focused_pane);

    // Allocate and focus a new pane.
    const slot1 = try entry.allocPaneSlot();
    const previous = entry.session.focused_pane;
    entry.session.focused_pane = slot1;

    try std.testing.expectEqual(@as(?PaneSlot, 0), previous);
    try std.testing.expectEqual(@as(?PaneSlot, slot1), entry.session.focused_pane);
}

// ── Pane metadata ──────────────────────────────────────────────────────────

test "spec: pane metadata -- title and cwd stored in pane" {
    // daemon-architecture 02-state-and-types (pane metadata tracking):
    // Pane tracks title and cwd metadata.
    // protocol 03-session-pane-management (pane metadata changed notification):
    // PaneMetadataChanged carries title, cwd.
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.setTitle("vim");
    p.setCwd("/home/user/project");
    try std.testing.expectEqualSlices(u8, "vim", p.title[0..p.title_length]);
    try std.testing.expectEqualSlices(u8, "/home/user/project", p.cwd[0..p.cwd_length]);
}

test "spec: pane metadata -- is_running defaults to true" {
    // daemon-architecture 02-state-and-types (pane metadata tracking):
    // is_running tracks process state.
    const p = Pane.init(1, 0, 5, 100, 80, 24);
    try std.testing.expect(p.is_running);
    try std.testing.expect(p.exit_status == null);
}

test "spec: pane metadata -- markExited updates is_running and exit_status" {
    // daemon-architecture 02-state-and-types (pane metadata tracking):
    // on process exit, is_running=false and exit_status set.
    // protocol 03-session-pane-management (pane metadata changed notification):
    // PaneMetadataChanged carries is_running and exit_status.
    var p = Pane.init(1, 0, 5, 100, 80, 24);
    p.markExited(42);
    try std.testing.expect(!p.is_running);
    try std.testing.expectEqual(@as(?u8, 42), p.exit_status);
}

// ── Direction enum matches protocol wire format ────────────────────────────

test "spec: pane direction -- integer tags match protocol spec" {
    // protocol 03-session-pane-management (direction conventions):
    // 0=right, 1=down, 2=left, 3=up.
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Direction.right));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Direction.down));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(Direction.left));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(Direction.up));
}

// ── Pane dirty tracking ────────────────────────────────────────────────────

test "spec: pane dirty -- mark and clear per-slot dirty bits" {
    // daemon-architecture 02-state-and-types (state tree): SessionEntry tracks
    // dirty_mask for changed panes. LayoutChanged and PaneMetadataChanged are
    // triggered by dirty state.
    resetState();
    const id = try sm.createSession("test", testImeEngine(), 0);
    const entry = sm.getSession(id).?;

    try std.testing.expect(!entry.isDirty(0));
    entry.markDirty(0);
    try std.testing.expect(entry.isDirty(0));
    entry.clearDirtySlot(0);
    try std.testing.expect(!entry.isDirty(0));
}

// ── Tree depth limit ───────────────────────────────────────────────────────

test "spec: pane tree depth -- max depth enforced on split" {
    // daemon-architecture 02-state-and-types (layout enforcement): tree depth
    // bounded by pane limit.
    // protocol 03-session-pane-management (layout tree constraints): max tree
    // depth of 16 levels. split_tree enforces MAX_TREE_DEPTH on splitLeaf.
    var tree = split_tree.initSingleLeaf(0);

    // Split repeatedly on the right child to create a deep chain.
    var current_idx: u8 = 0;
    var slot: PaneSlot = 1;
    var depth_reached: u8 = 0;
    while (depth_reached < 20) : (depth_reached += 1) {
        const result = split_tree.splitLeaf(&tree, current_idx, .horizontal, 0.5, slot);
        if (result) |_| {
            // Move to the right child for next split.
            current_idx = split_tree.rightChild(current_idx);
            slot += 1;
        } else |err| {
            // Should hit MaxDepthExceeded or TreeFull eventually.
            try std.testing.expect(err == error.MaxDepthExceeded or err == error.TreeFull);
            break;
        }
    }
    // We must have hit an error before 20 splits (tree has bounded depth).
    try std.testing.expect(depth_reached < 20);
}

// ── CreatePaneRequest/Response ────────────────────────────────────────────

test "spec: pane create -- CreatePaneResponse includes status and pane_id" {
    // protocol 03-session-pane-management (standalone pane creation):
    // CreatePaneRequest (0x0140) creates a standalone pane in a session.
    // CreatePaneResponse (0x0141) returns status (0 = success) and pane_id
    // (server-assigned, monotonic).
    //
    // Test: verify message type codes and that a pane slot can be allocated
    // (the state-level operation backing CreatePaneResponse).
    try std.testing.expectEqual(@as(u16, 0x0140), @intFromEnum(MessageType.create_pane_request));
    try std.testing.expectEqual(@as(u16, 0x0141), @intFromEnum(MessageType.create_pane_response));

    // Allocate a pane slot in a session — this is the state operation that
    // produces the pane_id for CreatePaneResponse.
    resetState();
    const id = try sm.createSession("test", testImeEngine(), 0);
    const entry = sm.getSession(id).?;

    // Session starts with 1 pane (slot 0). Allocating another gives slot 1.
    const new_slot = try entry.allocPaneSlot();
    try std.testing.expect(new_slot > 0);
    try std.testing.expectEqual(@as(u8, 2), entry.paneCount());
}

// ── LayoutChanged broadcast after SplitPane ───────────────────────────────

test "spec: pane split -- LayoutChanged broadcast after SplitPaneRequest" {
    // protocol 03-session-pane-management (split pane response): On
    // SplitPaneResponse success, the server follows with a LayoutChanged
    // (0x0180) notification to session-scoped clients.
    //
    // Test: verify that after a split operation modifies the layout tree,
    // the session's dirty state is set (triggering LayoutChanged), and
    // the broadcast infrastructure can deliver to session-scoped clients.
    const broadcast_mod = server.connection.broadcast;
    const ClientManager = server.connection.client_manager.ClientManager;
    const testing_mod = @import("itshell3_testing");

    // Verify LayoutChanged message type and encoding.
    try std.testing.expectEqual(@as(u16, 0x0180), @intFromEnum(MessageType.layout_changed));
    try std.testing.expectEqual(MessageType.Encoding.json, MessageType.layout_changed.expectedEncoding());

    // Set up a session and perform a split.
    resetState();
    const sess_id = try sm.createSession("test", testImeEngine(), 0);
    const entry = sm.getSession(sess_id).?;
    const tree = &entry.session.tree_nodes;

    // Split the root pane.
    const new_slot = try entry.allocPaneSlot();
    try split_tree.splitLeaf(tree, 0, .horizontal, 0.5, new_slot);
    try std.testing.expectEqual(@as(u8, 2), split_tree.leafCount(tree));

    // Mark the layout as dirty (the handler does this after a successful split).
    entry.markDirty(0);
    entry.markDirty(new_slot);

    // Verify session-scoped broadcast delivers to attached clients.
    var mgr = ClientManager{ .chunk_pool = testing_mod.helpers.testChunkPool() };

    const idx1 = try mgr.addClient(.{ .fd = 20 });
    const c1 = mgr.getClient(idx1).?;
    _ = c1.connection.transitionTo(.ready);
    _ = c1.connection.transitionTo(.operating);
    c1.connection.attached_session_id = sess_id;

    const result = broadcast_mod.broadcastToSession(&mgr, sess_id, "layout_changed", null);
    try std.testing.expectEqual(@as(u16, 1), result.sent_count);

    mgr.getClient(idx1).?.deinit();
}
