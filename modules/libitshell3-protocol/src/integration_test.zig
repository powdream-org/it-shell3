/// Integration tests: end-to-end message lifecycle across the full protocol stack.
///
/// These tests exercise: message struct → JSON/binary encode → frame → write →
/// read → decode → verify fields match.
const std = @import("std");
const builtin = @import("builtin");
const header_mod = @import("header.zig");
const message_type_mod = @import("message_type.zig");
const json_mod = @import("json.zig");
const handshake_mod = @import("handshake.zig");
const handshake_io_mod = @import("handshake_io.zig");
const session_mod = @import("session.zig");
const pane_mod = @import("pane.zig");
const input_mod = @import("input.zig");
const error_mod = @import("error.zig");
const cell_mod = @import("cell.zig");
const frame_update_mod = @import("frame_update.zig");
const reader_mod = @import("reader.zig");
const writer_mod = @import("writer.zig");
const transport_mod = @import("transport.zig");
const connection_mod = @import("connection.zig");

// ── Test 1: Handshake round-trip over fixedBufferStream ──────────────────────

test "integration: ClientHello encode → frame → readFrame → decode" {
    const allocator = std.testing.allocator;

    const hello = handshake_mod.ClientHello{
        .protocol_version_min = 1,
        .protocol_version_max = 1,
        .client_name = "integration-test",
        .capabilities = &.{ "mouse", "search" },
    };

    // Encode to JSON
    const payload = try json_mod.encode(allocator, hello);
    defer allocator.free(payload);

    // Write frame to buffer
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const hdr = header_mod.Header{
        .msg_type = @intFromEnum(message_type_mod.MessageType.client_hello),
        .flags = .{},
        .payload_len = @intCast(payload.len),
        .sequence = 1,
    };
    try writer_mod.writeFrame(fbs.writer(), hdr, payload);

    // Read frame back
    var read_buf: [4096]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(fbs.getWritten());
    const frame = try reader_mod.readFrame(fbs2.reader(), &read_buf);

    try std.testing.expectEqual(
        @intFromEnum(message_type_mod.MessageType.client_hello),
        frame.header.msg_type,
    );
    try std.testing.expectEqual(@as(u32, 1), frame.header.sequence);

    // Decode payload
    const parsed = try json_mod.decode(handshake_mod.ClientHello, allocator, frame.payload);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("integration-test", parsed.value.client_name);
    try std.testing.expectEqual(@as(u32, 1), parsed.value.protocol_version_min);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.capabilities.len);
}

// ── Test 2: Session/pane message round-trip ───────────────────────────────────

test "integration: CreateSessionRequest round-trip" {
    const allocator = std.testing.allocator;

    const req = session_mod.CreateSessionRequest{
        .name = "my-session",
        .shell = "/bin/zsh",
        .cols = 120,
        .rows = 40,
    };

    const payload = try json_mod.encode(allocator, req);
    defer allocator.free(payload);

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const hdr = header_mod.Header{
        .msg_type = @intFromEnum(message_type_mod.MessageType.create_session_request),
        .flags = .{},
        .payload_len = @intCast(payload.len),
        .sequence = 2,
    };
    try writer_mod.writeFrame(fbs.writer(), hdr, payload);

    var read_buf: [4096]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(fbs.getWritten());
    const frame = try reader_mod.readFrame(fbs2.reader(), &read_buf);

    const parsed = try json_mod.decode(session_mod.CreateSessionRequest, allocator, frame.payload);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("my-session", parsed.value.name.?);
    try std.testing.expectEqual(@as(?u16, 120), parsed.value.cols);
    try std.testing.expectEqual(@as(?u16, 40), parsed.value.rows);
}

// ── Test 3: FrameUpdate binary integration ────────────────────────────────────

test "integration: FrameUpdate encode → frame → decode" {
    const allocator = std.testing.allocator;

    // Build a minimal I-frame with one dirty row (2 cells)
    const cells = [_]cell_mod.CellData{
        cell_mod.CellData{
            .codepoint = 'A',
            .flags = 0,
            .wide = 0,
            .content_tag = 0,
            .fg_color = cell_mod.PackedColor.default_color,
            .bg_color = cell_mod.PackedColor.default_color,
        },
        cell_mod.CellData{
            .codepoint = 'B',
            .flags = 0,
            .wide = 0,
            .content_tag = 0,
            .fg_color = cell_mod.PackedColor.default_color,
            .bg_color = cell_mod.PackedColor.default_color,
        },
    };

    const dirty_rows = [_]frame_update_mod.DirtyRow{
        .{
            .header = .{
                .y = 0,
                .row_flags = 0,
                .selection_start = 0,
                .selection_end = 0,
                .num_cells = 2,
            },
            .cells = &cells,
            .grapheme_entries = &.{},
            .underline_color_entries = &.{},
        },
    };

    const frame_hdr = frame_update_mod.FrameHeader{
        .session_id = 1,
        .pane_id = 2,
        .frame_sequence = 1,
        .frame_type = .i_frame,
        .screen = .primary,
        .section_flags = 0,
    };

    const binary_payload = try frame_update_mod.encodeFrameUpdate(
        allocator,
        frame_hdr,
        &dirty_rows,
        null,
    );
    defer allocator.free(binary_payload);

    // Wrap in a protocol frame
    var buf: [65536]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const msg_hdr = header_mod.Header{
        .msg_type = @intFromEnum(message_type_mod.MessageType.frame_update),
        .flags = .{},
        .payload_len = @intCast(binary_payload.len),
        .sequence = 3,
    };
    try writer_mod.writeFrame(fbs.writer(), msg_hdr, binary_payload);

    // Read the frame back
    var read_buf: [65536]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(fbs.getWritten());
    const frame = try reader_mod.readFrame(fbs2.reader(), &read_buf);

    try std.testing.expectEqual(
        @intFromEnum(message_type_mod.MessageType.frame_update),
        frame.header.msg_type,
    );

    // Decode the FrameUpdate payload
    try std.testing.expect(frame.payload.len >= frame_update_mod.FRAME_HEADER_SIZE);
    const fh = frame_update_mod.FrameHeader.decode(
        frame.payload[0..frame_update_mod.FRAME_HEADER_SIZE],
    );
    try std.testing.expectEqual(@as(u32, 1), fh.session_id);
    try std.testing.expectEqual(@as(u32, 2), fh.pane_id);
    try std.testing.expectEqual(frame_update_mod.FrameType.i_frame, fh.frame_type);
}

// ── Test 4: Multi-message stream ──────────────────────────────────────────────

test "integration: multi-message stream maintains sequence order" {
    const allocator = std.testing.allocator;

    // Write 3 messages to a buffer
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var seq = reader_mod.SequenceTracker{};

    const msgs = [_]struct { mt: message_type_mod.MessageType, payload: []const u8 }{
        .{ .mt = .heartbeat, .payload = "{}" },
        .{ .mt = .heartbeat_ack, .payload = "{}" },
        .{ .mt = .disconnect, .payload = "{}" },
    };

    for (msgs) |msg| {
        const s = seq.advance();
        const h = header_mod.Header{
            .msg_type = @intFromEnum(msg.mt),
            .flags = .{},
            .payload_len = @intCast(msg.payload.len),
            .sequence = s,
        };
        try writer_mod.writeFrame(fbs.writer(), h, msg.payload);
    }

    // Read them all back in order
    var read_buf: [4096]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(fbs.getWritten());

    var expected_seq: u32 = 1;
    for (msgs) |msg| {
        const frame = try reader_mod.readFrame(fbs2.reader(), &read_buf);
        try std.testing.expectEqual(@intFromEnum(msg.mt), frame.header.msg_type);
        try std.testing.expectEqual(expected_seq, frame.header.sequence);
        expected_seq += 1;
    }

    _ = allocator;
}

// ── Test 5: Error response round-trip ────────────────────────────────────────

test "integration: error response flags RESPONSE + ERROR" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const hdr = header_mod.Header{
        .msg_type = @intFromEnum(message_type_mod.MessageType.@"error"),
        .flags = .{ .response = true, .@"error" = true },
        .payload_len = 2,
        .sequence = 9,
    };
    try writer_mod.writeFrame(fbs.writer(), hdr, "{}");

    var read_buf: [512]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(fbs.getWritten());
    const frame = try reader_mod.readFrame(fbs2.reader(), &read_buf);

    try std.testing.expect(frame.header.flags.response);
    try std.testing.expect(frame.header.flags.@"error");
    try std.testing.expectEqual(
        @intFromEnum(message_type_mod.MessageType.@"error"),
        frame.header.msg_type,
    );
}

// ── Test 6: Full connection lifecycle over socketpair ─────────────────────────

test "integration: full connection lifecycle over socketpair" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;

    const allocator = std.testing.allocator;

    var fds: [2]std.posix.socket_t = undefined;
    const rc = std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds);
    try std.testing.expectEqual(@as(c_int, 0), rc);

    var client_ut = transport_mod.UnixTransport{ .socket_fd = fds[0] };
    var server_ut = transport_mod.UnixTransport{ .socket_fd = fds[1] };
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    var client_conn = connection_mod.Connection.init(client_ut.transport());
    var server_conn = connection_mod.Connection.init(server_ut.transport());

    const client_hello = handshake_mod.ClientHello{
        .protocol_version_min = 1,
        .protocol_version_max = 1,
        .client_name = "lifecycle-test",
        .capabilities = &.{"mouse"},
    };

    // Client handshake in a thread
    const client_thread = try std.Thread.spawn(.{}, struct {
        fn run(cc: *connection_mod.Connection, alloc: std.mem.Allocator, hello: handshake_mod.ClientHello) !void {
            var payload_buf: [4096]u8 = undefined;
            const result = try handshake_io_mod.performClientHandshake(cc, alloc, hello, &payload_buf);
            try std.testing.expectEqual(@as(u32, 7), result.client_id);
            try std.testing.expectEqual(connection_mod.ConnectionState.ready, cc.state);
        }
    }.run, .{ &client_conn, allocator, client_hello });

    // Server handshake on main thread
    var server_payload_buf: [4096]u8 = undefined;
    const server_config = handshake_io_mod.ServerConfig{
        .next_client_id = 7,
        .server_pid = 999,
        .supported_caps = &.{"mouse"},
    };
    const result = try handshake_io_mod.performServerHandshake(
        &server_conn,
        allocator,
        server_config,
        &server_payload_buf,
    );

    client_thread.join();

    try std.testing.expectEqual(@as(u32, 7), result.client_id);
    try std.testing.expect(result.negotiated_caps.mouse);
    try std.testing.expectEqual(connection_mod.ConnectionState.ready, server_conn.state);

    // After handshake: both are READY. Validate state machine allows session msgs.
    try server_conn.validateMessageType(@intFromEnum(message_type_mod.MessageType.create_session_request));
    try server_conn.validateMessageType(@intFromEnum(message_type_mod.MessageType.list_sessions_request));

    // Simulate attach: READY -> OPERATING
    try server_conn.attachSession(42);
    try std.testing.expectEqual(connection_mod.ConnectionState.operating, server_conn.state);

    // OPERATING allows key events
    try server_conn.validateMessageType(@intFromEnum(message_type_mod.MessageType.key_event));

    // Begin disconnect: OPERATING -> DISCONNECTING
    try server_conn.beginDisconnect();
    try std.testing.expectEqual(connection_mod.ConnectionState.disconnecting, server_conn.state);
}

// ── Test 7: SequenceTracker wrap-around ───────────────────────────────────────

test "integration: sequence tracker wraps from 0xFFFFFFFF to 1" {
    var seq = reader_mod.SequenceTracker{ .next = 0xFFFFFFFE };

    try std.testing.expectEqual(@as(u32, 0xFFFFFFFE), seq.advance());
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), seq.advance());
    // Wrap: skips 0
    try std.testing.expectEqual(@as(u32, 1), seq.advance());
    try std.testing.expectEqual(@as(u32, 2), seq.advance());
}
