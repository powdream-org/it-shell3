const std = @import("std");
const json_mod = @import("json.zig");

/// ClientHello (0x0001, C->S)
pub const ClientHello = struct {
    protocol_version_min: u8 = 1,
    protocol_version_max: u8 = 1,
    client_type: ClientType = .native,
    capabilities: []const []const u8 = &.{},
    render_capabilities: []const []const u8 = &.{},
    preferred_input_methods: []const InputMethodPref = &.{},
    client_name: []const u8 = "",
    client_version: []const u8 = "",
    terminal_type: []const u8 = "xterm-256color",
    cols: u16 = 80,
    rows: u16 = 24,
    pixel_width: ?u16 = null,
    pixel_height: ?u16 = null,

    pub const ClientType = enum { native, control, headless };

    pub const InputMethodPref = struct {
        method: []const u8,
        layout: ?[]const u8 = null,
    };
};

/// ServerHello (0x0002, S->C)
pub const ServerHello = struct {
    protocol_version: u32 = 1,
    client_id: u32,
    negotiated_caps: []const []const u8 = &.{},
    negotiated_render_caps: []const []const u8 = &.{},
    supported_input_methods: []const InputMethodInfo = &.{},
    server_pid: u32,
    server_name: []const u8 = "itshell3d",
    server_version: []const u8 = "",
    heartbeat_interval_ms: u32 = 30000,
    max_panes_per_session: u16 = 0,
    max_sessions: u16 = 0,
    coalescing_config: ?CoalescingConfig = null,
    sessions: []const SessionSummary = &.{},

    pub const InputMethodInfo = struct {
        method: []const u8,
        layouts: []const []const u8 = &.{},
    };

    pub const CoalescingConfig = struct {
        interactive_threshold_kbps: u32 = 1,
        active_interval_ms: u16 = 16,
        bulk_threshold_kbps: u32 = 100,
        bulk_interval_ms: u16 = 33,
        idle_timeout_ms: u16 = 500,
        preedit_fallback_ms: u16 = 200,
    };

    pub const SessionSummary = struct {
        session_id: u32,
        name: []const u8,
        attached_clients: u8 = 0,
        pane_count: u16 = 1,
        created_at: u64 = 0,
        last_activity: u64 = 0,
    };
};

/// Heartbeat (0x0003, bidirectional)
pub const Heartbeat = struct {
    ping_id: u32,
};

/// HeartbeatAck (0x0004, bidirectional)
pub const HeartbeatAck = struct {
    ping_id: u32,
};

/// Disconnect (0x0005, bidirectional)
pub const Disconnect = struct {
    reason: []const u8 = "",
    detail: []const u8 = "",
};

test "ClientHello JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = ClientHello{
        .protocol_version_min = 1,
        .protocol_version_max = 1,
        .client_type = .native,
        .client_name = "it-shell3-macos",
        .client_version = "1.0.0",
        .cols = 80,
        .rows = 24,
    };
    const json = try json_mod.encode(allocator, original);
    defer allocator.free(json);
    const parsed = try json_mod.decode(ClientHello, allocator, json);
    defer parsed.deinit();
    try std.testing.expectEqual(original.protocol_version_min, parsed.value.protocol_version_min);
    try std.testing.expectEqual(original.cols, parsed.value.cols);
    try std.testing.expectEqual(original.rows, parsed.value.rows);
    try std.testing.expectEqualStrings(original.client_name, parsed.value.client_name);
}

test "ClientHello optional pixel fields omitted when null" {
    const allocator = std.testing.allocator;
    // pixel_width/pixel_height are null by default
    const original = ClientHello{};
    const json = try json_mod.encode(allocator, original);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "pixel_width") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "pixel_height") == null);
}

test "ClientHello optional pixel fields present when set" {
    const allocator = std.testing.allocator;
    const original = ClientHello{ .pixel_width = 1920, .pixel_height = 1080 };
    const json = try json_mod.encode(allocator, original);
    defer allocator.free(json);
    const parsed = try json_mod.decode(ClientHello, allocator, json);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?u16, 1920), parsed.value.pixel_width);
    try std.testing.expectEqual(@as(?u16, 1080), parsed.value.pixel_height);
}

test "ServerHello JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = ServerHello{
        .protocol_version = 1,
        .client_id = 3,
        .server_pid = 6839,
        .server_name = "itshell3d",
        .server_version = "1.0.0",
        .heartbeat_interval_ms = 30000,
    };
    const json = try json_mod.encode(allocator, original);
    defer allocator.free(json);
    const parsed = try json_mod.decode(ServerHello, allocator, json);
    defer parsed.deinit();
    try std.testing.expectEqual(original.client_id, parsed.value.client_id);
    try std.testing.expectEqual(original.server_pid, parsed.value.server_pid);
    try std.testing.expectEqualStrings(original.server_name, parsed.value.server_name);
}

test "ServerHello coalescing_config omitted when null" {
    const allocator = std.testing.allocator;
    const original = ServerHello{ .client_id = 1, .server_pid = 100 };
    const json = try json_mod.encode(allocator, original);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "coalescing_config") == null);
}

test "ServerHello coalescing_config round-trip when present" {
    const allocator = std.testing.allocator;
    const original = ServerHello{
        .client_id = 1,
        .server_pid = 100,
        .coalescing_config = .{
            .active_interval_ms = 16,
            .bulk_interval_ms = 33,
        },
    };
    const json = try json_mod.encode(allocator, original);
    defer allocator.free(json);
    const parsed = try json_mod.decode(ServerHello, allocator, json);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.coalescing_config != null);
    try std.testing.expectEqual(@as(u32, 16), parsed.value.coalescing_config.?.active_interval_ms);
}

test "Heartbeat JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = Heartbeat{ .ping_id = 42 };
    const json = try json_mod.encode(allocator, original);
    defer allocator.free(json);
    const parsed = try json_mod.decode(Heartbeat, allocator, json);
    defer parsed.deinit();
    try std.testing.expectEqual(original.ping_id, parsed.value.ping_id);
}

test "HeartbeatAck JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = HeartbeatAck{ .ping_id = 7 };
    const json = try json_mod.encode(allocator, original);
    defer allocator.free(json);
    const parsed = try json_mod.decode(HeartbeatAck, allocator, json);
    defer parsed.deinit();
    try std.testing.expectEqual(original.ping_id, parsed.value.ping_id);
}

test "Disconnect JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = Disconnect{ .reason = "shutdown", .detail = "user request" };
    const json = try json_mod.encode(allocator, original);
    defer allocator.free(json);
    const parsed = try json_mod.decode(Disconnect, allocator, json);
    defer parsed.deinit();
    try std.testing.expectEqualStrings(original.reason, parsed.value.reason);
    try std.testing.expectEqualStrings(original.detail, parsed.value.detail);
}
