const std = @import("std");
const ime_consumer = @import("../server/ime_consumer.zig");

/// Mock PTY writer that records writes into a fixed buffer for test verification.
/// Shared across ime_consumer, ime_lifecycle, and ime_procedures tests.
pub const MockPtyWriter = struct {
    buf: [1024]u8 = @splat(0),
    len: usize = 0,

    pub fn writer(self: *MockPtyWriter) ime_consumer.PtyWriter {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    pub fn written(self: *const MockPtyWriter) []const u8 {
        return self.buf[0..self.len];
    }

    const vtable = ime_consumer.PtyWriter.VTable{
        .write = writeImpl,
    };

    fn writeImpl(ptr: *anyopaque, _: std.posix.fd_t, data: []const u8) ime_consumer.PtyWriter.WriteError!usize {
        const self: *MockPtyWriter = @ptrCast(@alignCast(ptr));
        const available = self.buf.len - self.len;
        const to_copy = @min(data.len, available);
        @memcpy(self.buf[self.len..][0..to_copy], data[0..to_copy]);
        self.len += to_copy;
        return data.len;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

test "MockPtyWriter: records written data" {
    var pw = MockPtyWriter{};
    _ = try pw.writer().write(10, "hello");
    _ = try pw.writer().write(10, " world");
    try std.testing.expectEqualSlices(u8, "hello world", pw.written());
}

test "MockPtyWriter: default is empty" {
    const pw = MockPtyWriter{};
    try std.testing.expectEqual(@as(usize, 0), pw.written().len);
}
