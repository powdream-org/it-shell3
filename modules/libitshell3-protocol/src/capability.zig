const std = @import("std");

/// General capability flags. See the server-client-protocols capability spec.
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

/// Render capability flags. See the server-client-protocols capability spec.
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
