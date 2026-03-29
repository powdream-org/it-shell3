//! Capability enums negotiated during the client-server handshake.
//! See the server-client-protocols capability spec for semantics.

const std = @import("std");

/// General protocol capability negotiated in ClientHello/ServerHello.
pub const Capability = enum {
    clipboard_sync,
    mouse,
    selection,
    search,
    fd_passing,
    agent_detection,
    flow_control,
    pixel_dimensions,
    sixel,
    kitty_graphics,
    notifications,
};

/// Render-specific capability negotiated in ClientHello/ServerHello.
pub const RenderCapability = enum {
    cell_data,
    dirty_tracking,
    cursor_style,
    true_color,
    @"256_color",
    underline_styles,
    hyperlinks,
    vt_fallback,
};
