const std = @import("std");
const header_mod = @import("header.zig");

/// Write a complete frame (header + payload) to a writer.
pub fn writeFrame(writer: anytype, hdr: header_mod.Header, payload: []const u8) @TypeOf(writer).Error!void {
    var hdr_buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&hdr_buf);
    try writer.writeAll(&hdr_buf);
    if (payload.len > 0) {
        try writer.writeAll(payload);
    }
}

test "writeFrame: produces correct bytes" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const hdr = header_mod.Header{
        .msg_type = 0x0100,
        .flags = .{},
        .payload_length = 3,
        .sequence = 7,
    };
    try writeFrame(fbs.writer(), hdr, "abc");

    const written = fbs.getWritten();
    // Should be header (16) + payload (3) = 19 bytes
    try std.testing.expectEqual(@as(usize, 19), written.len);
    // Magic bytes
    try std.testing.expectEqual(@as(u8, 0x49), written[0]);
    try std.testing.expectEqual(@as(u8, 0x54), written[1]);
    // Payload follows header
    try std.testing.expectEqualSlices(u8, "abc", written[16..19]);
}
