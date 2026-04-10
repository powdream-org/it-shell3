//! Dispatcher for input forwarding messages (0x02xx range).
//! Handles KeyEvent (0x0200), TextInput (0x0201), PasteData (0x0205),
//! and FocusEvent (0x0206). Implements 5-tier input processing priority.
//!
//! Per protocol 04-input-and-renderstate and daemon-behavior policies-and-procedures.

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const message_dispatcher = @import("message_dispatcher.zig");
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;
const handler_utils = @import("handler_utils.zig");
const server = @import("itshell3_server");
const core = @import("itshell3_core");
const types = core.types;
const input = @import("itshell3_input");
const interfaces = server.os.interfaces;
const ime_consumer = server.ime.consumer;
const procedures = server.ime.procedures;
const BroadcastContext = procedures.BroadcastContext;
const preedit_builder = server.handlers.preedit_message_builder;
const broadcast_mod = server.connection.broadcast;
const envelope = @import("protocol_envelope.zig");

/// Dispatches an input-category message with priority ordering.
/// P1: KeyEvent (0x0200), TextInput (0x0201) — highest priority.
/// P2: MouseButton/Scroll — deferred to Plan 17+.
/// P3: MouseMove — deferred to Plan 17+.
/// P4: PasteData (0x0205).
/// P5: FocusEvent (0x0206) — lowest priority.
///
/// Within a single dispatch call, messages are processed individually.
/// Priority ordering is applied when multiple messages are batched
/// in the event loop (future Plan 9 event batching).
pub fn dispatch(params: CategoryDispatchParams) void {
    switch (params.msg_type) {
        .key_event => handleKeyEvent(params),
        .text_input => handleTextInput(params),
        .paste_data => handlePasteData(params),
        .focus_event => handleFocusEvent(params),
        else => {},
    }
}

/// Priority tier for input message ordering.
pub const InputPriority = enum(u8) {
    /// P1: KeyEvent, TextInput — interactive keystroke path.
    p1_key_text = 1,
    /// P2: MouseButton, MouseScroll — deferred to Plan 17+.
    p2_mouse_button = 2,
    /// P3: MouseMove — deferred to Plan 17+.
    p3_mouse_move = 3,
    /// P4: PasteData — bulk data, lower than interactive input.
    p4_paste = 4,
    /// P5: FocusEvent — state notification, lowest priority.
    p5_focus = 5,
};

/// Returns the priority tier for a message type.
pub fn priorityOf(msg_type: MessageType) InputPriority {
    return switch (msg_type) {
        .key_event, .text_input => .p1_key_text,
        .paste_data => .p4_paste,
        .focus_event => .p5_focus,
        else => .p5_focus,
    };
}

/// Toggle bindings for input method switching (Phase 0 shortcut check).
const toggle_bindings = [_]input.ToggleBinding{
    .{ .hid_keycode = 0xE6, .toggle_method = "korean_2set" }, // Right Alt
};

// ── KeyEvent (0x0200) ──────────────────────────────────────────────────────

fn handleKeyEvent(params: CategoryDispatchParams) void {
    const client = params.client;
    const payload = params.payload;

    const keycode = handler_utils.extractU16Field(payload, "\"keycode\":") orelse return;
    const action_raw = handler_utils.extractU8Field(payload, "\"action\":") orelse 0;
    const modifiers = handler_utils.extractU8Field(payload, "\"modifiers\":") orelse 0;
    const pane_id = handler_utils.extractU32Field(payload, "\"pane_id\":") orelse 0;

    // Convert action to enum.
    const action: core.KeyEvent.Action = switch (action_raw) {
        0 => .press,
        1 => .release,
        2 => .repeat,
        else => .press,
    };

    // Decompose wire event to internal KeyEvent.
    const key = input.decomposeWireEvent(keycode, modifiers, action);

    // Resolve target session entry.
    const entry = handler_utils.resolveSessionByPaneId(
        params.context.session_manager,
        client,
        pane_id,
    ) orelse return;

    const client_id = client.getClientId();
    const pty_ops = params.context.pty_ops orelse &handler_utils.no_op_pty_ops;

    // Update latest_client_id on the session entry.
    entry.latest_client_id = client_id;

    // Preedit ownership transfer if a different client is composing.
    const session = &entry.session;
    if (session.preedit.owner) |owner| {
        if (owner != client_id) {
            var seq = params.header.sequence;
            const resolved_pane_id = if (pane_id == 0)
                entry.getPaneIdOrNone(session.focused_pane)
            else
                pane_id;
            var bc = BroadcastContext{
                .client_manager = params.context.client_manager,
                .session_id = session.session_id,
                .pane_id = resolved_pane_id,
                .sequence = &seq,
            };
            const focused = entry.focusedPane();
            const pty_fd: std.posix.fd_t = if (focused) |p| p.pty_fd else -1;
            procedures.ownershipTransferWithBroadcast(session, pty_fd, pty_ops, client_id, "replaced_by_other_client", &bc);
        }
    }

    const focused = entry.focusedPane();
    const pty_fd: std.posix.fd_t = if (focused) |p| p.pty_fd else -1;

    const preedit_dirty = processKeyEvent(session, key, pty_fd, pty_ops);

    // Broadcast preedit messages based on state transitions.
    if (preedit_dirty) {
        broadcastPreeditState(params, entry, session);
    }

    client.recordActivity();
}

/// Core logic for KeyEvent: route through Phase 0 + Phase 1, then consume
/// the result via Phase 2. Returns true if preedit state changed (dirty).
/// Extracted for unit testability — accepts explicit dependencies.
fn processKeyEvent(
    session: *core.session.Session,
    key: core.KeyEvent,
    pty_fd: std.posix.fd_t,
    pty_ops: *const interfaces.PtyOps,
) bool {
    // Route through Phase 0 + Phase 1.
    const result = input.handleKeyEvent(session.ime_engine, key, &toggle_bindings);

    // Phase 2: consume the result.
    switch (result) {
        .consumed => |ime_result| {
            _ = ime_consumer.consumeImeResult(ime_result, session, pty_fd, pty_ops, null);
            return false;
        },
        .bypassed => |bypass_key| {
            // Encode via ghostty key_encode and write to PTY.
            // Per daemon-architecture spec key_encode API:
            // Bypassed keys are encoded using ghostty's key_encode helper
            // and written directly to the PTY fd. The ghostty key_encode
            // API is a stateless pure function (ghostty helper functions).
            // TODO(Plan 12): Wire ghostty key_encode helper to encode
            // bypass_key and write to PTY. Currently no-op.
            _ = bypass_key;
            return false;
        },
        .processed => |ime_result| {
            return ime_consumer.consumeImeResult(ime_result, session, pty_fd, pty_ops, null);
        },
    }
}

/// Broadcasts preedit state changes (PreeditStart, PreeditUpdate, or PreeditEnd).
fn broadcastPreeditState(
    params: CategoryDispatchParams,
    entry: *server.state.session_entry.SessionEntry,
    session: *core.session.Session,
) void {
    const pane_id = entry.getPaneIdOrNone(session.focused_pane);
    var seq = params.header.sequence;

    if (session.current_preedit) |preedit_text| {
        // Active preedit -- send PreeditUpdate (or PreeditStart if new session).
        if (session.preedit.owner == null) {
            // New composition -- set owner and send PreeditStart.
            session.preedit.owner = params.client.getClientId();
            var start_buf: envelope.ScratchBuf = undefined;
            seq += 1;
            if (preedit_builder.buildPreeditStart(
                pane_id,
                params.client.getClientId(),
                session.getActiveInputMethod(),
                session.preedit.session_id,
                seq,
                &start_buf,
            )) |msg| {
                _ = broadcast_mod.broadcastToSession(
                    params.context.client_manager,
                    session.session_id,
                    msg,
                    null,
                );
            }
        }
        // Send PreeditUpdate.
        var update_buf: envelope.ScratchBuf = undefined;
        seq += 1;
        if (preedit_builder.buildPreeditUpdate(
            pane_id,
            session.preedit.session_id,
            preedit_text,
            seq,
            &update_buf,
        )) |msg| {
            _ = broadcast_mod.broadcastToSession(
                params.context.client_manager,
                session.session_id,
                msg,
                null,
            );
        }
    } else {
        // Preedit cleared -- send PreeditEnd if there was an owner.
        if (session.preedit.owner != null) {
            var end_buf: envelope.ScratchBuf = undefined;
            seq += 1;
            if (preedit_builder.buildPreeditEnd(
                pane_id,
                session.preedit.session_id,
                "committed",
                "",
                seq,
                &end_buf,
            )) |msg| {
                _ = broadcast_mod.broadcastToSession(
                    params.context.client_manager,
                    session.session_id,
                    msg,
                    null,
                );
            }
            session.preedit.owner = null;
            session.preedit.incrementSessionId();
        }
    }
}

// ── TextInput (0x0201) ─────────────────────────────────────────────────────

fn handleTextInput(params: CategoryDispatchParams) void {
    const payload = params.payload;

    const pane_id = handler_utils.extractU32Field(payload, "\"pane_id\":") orelse 0;
    const text = handler_utils.extractStringField(payload, "\"text\":\"") orelse return;

    // Validate text length.
    if (text.len > 65535) return;

    const entry = handler_utils.resolveSessionByPaneId(
        params.context.session_manager,
        params.client,
        pane_id,
    ) orelse return;
    const pane = resolvePaneInEntry(entry, pane_id) orelse return;
    const pty_ops = params.context.pty_ops orelse &handler_utils.no_op_pty_ops;

    processTextInput(pane.pty_fd, pty_ops, text);

    params.client.recordActivity();
}

/// Core logic for TextInput: write text directly to PTY (bypass IME).
/// Extracted for unit testability.
fn processTextInput(
    pty_fd: std.posix.fd_t,
    pty_ops: *const interfaces.PtyOps,
    text: []const u8,
) void {
    _ = pty_ops.write(pty_fd, text) catch {};
}

// ── PasteData (0x0205) ─────────────────────────────────────────────────────

fn handlePasteData(params: CategoryDispatchParams) void {
    const payload = params.payload;

    const pane_id = handler_utils.extractU32Field(payload, "\"pane_id\":") orelse 0;
    const bracketed_paste = handler_utils.extractBoolField(payload, "\"bracketed_paste\":") orelse false;
    const first_chunk = handler_utils.extractBoolField(payload, "\"first_chunk\":") orelse true;
    const final_chunk = handler_utils.extractBoolField(payload, "\"final_chunk\":") orelse true;
    const data = handler_utils.extractStringField(payload, "\"data\":\"") orelse return;

    const entry = handler_utils.resolveSessionByPaneId(
        params.context.session_manager,
        params.client,
        pane_id,
    ) orelse return;
    const pane = resolvePaneInEntry(entry, pane_id) orelse return;
    const pty_ops = params.context.pty_ops orelse &handler_utils.no_op_pty_ops;

    processPasteData(pane.pty_fd, pty_ops, data, bracketed_paste, first_chunk, final_chunk);

    params.client.recordActivity();
}

/// Core logic for PasteData: write paste data to PTY with optional bracketed
/// paste wrapping. Extracted for unit testability.
fn processPasteData(
    pty_fd: std.posix.fd_t,
    pty_ops: *const interfaces.PtyOps,
    data: []const u8,
    bracketed_paste: bool,
    first_chunk: bool,
    final_chunk: bool,
) void {
    // Bracketed paste prefix.
    if (first_chunk and bracketed_paste) {
        _ = pty_ops.write(pty_fd, "\x1b[200~") catch {};
    }

    // Write paste data.
    _ = pty_ops.write(pty_fd, data) catch {};

    // Bracketed paste suffix.
    if (final_chunk and bracketed_paste) {
        _ = pty_ops.write(pty_fd, "\x1b[201~") catch {};
    }
}

// ── FocusEvent (0x0206) ────────────────────────────────────────────────────

fn handleFocusEvent(params: CategoryDispatchParams) void {
    const payload = params.payload;

    const pane_id = handler_utils.extractU32Field(payload, "\"pane_id\":") orelse 0;
    const focused = handler_utils.extractBoolField(payload, "\"focused\":") orelse true;

    const entry = handler_utils.resolveSessionByPaneId(
        params.context.session_manager,
        params.client,
        pane_id,
    ) orelse return;
    const pane = resolvePaneInEntry(entry, pane_id) orelse return;
    const pty_ops = params.context.pty_ops orelse &handler_utils.no_op_pty_ops;

    processFocusEvent(pane.pty_fd, pty_ops, focused);

    params.client.recordActivity();
}

/// Core logic for FocusEvent: write focus reporting escape sequence to PTY.
/// Focus reporting (CSI ? 1004 h). Per protocol 04 focus event spec: the server
/// checks the terminal's focus_reporting mode before writing the escape
/// sequence. If focus reporting is not enabled, the escape is suppressed.
///
/// Per daemon-architecture spec ghostty helper functions: terminal mode query uses
/// ghostty's Options.fromTerminal() helper. Since the ghostty terminal
/// pointer is available on the Pane struct but the mode query API is not
/// yet ported, we write unconditionally as a safe fallback (terminal
/// applications ignore focus escapes when mode 1004 is not set).
/// Extracted for unit testability.
fn processFocusEvent(
    pty_fd: std.posix.fd_t,
    pty_ops: *const interfaces.PtyOps,
    focused: bool,
) void {
    // TODO(Plan 12): Check terminal focus_reporting mode via
    // Options.fromTerminal() and skip write if disabled.
    if (focused) {
        _ = pty_ops.write(pty_fd, "\x1b[I") catch {};
    } else {
        _ = pty_ops.write(pty_fd, "\x1b[O") catch {};
    }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn resolvePaneInEntry(
    entry: *server.state.session_entry.SessionEntry,
    pane_id: types.PaneId,
) ?*server.state.pane.Pane {
    if (pane_id == 0) {
        return entry.focusedPane();
    }
    if (entry.findPaneSlotByPaneId(pane_id)) |slot| {
        return entry.getPaneAtSlot(slot);
    }
    return null;
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "priorityOf: correct priority tiers per spec" {
    try std.testing.expectEqual(InputPriority.p1_key_text, priorityOf(.key_event));
    try std.testing.expectEqual(InputPriority.p1_key_text, priorityOf(.text_input));
    try std.testing.expectEqual(InputPriority.p4_paste, priorityOf(.paste_data));
    try std.testing.expectEqual(InputPriority.p5_focus, priorityOf(.focus_event));
}

test "toggle_bindings: contains right alt for korean_2set" {
    try std.testing.expectEqual(@as(usize, 1), toggle_bindings.len);
    try std.testing.expectEqual(@as(u16, 0xE6), toggle_bindings[0].hid_keycode);
    try std.testing.expectEqualSlices(u8, "korean_2set", toggle_bindings[0].toggle_method);
}

// ── Core Function Tests ─────────────────────────────────────────────────────

test "processTextInput: writes text directly to PTY" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    processTextInput(10, &pty_ops, "hello world");

    try std.testing.expectEqualSlices(u8, "hello world", mock_pty.written());
}

test "processTextInput: empty text writes nothing" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    processTextInput(10, &pty_ops, "");

    try std.testing.expectEqual(@as(usize, 0), mock_pty.written().len);
}

test "processPasteData: single chunk without bracketed paste" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    processPasteData(10, &pty_ops, "pasted text", false, true, true);

    try std.testing.expectEqualSlices(u8, "pasted text", mock_pty.written());
}

test "processPasteData: single chunk with bracketed paste" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    processPasteData(10, &pty_ops, "data", true, true, true);

    try std.testing.expectEqualSlices(u8, "\x1b[200~data\x1b[201~", mock_pty.written());
}

test "processPasteData: first chunk only with bracketed paste" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    processPasteData(10, &pty_ops, "chunk1", true, true, false);

    try std.testing.expectEqualSlices(u8, "\x1b[200~chunk1", mock_pty.written());
}

test "processPasteData: middle chunk with bracketed paste (no prefix or suffix)" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    processPasteData(10, &pty_ops, "chunk2", true, false, false);

    try std.testing.expectEqualSlices(u8, "chunk2", mock_pty.written());
}

test "processPasteData: final chunk with bracketed paste" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    processPasteData(10, &pty_ops, "chunk3", true, false, true);

    try std.testing.expectEqualSlices(u8, "chunk3\x1b[201~", mock_pty.written());
}

test "processFocusEvent: focused=true writes CSI I" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    processFocusEvent(10, &pty_ops, true);

    try std.testing.expectEqualSlices(u8, "\x1b[I", mock_pty.written());
}

test "processFocusEvent: focused=false writes CSI O" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    processFocusEvent(10, &pty_ops, false);

    try std.testing.expectEqualSlices(u8, "\x1b[O", mock_pty.written());
}

test "processKeyEvent: direct mode key produces committed text via PTY" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    const mock_ime = test_mod.mock_ime_engine;
    const session_mod = core.session;
    var mock = mock_ime.MockImeEngine{
        .active_input_method = "direct",
        .results = &[_]core.ImeResult{
            .{ .committed_text = "a", .preedit_changed = false },
        },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    const key = core.KeyEvent{ .hid_keycode = 0x04, .modifiers = .{}, .shift = false, .action = .press };
    const dirty = processKeyEvent(&session, key, 10, &pty_ops);

    try std.testing.expect(!dirty);
    try std.testing.expectEqualSlices(u8, "a", mock_pty.written());
}

test "processKeyEvent: korean mode key produces preedit change" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    const mock_ime = test_mod.mock_ime_engine;
    const session_mod = core.session;
    var mock = mock_ime.MockImeEngine{
        .active_input_method = "korean_2set",
        .results = &[_]core.ImeResult{
            .{ .preedit_text = "\xe3\x84\xb1", .preedit_changed = true },
        },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    const key = core.KeyEvent{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press };
    const dirty = processKeyEvent(&session, key, 10, &pty_ops);

    try std.testing.expect(dirty);
}

test "processKeyEvent: bypassed key (high HID keycode) does not write to PTY" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    const mock_ime = test_mod.mock_ime_engine;
    const session_mod = core.session;
    var mock = mock_ime.MockImeEngine{
        .active_input_method = "direct",
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    // HID keycode 0xFF is above HID_KEYCODE_MAX and should be bypassed.
    const key = core.KeyEvent{ .hid_keycode = 0xFF, .modifiers = .{}, .shift = false, .action = .press };
    const dirty = processKeyEvent(&session, key, 10, &pty_ops);

    try std.testing.expect(!dirty);
    try std.testing.expectEqual(@as(usize, 0), mock_pty.written().len);
}
