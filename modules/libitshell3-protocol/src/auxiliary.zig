const std = @import("std");
const json_mod = @import("json.zig");

// ---- Flow Control (0x0500-0x05FF) ----

/// ClientDisplayInfo (0x0505, C->S)
pub const ClientDisplayInfo = struct {
    display_refresh_hz: u32 = 60,
    power_state: []const u8 = "ac",
    preferred_max_fps: u32 = 0,
    transport_type: []const u8 = "local",
    estimated_rtt_ms: u16 = 0,
    bandwidth_hint: []const u8 = "local",
};

/// ClientDisplayInfoAck (0x0506, S->C)
pub const ClientDisplayInfoAck = struct {
    status: u32 = 0,
    effective_max_fps: u32 = 60,
};

/// PausePane (0x0500, S->C)
pub const PausePane = struct {
    pane_id: u32,
    ring_lag_percent: u32 = 0,
    ring_lag_bytes: u64 = 0,
};

/// ContinuePane (0x0501, C->S)
pub const ContinuePane = struct {
    pane_id: u32,
};

/// FlowControlConfig (0x0502, C->S)
pub const FlowControlConfig = struct {
    max_queue_age_ms: u32 = 5000,
    auto_continue: bool = true,
    resize_exclusion_timeout_ms: u32 = 5000,
    stale_timeout_ms: u32 = 60000,
    eviction_timeout_ms: u32 = 300000,
};

/// FlowControlConfigAck (0x0503, S->C)
pub const FlowControlConfigAck = struct {
    status: u32 = 0,
    effective_max_age_ms: u32 = 5000,
    effective_resize_exclusion_ms: u32 = 5000,
    effective_stale_ms: u32 = 60000,
    effective_eviction_ms: u32 = 300000,
};

/// Per-pane queue status entry
pub const PaneQueueStatus = struct {
    pane_id: u32,
    ring_lag_bytes: u64 = 0,
    ring_lag_percent: u32 = 0,
    paused: bool = false,
};

/// OutputQueueStatus (0x0504, S->C)
pub const OutputQueueStatus = struct {
    panes: []const PaneQueueStatus = &.{},
};

// ---- Clipboard (0x0600-0x06FF) ----

/// ClipboardWrite (0x0600, S->C)
pub const ClipboardWrite = struct {
    pane_id: u32,
    clipboard_type: []const u8 = "system",
    data: []const u8,
    encoding: []const u8 = "utf8",
};

/// ClipboardRead (0x0601, C->S)
pub const ClipboardRead = struct {
    pane_id: u32,
    clipboard_type: []const u8 = "system",
};

/// ClipboardReadResponse (0x0602, S->C)
pub const ClipboardReadResponse = struct {
    pane_id: u32,
    clipboard_type: []const u8 = "system",
    status: u32 = 0,
    data: []const u8 = "",
};

/// ClipboardChanged (0x0603, S->C)
pub const ClipboardChanged = struct {
    clipboard_type: []const u8 = "system",
    data: []const u8 = "",
};

/// ClipboardWriteFromClient (0x0604, C->S)
pub const ClipboardWriteFromClient = struct {
    clipboard_type: []const u8 = "system",
    data: []const u8,
};

// ---- Persistence (0x0700-0x07FF) ----

/// SnapshotRequest (0x0700, C->S)
pub const SnapshotRequest = struct {
    session_id: u32 = 0,
    include_scrollback: bool = true,
    max_scrollback_lines: u32 = 4000,
};

/// SnapshotResponse (0x0701, S->C)
pub const SnapshotResponse = struct {
    status: u32 = 0,
    path: []const u8 = "",
    snapshot_size: u64 = 0,
    timestamp: u64 = 0,
    @"error": ?[]const u8 = null,
};

/// RestoreSessionRequest (0x0702, C->S)
pub const RestoreSessionRequest = struct {
    path: []const u8 = "",
    snapshot_session_name: []const u8 = "",
    restore_scrollback: bool = true,
};

/// RestoreSessionResponse (0x0703, S->C)
pub const RestoreSessionResponse = struct {
    status: u32 = 0,
    session_id: u32 = 0,
    pane_count: u32 = 0,
    @"error": ?[]const u8 = null,
};

/// SnapshotListRequest (0x0704, C->S)
pub const SnapshotListRequest = struct {};

/// Snapshot info entry
pub const SnapshotInfo = struct {
    path: []const u8,
    name: []const u8 = "",
    timestamp: u64 = 0,
    file_size: u64 = 0,
    has_scrollback: bool = false,
};

/// SnapshotListResponse (0x0705, S->C)
pub const SnapshotListResponse = struct {
    status: u32 = 0,
    snapshots: []const SnapshotInfo = &.{},
};

/// SnapshotAutoSaveConfig (0x0706, C->S)
pub const SnapshotAutoSaveConfig = struct {
    interval_ms: u32 = 8000,
    include_scrollback: bool = true,
    max_scrollback_lines: u32 = 4000,
};

/// SnapshotAutoSaveConfigAck (0x0707, S->C)
pub const SnapshotAutoSaveConfigAck = struct {
    status: u32 = 0,
    effective_interval_ms: u32 = 8000,
};

// ---- Opt-in Notifications (0x0800-0x08FF) ----

/// PaneTitleChanged (0x0800, S->C)
pub const PaneTitleChanged = struct {
    pane_id: u32,
    title: []const u8,
};

/// ProcessExited (0x0801, S->C)
pub const ProcessExited = struct {
    pane_id: u32,
    exit_code: i32 = 0,
    process_name: []const u8 = "",
};

/// Bell (0x0802, S->C)
pub const Bell = struct {
    pane_id: u32,
    timestamp: u64 = 0,
};

/// RendererHealth (0x0803, S->C)
pub const RendererHealth = struct {
    pane_id: u32,
    frames_processed: u64 = 0,
    frames_dropped: u64 = 0,
    avg_frame_time_us: u32 = 0,
    pty_bytes_read: u64 = 0,
    ring_usage_bytes: u64 = 0,
    ring_usage_percent: u32 = 0,
    coalescing_tier: []const u8 = "idle",
};

/// PaneCwdChanged (0x0804, S->C)
pub const PaneCwdChanged = struct {
    pane_id: u32,
    cwd: []const u8,
};

/// ActivityDetected (0x0805, S->C)
pub const ActivityDetected = struct {
    pane_id: u32,
    timestamp: u64 = 0,
};

/// SilenceDetected (0x0806, S->C)
pub const SilenceDetected = struct {
    pane_id: u32,
    silence_duration_ms: u32 = 0,
};

// ---- Subscriptions (0x0810-0x081F) ----

/// Subscription config
pub const SubscriptionConfig = struct {
    renderer_health_interval_ms: ?u32 = null,
    silence_threshold_ms: ?u32 = null,
    queue_status_interval_ms: ?u32 = null,
};

/// Subscribe (0x0810, C->S)
pub const Subscribe = struct {
    pane_id: u32 = 0,
    event_mask: u32 = 0,
    config: ?SubscriptionConfig = null,
};

/// SubscribeAck (0x0811, S->C)
pub const SubscribeAck = struct {
    status: u32 = 0,
    active_mask: u32 = 0,
};

/// Unsubscribe (0x0812, C->S)
pub const Unsubscribe = struct {
    pane_id: u32 = 0,
    event_mask: u32 = 0,
};

/// UnsubscribeAck (0x0813, S->C)
pub const UnsubscribeAck = struct {
    status: u32 = 0,
    active_mask: u32 = 0,
};

/// Event mask bit constants
pub const EventMask = struct {
    pub const pane_title_changed: u32 = 0x0001;
    pub const process_exited: u32 = 0x0002;
    pub const bell: u32 = 0x0004;
    pub const renderer_health: u32 = 0x0008;
    pub const pane_cwd_changed: u32 = 0x0010;
    pub const activity_detected: u32 = 0x0020;
    pub const silence_detected: u32 = 0x0040;
    pub const clipboard_changed: u32 = 0x0080;
    pub const output_queue_status: u32 = 0x0100;
};

// ---- Extensions (0x0A00-0x0AFF) ----

/// Extension declaration entry
pub const ExtensionEntry = struct {
    ext_id: u32,
    version: []const u8 = "1.0",
    name: []const u8 = "",
    config: ?std.json.Value = null,
};

/// ExtensionList (0x0A00, bidirectional)
pub const ExtensionList = struct {
    extensions: []const ExtensionEntry = &.{},
};

/// Extension result entry
pub const ExtensionResult = struct {
    ext_id: u32,
    status: u32 = 0,
    accepted_version: []const u8 = "",
};

/// ExtensionListAck (0x0A01, bidirectional)
pub const ExtensionListAck = struct {
    results: []const ExtensionResult = &.{},
};

/// ExtensionMessage (0x0A02, bidirectional)
pub const ExtensionMessage = struct {
    ext_id: u32,
    ext_msg_type: u32,
    payload: ?std.json.Value = null,
};

// --- Tests ---

test "ClientDisplayInfo: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = ClientDisplayInfo{
        .display_refresh_hz = 120,
        .power_state = "battery",
        .transport_type = "ssh_tunnel",
        .estimated_rtt_ms = 50,
        .bandwidth_hint = "wan",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(ClientDisplayInfo, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 120), parsed.value.display_refresh_hz);
    try std.testing.expectEqualStrings("battery", parsed.value.power_state);
    try std.testing.expectEqualStrings("ssh_tunnel", parsed.value.transport_type);
}

test "FlowControlConfig: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = FlowControlConfig{
        .max_queue_age_ms = 10000,
        .auto_continue = false,
        .stale_timeout_ms = 120000,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(FlowControlConfig, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 10000), parsed.value.max_queue_age_ms);
    try std.testing.expect(!parsed.value.auto_continue);
}

test "ClipboardWrite: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = ClipboardWrite{
        .pane_id = 1,
        .clipboard_type = "selection",
        .data = "copied text",
        .encoding = "utf8",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(ClipboardWrite, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("copied text", parsed.value.data);
    try std.testing.expectEqualStrings("selection", parsed.value.clipboard_type);
}

test "Subscribe: JSON round-trip with config" {
    const allocator = std.testing.allocator;
    const original = Subscribe{
        .pane_id = 0,
        .event_mask = EventMask.bell | EventMask.process_exited | EventMask.silence_detected,
        .config = .{ .silence_threshold_ms = 15000 },
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(Subscribe, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(EventMask.bell | EventMask.process_exited | EventMask.silence_detected, parsed.value.event_mask);
    try std.testing.expect(parsed.value.config != null);
    try std.testing.expectEqual(@as(?u32, 15000), parsed.value.config.?.silence_threshold_ms);
}

test "SnapshotRequest: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = SnapshotRequest{ .session_id = 1, .include_scrollback = false };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(SnapshotRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.session_id);
    try std.testing.expect(!parsed.value.include_scrollback);
}

test "ProcessExited: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = ProcessExited{ .pane_id = 1, .exit_code = -9, .process_name = "make" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(ProcessExited, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, -9), parsed.value.exit_code);
    try std.testing.expectEqualStrings("make", parsed.value.process_name);
}

test "EventMask: constants" {
    try std.testing.expectEqual(@as(u32, 0x0001), EventMask.pane_title_changed);
    try std.testing.expectEqual(@as(u32, 0x0100), EventMask.output_queue_status);
    const all = EventMask.pane_title_changed | EventMask.process_exited | EventMask.bell |
        EventMask.renderer_health | EventMask.pane_cwd_changed | EventMask.activity_detected |
        EventMask.silence_detected | EventMask.clipboard_changed | EventMask.output_queue_status;
    try std.testing.expectEqual(@as(u32, 0x01FF), all);
}

test "RendererHealth: JSON round-trip" {
    const allocator = std.testing.allocator;
    const original = RendererHealth{
        .pane_id = 1,
        .frames_processed = 180,
        .frames_dropped = 2,
        .avg_frame_time_us = 450,
        .ring_usage_percent = 25,
        .coalescing_tier = "active",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(RendererHealth, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("active", parsed.value.coalescing_tier);
    try std.testing.expectEqual(@as(u64, 180), parsed.value.frames_processed);
}
