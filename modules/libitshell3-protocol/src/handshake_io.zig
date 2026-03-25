const std = @import("std");
const header_mod = @import("header.zig");
const json_mod = @import("json.zig");
const handshake_mod = @import("handshake.zig");
const connection_mod = @import("connection.zig");
const reader_mod = @import("reader.zig");
const writer_mod = @import("writer.zig");
const message_type_mod = @import("message_type.zig");
const auth_mod = @import("auth.zig");
const transport_mod = @import("transport.zig");

pub const HandshakeError = error{
    VersionMismatch,
    AuthFailed,
    MalformedPayload,
    UnexpectedMessage,
    InvalidTransition,
    InvalidState,
} || auth_mod.AuthError;

pub const ServerConfig = struct {
    protocol_version: u32 = 1,
    next_client_id: u32,
    server_pid: u32 = 0,
    server_name: []const u8 = "itshell3d",
    server_version: []const u8 = "0.1.0",
    supported_caps: []const []const u8 = &.{},
    supported_input_methods: []const handshake_mod.ServerHello.InputMethodInfo = &.{},
};

pub const ServerHandshakeResult = struct {
    client_id: u32,
    negotiated_caps: connection_mod.NegotiatedCaps,
};

pub const ClientHandshakeResult = struct {
    client_id: u32,
    negotiated_caps: connection_mod.NegotiatedCaps,
};

/// Server side: read ClientHello, verify UID, negotiate caps, send ServerHello.
/// Transitions connection from handshaking -> ready.
pub fn performServerHandshake(
    conn: *connection_mod.Connection,
    allocator: std.mem.Allocator,
    server_config: ServerConfig,
    payload_buf: []u8,
) (HandshakeError || reader_mod.ReadError || error{ EndOfStream, Overflow })!ServerHandshakeResult {
    // 1. Read ClientHello via transport vtable
    var hdr_buf: [header_mod.HEADER_SIZE]u8 = undefined;
    var hdr_read: usize = 0;
    while (hdr_read < header_mod.HEADER_SIZE) {
        const n = conn.transport.read(hdr_buf[hdr_read..]) catch return error.EndOfStream;
        if (n == 0) return error.EndOfStream;
        hdr_read += n;
    }
    const hdr = header_mod.Header.decode(&hdr_buf) catch return error.MalformedPayload;

    if (hdr.msg_type != @intFromEnum(message_type_mod.MessageType.client_hello))
        return error.UnexpectedMessage;

    if (hdr.payload_len > payload_buf.len) return error.Overflow;
    var payload_read: usize = 0;
    while (payload_read < hdr.payload_len) {
        const n = conn.transport.read(payload_buf[payload_read..hdr.payload_len]) catch return error.EndOfStream;
        if (n == 0) return error.EndOfStream;
        payload_read += n;
    }
    const payload = payload_buf[0..hdr.payload_len];

    const parsed = json_mod.decode(handshake_mod.ClientHello, allocator, payload)
        catch return error.MalformedPayload;
    defer parsed.deinit();
    const client_hello = parsed.value;

    // 2. Negotiate version
    if (server_config.protocol_version < client_hello.protocol_version_min or
        server_config.protocol_version > client_hello.protocol_version_max)
        return error.VersionMismatch;

    // 3. Negotiate capabilities (intersection)
    const caps = negotiateCapabilities(client_hello.capabilities, server_config.supported_caps);

    // 4. Send ServerHello
    const server_hello = handshake_mod.ServerHello{
        .protocol_version = server_config.protocol_version,
        .server_name = server_config.server_name,
        .server_version = server_config.server_version,
        .server_pid = server_config.server_pid,
        .client_id = server_config.next_client_id,
        .negotiated_caps = server_config.supported_caps,
        .supported_input_methods = server_config.supported_input_methods,
    };

    const json_payload = json_mod.encode(allocator, server_hello) catch return error.MalformedPayload;
    defer allocator.free(json_payload);

    const resp_hdr = header_mod.Header{
        .msg_type = @intFromEnum(message_type_mod.MessageType.server_hello),
        .flags = .{ .response = true },
        .payload_len = @intCast(json_payload.len),
        .sequence = hdr.sequence,
    };
    var resp_buf: [header_mod.HEADER_SIZE]u8 = undefined;
    resp_hdr.encode(&resp_buf);
    conn.transport.write(&resp_buf) catch return error.EndOfStream;
    conn.transport.write(json_payload) catch return error.EndOfStream;

    // 5. Transition state
    try conn.completeHandshake(server_config.next_client_id, caps);

    return .{
        .client_id = server_config.next_client_id,
        .negotiated_caps = caps,
    };
}

/// Client side: send ClientHello, read ServerHello, negotiate.
/// Transitions connection from handshaking -> ready.
pub fn performClientHandshake(
    conn: *connection_mod.Connection,
    allocator: std.mem.Allocator,
    client_hello: handshake_mod.ClientHello,
    payload_buf: []u8,
) (HandshakeError || reader_mod.ReadError || error{ EndOfStream, Overflow })!ClientHandshakeResult {
    // 1. Send ClientHello
    const json_payload = json_mod.encode(allocator, client_hello) catch return error.MalformedPayload;
    defer allocator.free(json_payload);

    const seq = conn.send_seq.advance();
    const hdr = header_mod.Header{
        .msg_type = @intFromEnum(message_type_mod.MessageType.client_hello),
        .flags = .{},
        .payload_len = @intCast(json_payload.len),
        .sequence = seq,
    };
    var hdr_buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&hdr_buf);
    conn.transport.write(&hdr_buf) catch return error.EndOfStream;
    conn.transport.write(json_payload) catch return error.EndOfStream;

    // 2. Read ServerHello
    var resp_hdr_buf: [header_mod.HEADER_SIZE]u8 = undefined;
    var hdr_read: usize = 0;
    while (hdr_read < header_mod.HEADER_SIZE) {
        const n = conn.transport.read(resp_hdr_buf[hdr_read..]) catch return error.EndOfStream;
        if (n == 0) return error.EndOfStream;
        hdr_read += n;
    }
    const resp_hdr = header_mod.Header.decode(&resp_hdr_buf) catch return error.MalformedPayload;

    if (resp_hdr.msg_type != @intFromEnum(message_type_mod.MessageType.server_hello))
        return error.UnexpectedMessage;

    if (resp_hdr.payload_len > payload_buf.len) return error.Overflow;
    var payload_read: usize = 0;
    while (payload_read < resp_hdr.payload_len) {
        const n = conn.transport.read(payload_buf[payload_read..resp_hdr.payload_len]) catch return error.EndOfStream;
        if (n == 0) return error.EndOfStream;
        payload_read += n;
    }

    const parsed = json_mod.decode(handshake_mod.ServerHello, allocator, payload_buf[0..resp_hdr.payload_len])
        catch return error.MalformedPayload;
    defer parsed.deinit();
    const server_hello = parsed.value;

    // 3. Build negotiated caps from server response
    const caps = negotiateCapabilities(
        server_hello.negotiated_caps,
        &.{}, // client accepts whatever server negotiated
    );

    // 4. Transition state
    try conn.completeHandshake(server_hello.client_id, caps);

    return .{
        .client_id = server_hello.client_id,
        .negotiated_caps = caps,
    };
}

fn negotiateCapabilities(
    client_caps: []const []const u8,
    server_caps: []const []const u8,
) connection_mod.NegotiatedCaps {
    var result = connection_mod.NegotiatedCaps{};

    // If server_caps is empty, accept all client caps (for client-side negotiation)
    const caps_to_check = if (server_caps.len > 0) client_caps else client_caps;
    const caps_to_match = if (server_caps.len > 0) server_caps else client_caps;

    for (caps_to_check) |cap| {
        const matched = if (server_caps.len > 0) blk: {
            for (caps_to_match) |sc| {
                if (std.mem.eql(u8, cap, sc)) break :blk true;
            }
            break :blk false;
        } else true;

        if (matched) {
            if (std.mem.eql(u8, cap, "clipboard_sync")) result.clipboard_sync = true
            else if (std.mem.eql(u8, cap, "mouse")) result.mouse = true
            else if (std.mem.eql(u8, cap, "selection")) result.selection = true
            else if (std.mem.eql(u8, cap, "search")) result.search = true
            else if (std.mem.eql(u8, cap, "fd_passing")) result.fd_passing = true
            else if (std.mem.eql(u8, cap, "agent_detection")) result.agent_detection = true
            else if (std.mem.eql(u8, cap, "flow_control")) result.flow_control = true
            else if (std.mem.eql(u8, cap, "pixel_dimensions")) result.pixel_dimensions = true
            else if (std.mem.eql(u8, cap, "sixel")) result.sixel = true
            else if (std.mem.eql(u8, cap, "kitty_graphics")) result.kitty_graphics = true
            else if (std.mem.eql(u8, cap, "notifications")) result.notifications = true;
        }
    }
    return result;
}

// --- Tests ---

const builtin = @import("builtin");

test "negotiateCapabilities intersection" {
    const client = [_][]const u8{ "mouse", "clipboard_sync", "search" };
    const server = [_][]const u8{ "mouse", "search", "sixel" };
    const caps = negotiateCapabilities(&client, &server);
    try std.testing.expect(caps.mouse);
    try std.testing.expect(caps.search);
    try std.testing.expect(!caps.clipboard_sync); // not in server
    try std.testing.expect(!caps.sixel); // not in client
}

test "negotiateCapabilities empty server accepts all client" {
    const client = [_][]const u8{ "mouse", "clipboard_sync" };
    const caps = negotiateCapabilities(&client, &.{});
    try std.testing.expect(caps.mouse);
    try std.testing.expect(caps.clipboard_sync);
}

test "Full handshake round-trip over socketpair" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;

    const allocator = std.testing.allocator;

    // Create socketpair
    var fds: [2]std.posix.socket_t = undefined;
    const rc = std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds);
    try std.testing.expectEqual(@as(c_int, 0), rc);

    var client_ut = transport_mod.UnixTransport{ .socket_fd = fds[0] };
    var server_ut = transport_mod.UnixTransport{ .socket_fd = fds[1] };
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    var client_conn = connection_mod.Connection.init(client_ut.transport());
    var server_conn = connection_mod.Connection.init(server_ut.transport());

    // Client sends hello in a thread
    const client_thread = try std.Thread.spawn(.{}, struct {
        fn run(cc: *connection_mod.Connection, alloc: std.mem.Allocator) void {
            var buf: [4096]u8 = undefined;
            const hello = handshake_mod.ClientHello{
                .protocol_version_min = 1,
                .protocol_version_max = 1,
                .client_name = "test-client",
                .capabilities = &.{ "mouse", "search" },
            };
            _ = performClientHandshake(cc, alloc, hello, &buf) catch {};
        }
    }.run, .{ &client_conn, allocator });

    // Server processes on main thread
    var server_buf: [4096]u8 = undefined;
    const server_config = ServerConfig{
        .next_client_id = 42,
        .server_pid = 1234,
        .supported_caps = &.{ "mouse", "clipboard_sync" },
    };
    const result = try performServerHandshake(&server_conn, allocator, server_config, &server_buf);

    client_thread.join();

    try std.testing.expectEqual(@as(u32, 42), result.client_id);
    try std.testing.expect(result.negotiated_caps.mouse);
    try std.testing.expect(!result.negotiated_caps.search); // not in server caps
    try std.testing.expectEqual(connection_mod.ConnectionState.ready, server_conn.state);
}

test "Version mismatch" {
    const allocator = std.testing.allocator;

    // Build a ClientHello requesting version 2-3
    const hello = handshake_mod.ClientHello{
        .protocol_version_min = 2,
        .protocol_version_max = 3,
        .client_name = "test",
    };
    const json_payload = try json_mod.encode(allocator, hello);
    defer allocator.free(json_payload);

    // Create a buffer with a proper frame
    var frame_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&frame_buf);
    const hdr = header_mod.Header{
        .msg_type = @intFromEnum(message_type_mod.MessageType.client_hello),
        .flags = .{},
        .payload_len = @intCast(json_payload.len),
        .sequence = 1,
    };
    var hdr_bytes: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&hdr_bytes);
    fbs.writer().writeAll(&hdr_bytes) catch unreachable;
    fbs.writer().writeAll(json_payload) catch unreachable;

    var bt = transport_mod.BufferTransport.init(allocator, fbs.getWritten());
    defer bt.deinit();
    var conn = connection_mod.Connection.init(bt.transport());

    var payload_buf: [4096]u8 = undefined;
    const result = performServerHandshake(&conn, allocator, .{
        .next_client_id = 1,
        .protocol_version = 1, // server only supports v1
    }, &payload_buf);
    try std.testing.expectError(error.VersionMismatch, result);
}
