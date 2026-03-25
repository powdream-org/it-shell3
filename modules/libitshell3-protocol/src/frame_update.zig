const std = @import("std");
const cell_mod = @import("cell.zig");
const json_mod = @import("json.zig");

// --- Frame Header (20 bytes binary) ---

pub const FRAME_HEADER_SIZE: usize = 20;

pub const FrameType = enum(u8) {
    p_frame = 0, // Partial (delta)
    i_frame = 1, // Keyframe (full)
};

pub const Screen = enum(u8) {
    primary = 0,
    alternate = 1,
};

pub const SectionFlags = struct {
    pub const dirty_rows: u16 = 1 << 4;
    pub const json_metadata: u16 = 1 << 7;
};

pub const FrameHeader = struct {
    session_id: u32,
    pane_id: u32,
    frame_sequence: u64,
    frame_type: FrameType,
    screen: Screen,
    section_flags: u16,

    pub fn encode(self: FrameHeader, buf: *[FRAME_HEADER_SIZE]u8) void {
        std.mem.writeInt(u32, buf[0..4], self.session_id, .little);
        std.mem.writeInt(u32, buf[4..8], self.pane_id, .little);
        std.mem.writeInt(u64, buf[8..16], self.frame_sequence, .little);
        buf[16] = @intFromEnum(self.frame_type);
        buf[17] = @intFromEnum(self.screen);
        std.mem.writeInt(u16, buf[18..20], self.section_flags, .little);
    }

    pub fn decode(buf: *const [FRAME_HEADER_SIZE]u8) FrameHeader {
        return .{
            .session_id = std.mem.readInt(u32, buf[0..4], .little),
            .pane_id = std.mem.readInt(u32, buf[4..8], .little),
            .frame_sequence = std.mem.readInt(u64, buf[8..16], .little),
            .frame_type = @enumFromInt(buf[16]),
            .screen = @enumFromInt(buf[17]),
            .section_flags = std.mem.readInt(u16, buf[18..20], .little),
        };
    }

    pub fn hasDirtyRows(self: FrameHeader) bool {
        return self.section_flags & SectionFlags.dirty_rows != 0;
    }

    pub fn hasJsonMetadata(self: FrameHeader) bool {
        return self.section_flags & SectionFlags.json_metadata != 0;
    }
};

// --- DirtyRows ---

pub const DirtyRow = struct {
    header: cell_mod.RowHeader,
    cells: []const cell_mod.CellData,
    grapheme_entries: []const cell_mod.GraphemeEntry = &.{},
    underline_color_entries: []const cell_mod.UnderlineColorEntry = &.{},
};

/// Encode dirty rows to a writer.
pub fn encodeDirtyRows(rows: []const DirtyRow, writer: anytype) !void {
    var count_buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &count_buf, @intCast(rows.len), .little);
    try writer.writeAll(&count_buf);

    for (rows) |row| {
        var rh_buf: [cell_mod.RowHeader.SIZE]u8 = undefined;
        cell_mod.encodeRowHeader(row.header, &rh_buf);
        try writer.writeAll(&rh_buf);

        for (row.cells) |c| {
            var cell_buf: [16]u8 = undefined;
            cell_mod.encodeCellData(c, &cell_buf);
            try writer.writeAll(&cell_buf);
        }

        try cell_mod.encodeGraphemeTable(row.grapheme_entries, writer);
        try cell_mod.encodeUnderlineColorTable(row.underline_color_entries, writer);
    }
}

/// Decode dirty rows from a reader. Caller owns returned memory.
pub fn decodeDirtyRows(reader: anytype, allocator: std.mem.Allocator) ![]DirtyRow {
    var count_buf: [2]u8 = undefined;
    try reader.readNoEof(&count_buf);
    const num_rows = std.mem.readInt(u16, &count_buf, .little);

    const rows = try allocator.alloc(DirtyRow, num_rows);
    errdefer allocator.free(rows);
    var initialized: usize = 0;
    errdefer for (rows[0..initialized]) |row| {
        allocator.free(row.cells);
        allocator.free(row.grapheme_entries);
        allocator.free(row.underline_color_entries);
    };

    for (rows) |*row| {
        var rh_buf: [cell_mod.RowHeader.SIZE]u8 = undefined;
        try reader.readNoEof(&rh_buf);
        row.header = cell_mod.decodeRowHeader(&rh_buf);

        // Decode cells
        const num_cells = row.header.num_cells;
        const cells = try allocator.alloc(cell_mod.CellData, num_cells);
        errdefer allocator.free(cells);
        for (cells) |*c| {
            var cell_buf: [16]u8 = undefined;
            try reader.readNoEof(&cell_buf);
            c.* = cell_mod.decodeCellData(&cell_buf);
        }
        row.cells = cells;

        // Decode grapheme table
        var g_count_buf: [2]u8 = undefined;
        try reader.readNoEof(&g_count_buf);
        const num_graphemes = std.mem.readInt(u16, &g_count_buf, .little);
        const graphemes = try allocator.alloc(cell_mod.GraphemeEntry, num_graphemes);
        errdefer allocator.free(graphemes);
        for (graphemes) |*g| {
            var col_buf: [2]u8 = undefined;
            try reader.readNoEof(&col_buf);
            g.col_index = std.mem.readInt(u16, &col_buf, .little);
            const extra_count = try reader.readByte();
            const extras = try allocator.alloc(u32, extra_count);
            errdefer allocator.free(extras);
            for (extras) |*cp| {
                var cp_buf: [4]u8 = undefined;
                try reader.readNoEof(&cp_buf);
                cp.* = std.mem.readInt(u32, &cp_buf, .little);
            }
            g.extra_codepoints = extras;
        }
        row.grapheme_entries = graphemes;

        // Decode underline color table
        var u_count_buf: [2]u8 = undefined;
        try reader.readNoEof(&u_count_buf);
        const num_underlines = std.mem.readInt(u16, &u_count_buf, .little);
        const underlines = try allocator.alloc(cell_mod.UnderlineColorEntry, num_underlines);
        errdefer allocator.free(underlines);
        for (underlines) |*u| {
            var col_buf: [2]u8 = undefined;
            try reader.readNoEof(&col_buf);
            u.col_index = std.mem.readInt(u16, &col_buf, .little);
            const tag = try reader.readByte();
            var data: [3]u8 = undefined;
            try reader.readNoEof(&data);
            u.underline_color = .{ .tag = tag, .data = data };
        }
        row.underline_color_entries = underlines;

        initialized += 1;
    }

    return rows;
}

/// Free dirty rows allocated by decodeDirtyRows.
pub fn freeDirtyRows(rows: []DirtyRow, allocator: std.mem.Allocator) void {
    for (rows) |row| {
        allocator.free(row.cells);
        for (row.grapheme_entries) |g| {
            allocator.free(g.extra_codepoints);
        }
        allocator.free(row.grapheme_entries);
        allocator.free(row.underline_color_entries);
    }
    allocator.free(rows);
}

// --- JSON Metadata ---

pub const FrameMetadata = struct {
    cursor: ?CursorInfo = null,
    dimensions: ?DimensionsInfo = null,
    colors: ?ColorInfo = null,
    mouse: ?MouseInfo = null,
    terminal_modes: ?TerminalModes = null,

    pub const CursorInfo = struct {
        x: u16 = 0,
        y: u16 = 0,
        visible: bool = true,
        style: u8 = 0,
        blinking: bool = true,
        password_input: ?bool = null,
    };

    pub const DimensionsInfo = struct {
        cols: u16,
        rows: u16,
    };

    pub const ColorInfo = struct {
        fg: ?[3]u8 = null,
        bg: ?[3]u8 = null,
        cursor_color: ?[3]u8 = null,
        palette: ?[][3]u8 = null,
        palette_changes: ?[]const PaletteChange = null,
    };

    pub const PaletteChange = struct {
        index: u8,
        color: [3]u8,
    };

    pub const MouseInfo = struct {
        tracking: u8 = 0,
        format: u8 = 0,
    };

    pub const TerminalModes = struct {
        bracketed_paste: ?bool = null,
        focus_reporting: ?bool = null,
        application_cursor_keys: ?bool = null,
        application_keypad: ?bool = null,
        kitty_keyboard_flags: ?u8 = null,
    };
};

/// Encode JSON metadata blob: [json_len (u32 LE)] [json_data]
pub fn encodeJsonMetadata(allocator: std.mem.Allocator, metadata: FrameMetadata, writer: anytype) !void {
    const json_bytes = try json_mod.encode(allocator, metadata);
    defer allocator.free(json_bytes);
    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, @intCast(json_bytes.len), .little);
    try writer.writeAll(&len_buf);
    try writer.writeAll(json_bytes);
}

/// Decode JSON metadata blob. Caller must call deinit() on result.
pub fn decodeJsonMetadata(reader: anytype, allocator: std.mem.Allocator) !std.json.Parsed(FrameMetadata) {
    var len_buf: [4]u8 = undefined;
    try reader.readNoEof(&len_buf);
    const json_len = std.mem.readInt(u32, &len_buf, .little);
    const json_bytes = try allocator.alloc(u8, json_len);
    defer allocator.free(json_bytes);
    try reader.readNoEof(json_bytes);
    return json_mod.decode(FrameMetadata, allocator, json_bytes);
}

/// Encode a complete FrameUpdate payload (after the 16-byte protocol header).
/// Returns the payload bytes. Caller owns the memory.
pub fn encodeFrameUpdate(
    allocator: std.mem.Allocator,
    frame_header: FrameHeader,
    dirty_rows: ?[]const DirtyRow,
    metadata: ?FrameMetadata,
) ![]u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    // Write frame header
    var fh_buf: [FRAME_HEADER_SIZE]u8 = undefined;
    frame_header.encode(&fh_buf);
    try buf.appendSlice(allocator, &fh_buf);

    // Write dirty rows section
    if (dirty_rows) |rows| {
        try encodeDirtyRows(rows, buf.writer(allocator));
    }

    // Write JSON metadata section
    if (metadata) |md| {
        try encodeJsonMetadata(allocator, md, buf.writer(allocator));
    }

    return buf.toOwnedSlice(allocator);
}

// --- Tests ---

test "FrameHeader encode/decode round-trip" {
    const fh = FrameHeader{
        .session_id = 1,
        .pane_id = 2,
        .frame_sequence = 42,
        .frame_type = .p_frame,
        .screen = .primary,
        .section_flags = SectionFlags.dirty_rows | SectionFlags.json_metadata,
    };
    var buf: [FRAME_HEADER_SIZE]u8 = undefined;
    fh.encode(&buf);
    const decoded = FrameHeader.decode(&buf);
    try std.testing.expectEqual(fh.session_id, decoded.session_id);
    try std.testing.expectEqual(fh.pane_id, decoded.pane_id);
    try std.testing.expectEqual(fh.frame_sequence, decoded.frame_sequence);
    try std.testing.expectEqual(fh.frame_type, decoded.frame_type);
    try std.testing.expectEqual(fh.screen, decoded.screen);
    try std.testing.expectEqual(fh.section_flags, decoded.section_flags);
    try std.testing.expect(decoded.hasDirtyRows());
    try std.testing.expect(decoded.hasJsonMetadata());
}

test "Empty P-frame (JSON metadata only)" {
    const fh = FrameHeader{
        .session_id = 1,
        .pane_id = 1,
        .frame_sequence = 1,
        .frame_type = .p_frame,
        .screen = .primary,
        .section_flags = SectionFlags.json_metadata,
    };
    try std.testing.expect(!fh.hasDirtyRows());
    try std.testing.expect(fh.hasJsonMetadata());
}

test "I-frame FrameHeader" {
    const fh = FrameHeader{
        .session_id = 1,
        .pane_id = 1,
        .frame_sequence = 100,
        .frame_type = .i_frame,
        .screen = .alternate,
        .section_flags = SectionFlags.dirty_rows | SectionFlags.json_metadata,
    };
    var buf: [FRAME_HEADER_SIZE]u8 = undefined;
    fh.encode(&buf);
    const decoded = FrameHeader.decode(&buf);
    try std.testing.expectEqual(FrameType.i_frame, decoded.frame_type);
    try std.testing.expectEqual(Screen.alternate, decoded.screen);
}

test "DirtyRows encode/decode round-trip (1 row, 3 cells)" {
    const allocator = std.testing.allocator;

    const cells = [_]cell_mod.CellData{
        .{ .codepoint = 'A', .flags = 0, .wide = 0, .content_tag = 0, .fg_color = cell_mod.PackedColor.default_color, .bg_color = cell_mod.PackedColor.default_color },
        .{ .codepoint = 'B', .flags = cell_mod.StyleFlags.bold, .wide = 0, .content_tag = 0, .fg_color = cell_mod.PackedColor.rgb(255, 0, 0), .bg_color = cell_mod.PackedColor.default_color },
        .{ .codepoint = 'C', .flags = 0, .wide = 0, .content_tag = 0, .fg_color = cell_mod.PackedColor.default_color, .bg_color = cell_mod.PackedColor.default_color },
    };

    const rows = [_]DirtyRow{.{
        .header = .{ .y = 0, .row_flags = 0, .selection_start = 0, .selection_end = 0, .num_cells = 3 },
        .cells = &cells,
    }};

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try encodeDirtyRows(&rows, fbs.writer());

    const written = fbs.getWritten();
    var read_stream = std.io.fixedBufferStream(written);
    const decoded_rows = try decodeDirtyRows(read_stream.reader(), allocator);
    defer freeDirtyRows(decoded_rows, allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded_rows.len);
    try std.testing.expectEqual(@as(u16, 0), decoded_rows[0].header.y);
    try std.testing.expectEqual(@as(usize, 3), decoded_rows[0].cells.len);
    try std.testing.expectEqual(@as(u32, 'A'), decoded_rows[0].cells[0].codepoint);
    try std.testing.expectEqual(@as(u32, 'B'), decoded_rows[0].cells[1].codepoint);
    try std.testing.expectEqual(cell_mod.StyleFlags.bold, decoded_rows[0].cells[1].flags);
}

test "DirtyRows with wide char pair" {
    const allocator = std.testing.allocator;

    const cells = [_]cell_mod.CellData{
        .{ .codepoint = 0xD55C, .flags = 0, .wide = cell_mod.CellData.Wide.wide, .content_tag = 0, .fg_color = cell_mod.PackedColor.default_color, .bg_color = cell_mod.PackedColor.default_color },
        .{ .codepoint = 0, .flags = 0, .wide = cell_mod.CellData.Wide.spacer_tail, .content_tag = 0, .fg_color = cell_mod.PackedColor.default_color, .bg_color = cell_mod.PackedColor.default_color },
    };

    const rows = [_]DirtyRow{.{
        .header = .{ .y = 5, .row_flags = 0, .selection_start = 0, .selection_end = 0, .num_cells = 2 },
        .cells = &cells,
    }};

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try encodeDirtyRows(&rows, fbs.writer());

    var read_stream = std.io.fixedBufferStream(fbs.getWritten());
    const decoded = try decodeDirtyRows(read_stream.reader(), allocator);
    defer freeDirtyRows(decoded, allocator);

    try std.testing.expectEqual(cell_mod.CellData.Wide.wide, decoded[0].cells[0].wide);
    try std.testing.expectEqual(cell_mod.CellData.Wide.spacer_tail, decoded[0].cells[1].wide);
    try std.testing.expectEqual(@as(u32, 0xD55C), decoded[0].cells[0].codepoint);
}

test "DirtyRows with grapheme entries" {
    const allocator = std.testing.allocator;

    const extra_cps = [_]u32{ 0x0302, 0x0308 };
    const graphemes = [_]cell_mod.GraphemeEntry{.{ .col_index = 2, .extra_codepoints = &extra_cps }};

    const cells = [_]cell_mod.CellData{
        .{ .codepoint = 'e', .flags = 0, .wide = 0, .content_tag = cell_mod.CellData.ContentTag.codepoint_grapheme, .fg_color = cell_mod.PackedColor.default_color, .bg_color = cell_mod.PackedColor.default_color },
    };

    const rows = [_]DirtyRow{.{
        .header = .{ .y = 0, .row_flags = 0, .selection_start = 0, .selection_end = 0, .num_cells = 1 },
        .cells = &cells,
        .grapheme_entries = &graphemes,
    }};

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try encodeDirtyRows(&rows, fbs.writer());

    var read_stream = std.io.fixedBufferStream(fbs.getWritten());
    const decoded = try decodeDirtyRows(read_stream.reader(), allocator);
    defer freeDirtyRows(decoded, allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded[0].grapheme_entries.len);
    try std.testing.expectEqual(@as(u16, 2), decoded[0].grapheme_entries[0].col_index);
    try std.testing.expectEqual(@as(usize, 2), decoded[0].grapheme_entries[0].extra_codepoints.len);
    try std.testing.expectEqual(@as(u32, 0x0302), decoded[0].grapheme_entries[0].extra_codepoints[0]);
}

test "FrameMetadata JSON round-trip" {
    const allocator = std.testing.allocator;
    const metadata = FrameMetadata{
        .cursor = .{ .x = 5, .y = 10, .visible = true, .style = 0, .blinking = true },
        .dimensions = .{ .cols = 80, .rows = 24 },
        .mouse = .{ .tracking = 1, .format = 1 },
    };
    const j = try json_mod.encode(allocator, metadata);
    defer allocator.free(j);
    const parsed = try json_mod.decode(FrameMetadata, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u16, 5), parsed.value.cursor.?.x);
    try std.testing.expectEqual(@as(u16, 80), parsed.value.dimensions.?.cols);
}

test "JSON metadata blob encode/decode" {
    const allocator = std.testing.allocator;
    const metadata = FrameMetadata{
        .cursor = .{ .x = 0, .y = 0, .visible = true },
        .terminal_modes = .{ .bracketed_paste = true, .focus_reporting = false },
    };

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try encodeJsonMetadata(allocator, metadata, fbs.writer());

    var read_stream = std.io.fixedBufferStream(fbs.getWritten());
    const decoded = try decodeJsonMetadata(read_stream.reader(), allocator);
    defer decoded.deinit();
    try std.testing.expect(decoded.value.cursor != null);
    try std.testing.expect(decoded.value.terminal_modes.?.bracketed_paste.?);
}

test "Full FrameUpdate encode (dirty rows + metadata)" {
    const allocator = std.testing.allocator;

    const cells = [_]cell_mod.CellData{
        .{ .codepoint = 'X', .flags = 0, .wide = 0, .content_tag = 0, .fg_color = cell_mod.PackedColor.default_color, .bg_color = cell_mod.PackedColor.default_color },
    };
    const dirty = [_]DirtyRow{.{
        .header = .{ .y = 0, .row_flags = 0, .selection_start = 0, .selection_end = 0, .num_cells = 1 },
        .cells = &cells,
    }};

    const fh = FrameHeader{
        .session_id = 1,
        .pane_id = 1,
        .frame_sequence = 1,
        .frame_type = .p_frame,
        .screen = .primary,
        .section_flags = SectionFlags.dirty_rows | SectionFlags.json_metadata,
    };

    const metadata = FrameMetadata{
        .cursor = .{ .x = 1, .y = 0 },
    };

    const payload = try encodeFrameUpdate(allocator, fh, &dirty, metadata);
    defer allocator.free(payload);

    // Verify frame header at start
    try std.testing.expect(payload.len >= FRAME_HEADER_SIZE);
    const decoded_fh = FrameHeader.decode(payload[0..FRAME_HEADER_SIZE]);
    try std.testing.expectEqual(@as(u32, 1), decoded_fh.session_id);
    try std.testing.expectEqual(FrameType.p_frame, decoded_fh.frame_type);
}
