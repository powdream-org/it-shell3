//! Dispatcher for CJK and IME messages (0x04xx range).
//! Handles InputMethodSwitch (0x0404) and AmbiguousWidthConfig (0x0406).
//!
//! Per protocol 05-cjk-preedit-protocol.

const std = @import("std");
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;
const message_dispatcher = @import("message_dispatcher.zig");
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;
const handler_utils = @import("handler_utils.zig");
const envelope = @import("protocol_envelope.zig");
const ime_error_builder = @import("ime_error_builder.zig");
const ErrorCode = ime_error_builder.ErrorCode;
const server = @import("itshell3_server");
const procedures = server.ime.procedures;
const BroadcastContext = procedures.BroadcastContext;
const core = @import("itshell3_core");
const types = core.types;

/// Dispatches an IME-category message.
pub fn dispatch(params: CategoryDispatchParams) void {
    switch (params.msg_type) {
        .input_method_switch => handleInputMethodSwitch(params),
        .ambiguous_width_config => handleAmbiguousWidthConfig(params),
        else => {},
    }
}

/// Handles InputMethodSwitch (0x0404, C->S).
fn handleInputMethodSwitch(params: CategoryDispatchParams) void {
    const client = params.client;
    const payload = params.payload;
    const sequence = params.header.sequence;

    const pane_id = handler_utils.extractU32Field(payload, "\"pane_id\":") orelse 0;
    const commit_current = handler_utils.extractBoolField(payload, "\"commit_current\":") orelse true;
    const input_method = handler_utils.extractStringField(payload, "\"input_method\":\"") orelse "direct";

    // Resolve session from pane_id.
    const entry = handler_utils.resolveSessionByPaneId(
        params.context.session_manager,
        client,
        pane_id,
    ) orelse {
        var buf: envelope.ScratchBuf = undefined;
        if (ime_error_builder.buildIMEError(pane_id, .pane_not_found, "Pane does not exist", sequence, &buf)) |msg| {
            client.enqueueDirect(msg) catch {};
        }
        return;
    };

    // Validate input method is supported.
    if (!isSupportedInputMethod(input_method)) {
        var buf: envelope.ScratchBuf = undefined;
        if (ime_error_builder.buildIMEError(pane_id, .unknown_input_method, "Unknown input method", sequence, &buf)) |msg| {
            client.enqueueDirect(msg) catch {};
        }
        return;
    }

    // Build broadcast context.
    var seq = sequence;
    var bc = BroadcastContext{
        .client_manager = params.context.client_manager,
        .session_id = entry.session.session_id,
        .pane_id = pane_id,
        .sequence = &seq,
    };

    // Resolve PTY fd and ops for the focused pane.
    const focused_pane = entry.focusedPane();
    const pty_fd: std.posix.fd_t = if (focused_pane) |p| p.pty_fd else -1;
    const pty_ops = params.context.pty_ops orelse &handler_utils.no_op_pty_ops;

    processInputMethodSwitch(&entry.session, input_method, commit_current, pty_fd, pty_ops, &bc);

    client.recordActivity();
}

/// Core logic for InputMethodSwitch: delegates to the IME procedure with
/// explicit dependencies. Extracted for unit testability.
fn processInputMethodSwitch(
    session: *core.session.Session,
    input_method: []const u8,
    commit_current: bool,
    pty_fd: std.posix.fd_t,
    pty_ops: *const server.os.interfaces.PtyOps,
    broadcast_context: ?*const BroadcastContext,
) void {
    procedures.onInputMethodSwitchWithBroadcast(
        session,
        input_method,
        commit_current,
        pty_fd,
        pty_ops,
        broadcast_context,
    );
}

/// Handles AmbiguousWidthConfig (0x0406).
fn handleAmbiguousWidthConfig(params: CategoryDispatchParams) void {
    // AmbiguousWidthConfig pass-through to terminal instances.
    // TODO(Plan 9): Apply ambiguous_width to ghostty Terminal instances
    // once frame export pipeline is wired.
    params.client.recordActivity();
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Whether an input method identifier is supported in v1.
fn isSupportedInputMethod(method: []const u8) bool {
    return std.mem.eql(u8, method, "direct") or
        std.mem.eql(u8, method, "korean_2set");
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "isSupportedInputMethod: direct and korean_2set are supported" {
    try std.testing.expect(isSupportedInputMethod("direct"));
    try std.testing.expect(isSupportedInputMethod("korean_2set"));
    try std.testing.expect(!isSupportedInputMethod("japanese_romaji"));
    try std.testing.expect(!isSupportedInputMethod("foobar"));
}

// ── Core Function Tests ─────────────────────────────────────────────────────

test "processInputMethodSwitch: switches from direct to korean_2set" {
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

    processInputMethodSwitch(&session, "korean_2set", true, -1, &pty_ops, null);

    try std.testing.expectEqual(@as(usize, 1), mock.set_active_input_method_count);
    try std.testing.expectEqualSlices(u8, "korean_2set", session.getActiveInputMethod());
}

test "processInputMethodSwitch: commit_current=true flushes composition" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    const mock_ime = test_mod.mock_ime_engine;
    const session_mod = core.session;
    var mock = mock_ime.MockImeEngine{
        .active_input_method = "korean_2set",
        .set_active_input_method_result = .{ .committed_text = "flushed", .preedit_changed = true },
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 5;
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    processInputMethodSwitch(&session, "direct", true, 10, &pty_ops, null);

    try std.testing.expectEqualSlices(u8, "flushed", mock_pty.written());
    try std.testing.expect(session.preedit.owner == null);
}

test "processInputMethodSwitch: commit_current=false resets without flushing" {
    const test_mod = @import("itshell3_testing");
    const MockPtyOps = test_mod.mock_os.MockPtyOps;
    const mock_ime = test_mod.mock_ime_engine;
    const session_mod = core.session;
    var mock = mock_ime.MockImeEngine{
        .active_input_method = "korean_2set",
    };
    var session = session_mod.Session.init(1, "test", 0, mock.engine(), 0);
    session.preedit.owner = 5;
    session.setPreedit("composing");
    var mock_pty = MockPtyOps{};
    const pty_ops = mock_pty.ops();

    processInputMethodSwitch(&session, "direct", false, 10, &pty_ops, null);

    try std.testing.expectEqual(@as(usize, 1), mock.reset_count);
    try std.testing.expectEqual(@as(usize, 0), mock.flush_count);
    try std.testing.expect(session.preedit.owner == null);
    try std.testing.expectEqualSlices(u8, "direct", session.getActiveInputMethod());
}
