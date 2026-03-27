//! UCS-4 (uint32) to UTF-8 conversion utilities.
//! Used to convert libhangul's UCS-4 output strings to UTF-8 for ImeResult.

const std = @import("std");
const c = @import("c.zig");

/// Encode a single UCS-4 codepoint to UTF-8.
/// Returns the number of bytes written (1–4), or 0 if the codepoint is invalid
/// or the buffer is too small.
pub fn encodeCodepoint(cp: u32, buf: []u8) u8 {
    if (cp < 0x80) {
        if (buf.len < 1) return 0;
        buf[0] = @intCast(cp);
        return 1;
    } else if (cp < 0x800) {
        if (buf.len < 2) return 0;
        buf[0] = @intCast(0xC0 | (cp >> 6));
        buf[1] = @intCast(0x80 | (cp & 0x3F));
        return 2;
    } else if (cp < 0x10000) {
        if (buf.len < 3) return 0;
        buf[0] = @intCast(0xE0 | (cp >> 12));
        buf[1] = @intCast(0x80 | ((cp >> 6) & 0x3F));
        buf[2] = @intCast(0x80 | (cp & 0x3F));
        return 3;
    } else if (cp <= 0x10FFFF) {
        if (buf.len < 4) return 0;
        buf[0] = @intCast(0xF0 | (cp >> 18));
        buf[1] = @intCast(0x80 | ((cp >> 12) & 0x3F));
        buf[2] = @intCast(0x80 | ((cp >> 6) & 0x3F));
        buf[3] = @intCast(0x80 | (cp & 0x3F));
        return 4;
    }
    return 0; // invalid codepoint
}

/// Convert a null-terminated UCS-4 string (from libhangul) to UTF-8.
/// Returns the number of bytes written to `buf`.
/// Returns 0 if the input is empty or null.
pub fn ucs4ToUtf8(ucs4: [*c]const c.ucschar, buf: []u8) usize {
    if (ucs4 == null) return 0;

    var pos: usize = 0;
    var i: usize = 0;
    while (ucs4[i] != 0) : (i += 1) {
        const remaining = buf.len - pos;
        if (remaining < 4) break; // conservative: ensure room for max codepoint
        const n = encodeCodepoint(ucs4[i], buf[pos..]);
        if (n == 0) break;
        pos += n;
    }
    return pos;
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

test "encodeCodepoint: ASCII" {
    var buf: [4]u8 = undefined;
    const n = encodeCodepoint('a', &buf);
    try std.testing.expectEqual(@as(u8, 1), n);
    try std.testing.expectEqual(@as(u8, 'a'), buf[0]);
}

test "encodeCodepoint: 2-byte (Latin)" {
    var buf: [4]u8 = undefined;
    // é = U+00E9
    const n = encodeCodepoint(0xE9, &buf);
    try std.testing.expectEqual(@as(u8, 2), n);
    try std.testing.expectEqualSlices(u8, "\xC3\xA9", buf[0..2]);
}

test "encodeCodepoint: 3-byte (Korean)" {
    var buf: [4]u8 = undefined;
    // ㄱ = U+3131
    const n = encodeCodepoint(0x3131, &buf);
    try std.testing.expectEqual(@as(u8, 3), n);
    try std.testing.expectEqualSlices(u8, "\xE3\x84\xB1", buf[0..3]);

    // 한 = U+D55C
    const n2 = encodeCodepoint(0xD55C, &buf);
    try std.testing.expectEqual(@as(u8, 3), n2);
    try std.testing.expectEqualSlices(u8, "\xED\x95\x9C", buf[0..3]);
}

test "encodeCodepoint: 4-byte (emoji)" {
    var buf: [4]u8 = undefined;
    // 😀 = U+1F600
    const n = encodeCodepoint(0x1F600, &buf);
    try std.testing.expectEqual(@as(u8, 4), n);
    try std.testing.expectEqualSlices(u8, "\xF0\x9F\x98\x80", buf[0..4]);
}

test "encodeCodepoint: buffer too small" {
    var buf: [1]u8 = undefined;
    // 3-byte char in 1-byte buffer
    const n = encodeCodepoint(0x3131, &buf);
    try std.testing.expectEqual(@as(u8, 0), n);
}

test "encodeCodepoint: invalid codepoint" {
    var buf: [4]u8 = undefined;
    const n = encodeCodepoint(0x110000, &buf);
    try std.testing.expectEqual(@as(u8, 0), n);
}

test "ucs4ToUtf8: single Korean character" {
    // 가 = U+AC00
    const ucs4 = [_]c.ucschar{ 0xAC00, 0 };
    var buf: [64]u8 = undefined;
    const n = ucs4ToUtf8(&ucs4, &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualSlices(u8, "\xEA\xB0\x80", buf[0..3]);
}

test "ucs4ToUtf8: Korean syllable 한" {
    // 한 = U+D55C
    const ucs4 = [_]c.ucschar{ 0xD55C, 0 };
    var buf: [64]u8 = undefined;
    const n = ucs4ToUtf8(&ucs4, &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualSlices(u8, "\xED\x95\x9C", buf[0..3]);
}

test "ucs4ToUtf8: multiple characters" {
    // 간 = U+AC04, ㄱ = U+3131
    const ucs4 = [_]c.ucschar{ 0xAC04, 0x3131, 0 };
    var buf: [64]u8 = undefined;
    const n = ucs4ToUtf8(&ucs4, &buf);
    try std.testing.expectEqual(@as(usize, 6), n);
    try std.testing.expectEqualSlices(u8, "\xEA\xB0\x84\xE3\x84\xB1", buf[0..6]);
}

test "ucs4ToUtf8: empty string" {
    const ucs4 = [_]c.ucschar{0};
    var buf: [64]u8 = undefined;
    const n = ucs4ToUtf8(&ucs4, &buf);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "ucs4ToUtf8: ASCII characters" {
    const ucs4 = [_]c.ucschar{ 'H', 'i', 0 };
    var buf: [64]u8 = undefined;
    const n = ucs4ToUtf8(&ucs4, &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualSlices(u8, "Hi", buf[0..2]);
}
