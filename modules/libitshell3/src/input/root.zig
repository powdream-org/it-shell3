pub const wire_decompose = @import("wire_decompose.zig");
pub const key_router = @import("key_router.zig");

// Re-exports
pub const decomposeWireEvent = wire_decompose.decomposeWireEvent;
pub const routeKeyEvent = key_router.routeKeyEvent;
pub const RouteResult = key_router.RouteResult;
pub const ToggleBinding = key_router.ToggleBinding;
