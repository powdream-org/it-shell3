const std = @import("std");

/// General capability flags (Doc 02 §4)
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

/// Render capability flags (Doc 02 §5.1)
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

test "Capability enum values exist" {
    // Spot-check all spec-defined capability names
    _ = Capability.clipboard_sync;
    _ = Capability.mouse;
    _ = Capability.selection;
    _ = Capability.search;
    _ = Capability.fd_passing;
    _ = Capability.agent_detection;
    _ = Capability.flow_control;
    _ = Capability.pixel_dimensions;
    _ = Capability.sixel;
    _ = Capability.kitty_graphics;
    _ = Capability.notifications;
}

test "RenderCapability enum values exist" {
    _ = RenderCapability.cell_data;
    _ = RenderCapability.dirty_tracking;
    _ = RenderCapability.cursor_style;
    _ = RenderCapability.true_color;
    _ = RenderCapability.@"256_color";
    _ = RenderCapability.underline_styles;
    _ = RenderCapability.hyperlinks;
    _ = RenderCapability.vt_fallback;
}
