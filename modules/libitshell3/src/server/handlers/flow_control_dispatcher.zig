//! Dispatcher for flow control and auxiliary messages (0x05xx range).
//! Handles ClientDisplayInfo (0x0505) in Plan 8; remaining flow control
//! messages (PausePane, ContinuePane, etc.) deferred to Plan 9.
//!
//! Per protocol 06-flow-control-and-auxiliary.

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const message_dispatcher = @import("message_dispatcher.zig");
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;
const handler_utils = @import("handler_utils.zig");
const envelope = @import("protocol_envelope.zig");
const server = @import("itshell3_server");
const ClientState = server.connection.client_state.ClientState;
const ClientDisplayInfo = ClientState.ClientDisplayInfo;

/// Dispatches a flow-control-category message.
pub fn dispatch(params: CategoryDispatchParams) void {
    switch (params.msg_type) {
        .client_display_info => handleClientDisplayInfo(params),
        else => {
            // TODO(Plan 9): Implement flow control handlers (PausePane,
            // ContinuePane, FlowControlConfig, etc.).
        },
    }
}

/// Handles ClientDisplayInfo (0x0505, C->S).
/// Parses display, power, and transport fields, populates client state,
/// and sends ClientDisplayInfoAck (0x0506).
fn handleClientDisplayInfo(params: CategoryDispatchParams) void {
    const client = params.client;
    const payload = params.payload;
    const sequence = params.header.sequence;

    applyDisplayInfo(&client.display_info, payload);

    // Send ClientDisplayInfoAck (0x0506).
    const effective_max_fps = computeEffectiveMaxFps(&client.display_info);

    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    var json_buffer: [128]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buffer, "{{\"status\":0,\"effective_max_fps\":{d}}}", .{
        effective_max_fps,
    }) catch return;
    const response = envelope.wrapResponse(
        &response_buffer,
        @intFromEnum(MessageType.client_display_info_ack),
        sequence,
        json,
    ) orelse return;
    client.enqueueDirect(response) catch {};

    client.recordActivity();
}

/// Core logic: parse display info fields from JSON payload and apply to
/// client display info struct. Extracted for unit testability.
fn applyDisplayInfo(display_info: *ClientDisplayInfo, payload: []const u8) void {
    if (handler_utils.extractU16Field(payload, "\"display_refresh_hz\":")) |refresh_hz| {
        display_info.display_refresh_hz = refresh_hz;
    }
    if (handler_utils.extractStringField(payload, "\"power_state\":\"")) |power_state| {
        display_info.power_state = parsePowerState(power_state);
    }
    if (handler_utils.extractU16Field(payload, "\"preferred_max_fps\":")) |preferred_max_fps| {
        display_info.preferred_max_fps = preferred_max_fps;
    }
    if (handler_utils.extractStringField(payload, "\"transport_type\":\"")) |transport_type| {
        display_info.transport_type = parseTransportType(transport_type);
    }
    if (handler_utils.extractU16Field(payload, "\"estimated_rtt_ms\":")) |estimated_rtt_ms| {
        display_info.estimated_rtt_ms = estimated_rtt_ms;
    }
    if (handler_utils.extractStringField(payload, "\"bandwidth_hint\":\"")) |bandwidth_hint| {
        display_info.bandwidth_hint = parseBandwidthHint(bandwidth_hint);
    }
}

/// Computes effective max FPS from client display info.
/// Returns preferred_max_fps if nonzero, otherwise display_refresh_hz.
/// Extracted for unit testability.
fn computeEffectiveMaxFps(display_info: *const ClientDisplayInfo) u16 {
    return if (display_info.preferred_max_fps > 0)
        display_info.preferred_max_fps
    else
        display_info.display_refresh_hz;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn parsePowerState(value: []const u8) ClientDisplayInfo.PowerState {
    if (std.mem.eql(u8, value, "battery")) return .battery;
    if (std.mem.eql(u8, value, "low_battery")) return .low_battery;
    return .ac;
}

fn parseTransportType(value: []const u8) ClientDisplayInfo.TransportType {
    if (std.mem.eql(u8, value, "ssh_tunnel")) return .ssh_tunnel;
    if (std.mem.eql(u8, value, "unknown")) return .unknown;
    return .local;
}

fn parseBandwidthHint(value: []const u8) ClientDisplayInfo.BandwidthHint {
    if (std.mem.eql(u8, value, "lan")) return .lan;
    if (std.mem.eql(u8, value, "wan")) return .wan;
    if (std.mem.eql(u8, value, "cellular")) return .cellular;
    return .local;
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "parsePowerState: maps string to enum" {
    try std.testing.expectEqual(ClientDisplayInfo.PowerState.ac, parsePowerState("ac"));
    try std.testing.expectEqual(ClientDisplayInfo.PowerState.battery, parsePowerState("battery"));
    try std.testing.expectEqual(ClientDisplayInfo.PowerState.low_battery, parsePowerState("low_battery"));
    try std.testing.expectEqual(ClientDisplayInfo.PowerState.ac, parsePowerState("unknown_value"));
}

test "parseTransportType: maps string to enum" {
    try std.testing.expectEqual(ClientDisplayInfo.TransportType.local, parseTransportType("local"));
    try std.testing.expectEqual(ClientDisplayInfo.TransportType.ssh_tunnel, parseTransportType("ssh_tunnel"));
    try std.testing.expectEqual(ClientDisplayInfo.TransportType.unknown, parseTransportType("unknown"));
}

test "parseBandwidthHint: maps string to enum" {
    try std.testing.expectEqual(ClientDisplayInfo.BandwidthHint.local, parseBandwidthHint("local"));
    try std.testing.expectEqual(ClientDisplayInfo.BandwidthHint.lan, parseBandwidthHint("lan"));
    try std.testing.expectEqual(ClientDisplayInfo.BandwidthHint.wan, parseBandwidthHint("wan"));
    try std.testing.expectEqual(ClientDisplayInfo.BandwidthHint.cellular, parseBandwidthHint("cellular"));
}

// ── Core Function Tests ─────────────────────────────────────────────────────

test "applyDisplayInfo: parses all fields from JSON payload" {
    var info = ClientDisplayInfo{};
    const payload = "{\"display_refresh_hz\":120,\"power_state\":\"battery\",\"preferred_max_fps\":30,\"transport_type\":\"ssh_tunnel\",\"estimated_rtt_ms\":50,\"bandwidth_hint\":\"wan\"}";

    applyDisplayInfo(&info, payload);

    try std.testing.expectEqual(@as(u16, 120), info.display_refresh_hz);
    try std.testing.expectEqual(ClientDisplayInfo.PowerState.battery, info.power_state);
    try std.testing.expectEqual(@as(u16, 30), info.preferred_max_fps);
    try std.testing.expectEqual(ClientDisplayInfo.TransportType.ssh_tunnel, info.transport_type);
    try std.testing.expectEqual(@as(u16, 50), info.estimated_rtt_ms);
    try std.testing.expectEqual(ClientDisplayInfo.BandwidthHint.wan, info.bandwidth_hint);
}

test "applyDisplayInfo: partial payload only updates present fields" {
    var info = ClientDisplayInfo{};
    const payload = "{\"display_refresh_hz\":144}";

    applyDisplayInfo(&info, payload);

    try std.testing.expectEqual(@as(u16, 144), info.display_refresh_hz);
    // Defaults should remain.
    try std.testing.expectEqual(ClientDisplayInfo.PowerState.ac, info.power_state);
    try std.testing.expectEqual(@as(u16, 0), info.preferred_max_fps);
    try std.testing.expectEqual(ClientDisplayInfo.TransportType.local, info.transport_type);
}

test "applyDisplayInfo: empty payload leaves defaults" {
    var info = ClientDisplayInfo{};

    applyDisplayInfo(&info, "{}");

    try std.testing.expectEqual(@as(u16, 60), info.display_refresh_hz);
    try std.testing.expectEqual(ClientDisplayInfo.PowerState.ac, info.power_state);
}

test "computeEffectiveMaxFps: uses preferred when nonzero" {
    const info = ClientDisplayInfo{
        .display_refresh_hz = 60,
        .preferred_max_fps = 30,
    };
    try std.testing.expectEqual(@as(u16, 30), computeEffectiveMaxFps(&info));
}

test "computeEffectiveMaxFps: falls back to display_refresh_hz when preferred is zero" {
    const info = ClientDisplayInfo{
        .display_refresh_hz = 120,
        .preferred_max_fps = 0,
    };
    try std.testing.expectEqual(@as(u16, 120), computeEffectiveMaxFps(&info));
}
