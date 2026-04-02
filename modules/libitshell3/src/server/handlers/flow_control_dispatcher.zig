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

    if (handler_utils.extractU16Field(payload, "\"display_refresh_hz\":")) |hz| {
        client.display_info.display_refresh_hz = hz;
    }
    if (handler_utils.extractStringField(payload, "\"power_state\":\"")) |ps| {
        client.display_info.power_state = parsePowerState(ps);
    }
    if (handler_utils.extractU16Field(payload, "\"preferred_max_fps\":")) |fps| {
        client.display_info.preferred_max_fps = fps;
    }
    if (handler_utils.extractStringField(payload, "\"transport_type\":\"")) |tt| {
        client.display_info.transport_type = parseTransportType(tt);
    }
    if (handler_utils.extractU16Field(payload, "\"estimated_rtt_ms\":")) |rtt| {
        client.display_info.estimated_rtt_ms = rtt;
    }
    if (handler_utils.extractStringField(payload, "\"bandwidth_hint\":\"")) |bw| {
        client.display_info.bandwidth_hint = parseBandwidthHint(bw);
    }

    // Send ClientDisplayInfoAck (0x0506).
    const effective_max_fps: u16 = if (client.display_info.preferred_max_fps > 0)
        client.display_info.preferred_max_fps
    else
        client.display_info.display_refresh_hz;

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
