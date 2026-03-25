//! Thin helper functions for ghostty RenderState lifecycle and dirty tracking.
//! These are free functions, NOT wrapper types — per design spec §1.2/§4.5.
const std = @import("std");
const ghostty = @import("ghostty");
const Allocator = std.mem.Allocator;

pub const RenderState = ghostty.RenderState;
pub const Terminal = ghostty.Terminal;

/// Create a new empty RenderState.
pub fn initRenderState() RenderState {
    return RenderState.empty;
}

/// Destroy a RenderState, freeing all retained memory.
pub fn deinitRenderState(rs: *RenderState, alloc: Allocator) void {
    rs.deinit(alloc);
}

/// Update the RenderState from the current terminal state.
/// After this call, the RenderState reflects the terminal's viewport.
pub fn updateRenderState(rs: *RenderState, alloc: Allocator, t: *Terminal) !void {
    try rs.update(alloc, t);
}

/// Check if the RenderState has any dirty rows since last render.
/// Returns true if any rows changed (partial or full redraw needed).
pub fn isDirty(rs: *const RenderState) bool {
    return rs.dirty != .false;
}

/// Check if a full redraw is needed (dimensions changed, screen switch, etc.)
pub fn isFullDirty(rs: *const RenderState) bool {
    return rs.dirty == .full;
}

// --- Tests ---

const terminal_mod = @import("terminal.zig");

test "initRenderState creates empty state" {
    var rs = initRenderState();
    try std.testing.expectEqual(@as(ghostty.size.CellCountInt, 0), rs.rows);
    try std.testing.expectEqual(@as(ghostty.size.CellCountInt, 0), rs.cols);
    try std.testing.expect(!isDirty(&rs));
}

test "updateRenderState after feed marks dirty" {
    var t = try terminal_mod.initTerminal(std.testing.allocator, 80, 24);
    defer terminal_mod.deinitTerminal(&t, std.testing.allocator);

    var rs = initRenderState();
    defer deinitRenderState(&rs, std.testing.allocator);

    // Feed some text to make terminal state different from empty RenderState
    try terminal_mod.feedTerminal(&t, "Hello World");

    try updateRenderState(&rs, std.testing.allocator, &t);
    // First update always marks full dirty (dimension change from 0x0 to 80x24)
    try std.testing.expect(isDirty(&rs));
    try std.testing.expect(isFullDirty(&rs));
}

test "updateRenderState reflects terminal dimensions" {
    var t = try terminal_mod.initTerminal(std.testing.allocator, 80, 24);
    defer terminal_mod.deinitTerminal(&t, std.testing.allocator);

    var rs = initRenderState();
    defer deinitRenderState(&rs, std.testing.allocator);

    try updateRenderState(&rs, std.testing.allocator, &t);
    // After update, RenderState dimensions match terminal
    try std.testing.expectEqual(@as(ghostty.size.CellCountInt, 80), rs.cols);
    try std.testing.expectEqual(@as(ghostty.size.CellCountInt, 24), rs.rows);
}
