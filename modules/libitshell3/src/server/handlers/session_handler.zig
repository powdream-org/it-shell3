//! Handles session management requests: Create, List, Attach, Detach, Destroy,
//! and Rename. Each handler validates state, mutates SessionManager, sends a
//! response to the requester, and broadcasts notifications to peers.
//!
//! Per protocol 03-session-pane-management (0x0100-0x010B) and
//! daemon-behavior 02-event-handling (response-before-notification).

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const Header = protocol.header.Header;
const core = @import("itshell3_core");
const types = core.types;
const server = @import("itshell3_server");
const SessionManager = server.state.session_manager.SessionManager;
const SessionInfo = server.state.session_manager.SessionInfo;
const SessionEntry = server.state.session_entry.SessionEntry;
const ClientState = server.connection.client_state.ClientState;
const ClientManager = server.connection.client_manager.ClientManager;
const broadcast = server.connection.broadcast;
const envelope = @import("protocol_envelope.zig");
const notification_builder = @import("notification_builder.zig");
const preedit_message_builder = @import("preedit_message_builder.zig");
const handler_utils = @import("handler_utils.zig");
const pane_handler = @import("pane_handler.zig");
const procedures = server.ime.procedures;

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
    sequence: u64,
    request_name: []const u8,
) void {
    _ = client_slot;
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
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
        const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.create_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(response) catch {};
        return;
    };

    // The initial pane (slot 0) is reserved but not yet populated with a
    // real PTY process. The caller must do forkpty + Terminal.init.
    // TODO(Plan 9+): Spawn shell process via OS vtable forkpty.
    const initial_pane_id = ctx.session_manager.allocPaneId();

    // Build success response.
    var json_buffer: [256]u8 = undefined;
    const response_json = std.fmt.bufPrint(&json_buffer, "{{\"status\":0,\"session_id\":{d},\"pane_id\":{d}}}", .{
        session_id,
        initial_pane_id,
    }) catch return;
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.create_session_response), sequence, response_json) orelse return;
    client.enqueueDirect(response) catch {};

    // Broadcast SessionListChanged(event="created") to all connected clients.
    var notification_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notification_sequence = client.connection.advanceSendSequence();
    const notification = notification_builder.buildSessionListChanged("created", session_id, name, notification_sequence, &notification_buffer) orelse return;
    _ = broadcast.broadcastToActive(ctx.client_manager, notification, null);
}

// ── ListSessionsRequest (0x0102) ────────────────────────────────────────────

/// Handles ListSessionsRequest. Returns all sessions with metadata.
pub fn handleListSessions(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u64,
) void {
    _ = client_slot;
    var sessions: [types.MAX_SESSIONS]SessionInfo = undefined;
    const count = ctx.session_manager.getSessionList(&sessions);

    // Build JSON response with session list.
    var json_buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&json_buffer);
    const writer = stream.writer();

    writer.writeAll("{\"status\":0,\"sessions\":[") catch return;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (i > 0) writer.writeAll(",") catch return;
        const info = &sessions[i];

        // Count attached clients for this session.
        const attached_count = handler_utils.countAttachedClients(ctx.client_manager, info.session_id);

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
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const response = envelope.wrapResponse(
        &response_buffer,
        @intFromEnum(MessageType.list_sessions_response),
        sequence,
        json,
    ) orelse return;
    client.enqueueDirect(response) catch {};
}

// ── RenameSessionRequest (0x010A) ───────────────────────────────────────────

/// Handles RenameSessionRequest. Validates duplicate name, updates session,
/// sends response then SessionListChanged.
pub fn handleRenameSession(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u64,
    session_id: types.SessionId,
    new_name: []const u8,
) void {
    _ = client_slot;
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    // Check session exists.
    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err_json = "{\"status\":1,\"error\":\"session not found\"}";
        const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.rename_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(response) catch {};
        return;
    };

    // Check for duplicate name.
    if (ctx.session_manager.findSessionByName(new_name)) |existing| {
        if (existing.session.session_id != session_id) {
            const err_json = "{\"status\":2,\"error\":\"name already in use\"}";
            const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.rename_session_response), sequence, err_json) orelse return;
            client.enqueueDirect(response) catch {};
            return;
        }
    }

    // Update the name.
    entry.session.setName(new_name);

    // Response to requester (before notification).
    const ok_json = "{\"status\":0}";
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.rename_session_response), sequence, ok_json) orelse return;
    client.enqueueDirect(response) catch {};

    // Broadcast SessionListChanged(event="renamed") to all connected clients.
    var notification_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notification_sequence = client.connection.advanceSendSequence();
    const notification = notification_builder.buildSessionListChanged("renamed", session_id, new_name, notification_sequence, &notification_buffer) orelse return;
    _ = broadcast.broadcastToActive(ctx.client_manager, notification, null);
}

// ── AttachSessionRequest (0x0104) ───────────────────────────────────────────

/// Result of session resolution for attach requests.
const ResolveResult = struct {
    session_id: types.SessionId,
    action_taken: []const u8,
    created_session_id: ?types.SessionId,
};

/// Resolves the target session for attach: by session_id (direct), by
/// session_name (lookup), or by session_name + create_if_missing (create).
/// Returns null and sends an error response if resolution fails.
fn resolveSession(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    response_buffer: *[envelope.MAX_ENVELOPE_SIZE]u8,
    sequence: u64,
    session_id: types.SessionId,
    session_name: []const u8,
    create_if_missing: bool,
) ?ResolveResult {
    const msg_type = @intFromEnum(MessageType.attach_session_response);

    // Direct lookup by session_id.
    if (session_id != 0) {
        return .{ .session_id = session_id, .action_taken = "attached", .created_session_id = null };
    }

    // Lookup by name.
    if (ctx.session_manager.findSessionByName(session_name)) |existing| {
        return .{ .session_id = existing.session.session_id, .action_taken = "attached", .created_session_id = null };
    }

    // Not found -- create if requested.
    if (!create_if_missing) {
        handler_utils.sendErrorResponse(client, response_buffer, msg_type, sequence, 1, "session not found");
        return null;
    }

    const timestamp = std.time.milliTimestamp();
    const new_session_id = ctx.session_manager.createSession(
        session_name,
        ctx.default_ime_engine,
        timestamp,
    ) catch {
        handler_utils.sendErrorResponse(client, response_buffer, msg_type, sequence, 7, "max sessions reached");
        return null;
    };

    // TODO(Plan 9+): Spawn shell process for the initial pane.
    _ = ctx.session_manager.allocPaneId();

    return .{ .session_id = new_session_id, .action_taken = "created", .created_session_id = new_session_id };
}

/// Sends post-attach notifications: SessionListChanged (if created),
/// LayoutChanged to requester, ClientAttached to session peers.
fn sendAttachNotifications(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    entry: *SessionEntry,
    target_session_id: types.SessionId,
    session_name: []const u8,
    created_session_id: ?types.SessionId,
) void {
    const active_pane_id = entry.getPaneIdOrNone(entry.session.focused_pane);

    // Broadcast SessionListChanged(event="created") after response if we created.
    if (created_session_id) |new_id| {
        var session_notification_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
        const session_notification_sequence = client.connection.advanceSendSequence();
        const session_notification = notification_builder.buildSessionListChanged("created", new_id, session_name, session_notification_sequence, &session_notification_buffer) orelse return;
        _ = broadcast.broadcastToActive(ctx.client_manager, session_notification, null);
    }

    // Send LayoutChanged notification to the requester.
    // TODO(Plan 9): Send initial I-frame from ring buffer.
    var tree_buffer: [4096]u8 = @splat(0);
    if (pane_handler.buildLayoutPayload(entry, &tree_buffer)) |tree_json| {
        var layout_changed_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
        const layout_changed_sequence = client.connection.advanceSendSequence();
        if (notification_builder.buildLayoutChanged(
            target_session_id,
            active_pane_id,
            entry.isZoomed(),
            entry.getPaneIdOrNone(entry.zoomed_pane),
            tree_json,
            layout_changed_sequence,
            &layout_changed_buffer,
        )) |layout_changed_notification| {
            client.enqueueDirect(layout_changed_notification) catch {};
        }
    }

    // Broadcast ClientAttached to other session peers.
    const attached_count = handler_utils.countAttachedClients(ctx.client_manager, target_session_id);

    var notification_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notification_sequence = client.connection.advanceSendSequence();
    const notification = notification_builder.buildClientAttached(target_session_id, client.connection.client_id, "", attached_count, notification_sequence, &notification_buffer) orelse return;
    _ = broadcast.broadcastToSession(ctx.client_manager, target_session_id, notification, client_slot);
}

/// Handles AttachSessionRequest. Supports attach by session_id (direct lookup)
/// and by session_name with create_if_missing (merged from former
/// AttachOrCreate per ADR 00003). Transitions client to OPERATING, sets
/// attachment, sends response + LayoutChanged + ClientAttached.
pub fn handleAttachSession(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u64,
    session_id: types.SessionId,
    session_name: []const u8,
    create_if_missing: bool,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const msg_type = @intFromEnum(MessageType.attach_session_response);

    // Per ADR 00020: already attached returns error.
    if (client.connection.state == .operating) {
        handler_utils.sendErrorResponse(client, &response_buffer, msg_type, sequence, 3, "already attached to a session");
        return;
    }

    // Resolve target session: by session_id, by name, or create.
    const resolved = resolveSession(ctx, client, &response_buffer, sequence, session_id, session_name, create_if_missing) orelse return;

    // Find session entry.
    const entry = handler_utils.getSessionOrSendError(ctx.session_manager, client, &response_buffer, resolved.session_id, msg_type, sequence) orelse return;

    // Transition to OPERATING.
    if (!client.connection.transitionTo(.operating)) {
        handler_utils.sendErrorResponse(client, &response_buffer, msg_type, sequence, 7, "internal error");
        return;
    }

    // Set attachment.
    client.connection.attached_session_id = resolved.session_id;
    client.attached_session = entry;

    // Cancel ready idle timer.
    if (client.ready_idle_timer_id) |_| {
        client.ready_idle_timer_id = null;
    }

    // Build response with action_taken and pane_id per ADR 00003.
    const active_pane_id = entry.getPaneIdOrNone(entry.session.focused_pane);
    var json_response_buffer: [1024]u8 = undefined;
    const response_json = std.fmt.bufPrint(&json_response_buffer, "{{\"status\":0,\"action_taken\":\"{s}\",\"session_id\":{d},\"pane_id\":{d},\"name\":\"{s}\",\"active_pane_id\":{d},\"active_input_method\":\"{s}\",\"active_keyboard_layout\":\"{s}\",\"resize_policy\":\"latest\"}}", .{
        resolved.action_taken,
        resolved.session_id,
        active_pane_id,
        entry.session.getName(),
        active_pane_id,
        entry.session.getActiveInputMethod(),
        entry.session.getActiveKeyboardLayout(),
    }) catch return;
    const response = envelope.wrapResponse(&response_buffer, msg_type, sequence, response_json) orelse return;
    client.enqueueDirect(response) catch {};

    // Post-attach notifications.
    sendAttachNotifications(ctx, client, client_slot, entry, resolved.session_id, session_name, resolved.created_session_id);

    // PreeditSync: if any pane has active composition, send to the new client.
    sendPreeditSyncIfActive(client, entry);
}

// ── DetachSessionRequest (0x0106) ───────────────────────────────────────────

/// Handles DetachSessionRequest. Validates session_id matches attachment,
/// clears attachment, transitions to READY.
pub fn handleDetachSession(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u64,
    session_id: types.SessionId,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    if (client.connection.state != .operating) {
        const err_json = "{\"status\":1,\"error\":\"not attached to a session\"}";
        const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.detach_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(response) catch {};
        return;
    }

    // Validate session_id matches the currently attached session.
    if (client.connection.attached_session_id != session_id) {
        const err_json = "{\"status\":1,\"error\":\"session_id mismatch\"}";
        const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.detach_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(response) catch {};
        return;
    }
    const client_id = client.connection.client_id;

    // Clear attachment.
    client.connection.attached_session_id = 0;
    client.attached_session = null;
    _ = client.connection.transitionTo(.ready);

    // Response to requester.
    const ok_json = "{\"status\":0,\"reason\":\"client_requested\"}";
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.detach_session_response), sequence, ok_json) orelse return;
    client.enqueueDirect(response) catch {};

    // Count remaining attached clients.
    const attached_count = handler_utils.countAttachedClients(ctx.client_manager, session_id);

    // Broadcast ClientDetached to remaining session peers.
    var notification_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notification_sequence = client.connection.advanceSendSequence();
    const notification = notification_builder.buildClientDetached(session_id, client_id, "", "client_requested", attached_count, notification_sequence, &notification_buffer) orelse return;
    _ = broadcast.broadcastToSession(ctx.client_manager, session_id, notification, client_slot);
}

// ── DestroySessionRequest (0x0108) ──────────────────────────────────────────

/// Handles DestroySessionRequest. Per daemon-behavior 02-event-handling
/// (destroy cascade: 5 wire messages).
pub fn handleDestroySession(
    ctx: *SessionHandlerContext,
    client: *ClientState,
    client_slot: u16,
    sequence: u64,
    session_id: types.SessionId,
    force: bool,
) void {
    var response_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

    // Check session exists and get entry in a single lookup.
    const entry = ctx.session_manager.getSession(session_id) orelse {
        const err_json = "{\"status\":1,\"error\":\"session not found\"}";
        const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.destroy_session_response), sequence, err_json) orelse return;
        client.enqueueDirect(response) catch {};
        return;
    };

    // When force=false, check if any pane has a running process.
    if (!force) {
        var has_running = false;
        var p: u32 = 0;
        while (p < types.MAX_PANES) : (p += 1) {
            const slot: types.PaneSlot = @intCast(p);
            if (entry.getPaneAtSlot(slot)) |pane| {
                if (pane.is_running) {
                    has_running = true;
                    break;
                }
            }
        }
        if (has_running) {
            const err_json = "{\"status\":2,\"error\":\"PROCESSES_RUNNING\"}";
            const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.destroy_session_response), sequence, err_json) orelse return;
            client.enqueueDirect(response) catch {};
            return;
        }
    }
    var name_copy: [types.MAX_SESSION_NAME]u8 = @splat(0);
    const name_length = entry.session.name_length;
    @memcpy(name_copy[0..name_length], entry.session.name[0..name_length]);
    const session_name = name_copy[0..name_length];

    // 1. PreeditEnd to affected clients (if composition active).
    if (entry.session.preedit.owner != null) {
        var preedit_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
        const preedit_sequence = client.connection.advanceSendSequence();
        const focused_pane_id = entry.getPaneIdOrNone(entry.session.focused_pane);
        if (preedit_message_builder.buildPreeditEnd(
            focused_pane_id,
            entry.session.preedit.session_id,
            "session_destroyed",
            "",
            preedit_sequence,
            &preedit_buf,
        )) |preedit_msg| {
            _ = broadcast.broadcastToSession(ctx.client_manager, session_id, preedit_msg, null);
        }
        entry.session.preedit.owner = null;
        entry.session.setPreedit(null);
        entry.session.preedit.incrementSessionId();
    }

    // 2. DestroySessionResponse to requester.
    const ok_json = "{\"status\":0}";
    const response = envelope.wrapResponse(&response_buffer, @intFromEnum(MessageType.destroy_session_response), sequence, ok_json) orelse return;
    client.enqueueDirect(response) catch {};

    // 3. SessionListChanged(event="destroyed") broadcast to ALL connected clients.
    var notification_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
    const notification_sequence = client.connection.advanceSendSequence();
    const notification = notification_builder.buildSessionListChanged("destroyed", session_id, session_name, notification_sequence, &notification_buffer) orelse return;
    _ = broadcast.broadcastToActive(ctx.client_manager, notification, null);

    // 4. DetachSessionResponse to each other attached client.
    // 5. ClientDetached to requester for each detached peer.
    var c: u32 = 0;
    while (c < server.connection.client_manager.MAX_CLIENTS) : (c += 1) {
        const index: u16 = @intCast(c);
        if (index == client_slot) continue;
        const peer = ctx.client_manager.getClient(index) orelse continue;
        if (peer.connection.state != .operating) continue;
        if (peer.connection.attached_session_id != session_id) continue;

        const peer_client_id = peer.connection.client_id;

        // Force detach the peer.
        peer.connection.attached_session_id = 0;
        peer.attached_session = null;
        _ = peer.connection.transitionTo(.ready);

        // Reuse a single buffer for per-peer messages (only one peer processed at a time).
        var peer_buffer: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;

        // Send DetachSessionResponse to the peer.
        const detach_json = "{\"status\":0,\"reason\":\"session_destroyed\"}";
        const peer_sequence = peer.connection.advanceSendSequence();
        const detach_response = envelope.wrapResponse(&peer_buffer, @intFromEnum(MessageType.detach_session_response), peer_sequence, detach_json) orelse continue;
        peer.enqueueDirect(detach_response) catch {};

        // Send ClientDetached to the requester for this peer.
        const client_detached_sequence = client.connection.advanceSendSequence();
        const client_detached_notification = notification_builder.buildClientDetached(session_id, peer_client_id, "", "session_destroyed", 0, client_detached_sequence, &peer_buffer) orelse continue;
        client.enqueueDirect(client_detached_notification) catch {};
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

/// Sends PreeditSync to a newly attached client if any pane in the session
/// has an active composition. Per protocol 05-cjk-preedit-protocol PreeditSync.
fn sendPreeditSyncIfActive(client: *ClientState, entry: *SessionEntry) void {
    if (entry.session.preedit.owner) |owner| {
        if (entry.session.current_preedit) |preedit_text| {
            const pane_id = entry.getPaneIdOrNone(entry.session.focused_pane);
            var sync_buf: [envelope.MAX_ENVELOPE_SIZE]u8 = undefined;
            const sync_sequence = client.connection.advanceSendSequence();
            if (preedit_message_builder.buildPreeditSync(
                pane_id,
                entry.session.preedit.session_id,
                owner,
                entry.session.getActiveInputMethod(),
                preedit_text,
                sync_sequence,
                &sync_buf,
            )) |msg| {
                // Unicast to the joining client only.
                client.enqueueDirect(msg) catch {};
            }
        }
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

fn testSessionManager() *SessionManager {
    // Static test SessionManager.
    const S = struct {
        var session_manager = SessionManager.init();
    };
    S.session_manager.reset();
    return &S.session_manager;
}

test "handleListSessions: returns empty list when no sessions" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot_index = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot_index).?;
    _ = client.connection.transitionTo(.ready);

    const session_manager = testSessionManager();
    var context = SessionHandlerContext{
        .session_manager = session_manager,
        .client_manager = &client_manager,
        .disconnect_fn = struct {
            fn cb(_: u16) void {}
        }.cb,
        .default_ime_engine = helpers.testImeEngine(),
    };

    handleListSessions(&context, client, slot_index, 1);

    // Verify something was enqueued.
    try std.testing.expect(!client.direct_queue.isEmpty());

    client.deinit();
}

test "handleRenameSession: renames successfully" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot_index = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot_index).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);

    const session_manager = testSessionManager();
    // Create session directly for test.
    const sess_id = session_manager.createSession("old-name", helpers.testImeEngine(), 0) catch unreachable;

    var context = SessionHandlerContext{
        .session_manager = session_manager,
        .client_manager = &client_manager,
        .disconnect_fn = struct {
            fn cb(_: u16) void {}
        }.cb,
        .default_ime_engine = helpers.testImeEngine(),
    };

    handleRenameSession(&context, client, slot_index, 1, sess_id, "new-name");

    // Verify name changed.
    const entry = session_manager.getSession(sess_id).?;
    try std.testing.expectEqualSlices(u8, "new-name", entry.session.getName());

    client.deinit();
}

test "handleRenameSession: duplicate name returns error" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot_index = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot_index).?;
    _ = client.connection.transitionTo(.ready);

    const session_manager = testSessionManager();
    _ = session_manager.createSession("existing", helpers.testImeEngine(), 0) catch unreachable;
    const id2 = session_manager.createSession("other", helpers.testImeEngine(), 0) catch unreachable;

    var context = SessionHandlerContext{
        .session_manager = session_manager,
        .client_manager = &client_manager,
        .disconnect_fn = struct {
            fn cb(_: u16) void {}
        }.cb,
        .default_ime_engine = helpers.testImeEngine(),
    };

    handleRenameSession(&context, client, slot_index, 1, id2, "existing");

    // Name should NOT have changed.
    const entry = session_manager.getSession(id2).?;
    try std.testing.expectEqualSlices(u8, "other", entry.session.getName());

    client.deinit();
}

test "handleDetachSession: detaches client" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot_index = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot_index).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    const session_manager = testSessionManager();
    var context = SessionHandlerContext{
        .session_manager = session_manager,
        .client_manager = &client_manager,
        .disconnect_fn = struct {
            fn cb(_: u16) void {}
        }.cb,
        .default_ime_engine = helpers.testImeEngine(),
    };

    handleDetachSession(&context, client, slot_index, 1, 1);

    try std.testing.expectEqual(@as(u32, 0), client.connection.attached_session_id);
    try std.testing.expect(client.connection.state == .ready);

    client.deinit();
}

test "handleAttachSession: already attached returns error" {
    const helpers = @import("itshell3_testing").helpers;
    var client_manager = ClientManager{ .chunk_pool = helpers.testChunkPool() };
    const slot_index = try client_manager.addClient(.{ .fd = 10 });
    const client = client_manager.getClient(slot_index).?;
    _ = client.connection.transitionTo(.ready);
    _ = client.connection.transitionTo(.operating);
    client.connection.attached_session_id = 1;

    const session_manager = testSessionManager();
    var context = SessionHandlerContext{
        .session_manager = session_manager,
        .client_manager = &client_manager,
        .disconnect_fn = struct {
            fn cb(_: u16) void {}
        }.cb,
        .default_ime_engine = helpers.testImeEngine(),
    };

    handleAttachSession(&context, client, slot_index, 1, 2, "", false);

    // Client should still be in OPERATING with session 1.
    try std.testing.expectEqual(@as(u32, 1), client.connection.attached_session_id);

    client.deinit();
}
