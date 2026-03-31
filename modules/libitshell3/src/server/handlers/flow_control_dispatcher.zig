//! Stub dispatcher for flow control and auxiliary messages (0x05xx range).
//! Pre-wired entry point for Plan 9 implementation.
//!
//! Per protocol 01-protocol-overview (Flow Control & Backpressure range
//! 0x0500-0x05FF).

const message_dispatcher = @import("message_dispatcher.zig");
const CategoryDispatchParams = message_dispatcher.CategoryDispatchParams;

/// Dispatches a flow-control-category message. Currently a no-op stub.
pub fn dispatch(_: CategoryDispatchParams) void {
    // TODO(Plan 9): Implement flow control handlers (PauseOutput,
    // ResumeOutput, BackpressureNotify, etc.).
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "flow_control dispatch: stub does not crash on any flow control message" {
    const protocol = @import("itshell3_protocol");
    const Header = protocol.header.Header;
    const params = CategoryDispatchParams{
        .context = undefined,
        .client = undefined,
        .client_slot = 0,
        .msg_type = .pause_pane,
        .header = Header{
            .msg_type = @intFromEnum(protocol.message_type.MessageType.pause_pane),
            .flags = .{},
            .payload_length = 0,
            .sequence = 1,
        },
        .payload = "",
    };
    dispatch(params);
}
