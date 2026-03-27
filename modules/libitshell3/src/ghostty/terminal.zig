//! Thin helper functions for ghostty Terminal lifecycle.
//! These are free functions, NOT wrapper types — per design spec module-structure.
const std = @import("std");
const ghostty = @import("ghostty");
const Allocator = std.mem.Allocator;

pub const Terminal = ghostty.Terminal;
pub const CellCountInt = ghostty.size.CellCountInt;
pub const ReadonlyStream = ghostty.ReadonlyStream;

/// Create a headless Terminal instance. No Surface, no App, no GPU.
pub fn initTerminal(alloc: Allocator, cols: CellCountInt, rows: CellCountInt) !Terminal {
    return Terminal.init(alloc, .{ .cols = cols, .rows = rows });
}

/// Destroy a Terminal instance.
pub fn deinitTerminal(t: *Terminal, alloc: Allocator) void {
    t.deinit(alloc);
}

/// Resize the terminal grid.
pub fn resizeTerminal(t: *Terminal, alloc: Allocator, cols: CellCountInt, rows: CellCountInt) !void {
    try t.resize(alloc, cols, rows);
}

/// Create a persistent VT stream for a terminal. The stream holds parser
/// state (VT state machine position) that must persist across calls to
/// feedStream() — otherwise split escape sequences would be lost.
/// The caller must hold the stream for the terminal's lifetime.
pub fn createVtStream(t: *Terminal) ReadonlyStream {
    return t.vtStream();
}

/// Destroy a VT stream, freeing any parser allocations.
pub fn deinitVtStream(stream: *ReadonlyStream) void {
    stream.deinit();
}

/// Feed raw PTY output bytes through a persistent VT stream.
/// The stream must have been created via createVtStream() and held
/// for the terminal's lifetime to correctly handle split escape sequences.
pub fn feedStream(stream: *ReadonlyStream, bytes: []const u8) !void {
    try stream.nextSlice(bytes);
}

/// Convenience: feed bytes using a temporary stream. Only safe when the
/// input is guaranteed to contain complete escape sequences (e.g., tests).
/// For production PTY reads, use createVtStream() + feedStream() instead.
pub fn feedTerminal(t: *Terminal, bytes: []const u8) !void {
    var stream = t.vtStream();
    defer stream.deinit();
    try stream.nextSlice(bytes);
}

// --- Tests ---

test "initTerminal: creates terminal with correct dimensions" {
    var t = try initTerminal(std.testing.allocator, 80, 24);
    defer deinitTerminal(&t, std.testing.allocator);

    try std.testing.expectEqual(@as(CellCountInt, 80), t.cols);
    try std.testing.expectEqual(@as(CellCountInt, 24), t.rows);
}

test "feedTerminal: processes plain text" {
    var t = try initTerminal(std.testing.allocator, 80, 24);
    defer deinitTerminal(&t, std.testing.allocator);

    try feedTerminal(&t, "Hello");
    try std.testing.expectEqual(@as(usize, 5), t.screens.active.cursor.x);
    try std.testing.expectEqual(@as(usize, 0), t.screens.active.cursor.y);
}

test "feedTerminal: processes escape sequences" {
    var t = try initTerminal(std.testing.allocator, 80, 24);
    defer deinitTerminal(&t, std.testing.allocator);

    try feedTerminal(&t, "Hello\x1B[1;1H");
    try std.testing.expectEqual(@as(usize, 0), t.screens.active.cursor.x);
    try std.testing.expectEqual(@as(usize, 0), t.screens.active.cursor.y);
}

test "resizeTerminal: changes dimensions" {
    var t = try initTerminal(std.testing.allocator, 80, 24);
    defer deinitTerminal(&t, std.testing.allocator);

    try resizeTerminal(&t, std.testing.allocator, 120, 40);
    try std.testing.expectEqual(@as(CellCountInt, 120), t.cols);
    try std.testing.expectEqual(@as(CellCountInt, 40), t.rows);
}

test "feedTerminal: with empty bytes is no-op" {
    var t = try initTerminal(std.testing.allocator, 80, 24);
    defer deinitTerminal(&t, std.testing.allocator);

    try feedTerminal(&t, "");
    try std.testing.expectEqual(@as(usize, 0), t.screens.active.cursor.x);
}

test "createVtStream: persistent stream handles split escape sequences" {
    var t = try initTerminal(std.testing.allocator, 80, 24);
    defer deinitTerminal(&t, std.testing.allocator);

    var stream = createVtStream(&t);
    defer deinitVtStream(&stream);

    // Split ESC [ 1 ; 1 H across two feeds
    try feedStream(&stream, "Hello \x1B");
    try feedStream(&stream, "[1;1H");

    // Cursor should be at (0,0) — the split CSI sequence was reassembled
    try std.testing.expectEqual(@as(usize, 0), t.screens.active.cursor.x);
    try std.testing.expectEqual(@as(usize, 0), t.screens.active.cursor.y);
}
