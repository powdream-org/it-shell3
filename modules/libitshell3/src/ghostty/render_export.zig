//! Bulk export API for RenderState cell data.
//! Ported from PoC 06-07, adapted to import ghostty as a build dependency.
//!
//! Provides a flat, C-ABI-compatible representation of terminal cell data
//! for efficient cross-boundary transfer. Designed for the it-shell3
//! server-client protocol where the server extracts RenderState and
//! transmits cell data to the client.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ghostty = @import("ghostty");

const page = ghostty.page;
const RenderState = ghostty.RenderState;
const Style = ghostty.Style;

/// A flat, C-ABI-compatible cell for bulk export.
/// 16 bytes — power-of-2 aligned, SIMD-friendly.
/// Called CellData at the wire level (protocol docs), FlatCell in ghostty-internal code.
pub const FlatCell = extern struct {
    /// Primary codepoint (u21 extended to u32). 0 = empty cell.
    codepoint: u32 = 0,

    /// Foreground color. tag: 0=none, 1=palette(r=index), 2=rgb
    fg: PackedColor = .{},

    /// Background color. tag: 0=none, 1=palette(r=index), 2=rgb
    bg: PackedColor = .{},

    /// Style flags (matches ghostty's Flags packed u16).
    /// Bits: 0=bold, 1=italic, 2=faint, 3=blink, 4=inverse,
    ///       5=invisible, 6=strikethrough, 7=overline, 8-10=underline
    flags: u16 = 0,

    /// Wide character status: 0=narrow, 1=wide, 2=spacer_tail, 3=spacer_head
    wide: u8 = 0,

    /// Content tag: 0=codepoint, 1=codepoint_grapheme, 2=bg_color_palette, 3=bg_color_rgb
    content_tag: u8 = 0,

    comptime {
        std.debug.assert(@sizeOf(FlatCell) == 16);
    }
};

/// Packed color representation (4 bytes, C-ABI-compatible).
pub const PackedColor = extern struct {
    /// 0=none, 1=palette, 2=rgb
    tag: u8 = 0,
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,

    pub fn fromStyleColor(c: Style.Color) PackedColor {
        return switch (c) {
            .none => .{},
            .palette => |idx| .{ .tag = 1, .r = idx },
            .rgb => |rgb| .{ .tag = 2, .r = rgb.r, .g = rgb.g, .b = rgb.b },
        };
    }
};

/// Result of a bulk export operation.
pub const ExportResult = extern struct {
    /// Pointer to the flat cell buffer. Caller must free via freeExport().
    cells: [*]FlatCell,

    /// Number of rows exported.
    rows: u16,

    /// Number of columns exported.
    cols: u16,

    /// Bitmask of dirty rows (up to 256 rows). Bit N = row N is dirty.
    dirty_bitmap: [4]u64,

    /// Cursor position.
    cursor_x: u32,
    cursor_y: u32,

    /// Terminal default colors (resolved).
    bg: PackedColor,
    fg: PackedColor,

    /// 0=false, 1=partial, 2=full
    dirty_state: u8,

    _pad: [5]u8,
};

/// Flatten RenderState cells into a flat FlatCell[] buffer for wire transfer.
///
/// The caller must call updateRenderState() before this to snapshot terminal
/// state. This separation gives server/ explicit control over the
/// update → dirty-check → export pipeline (per daemon-architecture state-and-types spec).
///
/// The returned ExportResult owns the cell buffer. Caller must free via freeExport().
pub fn freeExport(alloc: Allocator, result: *ExportResult) void {
    const total: usize = @as(usize, result.rows) * @as(usize, result.cols);
    alloc.free(result.cells[0..total]);
    result.* = undefined;
}

pub fn bulkExport(
    alloc: Allocator,
    state: *const RenderState,
) Allocator.Error!ExportResult {
    const rows = state.rows;
    const cols = state.cols;
    const total_cells: usize = @as(usize, rows) * @as(usize, cols);

    const flat_cells = try alloc.alloc(FlatCell, total_cells);

    const row_data = state.row_data.slice();
    const row_cells_arr = row_data.items(.cells);
    const row_dirties = row_data.items(.dirty);

    var dirty_bitmap: [4]u64 = .{ 0, 0, 0, 0 };

    for (0..rows) |y| {
        const cells_slice = row_cells_arr[y].slice();
        const cells_raw = cells_slice.items(.raw);
        const cells_style = cells_slice.items(.style);
        const cell_count = @min(cells_raw.len, cols);

        // Record dirty state
        if (row_dirties[y] and y < 256) {
            dirty_bitmap[y / 64] |= @as(u64, 1) << @intCast(y % 64);
        }

        // Destination slice for this row
        const row_offset = y * cols;
        const dest = flat_cells[row_offset .. row_offset + cols];

        // Flatten each cell
        for (0..cell_count) |x| {
            const raw = cells_raw[x];
            const has_style = raw.hasStyling();
            const sty = cells_style[x];

            dest[x] = .{
                .codepoint = raw.codepoint(),
                .fg = PackedColor.fromStyleColor(if (has_style) sty.fg_color else .none),
                .bg = PackedColor.fromStyleColor(if (has_style) sty.bg_color else .none),
                .flags = if (has_style) @bitCast(sty.flags) else 0,
                .wide = @intFromEnum(raw.wide),
                .content_tag = @intFromEnum(raw.content_tag),
            };
        }

        // Zero-fill remaining cells if row is shorter than cols
        if (cell_count < cols) {
            @memset(dest[cell_count..], .{});
        }
    }

    return .{
        .cells = flat_cells.ptr,
        .rows = rows,
        .cols = cols,
        .dirty_bitmap = dirty_bitmap,
        .cursor_x = @intCast(state.cursor.active.x),
        .cursor_y = @intCast(state.cursor.active.y),
        .bg = .{ .tag = 2, .r = state.colors.background.r, .g = state.colors.background.g, .b = state.colors.background.b },
        .fg = .{ .tag = 2, .r = state.colors.foreground.r, .g = state.colors.foreground.g, .b = state.colors.foreground.b },
        .dirty_state = @intFromEnum(state.dirty),
        ._pad = .{ 0, 0, 0, 0, 0 },
    };
}

// --- Tests ---

const terminal_mod = @import("terminal.zig");
const render_state_mod = @import("render_state.zig");

test "FlatCell: size and alignment" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(FlatCell));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(FlatCell));
}

test "PackedColor.fromStyleColor: converts from Style.Color" {
    const none = PackedColor.fromStyleColor(.none);
    try std.testing.expectEqual(@as(u8, 0), none.tag);

    const pal = PackedColor.fromStyleColor(.{ .palette = 42 });
    try std.testing.expectEqual(@as(u8, 1), pal.tag);
    try std.testing.expectEqual(@as(u8, 42), pal.r);

    const rgb = PackedColor.fromStyleColor(.{ .rgb = .{ .r = 255, .g = 128, .b = 0 } });
    try std.testing.expectEqual(@as(u8, 2), rgb.tag);
    try std.testing.expectEqual(@as(u8, 255), rgb.r);
    try std.testing.expectEqual(@as(u8, 128), rgb.g);
    try std.testing.expectEqual(@as(u8, 0), rgb.b);
}

test "bulkExport: produces correct dimensions" {
    var t = try terminal_mod.initTerminal(std.testing.allocator, 80, 24);
    defer terminal_mod.deinitTerminal(&t, std.testing.allocator);

    var rs = render_state_mod.initRenderState();
    defer render_state_mod.deinitRenderState(&rs, std.testing.allocator);

    try render_state_mod.updateRenderState(&rs, std.testing.allocator, &t);
    var result = try bulkExport(std.testing.allocator, &rs);
    defer freeExport(std.testing.allocator, &result);

    try std.testing.expectEqual(@as(u16, 24), result.rows);
    try std.testing.expectEqual(@as(u16, 80), result.cols);
}

test "bulkExport: captures text content" {
    var t = try terminal_mod.initTerminal(std.testing.allocator, 80, 24);
    defer terminal_mod.deinitTerminal(&t, std.testing.allocator);

    try terminal_mod.feedTerminal(&t, "ABC");

    var rs = render_state_mod.initRenderState();
    defer render_state_mod.deinitRenderState(&rs, std.testing.allocator);

    try render_state_mod.updateRenderState(&rs, std.testing.allocator, &t);
    var result = try bulkExport(std.testing.allocator, &rs);
    defer freeExport(std.testing.allocator, &result);

    try std.testing.expectEqual(@as(u32, 'A'), result.cells[0].codepoint);
    try std.testing.expectEqual(@as(u32, 'B'), result.cells[1].codepoint);
    try std.testing.expectEqual(@as(u32, 'C'), result.cells[2].codepoint);
    try std.testing.expectEqual(@as(u32, 0), result.cells[3].codepoint);
}

test "bulkExport: cursor tracks terminal position" {
    var t = try terminal_mod.initTerminal(std.testing.allocator, 80, 24);
    defer terminal_mod.deinitTerminal(&t, std.testing.allocator);

    try terminal_mod.feedTerminal(&t, "Hello");

    var rs = render_state_mod.initRenderState();
    defer render_state_mod.deinitRenderState(&rs, std.testing.allocator);

    try render_state_mod.updateRenderState(&rs, std.testing.allocator, &t);
    var result = try bulkExport(std.testing.allocator, &rs);
    defer freeExport(std.testing.allocator, &result);

    try std.testing.expectEqual(@as(u32, 5), result.cursor_x);
    try std.testing.expectEqual(@as(u32, 0), result.cursor_y);
}

test "freeExport: cleans up allocation" {
    var t = try terminal_mod.initTerminal(std.testing.allocator, 10, 5);
    defer terminal_mod.deinitTerminal(&t, std.testing.allocator);

    var rs = render_state_mod.initRenderState();
    defer render_state_mod.deinitRenderState(&rs, std.testing.allocator);

    try render_state_mod.updateRenderState(&rs, std.testing.allocator, &t);
    var result = try bulkExport(std.testing.allocator, &rs);
    freeExport(std.testing.allocator, &result);
}
