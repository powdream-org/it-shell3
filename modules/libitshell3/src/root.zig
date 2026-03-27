const std = @import("std");

// core/
pub const types = @import("core/types.zig");
pub const preedit_state = @import("core/preedit_state.zig");
pub const split_tree = @import("core/split_tree.zig");
pub const pane = @import("core/pane.zig");
pub const session = @import("core/session.zig");
pub const session_manager = @import("core/session_manager.zig");
pub const navigation = @import("core/navigation.zig");
pub const ime_engine = @import("core/ime_engine.zig");

// os/
pub const os_interfaces = @import("os/interfaces.zig");
pub const os_pty = @import("os/pty.zig");
pub const os_signals = @import("os/signals.zig");
pub const os_kqueue = @import("os/kqueue.zig");

// input/
pub const input_wire_decompose = @import("input/wire_decompose.zig");
pub const input_key_router = @import("input/key_router.zig");

// server/
pub const signal_handler = @import("server/signal_handler.zig");
pub const handlers_signal = @import("server/handlers/signal.zig");
pub const handlers_pty_read = @import("server/handlers/pty_read.zig");
pub const handlers_client_accept = @import("server/handlers/client_accept.zig");
pub const handlers_client_read = @import("server/handlers/client_read.zig");
pub const event_loop = @import("server/event_loop.zig");
pub const ring_buffer = @import("server/ring_buffer.zig");
pub const frame_serializer = @import("server/frame_serializer.zig");
pub const direct_queue = @import("server/direct_queue.zig");
pub const client_writer = @import("server/client_writer.zig");
pub const pane_delivery = @import("server/pane_delivery.zig");
pub const ring_buffer_integration_test = @import("server/ring_buffer_integration_test.zig");
pub const ring_buffer_spec_compliance_test = @import("server/ring_buffer_spec_compliance_test.zig");
pub const ime_consumer = @import("server/ime_consumer.zig");
pub const ime_lifecycle = @import("server/ime_lifecycle.zig");
pub const ime_procedures = @import("server/ime_procedures.zig");

// testing/
pub const testing_helpers = @import("testing/helpers.zig");
pub const mock_os = @import("testing/mock_os.zig");
pub const mock_ime_engine = @import("testing/mock_ime_engine.zig");
pub const mock_pty_writer = @import("testing/mock_pty_writer.zig");

// ghostty helpers
pub const ghostty_types = @import("ghostty/types.zig");
pub const ghostty_terminal = @import("ghostty/terminal.zig");
pub const ghostty_render_state = @import("ghostty/render_state.zig");
pub const ghostty_key_encoder = @import("ghostty/key_encoder.zig");
pub const ghostty_render_export = @import("ghostty/render_export.zig");
pub const ghostty_preedit_overlay = @import("ghostty/preedit_overlay.zig");

// external
pub const protocol = @import("itshell3_protocol");

test {
    std.testing.refAllDecls(@This());
}
