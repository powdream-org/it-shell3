const std = @import("std");

/// PackedColor (4 bytes)
/// Byte 0: tag (0x00=default, 0x01=palette, 0x02=rgb)
/// Bytes 1-3: data (palette index or R,G,B)
pub const PackedColor = extern struct {
    tag: u8,
    data: [3]u8,

    pub const default_color: PackedColor = .{ .tag = 0x00, .data = .{ 0, 0, 0 } };

    pub fn palette(index: u8) PackedColor {
        return .{ .tag = 0x01, .data = .{ index, 0, 0 } };
    }

    pub fn rgb(r: u8, g: u8, b: u8) PackedColor {
        return .{ .tag = 0x02, .data = .{ r, g, b } };
    }

    pub fn isDefault(self: PackedColor) bool {
        return self.tag == 0x00;
    }
};

/// CellData (16 bytes, extern struct for exact binary layout)
/// All fields little-endian on wire.
/// Layout: codepoint(4) wide(1) flags(2) content_tag(1) fg_color(4) bg_color(4) = 16 bytes
pub const CellData = extern struct {
    codepoint: u32, // Unicode codepoint (0 = empty)
    wide: u8, // 0=narrow, 1=wide, 2=spacer_tail, 3=spacer_head
    flags: u16 align(1), // Style flags (see StyleFlags)
    content_tag: u8, // 0=codepoint, 1=codepoint_grapheme, 2=bg_color_palette, 3=bg_color_rgb
    fg_color: PackedColor,
    bg_color: PackedColor,

    comptime {
        if (@sizeOf(CellData) != 16) @compileError("CellData must be 16 bytes");
    }

    pub const Wide = struct {
        pub const narrow: u8 = 0;
        pub const wide: u8 = 1;
        pub const spacer_tail: u8 = 2;
        pub const spacer_head: u8 = 3;
    };

    pub const ContentTag = struct {
        pub const codepoint: u8 = 0;
        pub const codepoint_grapheme: u8 = 1;
        pub const bg_color_palette: u8 = 2;
        pub const bg_color_rgb: u8 = 3;
    };
};

/// Style flags (u16 LE). See the server-client-protocols RenderState spec.
pub const StyleFlags = struct {
    pub const bold: u16 = 1 << 0;
    pub const italic: u16 = 1 << 1;
    pub const faint: u16 = 1 << 2;
    pub const blink: u16 = 1 << 3;
    pub const inverse: u16 = 1 << 4;
    pub const invisible: u16 = 1 << 5;
    pub const strikethrough: u16 = 1 << 6;
    pub const overline: u16 = 1 << 7;
    // Bits 8-10: underline style (0=none, 1=single, 2=double, 3=curly, 4=dotted, 5=dashed)
    pub const underline_mask: u16 = 0x0700;
    pub const underline_shift: u8 = 8;
};

/// RowHeader (9 bytes binary)
/// Cannot use extern struct — C ABI pads after row_flags (u8) to align
/// selection_start (u16), making it 10 bytes. Use manual encode/decode.
pub const RowHeader = struct {
    y: u16, // Row index (0=top)
    row_flags: u8, // Bit 0=selection, 1=rle_encoded, 2-3=semantic_prompt, 4=hyperlink
    selection_start: u16,
    selection_end: u16,
    num_cells: u16, // Cell count (or run count if RLE)

    pub const SIZE: usize = 9;

    pub const RowFlags = struct {
        pub const selection: u8 = 1 << 0;
        pub const rle_encoded: u8 = 1 << 1;
        // Bits 2-3: semantic_prompt (0=none, 1=prompt, 2=prompt_continuation)
        pub const semantic_prompt_mask: u8 = 0x0C;
        pub const semantic_prompt_shift: u8 = 2;
        // Bit 4: hyperlink (row contains hyperlinked cells)
        pub const hyperlink: u8 = 1 << 4;
    };

    pub fn hasSelection(self: RowHeader) bool {
        return self.row_flags & RowFlags.selection != 0;
    }

    pub fn isRleEncoded(self: RowHeader) bool {
        return self.row_flags & RowFlags.rle_encoded != 0;
    }

    pub fn semanticPrompt(self: RowHeader) u2 {
        return @truncate((self.row_flags & RowFlags.semantic_prompt_mask) >> RowFlags.semantic_prompt_shift);
    }

    pub fn hasHyperlink(self: RowHeader) bool {
        return self.row_flags & RowFlags.hyperlink != 0;
    }
};

/// GraphemeTable entry — variable-length per row
pub const GraphemeEntry = struct {
    col_index: u16,
    extra_codepoints: []const u32,
};

/// UnderlineColorTable entry
pub const UnderlineColorEntry = struct {
    col_index: u16,
    underline_color: PackedColor,
};

/// Encode CellData to exactly 16 bytes (little-endian, portable)
/// Wire layout matches extern struct: codepoint(0-3) wide(4) flags(5-6) content_tag(7) fg(8-11) bg(12-15)
pub fn encodeCellData(cell: CellData, out: *[16]u8) void {
    std.mem.writeInt(u32, out[0..4], cell.codepoint, .little);
    out[4] = cell.wide;
    std.mem.writeInt(u16, out[5..7], cell.flags, .little);
    out[7] = cell.content_tag;
    out[8] = cell.fg_color.tag;
    out[9] = cell.fg_color.data[0];
    out[10] = cell.fg_color.data[1];
    out[11] = cell.fg_color.data[2];
    out[12] = cell.bg_color.tag;
    out[13] = cell.bg_color.data[0];
    out[14] = cell.bg_color.data[1];
    out[15] = cell.bg_color.data[2];
}

pub fn decodeCellData(buf: *const [16]u8) CellData {
    return .{
        .codepoint = std.mem.readInt(u32, buf[0..4], .little),
        .wide = buf[4],
        .flags = std.mem.readInt(u16, buf[5..7], .little),
        .content_tag = buf[7],
        .fg_color = .{ .tag = buf[8], .data = .{ buf[9], buf[10], buf[11] } },
        .bg_color = .{ .tag = buf[12], .data = .{ buf[13], buf[14], buf[15] } },
    };
}

/// Encode RowHeader to exactly 9 bytes (little-endian)
pub fn encodeRowHeader(rh: RowHeader, out: *[RowHeader.SIZE]u8) void {
    std.mem.writeInt(u16, out[0..2], rh.y, .little);
    out[2] = rh.row_flags;
    std.mem.writeInt(u16, out[3..5], rh.selection_start, .little);
    std.mem.writeInt(u16, out[5..7], rh.selection_end, .little);
    std.mem.writeInt(u16, out[7..9], rh.num_cells, .little);
}

pub fn decodeRowHeader(buf: *const [RowHeader.SIZE]u8) RowHeader {
    return .{
        .y = std.mem.readInt(u16, buf[0..2], .little),
        .row_flags = buf[2],
        .selection_start = std.mem.readInt(u16, buf[3..5], .little),
        .selection_end = std.mem.readInt(u16, buf[5..7], .little),
        .num_cells = std.mem.readInt(u16, buf[7..9], .little),
    };
}

/// RLE run: 2 bytes run_length + 16 bytes CellData = 18 bytes
pub const RLE_RUN_SIZE: usize = 18;

pub fn encodeRleRun(run_length: u16, cell: CellData, out: *[RLE_RUN_SIZE]u8) void {
    std.mem.writeInt(u16, out[0..2], run_length, .little);
    encodeCellData(cell, out[2..18]);
}

pub fn decodeRleRun(buf: *const [RLE_RUN_SIZE]u8) struct { run_length: u16, cell: CellData } {
    return .{
        .run_length = std.mem.readInt(u16, buf[0..2], .little),
        .cell = decodeCellData(buf[2..18]),
    };
}

/// Encode GraphemeTable entries to a writer.
pub fn encodeGraphemeTable(entries: []const GraphemeEntry, writer: anytype) !void {
    var count_buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &count_buf, @intCast(entries.len), .little);
    try writer.writeAll(&count_buf);
    for (entries) |entry| {
        var col_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &col_buf, entry.col_index, .little);
        try writer.writeAll(&col_buf);
        const extra_count: u8 = @intCast(entry.extra_codepoints.len);
        try writer.writeByte(extra_count);
        for (entry.extra_codepoints) |cp| {
            var cp_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &cp_buf, cp, .little);
            try writer.writeAll(&cp_buf);
        }
    }
}

/// Encode UnderlineColorTable entries to a writer.
pub fn encodeUnderlineColorTable(entries: []const UnderlineColorEntry, writer: anytype) !void {
    var count_buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &count_buf, @intCast(entries.len), .little);
    try writer.writeAll(&count_buf);
    for (entries) |entry| {
        var col_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &col_buf, entry.col_index, .little);
        try writer.writeAll(&col_buf);
        try writer.writeByte(entry.underline_color.tag);
        try writer.writeAll(&entry.underline_color.data);
    }
}

// ---- Tests ----

test "CellData: comptime size check" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(CellData));
}

test "RowHeader: SIZE constant is 9" {
    try std.testing.expectEqual(@as(usize, 9), RowHeader.SIZE);
}

test "PackedColor: constructors" {
    const d = PackedColor.default_color;
    try std.testing.expectEqual(@as(u8, 0x00), d.tag);
    try std.testing.expect(d.isDefault());

    const p = PackedColor.palette(42);
    try std.testing.expectEqual(@as(u8, 0x01), p.tag);
    try std.testing.expectEqual(@as(u8, 42), p.data[0]);

    const r = PackedColor.rgb(255, 128, 0);
    try std.testing.expectEqual(@as(u8, 0x02), r.tag);
    try std.testing.expectEqual(@as(u8, 255), r.data[0]);
    try std.testing.expectEqual(@as(u8, 128), r.data[1]);
    try std.testing.expectEqual(@as(u8, 0), r.data[2]);
}

test "encodeCellData/decodeCellData: round-trip narrow cell" {
    const cell = CellData{
        .codepoint = 0x0041, // 'A'
        .wide = CellData.Wide.narrow,
        .flags = StyleFlags.bold,
        .content_tag = CellData.ContentTag.codepoint,
        .fg_color = PackedColor.rgb(255, 255, 255),
        .bg_color = PackedColor.default_color,
    };
    var buf: [16]u8 = undefined;
    encodeCellData(cell, &buf);
    const decoded = decodeCellData(&buf);
    try std.testing.expectEqual(cell.codepoint, decoded.codepoint);
    try std.testing.expectEqual(cell.wide, decoded.wide);
    try std.testing.expectEqual(cell.flags, decoded.flags);
    try std.testing.expectEqual(cell.content_tag, decoded.content_tag);
    try std.testing.expectEqual(cell.fg_color.tag, decoded.fg_color.tag);
}

test "encodeCellData/decodeCellData: round-trip wide cell" {
    const wide_cell = CellData{
        .codepoint = 0xD55C, // 한
        .wide = CellData.Wide.wide,
        .flags = 0,
        .content_tag = CellData.ContentTag.codepoint,
        .fg_color = PackedColor.default_color,
        .bg_color = PackedColor.default_color,
    };
    var buf: [16]u8 = undefined;
    encodeCellData(wide_cell, &buf);
    const decoded = decodeCellData(&buf);
    try std.testing.expectEqual(CellData.Wide.wide, decoded.wide);
    try std.testing.expectEqual(@as(u32, 0xD55C), decoded.codepoint);

    // spacer_tail following wide cell
    const spacer = CellData{
        .codepoint = 0,
        .wide = CellData.Wide.spacer_tail,
        .flags = 0,
        .content_tag = 0,
        .fg_color = PackedColor.default_color,
        .bg_color = PackedColor.default_color,
    };
    encodeCellData(spacer, &buf);
    const decoded_spacer = decodeCellData(&buf);
    try std.testing.expectEqual(CellData.Wide.spacer_tail, decoded_spacer.wide);
}

test "encodeCellData/decodeCellData: all style flags set" {
    const all_flags: u16 = StyleFlags.bold | StyleFlags.italic | StyleFlags.faint |
        StyleFlags.blink | StyleFlags.inverse | StyleFlags.invisible |
        StyleFlags.strikethrough | StyleFlags.overline | StyleFlags.underline_mask;
    const cell = CellData{
        .codepoint = 0x41,
        .wide = 0,
        .flags = all_flags,
        .content_tag = 0,
        .fg_color = PackedColor.default_color,
        .bg_color = PackedColor.default_color,
    };
    var buf: [16]u8 = undefined;
    encodeCellData(cell, &buf);
    const decoded = decodeCellData(&buf);
    try std.testing.expectEqual(all_flags, decoded.flags);
}

test "encodeRowHeader/decodeRowHeader: round-trip" {
    const rh = RowHeader{
        .y = 10,
        .row_flags = RowHeader.RowFlags.selection | RowHeader.RowFlags.rle_encoded,
        .selection_start = 5,
        .selection_end = 15,
        .num_cells = 80,
    };
    var buf: [RowHeader.SIZE]u8 = undefined;
    encodeRowHeader(rh, &buf);
    const decoded = decodeRowHeader(&buf);
    try std.testing.expectEqual(rh.y, decoded.y);
    try std.testing.expectEqual(rh.row_flags, decoded.row_flags);
    try std.testing.expectEqual(rh.selection_start, decoded.selection_start);
    try std.testing.expectEqual(rh.selection_end, decoded.selection_end);
    try std.testing.expectEqual(rh.num_cells, decoded.num_cells);
    try std.testing.expect(decoded.hasSelection());
    try std.testing.expect(decoded.isRleEncoded());
}

test "RowHeader: semantic_prompt and hyperlink flags" {
    const rh = RowHeader{
        .y = 0,
        .row_flags = (2 << 2) | RowHeader.RowFlags.hyperlink, // prompt_continuation + hyperlink
        .selection_start = 0,
        .selection_end = 0,
        .num_cells = 0,
    };
    var buf: [RowHeader.SIZE]u8 = undefined;
    encodeRowHeader(rh, &buf);
    const decoded = decodeRowHeader(&buf);
    try std.testing.expectEqual(@as(u2, 2), decoded.semanticPrompt());
    try std.testing.expect(decoded.hasHyperlink());
}

test "encodeRleRun/decodeRleRun: round-trip" {
    const cell = CellData{
        .codepoint = 0x20, // space
        .wide = 0,
        .flags = 0,
        .content_tag = 0,
        .fg_color = PackedColor.default_color,
        .bg_color = PackedColor.default_color,
    };
    var buf: [RLE_RUN_SIZE]u8 = undefined;
    encodeRleRun(80, cell, &buf);
    const result = decodeRleRun(&buf);
    try std.testing.expectEqual(@as(u16, 80), result.run_length);
    try std.testing.expectEqual(cell.codepoint, result.cell.codepoint);
}

test "encodeGraphemeTable: 0 entries" {
    var buf: [2]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try encodeGraphemeTable(&.{}, fbs.writer());
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, buf[0..2], .little));
}

test "encodeGraphemeTable: 1 entry" {
    const entries = [_]GraphemeEntry{.{ .col_index = 5, .extra_codepoints = &[_]u32{ 0x302, 0x308 } }};
    var buf: [128]u8 = std.mem.zeroes([128]u8);
    var fbs = std.io.fixedBufferStream(&buf);
    try encodeGraphemeTable(&entries, fbs.writer());
    // num_entries=1, col_index=5, extra_count=2, cp1=0x302, cp2=0x308
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, buf[0..2], .little));
    try std.testing.expectEqual(@as(u16, 5), std.mem.readInt(u16, buf[2..4], .little));
    try std.testing.expectEqual(@as(u8, 2), buf[4]);
    try std.testing.expectEqual(@as(u32, 0x302), std.mem.readInt(u32, buf[5..9], .little));
}

test "encodeUnderlineColorTable: 1 entry" {
    const entries = [_]UnderlineColorEntry{.{ .col_index = 10, .underline_color = PackedColor.rgb(255, 0, 0) }};
    var buf: [128]u8 = std.mem.zeroes([128]u8);
    var fbs = std.io.fixedBufferStream(&buf);
    try encodeUnderlineColorTable(&entries, fbs.writer());
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, buf[0..2], .little));
    try std.testing.expectEqual(@as(u16, 10), std.mem.readInt(u16, buf[2..4], .little));
    try std.testing.expectEqual(@as(u8, 0x02), buf[4]); // rgb tag
    try std.testing.expectEqual(@as(u8, 255), buf[5]); // R
}
