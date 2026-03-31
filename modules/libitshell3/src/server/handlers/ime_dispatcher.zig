//! Stub dispatcher for CJK and IME messages (0x04xx range).
//! Pre-wired entry point for Plan 8 implementation.
//!
//! Per protocol 01-protocol-overview (CJK & IME range 0x0400-0x04FF).

const message_dispatcher = @import("message_dispatcher.zig");
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;

/// Dispatches an IME-category message. Currently a no-op stub.
pub fn dispatch(_: CategoryDispatchParams) void {
    // TODO(Plan 8): Implement IME handlers (InputMethodSwitch,
    // PreeditState, CommitText, etc.).
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "dispatch: stub does not crash on any IME message" {
    const protocol = @import("itshell3_protocol");
    const Header = protocol.header.Header;
    const params = CategoryDispatchParams{
        .context = undefined,
        .client = undefined,
        .client_slot = 0,
        .msg_type = .input_method_switch,
        .header = Header{
            .msg_type = @intFromEnum(protocol.message_type.MessageType.input_method_switch),
            .flags = .{},
            .payload_length = 0,
            .sequence = 1,
        },
        .payload = "",
    };
    dispatch(params);
}
