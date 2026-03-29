//! JSON encode/decode helpers shared across protocol unit tests.
//! Mirrors the production wire format (unknown-field tolerance, null omission).

const std = @import("std");

/// Alias for the parse error type returned by `decode`.
pub const ParseError = std.json.ParseError(std.json.Scanner);

/// Decodes a JSON payload into `T`, tolerating unknown fields for forward
/// compatibility.
pub fn decode(comptime T: type, allocator: std.mem.Allocator, payload: []const u8) ParseError!std.json.Parsed(T) {
    return std.json.parseFromSlice(T, allocator, payload, .{
        .ignore_unknown_fields = true,
    });
}

/// Encodes `value` to JSON, omitting null optional fields to match
/// the production wire format.
pub fn encode(allocator: std.mem.Allocator, value: anytype) error{OutOfMemory}![]u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{
        .emit_null_optional_fields = false,
    });
}

const TestMsg = struct {
    id: u32,
    name: []const u8,
    value: ?u32 = null,
};

test "encode/decode: round-trip" {
    const allocator = std.testing.allocator;
    const original = TestMsg{ .id = 42, .name = "hello", .value = 99 };
    const json = try encode(allocator, original);
    defer allocator.free(json);
    const parsed = try decode(TestMsg, allocator, json);
    defer parsed.deinit();
    try std.testing.expectEqual(original.id, parsed.value.id);
    try std.testing.expectEqualStrings(original.name, parsed.value.name);
    try std.testing.expectEqual(original.value, parsed.value.value);
}

test "decode: unknown fields tolerated" {
    const allocator = std.testing.allocator;
    const json = "{\"id\":1,\"name\":\"x\",\"unknown_field\":true}";
    const parsed = try decode(TestMsg, allocator, json);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.id);
}

test "encode: omits null optional fields" {
    const allocator = std.testing.allocator;
    const msg = TestMsg{ .id = 1, .name = "x", .value = null };
    const json = try encode(allocator, msg);
    defer allocator.free(json);
    // Should not contain "value" key
    try std.testing.expect(std.mem.indexOf(u8, json, "value") == null);
}

test "decode: null optional field treated as absent" {
    const allocator = std.testing.allocator;
    // Receivers must tolerate null values as "absent"
    const json = "{\"id\":5,\"name\":\"y\",\"value\":null}";
    const parsed = try decode(TestMsg, allocator, json);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 5), parsed.value.id);
    try std.testing.expectEqual(@as(?u32, null), parsed.value.value);
}
