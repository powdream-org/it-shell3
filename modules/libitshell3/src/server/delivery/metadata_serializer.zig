//! JSON metadata blob serializer for FrameUpdate messages. Produces the
//! length-prefixed JSON section (4-byte u32 LE + JSON bytes) per protocol
//! 04-input-and-renderstate FrameUpdate metadata format.
//!
//! I-frame metadata includes all required fields. P-frame metadata includes
//! only changed fields (absent fields are omitted, not null).

const std = @import("std");

/// Maximum size of the JSON metadata blob (excluding the 4-byte length prefix).
///
/// Worst-case calculation: cursor ~90B + dimensions ~30B + colors section with
/// full 256-entry palette (256 * "[255,255,255]," ~3584B) + fg/bg/cursor_color
/// ~60B + mouse ~30B + terminal_modes ~120B + structural overhead ~100B
/// = ~4014B minimum for I-frame with full palette. Buffer at 8192 provides
/// ~2x headroom for palette_changes in P-frames and future fields.
pub const MAX_JSON_METADATA_SIZE: usize = 8192;

/// Total buffer size needed: 4-byte length prefix + max JSON.
pub const METADATA_BUFFER_SIZE: usize = 4 + MAX_JSON_METADATA_SIZE;

/// Cursor state for metadata serialization.
/// Per protocol 04-input-and-renderstate Section 3.2 cursor fields.
pub const CursorInfo = struct {
    x: u16 = 0,
    y: u16 = 0,
    visible: bool = true,
    /// Cursor style as u8 per spec: 0=block, 1=bar, 2=underline.
    style: u8 = 0,
    blinking: bool = false,
    password_input: bool = false,
};

/// Terminal dimensions for metadata.
pub const DimensionsInfo = struct {
    cols: u16 = 80,
    rows: u16 = 24,
};

/// Color triple for palette entries.
pub const RgbColor = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

/// Terminal mode flags for metadata.
/// Per protocol 04-input-and-renderstate Section 3.2 terminal modes fields.
pub const TerminalModes = struct {
    bracketed_paste: bool = false,
    focus_reporting: bool = false,
    application_cursor_keys: bool = false,
    application_keypad: bool = false,
    kitty_keyboard_flags: u8 = 0,
};

/// Mouse state for metadata serialization.
/// Per protocol 04-input-and-renderstate Section 3.2 mouse fields.
pub const MouseState = struct {
    /// 0=off, 1=button, 2=any (motion), 3=sgr.
    tracking: u8 = 0,
    /// 0=normal, 1=sgr, 2=urxvt.
    format: u8 = 0,
};

/// Full metadata for I-frame serialization (all fields required).
/// Per protocol 04-input-and-renderstate Section 3.2.
pub const IFrameMetadata = struct {
    cursor: CursorInfo,
    dimensions: DimensionsInfo,
    /// Full 256-entry palette (REQUIRED in I-frames).
    palette: *const [256]RgbColor,
    /// Default foreground RGB (REQUIRED in I-frames).
    fg: RgbColor,
    /// Default background RGB (REQUIRED in I-frames).
    bg: RgbColor,
    /// Cursor color override (null when no override active).
    cursor_color: ?RgbColor = null,
    mouse: MouseState,
    terminal_modes: TerminalModes,
};

/// Delta metadata for P-frame serialization (only changed fields).
/// Per protocol 04-input-and-renderstate Section 3.2.
pub const PFrameMetadata = struct {
    cursor: ?CursorInfo = null,
    dimensions: ?DimensionsInfo = null,
    palette_changes: ?[]const PaletteChange = null,
    fg: ?RgbColor = null,
    bg: ?RgbColor = null,
    cursor_color: ?RgbColor = null,
    mouse: ?MouseState = null,
    terminal_modes: ?TerminalModes = null,
};

/// A single palette entry change for P-frame delta.
pub const PaletteChange = struct {
    index: u8,
    color: RgbColor,
};

/// Serializes I-frame metadata into a length-prefixed JSON blob.
/// Returns the total bytes written (4-byte prefix + JSON), or null on error.
pub fn serializeIFrameMetadata(
    metadata: *const IFrameMetadata,
    out: []u8,
) ?usize {
    if (out.len < METADATA_BUFFER_SIZE) return null;

    var json_buf: [MAX_JSON_METADATA_SIZE]u8 = undefined;
    var stream = std.io.fixedBufferStream(&json_buf);
    const writer = stream.writer();

    writer.writeAll("{") catch return null;

    // cursor (style as u8 per spec: 0=block, 1=bar, 2=underline)
    writer.print("\"cursor\":{{\"x\":{d},\"y\":{d},\"visible\":{},\"style\":{d},\"blinking\":{},\"password_input\":{}}}", .{
        metadata.cursor.x,
        metadata.cursor.y,
        metadata.cursor.visible,
        metadata.cursor.style,
        metadata.cursor.blinking,
        metadata.cursor.password_input,
    }) catch return null;

    // dimensions
    writer.print(",\"dimensions\":{{\"cols\":{d},\"rows\":{d}}}", .{
        metadata.dimensions.cols,
        metadata.dimensions.rows,
    }) catch return null;

    // colors (nested object per spec Section 3.2)
    writer.writeAll(",\"colors\":{") catch return null;
    // fg (REQUIRED in I-frames)
    writer.print("\"fg\":[{d},{d},{d}]", .{ metadata.fg.r, metadata.fg.g, metadata.fg.b }) catch return null;
    // bg (REQUIRED in I-frames)
    writer.print(",\"bg\":[{d},{d},{d}]", .{ metadata.bg.r, metadata.bg.g, metadata.bg.b }) catch return null;
    // cursor_color (included when override active)
    if (metadata.cursor_color) |cc| {
        writer.print(",\"cursor_color\":[{d},{d},{d}]", .{ cc.r, cc.g, cc.b }) catch return null;
    }
    // palette (REQUIRED in I-frames, 256 entries)
    writer.writeAll(",\"palette\":[") catch return null;
    for (metadata.palette, 0..) |color, i| {
        if (i > 0) writer.writeAll(",") catch return null;
        writer.print("[{d},{d},{d}]", .{ color.r, color.g, color.b }) catch return null;
    }
    writer.writeAll("]") catch return null;
    writer.writeAll("}") catch return null;

    // mouse (object with tracking/format per spec)
    writer.print(",\"mouse\":{{\"tracking\":{d},\"format\":{d}}}", .{
        metadata.mouse.tracking,
        metadata.mouse.format,
    }) catch return null;

    // terminal_modes
    writeTerminalModes(writer, &metadata.terminal_modes) catch return null;

    writer.writeAll("}") catch return null;

    const json_len = stream.getWritten().len;
    // Write 4-byte LE length prefix
    std.mem.writeInt(u32, out[0..4], @intCast(json_len), .little);
    @memcpy(out[4..][0..json_len], stream.getWritten());

    return 4 + json_len;
}

/// Serializes P-frame delta metadata into a length-prefixed JSON blob.
/// Only includes fields that have changed. Returns null if no fields changed
/// or on error.
pub fn serializePFrameMetadata(
    metadata: *const PFrameMetadata,
    out: []u8,
) ?usize {
    if (out.len < METADATA_BUFFER_SIZE) return null;

    // Check if anything changed
    if (metadata.cursor == null and
        metadata.dimensions == null and
        metadata.palette_changes == null and
        metadata.fg == null and
        metadata.bg == null and
        metadata.cursor_color == null and
        metadata.mouse == null and
        metadata.terminal_modes == null)
    {
        return null;
    }

    var json_buf: [MAX_JSON_METADATA_SIZE]u8 = undefined;
    var stream = std.io.fixedBufferStream(&json_buf);
    const writer = stream.writer();
    var first = true;

    writer.writeAll("{") catch return null;

    if (metadata.cursor) |cursor| {
        if (!first) writer.writeAll(",") catch return null;
        writer.print("\"cursor\":{{\"x\":{d},\"y\":{d},\"visible\":{},\"style\":{d},\"blinking\":{},\"password_input\":{}}}", .{
            cursor.x,
            cursor.y,
            cursor.visible,
            cursor.style,
            cursor.blinking,
            cursor.password_input,
        }) catch return null;
        first = false;
    }

    if (metadata.dimensions) |dims| {
        if (!first) writer.writeAll(",") catch return null;
        writer.print("\"dimensions\":{{\"cols\":{d},\"rows\":{d}}}", .{ dims.cols, dims.rows }) catch return null;
        first = false;
    }

    // colors section (nested object per spec)
    const has_colors = metadata.fg != null or metadata.bg != null or
        metadata.cursor_color != null or metadata.palette_changes != null;
    if (has_colors) {
        if (!first) writer.writeAll(",") catch return null;
        writer.writeAll("\"colors\":{") catch return null;
        var colors_first = true;

        if (metadata.fg) |fg| {
            writer.print("\"fg\":[{d},{d},{d}]", .{ fg.r, fg.g, fg.b }) catch return null;
            colors_first = false;
        }

        if (metadata.bg) |bg| {
            if (!colors_first) writer.writeAll(",") catch return null;
            writer.print("\"bg\":[{d},{d},{d}]", .{ bg.r, bg.g, bg.b }) catch return null;
            colors_first = false;
        }

        if (metadata.cursor_color) |cc| {
            if (!colors_first) writer.writeAll(",") catch return null;
            writer.print("\"cursor_color\":[{d},{d},{d}]", .{ cc.r, cc.g, cc.b }) catch return null;
            colors_first = false;
        }

        if (metadata.palette_changes) |changes| {
            if (!colors_first) writer.writeAll(",") catch return null;
            writer.writeAll("\"palette_changes\":[") catch return null;
            for (changes, 0..) |change, i| {
                if (i > 0) writer.writeAll(",") catch return null;
                writer.print("[{d},[{d},{d},{d}]]", .{
                    change.index,
                    change.color.r,
                    change.color.g,
                    change.color.b,
                }) catch return null;
            }
            writer.writeAll("]") catch return null;
        }

        writer.writeAll("}") catch return null;
        first = false;
    }

    if (metadata.mouse) |mouse| {
        if (!first) writer.writeAll(",") catch return null;
        writer.print("\"mouse\":{{\"tracking\":{d},\"format\":{d}}}", .{
            mouse.tracking,
            mouse.format,
        }) catch return null;
        first = false;
    }

    if (metadata.terminal_modes) |modes| {
        if (!first) writer.writeAll(",") catch return null;
        writeTerminalModes(writer, &modes) catch return null;
    }

    writer.writeAll("}") catch return null;

    const json_len = stream.getWritten().len;
    std.mem.writeInt(u32, out[0..4], @intCast(json_len), .little);
    @memcpy(out[4..][0..json_len], stream.getWritten());

    return 4 + json_len;
}

fn writeTerminalModes(writer: anytype, modes: *const TerminalModes) !void {
    try writer.print(",\"terminal_modes\":{{\"bracketed_paste\":{},\"focus_reporting\":{},\"application_cursor_keys\":{},\"application_keypad\":{},\"kitty_keyboard_flags\":{d}}}", .{
        modes.bracketed_paste,
        modes.focus_reporting,
        modes.application_cursor_keys,
        modes.application_keypad,
        modes.kitty_keyboard_flags,
    });
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "serializeIFrameMetadata: produces valid length-prefixed JSON" {
    var palette: [256]RgbColor = @splat(RgbColor{});
    palette[0] = .{ .r = 0, .g = 0, .b = 0 };
    palette[255] = .{ .r = 255, .g = 255, .b = 255 };

    const metadata = IFrameMetadata{
        .cursor = .{ .x = 5, .y = 10, .visible = true, .style = 0, .blinking = false, .password_input = false },
        .dimensions = .{ .cols = 80, .rows = 24 },
        .palette = &palette,
        .fg = .{ .r = 255, .g = 255, .b = 255 },
        .bg = .{ .r = 0, .g = 0, .b = 0 },
        .mouse = .{},
        .terminal_modes = .{},
    };

    var buf: [METADATA_BUFFER_SIZE]u8 = undefined;
    const total = serializeIFrameMetadata(&metadata, &buf);
    try std.testing.expect(total != null);

    // Verify length prefix
    const json_len = std.mem.readInt(u32, buf[0..4], .little);
    try std.testing.expectEqual(total.? - 4, json_len);

    // Verify JSON contains required fields per spec Section 3.2
    const json = buf[4..][0..json_len];
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cursor\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dimensions\"") != null);
    // Colors nested under "colors" object per spec
    try std.testing.expect(std.mem.indexOf(u8, json, "\"colors\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"palette\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fg\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"bg\"") != null);
    // mouse as object with tracking/format
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mouse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tracking\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"terminal_modes\"") != null);
    // Verify spec field names
    try std.testing.expect(std.mem.indexOf(u8, json, "\"application_cursor_keys\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"bracketed_paste\"") != null);
}

test "serializeIFrameMetadata: cursor fields serialize correctly" {
    var palette: [256]RgbColor = @splat(RgbColor{});
    const metadata = IFrameMetadata{
        .cursor = .{ .x = 42, .y = 7, .visible = false, .style = 1, .blinking = true, .password_input = true },
        .dimensions = .{ .cols = 80, .rows = 24 },
        .palette = &palette,
        .fg = .{},
        .bg = .{},
        .mouse = .{},
        .terminal_modes = .{},
    };

    var buf: [METADATA_BUFFER_SIZE]u8 = undefined;
    const total = serializeIFrameMetadata(&metadata, &buf);
    try std.testing.expect(total != null);

    const json_len = std.mem.readInt(u32, buf[0..4], .little);
    const json = buf[4..][0..json_len];
    try std.testing.expect(std.mem.indexOf(u8, json, "\"x\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"y\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"visible\":false") != null);
    // style is u8 per spec: 0=block, 1=bar, 2=underline
    try std.testing.expect(std.mem.indexOf(u8, json, "\"style\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"blinking\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"password_input\":true") != null);
}

test "serializeIFrameMetadata: cursor_color included when present" {
    var palette: [256]RgbColor = @splat(RgbColor{});
    const metadata = IFrameMetadata{
        .cursor = .{},
        .dimensions = .{},
        .palette = &palette,
        .fg = .{},
        .bg = .{},
        .cursor_color = .{ .r = 255, .g = 200, .b = 0 },
        .mouse = .{},
        .terminal_modes = .{},
    };

    var buf: [METADATA_BUFFER_SIZE]u8 = undefined;
    const total = serializeIFrameMetadata(&metadata, &buf);
    try std.testing.expect(total != null);

    const json_len = std.mem.readInt(u32, buf[0..4], .little);
    const json = buf[4..][0..json_len];
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cursor_color\":[255,200,0]") != null);
}

test "serializeIFrameMetadata: cursor_color omitted when null" {
    var palette: [256]RgbColor = @splat(RgbColor{});
    const metadata = IFrameMetadata{
        .cursor = .{},
        .dimensions = .{},
        .palette = &palette,
        .fg = .{},
        .bg = .{},
        .mouse = .{},
        .terminal_modes = .{},
    };

    var buf: [METADATA_BUFFER_SIZE]u8 = undefined;
    const total = serializeIFrameMetadata(&metadata, &buf);
    try std.testing.expect(total != null);

    const json_len = std.mem.readInt(u32, buf[0..4], .little);
    const json = buf[4..][0..json_len];
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cursor_color\"") == null);
}

test "serializeIFrameMetadata: palette produces 256 entries" {
    var palette: [256]RgbColor = @splat(RgbColor{});
    const metadata = IFrameMetadata{
        .cursor = .{},
        .dimensions = .{},
        .palette = &palette,
        .fg = .{},
        .bg = .{},
        .mouse = .{},
        .terminal_modes = .{},
    };

    var buf: [METADATA_BUFFER_SIZE]u8 = undefined;
    const total = serializeIFrameMetadata(&metadata, &buf);
    try std.testing.expect(total != null);

    const json_len = std.mem.readInt(u32, buf[0..4], .little);
    const json = buf[4..][0..json_len];
    // Count commas inside palette array as proxy for 256 entries
    // 256 entries separated by 255 commas within the palette array
    var comma_count: usize = 0;
    const palette_start = std.mem.indexOf(u8, json, "\"palette\":[").? + "\"palette\":[".len;
    // Find matching close bracket
    var depth: i32 = 1;
    var pos = palette_start;
    while (pos < json.len and depth > 0) : (pos += 1) {
        if (json[pos] == '[') depth += 1;
        if (json[pos] == ']') depth -= 1;
        if (json[pos] == ',' and depth == 1) comma_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 255), comma_count);
}

test "serializePFrameMetadata: null metadata returns null" {
    const metadata = PFrameMetadata{};
    var buf: [METADATA_BUFFER_SIZE]u8 = undefined;
    const total = serializePFrameMetadata(&metadata, &buf);
    try std.testing.expect(total == null);
}

test "serializePFrameMetadata: only includes changed fields" {
    const metadata = PFrameMetadata{
        .cursor = .{ .x = 10, .y = 5 },
    };

    var buf: [METADATA_BUFFER_SIZE]u8 = undefined;
    const total = serializePFrameMetadata(&metadata, &buf);
    try std.testing.expect(total != null);

    const json_len = std.mem.readInt(u32, buf[0..4], .little);
    const json = buf[4..][0..json_len];
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cursor\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dimensions\"") == null);
    // No colors section when no color fields changed
    try std.testing.expect(std.mem.indexOf(u8, json, "\"colors\"") == null);
}

test "serializePFrameMetadata: palette_changes delta format" {
    const changes = [_]PaletteChange{
        .{ .index = 0, .color = .{ .r = 255, .g = 0, .b = 0 } },
        .{ .index = 7, .color = .{ .r = 0, .g = 255, .b = 0 } },
    };
    const metadata = PFrameMetadata{
        .palette_changes = &changes,
    };

    var buf: [METADATA_BUFFER_SIZE]u8 = undefined;
    const total = serializePFrameMetadata(&metadata, &buf);
    try std.testing.expect(total != null);

    const json_len = std.mem.readInt(u32, buf[0..4], .little);
    const json = buf[4..][0..json_len];
    // palette_changes nested under colors object
    try std.testing.expect(std.mem.indexOf(u8, json, "\"colors\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"palette_changes\"") != null);
    // Per spec format: [[index, [r,g,b]], ...]
    try std.testing.expect(std.mem.indexOf(u8, json, "[0,[255,0,0]]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "[7,[0,255,0]]") != null);
}
