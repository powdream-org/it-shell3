//! JSON metadata blob serializer for FrameUpdate messages. Produces the
//! length-prefixed JSON section (4-byte u32 LE + JSON bytes) per protocol
//! 04-input-and-renderstate FrameUpdate metadata format.
//!
//! I-frame metadata includes all required fields. P-frame metadata includes
//! only changed fields (absent fields are omitted, not null).

const std = @import("std");

/// Maximum size of the JSON metadata blob (excluding the 4-byte length prefix).
pub const MAX_JSON_METADATA_SIZE: usize = 4096;

/// Total buffer size needed: 4-byte length prefix + max JSON.
pub const METADATA_BUFFER_SIZE: usize = 4 + MAX_JSON_METADATA_SIZE;

/// Cursor state for metadata serialization.
pub const CursorInfo = struct {
    x: u16 = 0,
    y: u16 = 0,
    visible: bool = true,
    style: CursorStyle = .block,
    blinking: bool = false,
    password_input: bool = false,

    pub const CursorStyle = enum {
        block,
        underline,
        bar,

        pub fn toStr(self: CursorStyle) []const u8 {
            return switch (self) {
                .block => "block",
                .underline => "underline",
                .bar => "bar",
            };
        }
    };
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
pub const TerminalModes = struct {
    application_cursor: bool = false,
    application_keypad: bool = false,
    auto_wrap: bool = true,
    mouse_tracking: MouseTracking = .none,
    focus_reporting: bool = false,
    bracketed_paste: bool = false,
    kitty_keyboard_flags: u8 = 0,

    pub const MouseTracking = enum {
        none,
        x10,
        normal,
        button,
        any,

        pub fn toStr(self: MouseTracking) []const u8 {
            return switch (self) {
                .none => "none",
                .x10 => "x10",
                .normal => "normal",
                .button => "button",
                .any => "any",
            };
        }
    };
};

/// Full metadata for I-frame serialization (all fields required).
pub const IFrameMetadata = struct {
    cursor: CursorInfo,
    dimensions: DimensionsInfo,
    palette: *const [256]RgbColor,
    fg: RgbColor,
    bg: RgbColor,
    mouse: TerminalModes.MouseTracking,
    terminal_modes: TerminalModes,
};

/// Delta metadata for P-frame serialization (only changed fields).
pub const PFrameMetadata = struct {
    cursor: ?CursorInfo = null,
    dimensions: ?DimensionsInfo = null,
    palette_changes: ?[]const PaletteChange = null,
    fg: ?RgbColor = null,
    bg: ?RgbColor = null,
    mouse: ?TerminalModes.MouseTracking = null,
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

    // cursor
    writer.print("\"cursor\":{{\"x\":{d},\"y\":{d},\"visible\":{},\"style\":\"{s}\",\"blinking\":{},\"password_input\":{}}}", .{
        metadata.cursor.x,
        metadata.cursor.y,
        metadata.cursor.visible,
        metadata.cursor.style.toStr(),
        metadata.cursor.blinking,
        metadata.cursor.password_input,
    }) catch return null;

    // dimensions
    writer.print(",\"dimensions\":{{\"cols\":{d},\"rows\":{d}}}", .{
        metadata.dimensions.cols,
        metadata.dimensions.rows,
    }) catch return null;

    // palette (256 entries, [r,g,b] triples)
    writer.writeAll(",\"palette\":[") catch return null;
    for (metadata.palette, 0..) |color, i| {
        if (i > 0) writer.writeAll(",") catch return null;
        writer.print("[{d},{d},{d}]", .{ color.r, color.g, color.b }) catch return null;
    }
    writer.writeAll("]") catch return null;

    // fg, bg
    writer.print(",\"fg\":[{d},{d},{d}]", .{ metadata.fg.r, metadata.fg.g, metadata.fg.b }) catch return null;
    writer.print(",\"bg\":[{d},{d},{d}]", .{ metadata.bg.r, metadata.bg.g, metadata.bg.b }) catch return null;

    // mouse
    writer.print(",\"mouse\":\"{s}\"", .{metadata.mouse.toStr()}) catch return null;

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
        writer.print("\"cursor\":{{\"x\":{d},\"y\":{d},\"visible\":{},\"style\":\"{s}\",\"blinking\":{},\"password_input\":{}}}", .{
            cursor.x,
            cursor.y,
            cursor.visible,
            cursor.style.toStr(),
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

    if (metadata.palette_changes) |changes| {
        if (!first) writer.writeAll(",") catch return null;
        writer.writeAll("\"palette_changes\":[") catch return null;
        for (changes, 0..) |change, i| {
            if (i > 0) writer.writeAll(",") catch return null;
            writer.print("{{\"index\":{d},\"color\":[{d},{d},{d}]}}", .{
                change.index,
                change.color.r,
                change.color.g,
                change.color.b,
            }) catch return null;
        }
        writer.writeAll("]") catch return null;
        first = false;
    }

    if (metadata.fg) |fg| {
        if (!first) writer.writeAll(",") catch return null;
        writer.print("\"fg\":[{d},{d},{d}]", .{ fg.r, fg.g, fg.b }) catch return null;
        first = false;
    }

    if (metadata.bg) |bg| {
        if (!first) writer.writeAll(",") catch return null;
        writer.print("\"bg\":[{d},{d},{d}]", .{ bg.r, bg.g, bg.b }) catch return null;
        first = false;
    }

    if (metadata.mouse) |mouse| {
        if (!first) writer.writeAll(",") catch return null;
        writer.print("\"mouse\":\"{s}\"", .{mouse.toStr()}) catch return null;
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
    try writer.print(",\"terminal_modes\":{{\"application_cursor\":{},\"application_keypad\":{},\"auto_wrap\":{},\"mouse_tracking\":\"{s}\",\"focus_reporting\":{},\"bracketed_paste\":{},\"kitty_keyboard_flags\":{d}}}", .{
        modes.application_cursor,
        modes.application_keypad,
        modes.auto_wrap,
        modes.mouse_tracking.toStr(),
        modes.focus_reporting,
        modes.bracketed_paste,
        modes.kitty_keyboard_flags,
    });
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "serializeIFrameMetadata: produces valid length-prefixed JSON" {
    var palette: [256]RgbColor = @splat(RgbColor{});
    palette[0] = .{ .r = 0, .g = 0, .b = 0 };
    palette[255] = .{ .r = 255, .g = 255, .b = 255 };

    const metadata = IFrameMetadata{
        .cursor = .{ .x = 5, .y = 10, .visible = true, .style = .block, .blinking = false, .password_input = false },
        .dimensions = .{ .cols = 80, .rows = 24 },
        .palette = &palette,
        .fg = .{ .r = 255, .g = 255, .b = 255 },
        .bg = .{ .r = 0, .g = 0, .b = 0 },
        .mouse = .none,
        .terminal_modes = .{},
    };

    var buf: [METADATA_BUFFER_SIZE]u8 = undefined;
    const total = serializeIFrameMetadata(&metadata, &buf);
    try std.testing.expect(total != null);

    // Verify length prefix
    const json_len = std.mem.readInt(u32, buf[0..4], .little);
    try std.testing.expectEqual(total.? - 4, json_len);

    // Verify JSON is valid UTF-8 and contains required fields
    const json = buf[4..][0..json_len];
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cursor\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dimensions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"palette\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fg\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"bg\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mouse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"terminal_modes\"") != null);
}

test "serializeIFrameMetadata: cursor fields serialize correctly" {
    var palette: [256]RgbColor = @splat(RgbColor{});
    const metadata = IFrameMetadata{
        .cursor = .{ .x = 42, .y = 7, .visible = false, .style = .bar, .blinking = true, .password_input = true },
        .dimensions = .{ .cols = 80, .rows = 24 },
        .palette = &palette,
        .fg = .{},
        .bg = .{},
        .mouse = .none,
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
    try std.testing.expect(std.mem.indexOf(u8, json, "\"style\":\"bar\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"blinking\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"password_input\":true") != null);
}

test "serializeIFrameMetadata: palette produces 256 entries" {
    var palette: [256]RgbColor = @splat(RgbColor{});
    const metadata = IFrameMetadata{
        .cursor = .{},
        .dimensions = .{},
        .palette = &palette,
        .fg = .{},
        .bg = .{},
        .mouse = .none,
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
    try std.testing.expect(std.mem.indexOf(u8, json, "\"palette\"") == null);
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
    try std.testing.expect(std.mem.indexOf(u8, json, "\"palette_changes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"index\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"index\":7") != null);
}
