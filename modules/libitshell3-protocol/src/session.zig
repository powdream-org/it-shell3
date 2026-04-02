//! Session management messages: create, list, attach, detach, destroy,
//! and rename.

const std = @import("std");

/// 0x0100, C->S.
pub const CreateSessionRequest = struct {
    name: ?[]const u8 = null,
    shell: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    cols: ?u16 = null,
    rows: ?u16 = null,
};

/// 0x0101, S->C.
pub const CreateSessionResponse = struct {
    status: u32 = 0,
    session_id: u32 = 0,
    pane_id: u32 = 0,
    @"error": ?[]const u8 = null,
};

/// 0x0102, C->S. Empty request body.
pub const ListSessionsRequest = struct {};

/// Entry within ListSessionsResponse.
pub const SessionInfo = struct {
    session_id: u32,
    name: []const u8,
    created_at: u64 = 0,
    pane_count: u16 = 1,
    attached_clients: u8 = 0,
};

/// 0x0103, S->C.
pub const ListSessionsResponse = struct {
    status: u32 = 0,
    sessions: []const SessionInfo = &.{},
};

/// 0x0104, C->S. Unified attach request: attach by session_id or
/// session_name, optionally creating a new session if missing.
/// Per ADR 00003 (AttachOrCreate merge into AttachSession).
pub const AttachSessionRequest = struct {
    session_id: u32 = 0,
    session_name: ?[]const u8 = null,
    create_if_missing: bool = false,
    cols: u16 = 80,
    rows: u16 = 24,
    readonly: bool = false,
    detach_others: bool = false,
    shell: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
};

/// 0x0105, S->C. Includes the current IME and resize policy state so the
/// client can synchronize immediately after attach.
/// Per ADR 00003, includes action_taken and pane_id fields from the
/// former AttachOrCreateResponse.
pub const AttachSessionResponse = struct {
    status: u32 = 0,
    action_taken: []const u8 = "attached",
    session_id: u32 = 0,
    pane_id: u32 = 0,
    name: []const u8 = "",
    active_pane_id: u32 = 0,
    active_input_method: []const u8 = "direct",
    active_keyboard_layout: []const u8 = "qwerty",
    resize_policy: []const u8 = "latest",
    @"error": ?[]const u8 = null,
};

/// 0x0106, C->S.
pub const DetachSessionRequest = struct {
    session_id: u32,
};

/// 0x0107, S->C.
pub const DetachSessionResponse = struct {
    status: u32 = 0,
    reason: []const u8 = "client_requested",
    @"error": ?[]const u8 = null,
};

/// 0x0108, C->S.
pub const DestroySessionRequest = struct {
    session_id: u32,
    force: bool = false,
};

/// 0x0109, S->C.
pub const DestroySessionResponse = struct {
    status: u32 = 0,
    @"error": ?[]const u8 = null,
};

/// 0x010A, C->S.
pub const RenameSessionRequest = struct {
    session_id: u32,
    name: []const u8,
};

/// 0x010B, S->C.
pub const RenameSessionResponse = struct {
    status: u32 = 0,
    @"error": ?[]const u8 = null,
};


test "CreateSessionRequest: JSON round-trip" {
    const json_mod = @import("testing/helpers.zig");
    const allocator = std.testing.allocator;
    const original = CreateSessionRequest{ .name = "my-session", .cols = 80, .rows = 24 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(CreateSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("my-session", parsed.value.name.?);
    try std.testing.expectEqual(@as(?u16, 80), parsed.value.cols);
}

test "CreateSessionResponse: JSON round-trip" {
    const json_mod = @import("testing/helpers.zig");
    const allocator = std.testing.allocator;
    const original = CreateSessionResponse{ .status = 0, .session_id = 5, .pane_id = 1 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(CreateSessionResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 5), parsed.value.session_id);
}

test "ListSessionsResponse: JSON round-trip" {
    const json_mod = @import("testing/helpers.zig");
    const allocator = std.testing.allocator;
    const sessions = [_]SessionInfo{.{ .session_id = 1, .name = "main", .pane_count = 2 }};
    const original = ListSessionsResponse{ .status = 0, .sessions = &sessions };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(ListSessionsResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.value.sessions.len);
    try std.testing.expectEqualStrings("main", parsed.value.sessions[0].name);
}

test "AttachSessionRequest: JSON round-trip by session_id" {
    const json_mod = @import("testing/helpers.zig");
    const allocator = std.testing.allocator;
    const original = AttachSessionRequest{ .session_id = 1, .cols = 100, .rows = 30 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(AttachSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.session_id);
    try std.testing.expectEqual(@as(u16, 100), parsed.value.cols);
    try std.testing.expectEqual(false, parsed.value.create_if_missing);
    try std.testing.expect(parsed.value.session_name == null);
}

test "AttachSessionRequest: JSON round-trip with create_if_missing" {
    const json_mod = @import("testing/helpers.zig");
    const allocator = std.testing.allocator;
    const original = AttachSessionRequest{
        .session_name = "dev",
        .create_if_missing = true,
        .shell = "/bin/zsh",
        .cwd = "/home/user",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(AttachSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("dev", parsed.value.session_name.?);
    try std.testing.expectEqual(true, parsed.value.create_if_missing);
    try std.testing.expectEqualStrings("/bin/zsh", parsed.value.shell.?);
    try std.testing.expectEqualStrings("/home/user", parsed.value.cwd.?);
    try std.testing.expectEqual(@as(u32, 0), parsed.value.session_id);
}

test "AttachSessionResponse: JSON round-trip" {
    const json_mod = @import("testing/helpers.zig");
    const allocator = std.testing.allocator;
    const original = AttachSessionResponse{
        .status = 0,
        .session_id = 2,
        .name = "dev",
        .active_pane_id = 3,
        .active_input_method = "korean_2set",
        .resize_policy = "latest",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(AttachSessionResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("dev", parsed.value.name);
    try std.testing.expectEqualStrings("korean_2set", parsed.value.active_input_method);
    try std.testing.expectEqualStrings("attached", parsed.value.action_taken);
    try std.testing.expectEqual(@as(u32, 0), parsed.value.pane_id);
}

test "AttachSessionResponse: action_taken created" {
    const json_mod = @import("testing/helpers.zig");
    const allocator = std.testing.allocator;
    const original = AttachSessionResponse{
        .action_taken = "created",
        .session_id = 1,
        .pane_id = 1,
        .name = "new-session",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(AttachSessionResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("created", parsed.value.action_taken);
    try std.testing.expectEqual(@as(u32, 1), parsed.value.pane_id);
}
