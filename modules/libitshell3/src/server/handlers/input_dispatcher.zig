//! Stub dispatcher for input forwarding messages (0x02xx range).
//! Pre-wired entry point for Plan 8 implementation.
//!
//! Per protocol 01-protocol-overview (Input Forwarding range 0x0200-0x02FF).

const message_dispatcher = @import("message_dispatcher.zig");
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;

/// Dispatches an input-category message. Currently a no-op stub.
pub fn dispatch(_: CategoryDispatchParams) void {
    // TODO(Plan 8): Implement input forwarding handlers (KeyEvent, TextInput,
    // MouseButton, MouseMove, PasteData).
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "dispatch: stub does not crash on any input message" {
    const protocol = @import("itshell3_protocol");
    const Header = protocol.header.Header;
    const params = CategoryDispatchParams{
        .context = undefined,
        .client = undefined,
        .client_slot = 0,
        .msg_type = .key_event,
        .header = Header{
            .msg_type = @intFromEnum(protocol.message_type.MessageType.key_event),
            .flags = .{},
            .payload_length = 0,
            .sequence = 1,
        },
        .payload = "",
    };
    dispatch(params);
}
