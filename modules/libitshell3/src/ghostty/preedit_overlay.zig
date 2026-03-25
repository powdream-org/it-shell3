//! Preedit overlay: inject preedit codepoints into exported FlatCell data.
//! Written from scratch per design spec §4.7.
//!
//! After bulkExport() produces the FlatCell[] array, this function overwrites
//! cells at the cursor position with preedit characters. This is the headless
//! equivalent of ghostty's renderer.State preedit handling.
const std = @import("std");
const render_export = @import("render_export.zig");

const FlatCell = render_export.FlatCell;
const ExportResult = render_export.ExportResult;

/// Overlay preedit codepoints onto an ExportResult at the cursor position.
///
/// - Overwrites FlatCell entries starting at (cursor_row, cursor_col)
/// - Wide characters (CJK) take 2 cells: first cell is wide, second is spacer_tail
/// - Truncates at the right edge of the screen (no wrap)
/// - Empty preedit is a no-op
/// - Marks affected rows dirty in the bitmap
pub fn overlayPreedit(
    result: *ExportResult,
    preedit: []const u21,
    cursor_row: u16,
    cursor_col: u16,
) void {
    if (preedit.len == 0) return;
    if (cursor_row >= result.rows) return;

    const cols: usize = result.cols;
    const row_offset: usize = @as(usize, cursor_row) * cols;
    var col: usize = cursor_col;

    for (preedit) |cp| {
        if (col >= cols) break; // Right edge — truncate

        const w = codepointWidth(cp);

        if (w == 2) {
            // Wide character needs 2 cells
            if (col + 1 >= cols) break; // Not enough room — truncate

            // First cell: wide character
            result.cells[row_offset + col] = .{
                .codepoint = @intCast(cp),
                .wide = 1, // wide
                .content_tag = 0, // codepoint
            };
            // Second cell: spacer tail
            result.cells[row_offset + col + 1] = .{
                .codepoint = 0,
                .wide = 2, // spacer_tail
                .content_tag = 0,
            };
            col += 2;
        } else {
            // Narrow character: 1 cell
            result.cells[row_offset + col] = .{
                .codepoint = @intCast(cp),
                .wide = 0, // narrow
                .content_tag = 0,
            };
            col += 1;
        }
    }

    // Mark the affected row dirty in the bitmap
    if (cursor_row < 256) {
        const word_idx: usize = cursor_row / 64;
        const bit_idx: u6 = @intCast(cursor_row % 64);
        result.dirty_bitmap[word_idx] |= @as(u64, 1) << bit_idx;
    }
}

/// Determine the display width of a codepoint.
/// Returns 2 for wide (East Asian Wide/Fullwidth) characters, 1 for narrow.
/// Covers Unicode East Asian Width property W and F categories.
/// Note: ghostty's internal uucode width tables are not exported via ghostty-vt,
/// so we maintain this table for preedit overlay only.
fn codepointWidth(cp: u21) u2 {
    // Hangul Jamo (U+1100 - U+115F, U+D7B0 - U+D7FF) — wide
    if (cp >= 0x1100 and cp <= 0x115F) return 2;
    if (cp >= 0xD7B0 and cp <= 0xD7FF) return 2;

    // CJK Radicals Supplement (U+2E80 - U+2EFF)
    if (cp >= 0x2E80 and cp <= 0x2EFF) return 2;

    // Kangxi Radicals (U+2F00 - U+2FDF)
    if (cp >= 0x2F00 and cp <= 0x2FDF) return 2;

    // CJK Symbols and Punctuation (U+3000 - U+303F)
    if (cp >= 0x3000 and cp <= 0x303F) return 2;

    // Hiragana (U+3040 - U+309F)
    if (cp >= 0x3040 and cp <= 0x309F) return 2;

    // Katakana (U+30A0 - U+30FF)
    if (cp >= 0x30A0 and cp <= 0x30FF) return 2;

    // Bopomofo (U+3100 - U+312F)
    if (cp >= 0x3100 and cp <= 0x312F) return 2;

    // Hangul Compatibility Jamo (U+3130 - U+318F)
    if (cp >= 0x3130 and cp <= 0x318F) return 2;

    // Kanbun (U+3190 - U+319F)
    if (cp >= 0x3190 and cp <= 0x319F) return 2;

    // Bopomofo Extended (U+31A0 - U+31BF)
    if (cp >= 0x31A0 and cp <= 0x31BF) return 2;

    // CJK Strokes (U+31C0 - U+31EF)
    if (cp >= 0x31C0 and cp <= 0x31EF) return 2;

    // Katakana Phonetic Extensions (U+31F0 - U+31FF)
    if (cp >= 0x31F0 and cp <= 0x31FF) return 2;

    // Enclosed CJK Letters and Months (U+3200 - U+32FF)
    if (cp >= 0x3200 and cp <= 0x32FF) return 2;

    // CJK Compatibility (U+3300 - U+33FF)
    if (cp >= 0x3300 and cp <= 0x33FF) return 2;

    // CJK Extension A (U+3400 - U+4DBF)
    if (cp >= 0x3400 and cp <= 0x4DBF) return 2;

    // CJK Unified Ideographs (U+4E00 - U+9FFF)
    if (cp >= 0x4E00 and cp <= 0x9FFF) return 2;

    // Yi Syllables + Radicals (U+A000 - U+A4CF)
    if (cp >= 0xA000 and cp <= 0xA4CF) return 2;

    // Hangul Syllables (U+AC00 - U+D7A3)
    if (cp >= 0xAC00 and cp <= 0xD7A3) return 2;

    // CJK Compatibility Ideographs (U+F900 - U+FAFF)
    if (cp >= 0xF900 and cp <= 0xFAFF) return 2;

    // Fullwidth Forms (U+FF01 - U+FF60, U+FFE0 - U+FFE6)
    if (cp >= 0xFF01 and cp <= 0xFF60) return 2;
    if (cp >= 0xFFE0 and cp <= 0xFFE6) return 2;

    // CJK Extensions B-H + Supplement (U+20000 - U+3134F)
    if (cp >= 0x20000 and cp <= 0x3134F) return 2;

    // Emoji Presentation (U+1F300 - U+1F9FF)
    if (cp >= 0x1F300 and cp <= 0x1F9FF) return 2;

    // Supplemental Symbols and Pictographs (U+1FA00 - U+1FAFF)
    if (cp >= 0x1FA00 and cp <= 0x1FAFF) return 2;

    // Symbols and Pictographs Extended-A (U+1FC00 - U+1FCFF)
    if (cp >= 0x1FC00 and cp <= 0x1FCFF) return 2;

    // Everything else is narrow
    return 1;
}

// --- Tests ---

test "overlayPreedit empty preedit is no-op" {
    const alloc = std.testing.allocator;
    const cells = try alloc.alloc(FlatCell, 10);
    defer alloc.free(cells);
    @memset(cells, .{});

    var result = ExportResult{
        .cells = cells.ptr,
        .rows = 1,
        .cols = 10,
        .dirty_bitmap = .{ 0, 0, 0, 0 },
        .cursor_x = 0,
        .cursor_y = 0,
        .bg = .{},
        .fg = .{},
        .dirty_state = 0,
        ._pad = .{ 0, 0, 0, 0, 0 },
    };

    overlayPreedit(&result, &.{}, 0, 0);
    // Nothing should have changed
    try std.testing.expectEqual(@as(u32, 0), result.cells[0].codepoint);
    try std.testing.expectEqual(@as(u64, 0), result.dirty_bitmap[0]);
}

test "overlayPreedit narrow character" {
    const alloc = std.testing.allocator;
    const cells = try alloc.alloc(FlatCell, 10);
    defer alloc.free(cells);
    @memset(cells, .{});

    var result = ExportResult{
        .cells = cells.ptr,
        .rows = 1,
        .cols = 10,
        .dirty_bitmap = .{ 0, 0, 0, 0 },
        .cursor_x = 0,
        .cursor_y = 0,
        .bg = .{},
        .fg = .{},
        .dirty_state = 0,
        ._pad = .{ 0, 0, 0, 0, 0 },
    };

    overlayPreedit(&result, &.{'A'}, 0, 3);
    try std.testing.expectEqual(@as(u32, 'A'), result.cells[3].codepoint);
    try std.testing.expectEqual(@as(u8, 0), result.cells[3].wide); // narrow
    // Row 0 should be marked dirty
    try std.testing.expect((result.dirty_bitmap[0] & 1) != 0);
}

test "overlayPreedit wide character (Hangul)" {
    const alloc = std.testing.allocator;
    const cells = try alloc.alloc(FlatCell, 10);
    defer alloc.free(cells);
    @memset(cells, .{});

    var result = ExportResult{
        .cells = cells.ptr,
        .rows = 1,
        .cols = 10,
        .dirty_bitmap = .{ 0, 0, 0, 0 },
        .cursor_x = 0,
        .cursor_y = 0,
        .bg = .{},
        .fg = .{},
        .dirty_state = 0,
        ._pad = .{ 0, 0, 0, 0, 0 },
    };

    // '한' = U+D55C (Hangul syllable, wide)
    overlayPreedit(&result, &.{0xD55C}, 0, 2);
    try std.testing.expectEqual(@as(u32, 0xD55C), result.cells[2].codepoint);
    try std.testing.expectEqual(@as(u8, 1), result.cells[2].wide); // wide
    try std.testing.expectEqual(@as(u32, 0), result.cells[3].codepoint);
    try std.testing.expectEqual(@as(u8, 2), result.cells[3].wide); // spacer_tail
}

test "overlayPreedit right edge truncation" {
    const alloc = std.testing.allocator;
    const cells = try alloc.alloc(FlatCell, 5);
    defer alloc.free(cells);
    @memset(cells, .{});

    var result = ExportResult{
        .cells = cells.ptr,
        .rows = 1,
        .cols = 5,
        .dirty_bitmap = .{ 0, 0, 0, 0 },
        .cursor_x = 0,
        .cursor_y = 0,
        .bg = .{},
        .fg = .{},
        .dirty_state = 0,
        ._pad = .{ 0, 0, 0, 0, 0 },
    };

    // Wide char at col 4 (only 1 cell remaining) — should be truncated
    overlayPreedit(&result, &.{0xD55C}, 0, 4);
    // Wide char needs 2 cells but only 1 available — should not be placed
    try std.testing.expectEqual(@as(u32, 0), result.cells[4].codepoint);
}

test "overlayPreedit multiple codepoints" {
    const alloc = std.testing.allocator;
    const cells = try alloc.alloc(FlatCell, 10);
    defer alloc.free(cells);
    @memset(cells, .{});

    var result = ExportResult{
        .cells = cells.ptr,
        .rows = 1,
        .cols = 10,
        .dirty_bitmap = .{ 0, 0, 0, 0 },
        .cursor_x = 0,
        .cursor_y = 0,
        .bg = .{},
        .fg = .{},
        .dirty_state = 0,
        ._pad = .{ 0, 0, 0, 0, 0 },
    };

    // "AB" — two narrow chars
    overlayPreedit(&result, &.{ 'A', 'B' }, 0, 0);
    try std.testing.expectEqual(@as(u32, 'A'), result.cells[0].codepoint);
    try std.testing.expectEqual(@as(u32, 'B'), result.cells[1].codepoint);
}

test "overlayPreedit cursor_row out of bounds is no-op" {
    const alloc = std.testing.allocator;
    const cells = try alloc.alloc(FlatCell, 10);
    defer alloc.free(cells);
    @memset(cells, .{});

    var result = ExportResult{
        .cells = cells.ptr,
        .rows = 1,
        .cols = 10,
        .dirty_bitmap = .{ 0, 0, 0, 0 },
        .cursor_x = 0,
        .cursor_y = 0,
        .bg = .{},
        .fg = .{},
        .dirty_state = 0,
        ._pad = .{ 0, 0, 0, 0, 0 },
    };

    overlayPreedit(&result, &.{'X'}, 5, 0); // row 5 but only 1 row
    try std.testing.expectEqual(@as(u32, 0), result.cells[0].codepoint);
}

test "codepointWidth Hangul syllable is wide" {
    try std.testing.expectEqual(@as(u2, 2), codepointWidth(0xD55C)); // 한
    try std.testing.expectEqual(@as(u2, 2), codepointWidth(0xAC00)); // 가
    try std.testing.expectEqual(@as(u2, 2), codepointWidth(0xD7A3)); // last syllable
}

test "codepointWidth ASCII is narrow" {
    try std.testing.expectEqual(@as(u2, 1), codepointWidth('A'));
    try std.testing.expectEqual(@as(u2, 1), codepointWidth(' '));
    try std.testing.expectEqual(@as(u2, 1), codepointWidth('~'));
}

test "codepointWidth CJK ideograph is wide" {
    try std.testing.expectEqual(@as(u2, 2), codepointWidth(0x4E00)); // 一
    try std.testing.expectEqual(@as(u2, 2), codepointWidth(0x9FFF)); // last CJK
}
