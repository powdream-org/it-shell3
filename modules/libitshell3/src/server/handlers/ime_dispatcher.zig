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
    const pty_ops = params.context.pty_ops orelse {
        // No PTY ops available -- cannot write committed text.
        // Still perform the switch logic without PTY write.
        procedures.onInputMethodSwitchWithBroadcast(
            &entry.session,
            input_method,
            commit_current,
            pty_fd,
            // Use a minimal no-op pty ops. The procedure will try to write
            // but the write call will be skipped if no committed text.
            &handler_utils.no_op_pty_ops,
            &bc,
        );
        client.recordActivity();
        return;
    };

    procedures.onInputMethodSwitchWithBroadcast(
        &entry.session,
        input_method,
        commit_current,
        pty_fd,
        pty_ops,
        &bc,
    );

    client.recordActivity();
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
