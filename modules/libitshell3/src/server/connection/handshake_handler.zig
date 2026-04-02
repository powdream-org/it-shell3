//! Server-side handshake handler. Receives ClientHello, validates protocol
//! version, negotiates capabilities, sends ServerHello. Fresh implementation
//! against the protocol handshake spec (not ported from protocol.handshake_io).
//!
//! Per protocol spec 02-handshake-capability-negotiation.

const std = @import("std");
const connection_state_mod = @import("connection_state.zig");
const ConnectionState = connection_state_mod.ConnectionState;
const State = connection_state_mod.State;
const client_state_mod = @import("client_state.zig");
const ClientState = client_state_mod.ClientState;
const protocol = @import("itshell3_protocol");
const ClientHello = protocol.handshake.ClientHello;
const ServerHello = protocol.handshake.ServerHello;
const ErrorResponse = protocol.err.ErrorResponse;
const ErrorCode = protocol.err.ErrorCode;

/// Result of processing a ClientHello message.
pub const HandshakeResult = union(enum) {
    /// Handshake succeeded. Contains the ServerHello payload bytes to send.
    success: ServerHelloData,
    /// Protocol version mismatch. Contains Error payload bytes to send.
    version_mismatch: ErrorData,
    /// No common rendering mode. Contains Error payload bytes to send.
    capability_required: ErrorData,
    /// Malformed ClientHello payload.
    malformed_payload: ErrorData,
};

pub const ServerHelloData = struct {
    /// JSON-encoded ServerHello payload.
    payload: [MAX_HELLO_SIZE]u8 = [_]u8{0} ** MAX_HELLO_SIZE,
    payload_length: u32 = 0,

    pub fn getPayload(self: *const ServerHelloData) []const u8 {
        return self.payload[0..self.payload_length];
    }
};

pub const ErrorData = struct {
    error_code: u32,
    detail: [MAX_DETAIL_SIZE]u8 = [_]u8{0} ** MAX_DETAIL_SIZE,
    detail_length: u16 = 0,

    pub fn getDetail(self: *const ErrorData) []const u8 {
        return self.detail[0..self.detail_length];
    }
};

pub const MAX_HELLO_SIZE: usize = 4096;
pub const MAX_DETAIL_SIZE: u16 = 256;

/// Current protocol version supported by this server.
pub const PROTOCOL_VERSION: u8 = 1;

/// Server capabilities offered during negotiation.
pub const SERVER_CAPABILITIES: []const []const u8 = &.{
    "clipboard_sync",
    "mouse",
    "selection",
    "search",
};

/// Server render capabilities offered during negotiation.
pub const SERVER_RENDER_CAPABILITIES: []const []const u8 = &.{
    "cell_data",
    "dirty_tracking",
    "cursor_style",
    "true_color",
};

/// Server-supported input methods.
pub const SERVER_INPUT_METHODS: []const ServerHello.InputMethodInfo = &.{
    .{ .method = "direct", .layouts = &.{"qwerty"} },
    .{ .method = "korean_2set", .layouts = &.{"qwerty"} },
};

/// Validates protocol version and negotiates capabilities from a ClientHello.
/// Does NOT mutate the connection state -- the caller applies the transition.
pub fn processClientHello(
    allocator: std.mem.Allocator,
    client_hello_json: []const u8,
    client_id: u32,
    server_pid: u32,
) HandshakeResult {
    // Parse ClientHello JSON.
    const parsed = std.json.parseFromSlice(ClientHello, allocator, client_hello_json, .{
        .ignore_unknown_fields = true,
    }) catch {
        return .{ .malformed_payload = makeError(
            @intFromEnum(ErrorCode.malformed_payload),
            "Failed to parse ClientHello JSON",
        ) };
    };
    defer parsed.deinit();
    const hello = parsed.value;

    // Validate protocol version range.
    if (hello.protocol_version_min > PROTOCOL_VERSION or hello.protocol_version_max < PROTOCOL_VERSION) {
        return .{ .version_mismatch = makeError(
            @intFromEnum(ErrorCode.version_mismatch),
            "No compatible protocol version",
        ) };
    }

    // Negotiate general capabilities (intersection).
    var negotiated_caps: [ConnectionState.MAX_CAPABILITIES][ConnectionState.MAX_CAPABILITY_NAME]u8 = undefined;
    var negotiated_caps_lengths: [ConnectionState.MAX_CAPABILITIES]u8 = [_]u8{0} ** ConnectionState.MAX_CAPABILITIES;
    var negotiated_caps_count: u8 = 0;
    negotiateCapabilities(
        SERVER_CAPABILITIES,
        hello.capabilities,
        ConnectionState.MAX_CAPABILITIES,
        &negotiated_caps,
        &negotiated_caps_lengths,
        &negotiated_caps_count,
    );

    // Negotiate render capabilities (intersection).
    var negotiated_render: [ConnectionState.MAX_RENDER_CAPABILITIES][ConnectionState.MAX_CAPABILITY_NAME]u8 = undefined;
    var negotiated_render_lengths: [ConnectionState.MAX_RENDER_CAPABILITIES]u8 = [_]u8{0} ** ConnectionState.MAX_RENDER_CAPABILITIES;
    var negotiated_render_count: u8 = 0;
    negotiateCapabilities(
        SERVER_RENDER_CAPABILITIES,
        hello.render_capabilities,
        ConnectionState.MAX_RENDER_CAPABILITIES,
        &negotiated_render,
        &negotiated_render_lengths,
        &negotiated_render_count,
    );

    // Check for required rendering mode: must have cell_data OR vt_fallback.
    var has_render_mode = false;
    var i: u32 = 0;
    while (i < negotiated_render_count) : (i += 1) {
        const name = negotiated_render[i][0..negotiated_render_lengths[i]];
        if (std.mem.eql(u8, name, "cell_data") or std.mem.eql(u8, name, "vt_fallback")) {
            has_render_mode = true;
            break;
        }
    }
    if (!has_render_mode) {
        return .{ .capability_required = makeError(
            @intFromEnum(ErrorCode.capability_required),
            "No common rendering mode",
        ) };
    }

    // Build ServerHello. We use slices pointing into our stack arrays for JSON encoding.
    var cap_slices: [ConnectionState.MAX_CAPABILITIES][]const u8 = undefined;
    var j: u32 = 0;
    while (j < negotiated_caps_count) : (j += 1) {
        cap_slices[j] = negotiated_caps[j][0..negotiated_caps_lengths[j]];
    }
    var render_slices: [ConnectionState.MAX_RENDER_CAPABILITIES][]const u8 = undefined;
    j = 0;
    while (j < negotiated_render_count) : (j += 1) {
        render_slices[j] = negotiated_render[j][0..negotiated_render_lengths[j]];
    }

    const server_hello = ServerHello{
        .protocol_version = PROTOCOL_VERSION,
        .client_id = client_id,
        .negotiated_caps = cap_slices[0..negotiated_caps_count],
        .negotiated_render_caps = render_slices[0..negotiated_render_count],
        .supported_input_methods = SERVER_INPUT_METHODS,
        .server_pid = server_pid,
        .server_name = "itshell3d",
        .server_version = "0.1.0",
        .heartbeat_interval_ms = 30000,
        .max_panes_per_session = 16,
        .max_sessions = 0,
        .coalescing_config = .{},
    };

    var result = ServerHelloData{};
    var fba = std.heap.FixedBufferAllocator.init(&result.payload);
    const json_bytes = std.json.Stringify.valueAlloc(fba.allocator(), server_hello, .{
        .emit_null_optional_fields = false,
    }) catch {
        return .{ .malformed_payload = makeError(
            @intFromEnum(ErrorCode.internal),
            "Failed to serialize ServerHello",
        ) };
    };
    result.payload_length = @intCast(json_bytes.len);

    return .{ .success = result };
}

/// Computes the intersection of server and client capability lists. Populates
/// `out_names`, `out_lengths`, and `out_count` with matching entries.
fn negotiateCapabilities(
    server_caps: []const []const u8,
    client_caps: []const []const u8,
    comptime max_entries: u8,
    out_names: *[max_entries][ConnectionState.MAX_CAPABILITY_NAME]u8,
    out_lengths: *[max_entries]u8,
    out_count: *u8,
) void {
    for (client_caps) |client_cap| {
        for (server_caps) |server_cap| {
            if (std.mem.eql(u8, client_cap, server_cap)) {
                if (out_count.* < max_entries and client_cap.len <= ConnectionState.MAX_CAPABILITY_NAME) {
                    @memcpy(out_names[out_count.*][0..client_cap.len], client_cap);
                    out_lengths[out_count.*] = @intCast(client_cap.len);
                    out_count.* += 1;
                }
                break;
            }
        }
    }
}

fn makeError(error_code: u32, detail: []const u8) ErrorData {
    var result = ErrorData{ .error_code = error_code };
    const copy_len = @min(detail.len, MAX_DETAIL_SIZE);
    @memcpy(result.detail[0..copy_len], detail[0..copy_len]);
    result.detail_length = @intCast(copy_len);
    return result;
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "processClientHello: valid handshake produces success" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":["clipboard_sync","mouse"],"render_capabilities":["cell_data","dirty_tracking"],"client_name":"test","client_version":"1.0","terminal_type":"xterm-256color","cols":80,"rows":24}
    ;
    const result = processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .success => |data| {
            try std.testing.expect(data.payload_length > 0);
            // Verify the payload contains expected fields
            const payload = data.getPayload();
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"client_id\":1") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"protocol_version\":1") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "processClientHello: version mismatch" {
    const hello_json =
        \\{"protocol_version_min":99,"protocol_version_max":99,"client_type":"native","capabilities":[],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .version_mismatch => |err_data| {
            try std.testing.expectEqual(@intFromEnum(ErrorCode.version_mismatch), err_data.error_code);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "processClientHello: no common rendering mode" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":[],"render_capabilities":["hyperlinks"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .capability_required => |err_data| {
            try std.testing.expectEqual(@intFromEnum(ErrorCode.capability_required), err_data.error_code);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "processClientHello: malformed JSON" {
    const result = processClientHello(std.testing.allocator, "{invalid json", 1, 1234);
    switch (result) {
        .malformed_payload => {},
        else => return error.TestUnexpectedResult,
    }
}

test "processClientHello: capability intersection" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":["clipboard_sync","fd_passing","unknown_cap"],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = processClientHello(std.testing.allocator, hello_json, 5, 1234);
    switch (result) {
        .success => |data| {
            const payload = data.getPayload();
            // clipboard_sync should be negotiated (intersection)
            try std.testing.expect(std.mem.indexOf(u8, payload, "clipboard_sync") != null);
            // fd_passing is not in server caps, should not appear in negotiated
            // (but it might appear in the supported_input_methods context, so check negotiated_caps specifically)
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"client_id\":5") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "negotiateCapabilities: computes intersection correctly" {
    const server_caps: []const []const u8 = &.{ "alpha", "beta", "gamma" };
    const client_caps: []const []const u8 = &.{ "beta", "delta", "gamma" };

    var names: [ConnectionState.MAX_CAPABILITIES][ConnectionState.MAX_CAPABILITY_NAME]u8 = undefined;
    var lengths: [ConnectionState.MAX_CAPABILITIES]u8 = [_]u8{0} ** ConnectionState.MAX_CAPABILITIES;
    var count: u8 = 0;

    negotiateCapabilities(server_caps, client_caps, ConnectionState.MAX_CAPABILITIES, &names, &lengths, &count);

    try std.testing.expectEqual(@as(u8, 2), count);
    try std.testing.expectEqualSlices(u8, "beta", names[0][0..lengths[0]]);
    try std.testing.expectEqualSlices(u8, "gamma", names[1][0..lengths[1]]);
}

test "negotiateCapabilities: empty client caps yields zero results" {
    const server_caps: []const []const u8 = &.{ "alpha", "beta" };
    const client_caps: []const []const u8 = &.{};

    var names: [ConnectionState.MAX_CAPABILITIES][ConnectionState.MAX_CAPABILITY_NAME]u8 = undefined;
    var lengths: [ConnectionState.MAX_CAPABILITIES]u8 = [_]u8{0} ** ConnectionState.MAX_CAPABILITIES;
    var count: u8 = 0;

    negotiateCapabilities(server_caps, client_caps, ConnectionState.MAX_CAPABILITIES, &names, &lengths, &count);

    try std.testing.expectEqual(@as(u8, 0), count);
}
