pub const interfaces = @import("interfaces.zig");
pub const pty = @import("pty.zig");
pub const kqueue = @import("kqueue.zig");
pub const signals = @import("signals.zig");

// Convenience re-exports
pub const PtyOps = interfaces.PtyOps;
pub const EventLoopOps = interfaces.EventLoopOps;
pub const SignalOps = interfaces.SignalOps;
pub const KqueueContext = kqueue.KqueueContext;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
