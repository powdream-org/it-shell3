//! Handles session management requests: Create, List, Attach, Detach, Destroy,
//! Rename, and AttachOrCreate. Each handler validates state, mutates
//! SessionManager, sends a response to the requester, and broadcasts
//! notifications to peers.
//!
//! Per protocol 03-session-pane-management (0x0100-0x010D) and
//! daemon-behavior 02-event-handling (response-before-notification).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const Header = protocol.header.Header;
const HEADER_SIZE = protocol.header.HEADER_SIZE;
const core = @import("itshell3_core");
const types = core.types;
const session_mod = core.session;
const server = @import("itshell3_server");
const SessionManager = server.state.session_manager.SessionManager;
const SessionInfo = server.state.session_manager.SessionInfo;
const SessionEntry = server.state.session_entry.SessionEntry;
const ClientState = server.connection.client_state.ClientState;
const ClientManager = server.connection.client_manager.ClientManager;
const broadcast = server.connection.broadcast;
const envelope = @import("protocol_envelope.zig");
const notification_builder = @import("notification_builder.zig");

/// Context for session handler operations.
pub const SessionHandlerContext = struct {
    session_manager: *SessionManager,
    client_manager: *ClientManager,
    /// Callback for initiating client disconnect.
    disconnect_fn: *const fn (client_slot: u16) void,
    /// IME engine for new session creation. Provided by daemon initialization.
    /// The daemon creates one ImeEngine vtable (backed by libitshell3-ime) and
    /// passes it here. Each session gets a copy of this vtable.
    default_ime_engine: core.ImeEngine,
};

// ── CreateSessionRequest (0x0100) ───────────────────────────────────────────

/// Handles CreateSessionRequest. Creates a new session and broadcasts
/// SessionListChanged to all connected clients.
pub fn handleCreateSession(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u32,
    request_name: []const u8,
) void {
    var resp_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const timestamp = std.time.milliTimestamp();

    // Use provided name or generate a default.
    var name_buf: [types.MAX_SESSION_NAME]u8 = undefined;
    const name = if (request_name.len > 0)
        request_name
    else blk: {
        break :blk std.fmt.bufPrint(&name_buf, "session-{d}", .{
            ctx.session_manager.next_session_id,
        }) catch "session";
    };

    const session_id = ctx.session_manager.createSession(
        name,
        ctx.default_ime_engine,
        timestamp,
    ) catch {
        const err_json = "{\"status\":7,\"error\":\"max sessions reached\"}";
        const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.create_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(resp) catch {};
        return;
    };

    // The initial pane (slot 0) is reserved but not yet populated with a
    // real PTY process. The caller must do forkpty + Terminal.init.
    // TODO(Plan 9+): Spawn shell process via OS vtable forkpty.
    const initial_pane_id = ctx.session_manager.allocPaneId();

    // Build success response.
    var json_buf: [256]u8 = undefined;
    const resp_json = std.fmt.bufPrint(&json_buf, "{{\"status\":0,\"session_id\":{d},\"pane_id\":{d}}}", .{
        session_id,
        initial_pane_id,
    }) catch return;
    const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.create_session_response), sequence, resp_json) orelse return;
    client.enqueueDirect(resp) catch {};

    // Broadcast SessionListChanged(event="created") to all connected clients.
    var notif_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notif_seq = client.connection.advanceSendSequence();
    const notif = notification_builder.buildSessionListChanged("created", session_id, name, notif_seq, &notif_buf) orelse return;
    _ = broadcast.broadcastToActive(ctx.client_manager, notif, client_slot);
}

// ── ListSessionsRequest (0x0102) ────────────────────────────────────────────

/// Handles ListSessionsRequest. Returns all sessions with metadata.
pub fn handleListSessions(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u32,
) void {
    _ = client_slot;
    var sessions: [types.MAX_SESSIONS]SessionInfo = undefined;
    const count = ctx.session_manager.getSessionList(&sessions);

    // Build JSON response with session list.
    var json_buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&json_buf);
    const writer = stream.writer();

    writer.writeAll("{\"status\":0,\"sessions\":[") catch return;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (i > 0) writer.writeAll(",") catch return;
        const info = &sessions[i];

        // Count attached clients for this session.
        var attached_count: u32 = 0;
        const mgr = ctx.client_manager;
        var c: u32 = 0;
        while (c < server.connection.client_manager.MAX_CLIENTS) : (c += 1) {
            const idx: u16 = @intCast(c);
            if (mgr.getClientConst(idx)) |cs| {
                if (cs.connection.state == .operating and
                    cs.connection.attached_session_id == info.session_id)
                {
                    attached_count += 1;
                }
            }
        }

        writer.print("{{\"session_id\":{d},\"name\":\"{s}\",\"created_at\":{d},\"pane_count\":{d},\"attached_clients\":{d}}}", .{
            info.session_id,
            info.getName(),
            info.created_at,
            info.pane_count,
            attached_count,
        }) catch return;
    }
    writer.writeAll("]}") catch return;

    const json = stream.getWritten();
    var resp_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const resp = envelope.wrapResponse(
        &resp_buf,
        @intFromEnum(MessageType.list_sessions_response),
        sequence,
        json,
    ) orelse return;
    client.enqueueDirect(resp) catch {};
}

// ── RenameSessionRequest (0x010A) ───────────────────────────────────────────

/// Handles RenameSessionRequest. Validates duplicate name, updates session,
/// sends response then SessionListChanged.
pub fn handleRenameSession(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u32,
    session_id: types.SessionId,
    new_name: []const u8,
) void {
    var resp_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    // Check session exists.
    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err_json = "{\"status\":1,\"error\":\"session not found\"}";
        const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.rename_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(resp) catch {};
        return;
    };

    // Check for duplicate name.
    if (ctx.session_manager.findSessionByName(new_name)) |existing| {
        if (existing.session.session_id != session_id) {
            const err_json = "{\"status\":2,\"error\":\"name already in use\"}";
            const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.rename_session_response), sequence, err_json) orelse return;
            client.enqueueDirect(resp) catch {};
            return;
        }
    }

    // Update the name.
    entry.session.setName(new_name);

    // Response to requester (before notification).
    const ok_json = "{\"status\":0}";
    const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.rename_session_response), sequence, ok_json) orelse return;
    client.enqueueDirect(resp) catch {};

    // Broadcast SessionListChanged(event="renamed") to all connected clients.
    var notif_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notif_seq = client.connection.advanceSendSequence();
    const notif = notification_builder.buildSessionListChanged("renamed", session_id, new_name, notif_seq, &notif_buf) orelse return;
    _ = broadcast.broadcastToActive(ctx.client_manager, notif, client_slot);
}

// ── AttachSessionRequest (0x0104) ───────────────────────────────────────────

/// Handles AttachSessionRequest. Transitions client to OPERATING, sets
/// attachment, sends response + LayoutChanged + ClientAttached.
pub fn handleAttachSession(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u32,
    session_id: types.SessionId,
) void {
    var resp_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    // Per ADR 00020: already attached returns error.
    if (client.connection.state == .operating) {
        const err_json = "{\"status\":3,\"error\":\"already attached to a session\"}";
        const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.attach_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(resp) catch {};
        return;
    }

    // Find session.
    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err_json = "{\"status\":1,\"error\":\"session not found\"}";
        const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.attach_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(resp) catch {};
        return;
    };

    // Transition to OPERATING.
    if (!client.connection.transitionTo(.operating)) {
        const err_json = "{\"status\":7,\"error\":\"internal error\"}";
        const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.attach_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(resp) catch {};
        return;
    }

    // Set attachment.
    client.connection.attached_session_id = session_id;
    client.attached_session = entry;

    // Cancel ready idle timer.
    if (client.ready_idle_timer_id) |_| {
        client.ready_idle_timer_id = null;
    }

    // Build response.
    const active_pane_id: types.PaneId = if (entry.session.focused_pane) |fp|
        if (entry.getPaneAtSlot(fp)) |pane| pane.pane_id else 0
    else
        0;

    var json_resp_buf: [1024]u8 = undefined;
    const resp_json = std.fmt.bufPrint(&json_resp_buf, "{{\"status\":0,\"session_id\":{d},\"name\":\"{s}\",\"active_pane_id\":{d},\"active_input_method\":\"{s}\",\"active_keyboard_layout\":\"{s}\",\"resize_policy\":\"latest\"}}", .{
        session_id,
        entry.session.getName(),
        active_pane_id,
        entry.session.getActiveInputMethod(),
        entry.session.getActiveKeyboardLayout(),
    }) catch return;
    const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.attach_session_response), sequence, resp_json) orelse return;
    client.enqueueDirect(resp) catch {};

    // TODO(Plan 9): Send LayoutChanged notification to requester.
    // TODO(Plan 9): Send initial I-frame from ring buffer.

    // Broadcast ClientAttached to other session peers.
    var attached_count: u32 = 0;
    var c: u32 = 0;
    while (c < server.connection.client_manager.MAX_CLIENTS) : (c += 1) {
        const idx: u16 = @intCast(c);
        if (ctx.client_manager.getClientConst(idx)) |cs| {
            if (cs.connection.state == .operating and cs.connection.attached_session_id == session_id) {
                attached_count += 1;
            }
        }
    }

    var notif_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notif_seq = client.connection.advanceSendSequence();
    const notif = notification_builder.buildClientAttached(session_id, client.connection.client_id, "", attached_count, notif_seq, &notif_buf) orelse return;
    _ = broadcast.broadcastToSession(ctx.client_manager, session_id, notif, client_slot);
}

// ── DetachSessionRequest (0x0106) ───────────────────────────────────────────

/// Handles DetachSessionRequest. Clears attachment, transitions to READY.
pub fn handleDetachSession(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u32,
) void {
    var resp_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    if (client.connection.state != .operating) {
        const err_json = "{\"status\":1,\"error\":\"not attached to a session\"}";
        const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.detach_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(resp) catch {};
        return;
    }

    const session_id = client.connection.attached_session_id;
    const client_id = client.connection.client_id;

    // Clear attachment.
    client.connection.attached_session_id = 0;
    client.attached_session = null;
    _ = client.connection.transitionTo(.ready);

    // Response to requester.
    const ok_json = "{\"status\":0,\"reason\":\"client_requested\"}";
    const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.detach_session_response), sequence, ok_json) orelse return;
    client.enqueueDirect(resp) catch {};

    // Count remaining attached clients.
    var attached_count: u32 = 0;
    var c: u32 = 0;
    while (c < server.connection.client_manager.MAX_CLIENTS) : (c += 1) {
        const idx: u16 = @intCast(c);
        if (ctx.client_manager.getClientConst(idx)) |cs| {
            if (cs.connection.state == .operating and cs.connection.attached_session_id == session_id) {
                attached_count += 1;
            }
        }
    }

    // Broadcast ClientDetached to remaining session peers.
    var notif_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notif_seq = client.connection.advanceSendSequence();
    const notif = notification_builder.buildClientDetached(session_id, client_id, "", "client_requested", attached_count, notif_seq, &notif_buf) orelse return;
    _ = broadcast.broadcastToSession(ctx.client_manager, session_id, notif, client_slot);
}

// ── DestroySessionRequest (0x0108) ──────────────────────────────────────────

/// Handles DestroySessionRequest. Per daemon-behavior 02-event-handling
/// (destroy cascade: 5 wire messages).
pub fn handleDestroySession(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u32,
    session_id: types.SessionId,
) void {
    var resp_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    // Check session exists and get entry in a single lookup.
    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err_json = "{\"status\":1,\"error\":\"session not found\"}";
        const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.destroy_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(resp) catch {};
        return;
    };
    var name_copy: [types.MAX_SESSION_NAME]u8 = @splat(0);
    const name_len = entry.session.name_length;
    @memcpy(name_copy[0..name_len], entry.session.name[0..name_len]);
    const session_name = name_copy[0..name_len];

    // TODO(Plan 8): 1. PreeditEnd to affected clients (if composition active).

    // 2. DestroySessionResponse to requester.
    const ok_json = "{\"status\":0}";
    const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.destroy_session_response), sequence, ok_json) orelse return;
    client.enqueueDirect(resp) catch {};

    // 3. SessionListChanged(event="destroyed") broadcast to ALL connected clients.
    var notif_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notif_seq = client.connection.advanceSendSequence();
    const notif = notification_builder.buildSessionListChanged("destroyed", session_id, session_name, notif_seq, &notif_buf) orelse return;
    _ = broadcast.broadcastToActive(ctx.client_manager, notif, null);

    // 4. DetachSessionResponse to each other attached client.
    // 5. ClientDetached to requester for each detached peer.
    var c: u32 = 0;
    while (c < server.connection.client_manager.MAX_CLIENTS) : (c += 1) {
        const idx: u16 = @intCast(c);
        if (idx == client_slot) continue;
        const peer = ctx.client_manager.getClient(idx) orelse continue;
        if (peer.connection.state != .operating) continue;
        if (peer.connection.attached_session_id != session_id) continue;

        const peer_client_id = peer.connection.client_id;

        // Force detach the peer.
        peer.connection.attached_session_id = 0;
        peer.attached_session = null;
        _ = peer.connection.transitionTo(.ready);

        // Reuse a single buffer for per-peer messages (only one peer processed at a time).
        var peer_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

        // Send DetachSessionResponse to the peer.
        const detach_json = "{\"status\":0,\"reason\":\"session_destroyed\"}";
        const detach_resp = envelope.wrapResponse(&peer_buf, @intFromEnum(MessageType.detach_session_response), 0, detach_json) orelse continue;
        peer.enqueueDirect(detach_resp) catch {};

        // Send ClientDetached to the requester for this peer.
        const cd_seq = client.connection.advanceSendSequence();
        const cd_notif = notification_builder.buildClientDetached(session_id, peer_client_id, "", "session_destroyed", 0, cd_seq, &peer_buf) orelse continue;
        client.enqueueDirect(cd_notif) catch {};
    }

    // If requester was attached to this session, clear their attachment too.
    if (client.connection.attached_session_id == session_id) {
        client.connection.attached_session_id = 0;
        client.attached_session = null;
        if (client.connection.state == .operating) {
            _ = client.connection.transitionTo(.ready);
        }
    }

    // Destroy the session in the manager.
    _ = ctx.session_manager.destroySession(session_id);
}

// ── AttachOrCreateRequest (0x010C) ──────────────────────────────────────────

/// Handles AttachOrCreateRequest. Finds or creates session by name,
/// then attaches.
pub fn handleAttachOrCreate(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u32,
    session_name: []const u8,
) void {
    var resp_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    // Per ADR 00020: already attached returns error.
    if (client.connection.state == .operating) {
        const err_json = "{\"status\":3,\"error\":\"already attached to a session\"}";
        const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.attach_or_create_response), sequence, err_json) orelse return;
        client.enqueueDirect(resp) catch {};
        return;
    }

    // Try to find existing session by name.
    if (ctx.session_manager.findSessionByName(session_name)) |entry| {
        // Attach to existing session.
        handleAttachSession(ctx, client, client_slot, sequence, entry.session.session_id);
        return;
    }

    // Session not found — create a new one and attach.
    const timestamp = std.time.milliTimestamp();
    const new_session_id = ctx.session_manager.createSession(
        session_name,
        ctx.default_ime_engine,
        timestamp,
    ) catch {
        const err_json = "{\"status\":7,\"error\":\"max sessions reached\"}";
        const resp = envelope.wrapResponse(&resp_buf, @intFromEnum(MessageType.attach_or_create_response), sequence, err_json) orelse return;
        client.enqueueDirect(resp) catch {};
        return;
    };

    // TODO(Plan 9+): Spawn shell process for the initial pane.
    _ = ctx.session_manager.allocPaneId();

    // Broadcast SessionListChanged(event="created").
    var notif_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notif_seq = client.connection.advanceSendSequence();
    const notif = notification_builder.buildSessionListChanged("created", new_session_id, session_name, notif_seq, &notif_buf) orelse return;
    _ = broadcast.broadcastToActive(ctx.client_manager, notif, client_slot);

    // Now attach to the new session.
    handleAttachSession(ctx, client, client_slot, sequence, new_session_id);
}

// ── Tests ────────────────────────────────────────────────────────────────────

fn testSessionManager() *SessionManager {
    // Static test SessionManager.
    const S = struct {
        var sm = SessionManager.init();
    };
    S.sm.reset();
    return &S.sm;
}

test "handleListSessions: returns empty list when no sessions" {
    const helpers = @import("itshell3_testing").helpers;
    var mgr = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const idx = try mgr.addClient(.{ .fd = 10 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);

    const sm = testSessionManager();
    var ctx = SessionHandlerContext{
        .session_manager = sm,
        .client_manager = &mgr,
        .disconnect_fn = struct {
            fn cb(_: u16) void {}
        }.cb,
        .default_ime_engine = helpers.testImeEngine(),
    };

    handleListSessions(&ctx, client, idx, 1);

    // Verify something was enqueued.
    try std.testing.expect(!client.direct_queue.isEmpty());

    client.deinit();
}

test "handleRenameSession: renames successfully" {
    const helpers = @import("itshell3_testing").helpers;
    var mgr = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const idx = try mgr.addClient(.{ .fd = 10 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);

    const sm = testSessionManager();
    // Create session directly for test.
    const sess_id = sm.createSession("old-name", helpers.testImeEngine(), 0) catch unreachable;

    var ctx = SessionHandlerContext{
        .session_manager = sm,
        .client_manager = &mgr,
        .disconnect_fn = struct {
            fn cb(_: u16) void {}
        }.cb,
        .default_ime_engine = helpers.testImeEngine(),
    };

    handleRenameSession(&ctx, client, idx, 1, sess_id, "new-name");

    // Verify name changed.
    const entry = sm.getSession(sess_id).?;
    try std.testing.expectEqualSlices(u8, "new-name", entry.session.getName());

    client.deinit();
}

test "handleRenameSession: duplicate name returns error" {
    const helpers = @import("itshell3_testing").helpers;
    var mgr = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const idx = try mgr.addClient(.{ .fd = 10 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);

    const sm = testSessionManager();
    _ = sm.createSession("existing", helpers.testImeEngine(), 0) catch unreachable;
    const id2 = sm.createSession("other", helpers.testImeEngine(), 0) catch unreachable;

    var ctx = SessionHandlerContext{
        .session_manager = sm,
        .client_manager = &mgr,
        .disconnect_fn = struct {
            fn cb(_: u16) void {}
        }.cb,
        .default_ime_engine = helpers.testImeEngine(),
    };

    handleRenameSession(&ctx, client, idx, 1, id2, "existing");

    // Name should NOT have changed.
    const entry = sm.getSession(id2).?;
    try std.testing.expectEqualSlices(u8, "other", entry.session.getName());

    client.deinit();
}

test "handleDetachSession: detaches client" {
    const helpers = @import("itshell3_testing").helpers;
    var mgr = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const idx = try mgr.addClient(.{ .fd = 10 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    const sm = testSessionManager();
    var ctx = SessionHandlerContext{
        .session_manager = sm,
        .client_manager = &mgr,
        .disconnect_fn = struct {
            fn cb(_: u16) void {}
        }.cb,
        .default_ime_engine = helpers.testImeEngine(),
    };

    handleDetachSession(&ctx, client, idx, 1);

    try std.testing.expectEqual(@as(u32, 0), client.connection.attached_session_id);
    try std.testing.expect(client.connection.state == .ready);

    client.deinit();
}

test "handleAttachSession: already attached returns error" {
    const helpers = @import("itshell3_testing").helpers;
    var mgr = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const idx = try mgr.addClient(.{ .fd = 10 });
    const client = mgr.getClient(idx).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    const sm = testSessionManager();
    var ctx = SessionHandlerContext{
        .session_manager = sm,
        .client_manager = &mgr,
        .disconnect_fn = struct {
            fn cb(_: u16) void {}
        }.cb,
        .default_ime_engine = helpers.testImeEngine(),
    };

    handleAttachSession(&ctx, client, idx, 1, 2);

    // Client should still be in OPERATING with session 1.
    try std.testing.expectEqual(@as(u32, 1), client.connection.attached_session_id);

    client.deinit();
}
