//! Top-level message dispatcher: thin page-level router that shifts
//! msg_type >> 8 to select one of six category dispatchers.
//!
//! Per ADR 00064 (category-based message dispatcher) and
//! protocol 01-protocol-overview (message type range definitions).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const Header = protocol.header.Header;
const server = @import("itshell3_server");
const interfaces = server.os.interfaces;
const EventLoopOps = interfaces.EventLoopOps;
const ClientManager = server.connection.client_manager.ClientManager;
const ClientState = server.connection.client_state.ClientState;
const HeartbeatManager = server.connection.heartbeat_manager.HeartbeatManager;
const SessionManager = server.state.session_manager.SessionManager;
const core = @import("itshell3_core");
const lifecycle_dispatcher = @import("lifecycle_dispatcher.zig");
const session_pane_dispatcher = @import("session_pane_dispatcher.zig");
const input_dispatcher = @import("input_dispatcher.zig");
const render_dispatcher = @import("render_dispatcher.zig");
const ime_dispatcher = @import("ime_dispatcher.zig");
const flow_control_dispatcher = @import("flow_control_dispatcher.zig");

/// Timeout after which a READY client that hasn't attached a session is
/// disconnected, per daemon-behavior spec.
pub const READY_IDLE_TIMEOUT_MS: u32 = 60_000;

/// Shared context for all dispatchers: server state references and callbacks.
pub const DispatcherContext = struct {
    client_manager: *ClientManager,
    heartbeat_manager: *HeartbeatManager,
    server_pid: u32,
    /// Callback for initiating client disconnect.
    disconnect_fn: *const fn (client_slot: u16) void,
    /// Event loop operations for timer management.
    event_loop_ops: *const EventLoopOps,
    event_loop_context: *anyopaque,
    /// Allocator for handshake processing and other dynamic allocations.
    allocator: std.mem.Allocator,
    /// Session manager reference for session/pane handlers.
    session_manager: *SessionManager = undefined,
    /// Default IME engine for session creation.
    default_ime_engine: core.ImeEngine = undefined,
};

/// Uniform parameter struct passed to all category dispatchers.
pub const CategoryDispatchParams = struct {
    context: *DispatcherContext,
    client: *ClientState,
    client_slot: u16,
    msg_type: MessageType,
    header: Header,
    payload: []const u8,
};

/// Routes a decoded message by page-level category (msg_type >> 8) to the
/// appropriate category dispatcher.
pub fn dispatch(
    ctx: *DispatcherContext,
    client_slot: u16,
    msg_type: MessageType,
    header: Header,
    payload: []const u8,
) void {
    const client = ctx.client_manager.getClient(client_slot) orelse return;
    const params = CategoryDispatchParams{
        .context = ctx,
        .client = client,
        .client_slot = client_slot,
        .msg_type = msg_type,
        .header = header,
        .payload = payload,
    };
    switch (@intFromEnum(msg_type) >> 8) {
        0x00 => lifecycle_dispatcher.dispatch(params),
        0x01 => session_pane_dispatcher.dispatch(params),
        0x02 => input_dispatcher.dispatch(params),
        0x03 => render_dispatcher.dispatch(params),
        0x04 => ime_dispatcher.dispatch(params),
        0x05 => flow_control_dispatcher.dispatch(params),
        else => {},
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

/// No-op event loop ops for tests.
const noop_event_loop_ops = EventLoopOps{
    .registerRead = struct {
        fn f(_: *anyopaque, _: std.posix.fd_t, _: ?interfaces.EventTarget) EventLoopOps.RegisterError!void {}
    }.f,
    .registerWrite = struct {
        fn f(_: *anyopaque, _: std.posix.fd_t, _: ?interfaces.EventTarget) EventLoopOps.RegisterError!void {}
    }.f,
    .unregister = struct {
        fn f(_: *anyopaque, _: std.posix.fd_t) void {}
    }.f,
    .registerTimer = struct {
        fn f(_: *anyopaque, _: u16, _: u32, _: ?interfaces.EventTarget) EventLoopOps.RegisterError!void {}
    }.f,
    .cancelTimer = struct {
        fn f(_: *anyopaque, _: u16) void {}
    }.f,
    .wait = struct {
        fn f(_: *anyopaque, _: ?u32) EventLoopOps.WaitError!server.os.PriorityEventBuffer.Iterator {
            // Not used in these tests; provide a dummy empty buffer.
            const empty = &server.os.PriorityEventBuffer{};
            return empty.iterator();
        }
    }.f,
};

test "dispatch: unknown message type does not crash" {
    var mgr = ClientManager{ .chunk_pool = @import("itshell3_testing").helpers.testChunkPool() };
    const idx = try mgr.addClient(.{ .fd = 10 });
    const c = mgr.getClient(idx).?;
    _ = c.connection.transitionTo(.ready);
    _ = c.connection.transitionTo(.operating);

    var hb_mgr = HeartbeatManager{};
    var disconnect_called = false;
    const disconnect_ctx = struct {
        var flag: *bool = undefined;
        fn cb(_: u16) void {
            flag.* = true;
        }
    };
    disconnect_ctx.flag = &disconnect_called;

    var dummy_el_ctx: u8 = 0;
    var ctx = DispatcherContext{
        .client_manager = &mgr,
        .heartbeat_manager = &hb_mgr,
        .server_pid = 1234,
        .disconnect_fn = disconnect_ctx.cb,
        .event_loop_ops = &noop_event_loop_ops,
        .event_loop_context = @ptrCast(&dummy_el_ctx),
        .allocator = std.testing.allocator,
    };

    // Dispatch an operational message type (stub, should not crash).
    const hdr = Header{
        .msg_type = @intFromEnum(MessageType.key_event),
        .flags = .{},
        .payload_length = 0,
        .sequence = 1,
    };
    dispatch(&ctx, idx, .key_event, hdr, "");
    // No crash = success.
    try std.testing.expect(!disconnect_called);

    mgr.getClient(idx).?.deinit();
}

test "dispatch: page-level routing covers all six categories" {
    // Verify that the page-level shift produces the expected category index
    // for representative message types from each range.
    try std.testing.expectEqual(@as(u16, 0x00), @intFromEnum(MessageType.client_hello) >> 8);
    try std.testing.expectEqual(@as(u16, 0x01), @intFromEnum(MessageType.create_session_request) >> 8);
    try std.testing.expectEqual(@as(u16, 0x02), @intFromEnum(MessageType.key_event) >> 8);
    try std.testing.expectEqual(@as(u16, 0x03), @intFromEnum(MessageType.frame_update) >> 8);
    try std.testing.expectEqual(@as(u16, 0x04), @intFromEnum(MessageType.input_method_switch) >> 8);
    try std.testing.expectEqual(@as(u16, 0x05), @intFromEnum(MessageType.pause_pane) >> 8);
}
