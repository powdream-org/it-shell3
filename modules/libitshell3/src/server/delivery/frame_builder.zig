//! Frame builder module. Converts FlatCell export data to CellData wire format
//! and assembles dirty bitmaps into DirtyRow arrays for frame serialization.
//!
//! Per daemon-architecture integration-boundaries spec (CellData = FlatCell
//! terminology binding, frame export pipeline steps S3-S4);
//! ADR 00056 (frame_builder.zig location and responsibility).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const CellData = protocol.cell.CellData;
const RowHeader = protocol.cell.RowHeader;
const DirtyRow = protocol.frame_update.DirtyRow;
const GraphemeEntry = protocol.cell.GraphemeEntry;
const UnderlineColorEntry = protocol.cell.UnderlineColorEntry;

/// Maximum rows supported per frame (matches typical terminal max).
pub const MAX_ROWS: u16 = 256;

/// A complete export result from the ghostty bulk export pipeline.
/// Contains cell data organized by row, a dirty bitmap, and optional
/// per-row side tables (grapheme table, underline color table).
pub const ExportResult = struct {
    /// Cell data for each row. Outer index = row, inner slice = cells in that row.
    rows: []const []const CellData,
    /// 256-bit dirty bitmap. Bit N set = row N has changed since last export.
    dirty_bitmap: [MAX_ROWS / 8]u8,
    /// Number of columns per row.
    cols: u16,
    /// Number of active rows.
    num_rows: u16,
    /// Per-row grapheme entries (optional side table from export).
    grapheme_tables: []const []const GraphemeEntry,
    /// Per-row underline color entries (optional side table from export).
    underline_color_tables: []const []const UnderlineColorEntry,
};

/// Assembles DirtyRow entries from an ExportResult based on its dirty bitmap.
/// For I-frames, pass `force_all = true` to include every row regardless of
/// the dirty bitmap.
///
/// Returns the number of DirtyRow entries written to `out_rows`.
pub fn assembleDirtyRows(
    export_result: *const ExportResult,
    force_all: bool,
    out_rows: []DirtyRow,
) u16 {
    var count: u16 = 0;
    const row_limit = @min(export_result.num_rows, MAX_ROWS);

    var row_idx: u16 = 0;
    while (row_idx < row_limit) : (row_idx += 1) {
        const is_dirty = force_all or isBitSet(&export_result.dirty_bitmap, row_idx);
        if (!is_dirty) continue;
        if (count >= out_rows.len) break;

        const row_data = if (row_idx < export_result.rows.len)
            export_result.rows[row_idx]
        else
            &[_]CellData{};

        const grapheme_entries = if (row_idx < export_result.grapheme_tables.len)
            export_result.grapheme_tables[row_idx]
        else
            &[_]GraphemeEntry{};

        const underline_color_entries = if (row_idx < export_result.underline_color_tables.len)
            export_result.underline_color_tables[row_idx]
        else
            &[_]UnderlineColorEntry{};

        out_rows[count] = DirtyRow{
            .header = RowHeader{
                .y = row_idx,
                .num_cells = @intCast(row_data.len),
                .row_flags = 0,
                .selection_start = 0,
                .selection_end = 0,
            },
            .cells = row_data,
            .grapheme_entries = grapheme_entries,
            .underline_color_entries = underline_color_entries,
        };
        count += 1;
    }

    return count;
}

/// Checks whether a bit is set in a 256-bit bitmap (32 bytes).
fn isBitSet(bitmap: *const [MAX_ROWS / 8]u8, bit_index: u16) bool {
    if (bit_index >= MAX_ROWS) return false;
    const byte_idx = bit_index / 8;
    const bit_offset: u3 = @intCast(bit_index % 8);
    return (bitmap[byte_idx] & (@as(u8, 1) << bit_offset)) != 0;
}

/// Clears a dirty bitmap to all zeros.
pub fn clearDirtyBitmap(bitmap: *[MAX_ROWS / 8]u8) void {
    @memset(bitmap, 0);
}

/// Sets a bit in the dirty bitmap.
pub fn setDirtyBit(bitmap: *[MAX_ROWS / 8]u8, row: u16) void {
    if (row >= MAX_ROWS) return;
    const byte_idx = row / 8;
    const bit_offset: u3 = @intCast(row % 8);
    bitmap[byte_idx] |= @as(u8, 1) << bit_offset;
}

/// Sets all bits in the dirty bitmap (for I-frame generation).
pub fn setAllDirtyBits(bitmap: *[MAX_ROWS / 8]u8) void {
    @memset(bitmap, 0xFF);
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "assembleDirtyRows: empty dirty bitmap produces no rows" {
    var bitmap: [MAX_ROWS / 8]u8 = @splat(0);
    _ = &bitmap;

    var cells: [3]CellData = @splat(std.mem.zeroes(CellData));
    const row_data = [_][]const CellData{&cells};
    const grapheme_tables = [_][]const GraphemeEntry{&.{}};
    const underline_color_tables = [_][]const UnderlineColorEntry{&.{}};

    const result = ExportResult{
        .rows = &row_data,
        .dirty_bitmap = bitmap,
        .cols = 3,
        .num_rows = 1,
        .grapheme_tables = &grapheme_tables,
        .underline_color_tables = &underline_color_tables,
    };

    var out: [MAX_ROWS]DirtyRow = undefined;
    const count = assembleDirtyRows(&result, false, &out);
    try std.testing.expectEqual(@as(u16, 0), count);
}

test "assembleDirtyRows: full dirty bitmap (I-frame) produces all rows" {
    var cells_row0: [2]CellData = @splat(std.mem.zeroes(CellData));
    cells_row0[0].codepoint = 'A';
    cells_row0[1].codepoint = 'B';

    var cells_row1: [2]CellData = @splat(std.mem.zeroes(CellData));
    cells_row1[0].codepoint = 'C';
    cells_row1[1].codepoint = 'D';

    const row_data = [_][]const CellData{ &cells_row0, &cells_row1 };
    const grapheme_tables = [_][]const GraphemeEntry{ &.{}, &.{} };
    const underline_color_tables = [_][]const UnderlineColorEntry{ &.{}, &.{} };

    var bitmap: [MAX_ROWS / 8]u8 = @splat(0);
    setAllDirtyBits(&bitmap);

    const result = ExportResult{
        .rows = &row_data,
        .dirty_bitmap = bitmap,
        .cols = 2,
        .num_rows = 2,
        .grapheme_tables = &grapheme_tables,
        .underline_color_tables = &underline_color_tables,
    };

    var out: [MAX_ROWS]DirtyRow = undefined;
    const count = assembleDirtyRows(&result, true, &out);
    try std.testing.expectEqual(@as(u16, 2), count);
    try std.testing.expectEqual(@as(u16, 0), out[0].header.y);
    try std.testing.expectEqual(@as(u16, 1), out[1].header.y);
    try std.testing.expectEqual(@as(u16, 2), out[0].header.num_cells);
}

test "assembleDirtyRows: sparse bitmap only includes dirty rows" {
    var cells: [3]CellData = @splat(std.mem.zeroes(CellData));
    cells[0].codepoint = 'X';

    const row_data = [_][]const CellData{ &cells, &cells, &cells, &cells };
    const grapheme_tables = [_][]const GraphemeEntry{ &.{}, &.{}, &.{}, &.{} };
    const underline_color_tables = [_][]const UnderlineColorEntry{ &.{}, &.{}, &.{}, &.{} };

    var bitmap: [MAX_ROWS / 8]u8 = @splat(0);
    setDirtyBit(&bitmap, 1);
    setDirtyBit(&bitmap, 3);

    const result = ExportResult{
        .rows = &row_data,
        .dirty_bitmap = bitmap,
        .cols = 3,
        .num_rows = 4,
        .grapheme_tables = &grapheme_tables,
        .underline_color_tables = &underline_color_tables,
    };

    var out: [MAX_ROWS]DirtyRow = undefined;
    const count = assembleDirtyRows(&result, false, &out);
    try std.testing.expectEqual(@as(u16, 2), count);
    try std.testing.expectEqual(@as(u16, 1), out[0].header.y);
    try std.testing.expectEqual(@as(u16, 3), out[1].header.y);
}

test "assembleDirtyRows: wide characters preserved through conversion" {
    var cells: [3]CellData = @splat(std.mem.zeroes(CellData));
    cells[0].codepoint = 0xD55C; // Korean character
    cells[0].wide = CellData.Wide.wide;
    cells[1].codepoint = 0;
    cells[1].wide = CellData.Wide.spacer_tail;
    cells[2].codepoint = 'A';

    const row_data = [_][]const CellData{&cells};
    const grapheme_tables = [_][]const GraphemeEntry{&.{}};
    const underline_color_tables = [_][]const UnderlineColorEntry{&.{}};

    var bitmap: [MAX_ROWS / 8]u8 = @splat(0);
    setDirtyBit(&bitmap, 0);

    const result = ExportResult{
        .rows = &row_data,
        .dirty_bitmap = bitmap,
        .cols = 3,
        .num_rows = 1,
        .grapheme_tables = &grapheme_tables,
        .underline_color_tables = &underline_color_tables,
    };

    var out: [MAX_ROWS]DirtyRow = undefined;
    const count = assembleDirtyRows(&result, false, &out);
    try std.testing.expectEqual(@as(u16, 1), count);
    try std.testing.expectEqual(CellData.Wide.wide, out[0].cells[0].wide);
    try std.testing.expectEqual(CellData.Wide.spacer_tail, out[0].cells[1].wide);
}

test "assembleDirtyRows: grapheme and underline color side tables assembled" {
    var cells: [2]CellData = @splat(std.mem.zeroes(CellData));
    cells[0].codepoint = 'A';

    const extra_cps = [_]u32{0x0301};
    const grapheme = [_]GraphemeEntry{.{ .col_index = 0, .extra_codepoints = &extra_cps }};
    const PackedColor = protocol.cell.PackedColor;
    const underline = [_]UnderlineColorEntry{.{ .col_index = 1, .underline_color = PackedColor.rgb(255, 0, 0) }};

    const row_data = [_][]const CellData{&cells};
    const grapheme_tables = [_][]const GraphemeEntry{&grapheme};
    const underline_color_tables = [_][]const UnderlineColorEntry{&underline};

    var bitmap: [MAX_ROWS / 8]u8 = @splat(0);
    setDirtyBit(&bitmap, 0);

    const result = ExportResult{
        .rows = &row_data,
        .dirty_bitmap = bitmap,
        .cols = 2,
        .num_rows = 1,
        .grapheme_tables = &grapheme_tables,
        .underline_color_tables = &underline_color_tables,
    };

    var out: [MAX_ROWS]DirtyRow = undefined;
    const count = assembleDirtyRows(&result, false, &out);
    try std.testing.expectEqual(@as(u16, 1), count);
    try std.testing.expectEqual(@as(usize, 1), out[0].grapheme_entries.len);
    try std.testing.expectEqual(@as(usize, 1), out[0].underline_color_entries.len);
    try std.testing.expectEqual(@as(u16, 0), out[0].grapheme_entries[0].col_index);
}

test "isBitSet: boundary conditions" {
    var bitmap: [MAX_ROWS / 8]u8 = @splat(0);
    try std.testing.expect(!isBitSet(&bitmap, 0));
    try std.testing.expect(!isBitSet(&bitmap, 255));

    setDirtyBit(&bitmap, 0);
    try std.testing.expect(isBitSet(&bitmap, 0));
    try std.testing.expect(!isBitSet(&bitmap, 1));

    setDirtyBit(&bitmap, 255);
    try std.testing.expect(isBitSet(&bitmap, 255));
}

test "clearDirtyBitmap: zeros all bits" {
    var bitmap: [MAX_ROWS / 8]u8 = @splat(0xFF);
    clearDirtyBitmap(&bitmap);
    for (bitmap) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}
