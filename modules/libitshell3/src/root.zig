const std = @import("std");

pub const types = @import("core/types.zig");
pub const preedit_state = @import("core/preedit_state.zig");
pub const split_tree = @import("core/split_tree.zig");
pub const pane = @import("core/pane.zig");
pub const session = @import("core/session.zig");
pub const session_manager = @import("core/session_manager.zig");
pub const navigation = @import("core/navigation.zig");

pub const os_interfaces = @import("os/interfaces.zig");
pub const os_pty = @import("os/pty.zig");
pub const os_socket = @import("os/socket.zig");
pub const os_signals = @import("os/signals.zig");
pub const os_kqueue = @import("os/kqueue.zig");
pub const testing_helpers = @import("testing/helpers.zig");
pub const mock_os = @import("testing/mock_os.zig");
pub const listener = @import("server/listener.zig");
pub const signal_handler = @import("server/signal_handler.zig");
pub const handlers_signal = @import("server/handlers/signal.zig");
pub const handlers_pty_read = @import("server/handlers/pty_read.zig");
pub const handlers_client_accept = @import("server/handlers/client_accept.zig");
pub const handlers_client_read = @import("server/handlers/client_read.zig");
pub const client = @import("server/client.zig");
pub const event_loop = @import("server/event_loop.zig");

pub const ghostty_types = @import("ghostty/types.zig");
pub const ghostty_terminal = @import("ghostty/terminal.zig");
pub const ghostty_render_state = @import("ghostty/render_state.zig");
pub const ghostty_key_encoder = @import("ghostty/key_encoder.zig");
pub const ghostty_mouse_encoder = @import("ghostty/mouse_encoder.zig");
pub const ghostty_render_export = @import("ghostty/render_export.zig");
pub const ghostty_preedit_overlay = @import("ghostty/preedit_overlay.zig");

test {
    std.testing.refAllDecls(@This());
}
