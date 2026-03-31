//! Stub dispatcher for render state messages (0x03xx range).
//! Pre-wired entry point for Plan 9 implementation.
//!
//! Per protocol 01-protocol-overview (Render State range 0x0300-0x03FF).

const message_dispatcher = @import("message_dispatcher.zig");
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;

/// Dispatches a render-category message. Currently a no-op stub.
pub fn dispatch(_: CategoryDispatchParams) void {
    // TODO(Plan 9): Implement render state handlers (FrameUpdate,
    // ScrollRequest, SearchRequest, etc.).
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "render dispatch: stub does not crash on any render message" {
    const protocol = @import("itshell3_protocol");
    const Header = protocol.header.Header;
    const params = CategoryDispatchParams{
        .context = undefined,
        .client = undefined,
        .client_slot = 0,
        .msg_type = .frame_update,
        .header = Header{
            .msg_type = @intFromEnum(protocol.message_type.MessageType.frame_update),
            .flags = .{},
            .payload_length = 0,
            .sequence = 1,
        },
        .payload = "",
    };
    dispatch(params);
}
