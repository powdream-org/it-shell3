//! Input routing module. Handles key event decomposition from wire format and
//! routes keys through Phase 0 (shortcut check) and Phase 1 (IME processing).

pub const wire_decompose = @import("wire_decompose.zig");
pub const key_router = @import("key_router.zig");

// Re-exports
pub const decomposeWireEvent = wire_decompose.decomposeWireEvent;
pub const handleKeyEvent = key_router.handleKeyEvent;
pub const RouteResult = key_router.RouteResult;
pub const ToggleBinding = key_router.ToggleBinding;

/// Backward-compatible alias for spec tests pending rename.
pub const routeKeyEvent = key_router.handleKeyEvent;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
