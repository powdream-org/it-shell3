const std = @import("std");

/// Generate a unique temporary socket path for testing.
/// Caller owns the returned slice and must free it with the provided allocator.
pub fn tempSocketPath(allocator: std.mem.Allocator) ![]u8 {
    var buf: [8]u8 = undefined;
    std.crypto.random.bytes(&buf);
    const hex = std.fmt.bytesToHex(buf, .lower);
    return std.fmt.allocPrint(
        allocator,
        "/tmp/itshell3-test-{s}.sock",
        .{&hex},
    );
}

test "tempSocketPath generates valid unique paths" {
    const allocator = std.testing.allocator;
    const path1 = try tempSocketPath(allocator);
    defer allocator.free(path1);
    const path2 = try tempSocketPath(allocator);
    defer allocator.free(path2);

    // Both start with the expected prefix
    try std.testing.expect(std.mem.startsWith(u8, path1, "/tmp/itshell3-test-"));
    try std.testing.expect(std.mem.endsWith(u8, path1, ".sock"));

    // Paths are unique
    try std.testing.expect(!std.mem.eql(u8, path1, path2));
}
