//! Mouse encoding helper: wraps ghostty's mouse_encode.encode().
//! Free functions, NOT wrapper types — per design spec §1.2/§4.5.
const std = @import("std");
const ghostty = @import("ghostty");

pub const MouseAction = ghostty.input.MouseAction;
pub const MouseButton = ghostty.input.MouseButton;
pub const MouseEncodeOptions = ghostty.input.MouseEncodeOptions;
pub const MouseEncodeEvent = ghostty.input.MouseEncodeEvent;

/// Maximum buffer size for a single encoded mouse sequence.
/// SGR mouse sequences are the longest: "\x1B[<btn;x;yM" ≤ ~20 bytes.
pub const max_encode_size = 32;

/// Encode a mouse event into terminal escape sequence bytes.
/// Returns the slice of `buf` that was written to, or an empty slice
/// if the event produces no output (e.g., mouse reporting disabled).
pub fn encodeMouse(
    buf: *[max_encode_size]u8,
    event: MouseEncodeEvent,
    opts: MouseEncodeOptions,
) std.Io.Writer.Error![]const u8 {
    var writer: std.Io.Writer = .fixed(buf);
    try ghostty.input.encodeMouse(&writer, event, opts);
    return writer.buffered();
}

// --- Tests ---

fn testMouseOptions() MouseEncodeOptions {
    // Construct options with SGR format and normal event mode.
    // The size field uses renderer_size.Size (not exported via ghostty-vt),
    // so we zero-init and set a minimal cell-based size.
    var opts: MouseEncodeOptions = std.mem.zeroes(MouseEncodeOptions);
    opts.event = .normal;
    opts.format = .sgr;
    opts.any_button_pressed = true;
    // Size fields: set screen to 800x600, cell to 10x20 so grid = 80x30.
    opts.size.screen.width = 800;
    opts.size.screen.height = 600;
    opts.size.cell.width = 10;
    opts.size.cell.height = 20;
    return opts;
}

test "mouse encoder types are accessible" {
    try std.testing.expect(@sizeOf(MouseEncodeEvent) > 0);
    try std.testing.expect(@sizeOf(MouseEncodeOptions) > 0);
    try std.testing.expect(@sizeOf(MouseAction) > 0);
    try std.testing.expect(@sizeOf(MouseButton) > 0);
}

test "encodeMouse left click produces SGR sequence" {
    var buf: [max_encode_size]u8 = undefined;
    const event: MouseEncodeEvent = .{
        .action = .press,
        .button = .left,
        .pos = .{ .x = 100, .y = 200 },
    };
    const result = try encodeMouse(&buf, event, testMouseOptions());
    // SGR format: ESC [ < btn ; x ; y M
    // btn=0 (left press), x=col+1, y=row+1 (1-based)
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, result, "\x1B[<"));
    // SGR press ends with 'M'
    try std.testing.expectEqual(@as(u8, 'M'), result[result.len - 1]);
}

test "encodeMouse release produces SGR release sequence" {
    var buf: [max_encode_size]u8 = undefined;
    const event: MouseEncodeEvent = .{
        .action = .release,
        .button = .left,
        .pos = .{ .x = 100, .y = 200 },
    };
    var opts = testMouseOptions();
    opts.any_button_pressed = false;
    const result = try encodeMouse(&buf, event, opts);
    // SGR release ends with 'm' (lowercase)
    try std.testing.expect(result.len > 0);
    try std.testing.expectEqual(@as(u8, 'm'), result[result.len - 1]);
}

test "encodeMouse no output when mouse reporting disabled" {
    var buf: [max_encode_size]u8 = undefined;
    const event: MouseEncodeEvent = .{
        .action = .press,
        .button = .left,
        .pos = .{ .x = 50, .y = 50 },
    };
    // event = .none means mouse reporting is off
    var opts = testMouseOptions();
    opts.event = .none;
    const result = try encodeMouse(&buf, event, opts);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}
