//! Spec compliance tests for client_read.zig.
//!
//! Tests verify observable behavior: feeding bytes through a real
//! SocketConnection (socketpair), message dispatch via callback,
//! peer_closed triggering disconnect, and partial frame accumulation.

const std = @import("std");
const server = @import("itshell3_server");
const client_read_mod = server.handlers.client_read;
const ClientReadContext = client_read_mod.ClientReadContext;
const client_manager_mod = server.connection.client_manager;
const ClientManager = client_manager_mod.ClientManager;
const transport = @import("itshell3_transport");
const SocketConnection = transport.transport.SocketConnection;
const protocol = @import("itshell3_protocol");
const Header = protocol.header.Header;
const HEADER_SIZE = protocol.header.HEADER_SIZE;
const MessageType = protocol.message_type.MessageType;
const interfaces = server.os.interfaces;
const Handler = server.handlers.event_loop.Handler;

// ── Test State ──────────────────────────────────────────────────────────────

const TestState = struct {
    dispatched_count: u32 = 0,
    last_msg_type: u16 = 0,
    last_client_slot: u16 = 0,
    last_sequence: u32 = 0,
    disconnect_count: u32 = 0,
    disconnect_slot: u16 = 0,
};

var test_state: TestState = .{};

fn testDispatch(client_slot: u16, msg_type: MessageType, header: Header, _: []const u8) void {
    test_state.dispatched_count += 1;
    test_state.last_msg_type = @intFromEnum(msg_type);
    test_state.last_client_slot = client_slot;
    test_state.last_sequence = header.sequence;
}

fn testDisconnect(client_slot: u16) void {
    test_state.disconnect_count += 1;
    test_state.disconnect_slot = client_slot;
}

fn resetTestState() void {
    test_state = .{};
}

/// Build a valid protocol frame: 16-byte header + payload.
fn buildFrame(buf: []u8, msg_type: u16, payload: []const u8, sequence: u32) usize {
    const hdr = Header{
        .msg_type = msg_type,
        .flags = .{},
        .payload_length = @intCast(payload.len),
        .sequence = sequence,
    };
    hdr.encode(buf[0..HEADER_SIZE]);
    @memcpy(buf[HEADER_SIZE..][0..payload.len], payload);
    return HEADER_SIZE + payload.len;
}

fn createSocketPair() ![2]std.posix.socket_t {
    const helpers = @import("itshell3_testing").helpers;
    return helpers.createPipe();
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "spec: client read -- complete frame dispatches via callback" {
    const t_helpers = @import("itshell3_transport").testing_helpers;
    const fds = try t_helpers.createSocketPair();
    const client_fd = fds[0];
    const writer_fd = fds[1];
    defer std.posix.close(writer_fd);

    resetTestState();

    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const slot = try mgr.addClient(SocketConnection{ .fd = client_fd });
    defer mgr.removeClient(slot);

    // Transition to ready so client_hello messages are allowed
    const client = mgr.getClient(slot).?;
    // Client starts in handshaking - client_hello is allowed there
    _ = client;

    var ctx = ClientReadContext{
        .client_manager = &mgr,
        .dispatch_fn = testDispatch,
        .disconnect_fn = testDisconnect,
    };

    // Build and send a client_hello frame (0x0001, allowed in handshaking)
    var frame_buf: [HEADER_SIZE + 5]u8 = undefined;
    const frame_len = buildFrame(&frame_buf, 0x0001, "hello", 1);
    _ = try std.posix.write(writer_fd, frame_buf[0..frame_len]);

    // Invoke chainHandle with a client target event
    const event = interfaces.Event{
        .fd = client_fd,
        .filter = .read,
        .target = .{ .client = .{ .client_idx = slot } },
    };
    client_read_mod.chainHandle(@ptrCast(&ctx), event, null);

    try std.testing.expectEqual(@as(u32, 1), test_state.dispatched_count);
    try std.testing.expectEqual(@as(u16, 0x0001), test_state.last_msg_type);
    try std.testing.expectEqual(slot, test_state.last_client_slot);
    try std.testing.expectEqual(@as(u32, 1), test_state.last_sequence);
}

test "spec: client read -- peer_closed triggers disconnect callback" {
    const t_helpers = @import("itshell3_transport").testing_helpers;
    const fds = try t_helpers.createSocketPair();
    const client_fd = fds[0];
    const writer_fd = fds[1];

    resetTestState();

    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const slot = try mgr.addClient(SocketConnection{ .fd = client_fd });
    defer mgr.removeClient(slot);

    var ctx = ClientReadContext{
        .client_manager = &mgr,
        .dispatch_fn = testDispatch,
        .disconnect_fn = testDisconnect,
    };

    // Close the writer end to cause peer_closed on recv
    std.posix.close(writer_fd);

    const event = interfaces.Event{
        .fd = client_fd,
        .filter = .read,
        .target = .{ .client = .{ .client_idx = slot } },
    };
    client_read_mod.chainHandle(@ptrCast(&ctx), event, null);

    try std.testing.expectEqual(@as(u32, 0), test_state.dispatched_count);
    try std.testing.expectEqual(@as(u32, 1), test_state.disconnect_count);
    try std.testing.expectEqual(slot, test_state.disconnect_slot);
}

test "spec: client read -- partial frames accumulate across recv calls" {
    const t_helpers = @import("itshell3_transport").testing_helpers;
    const fds = try t_helpers.createSocketPair();
    const client_fd = fds[0];
    const writer_fd = fds[1];
    defer std.posix.close(writer_fd);

    resetTestState();

    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const slot = try mgr.addClient(SocketConnection{ .fd = client_fd });
    defer mgr.removeClient(slot);

    var ctx = ClientReadContext{
        .client_manager = &mgr,
        .dispatch_fn = testDispatch,
        .disconnect_fn = testDisconnect,
    };

    // Build a complete frame
    var frame_buf: [HEADER_SIZE + 3]u8 = undefined;
    const frame_len = buildFrame(&frame_buf, 0x0001, "abc", 1);

    // Send only the header (partial frame)
    _ = try std.posix.write(writer_fd, frame_buf[0..HEADER_SIZE]);

    const event = interfaces.Event{
        .fd = client_fd,
        .filter = .read,
        .target = .{ .client = .{ .client_idx = slot } },
    };
    client_read_mod.chainHandle(@ptrCast(&ctx), event, null);

    // No complete frame yet
    try std.testing.expectEqual(@as(u32, 0), test_state.dispatched_count);

    // Send the remaining payload
    _ = try std.posix.write(writer_fd, frame_buf[HEADER_SIZE..frame_len]);

    client_read_mod.chainHandle(@ptrCast(&ctx), event, null);

    // Now the frame should be complete and dispatched
    try std.testing.expectEqual(@as(u32, 1), test_state.dispatched_count);
    try std.testing.expectEqual(@as(u16, 0x0001), test_state.last_msg_type);
}

test "spec: client read -- invalid message type for state is skipped" {
    const t_helpers = @import("itshell3_transport").testing_helpers;
    const fds = try t_helpers.createSocketPair();
    const client_fd = fds[0];
    const writer_fd = fds[1];
    defer std.posix.close(writer_fd);

    resetTestState();

    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const slot = try mgr.addClient(SocketConnection{ .fd = client_fd });
    defer mgr.removeClient(slot);

    var ctx = ClientReadContext{
        .client_manager = &mgr,
        .dispatch_fn = testDispatch,
        .disconnect_fn = testDisconnect,
    };

    // Client is in handshaking state. Send a key_event (0x0200) which is NOT
    // allowed in handshaking state.
    var frame_buf: [HEADER_SIZE + 4]u8 = undefined;
    const frame_len = buildFrame(&frame_buf, 0x0200, "test", 1);
    _ = try std.posix.write(writer_fd, frame_buf[0..frame_len]);

    const event = interfaces.Event{
        .fd = client_fd,
        .filter = .read,
        .target = .{ .client = .{ .client_idx = slot } },
    };
    client_read_mod.chainHandle(@ptrCast(&ctx), event, null);

    // Message should be skipped (not dispatched)
    try std.testing.expectEqual(@as(u32, 0), test_state.dispatched_count);
}

test "spec: client read -- multiple frames in single recv" {
    const t_helpers = @import("itshell3_transport").testing_helpers;
    const fds = try t_helpers.createSocketPair();
    const client_fd = fds[0];
    const writer_fd = fds[1];
    defer std.posix.close(writer_fd);

    resetTestState();

    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const slot = try mgr.addClient(SocketConnection{ .fd = client_fd });
    defer mgr.removeClient(slot);

    var ctx = ClientReadContext{
        .client_manager = &mgr,
        .dispatch_fn = testDispatch,
        .disconnect_fn = testDisconnect,
    };

    // Build two frames back-to-back
    var buf: [2 * (HEADER_SIZE + 3)]u8 = undefined;
    const len1 = buildFrame(&buf, 0x0001, "abc", 1);
    const len2 = buildFrame(buf[len1..], 0x0001, "xyz", 2);

    _ = try std.posix.write(writer_fd, buf[0 .. len1 + len2]);

    const event = interfaces.Event{
        .fd = client_fd,
        .filter = .read,
        .target = .{ .client = .{ .client_idx = slot } },
    };
    client_read_mod.chainHandle(@ptrCast(&ctx), event, null);

    // Both frames should be dispatched
    try std.testing.expectEqual(@as(u32, 2), test_state.dispatched_count);
    try std.testing.expectEqual(@as(u32, 2), test_state.last_sequence);
}

test "spec: client read -- recv_sequence_last updated after dispatch" {
    const t_helpers = @import("itshell3_transport").testing_helpers;
    const fds = try t_helpers.createSocketPair();
    const client_fd = fds[0];
    const writer_fd = fds[1];
    defer std.posix.close(writer_fd);

    resetTestState();

    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const slot = try mgr.addClient(SocketConnection{ .fd = client_fd });
    defer mgr.removeClient(slot);

    var ctx = ClientReadContext{
        .client_manager = &mgr,
        .dispatch_fn = testDispatch,
        .disconnect_fn = testDisconnect,
    };

    var frame_buf: [HEADER_SIZE + 2]u8 = undefined;
    const frame_len = buildFrame(&frame_buf, 0x0001, "ok", 42);
    _ = try std.posix.write(writer_fd, frame_buf[0..frame_len]);

    const event = interfaces.Event{
        .fd = client_fd,
        .filter = .read,
        .target = .{ .client = .{ .client_idx = slot } },
    };
    client_read_mod.chainHandle(@ptrCast(&ctx), event, null);

    const client = mgr.getClient(slot).?;
    try std.testing.expectEqual(@as(u32, 42), client.connection.recv_sequence_last);
}
