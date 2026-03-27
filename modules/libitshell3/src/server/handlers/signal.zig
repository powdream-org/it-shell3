/// Re-exports from signal_handler.zig.
/// Keeps the handlers/ directory structure consistent with the plan.
const signal_handler = @import("../signal_handler.zig");

pub const handleSignalEvent = signal_handler.handleSignalEvent;
