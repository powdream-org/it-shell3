//! OS interface module. Defines vtables for PTY, event loop, and signal
//! operations, with both real implementations and mock implementations for
//! testing. Event backends (kqueue/epoll) are in the event_backend/ subdirectory.

pub const interfaces = @import("interfaces.zig");
pub const pty = @import("pty.zig");
pub const event_backend = struct {
    pub const kqueue = @import("event_backend/kqueue.zig");
    pub const epoll = @import("event_backend/epoll.zig");
    pub const platform = @import("event_backend/platform.zig");
};
pub const signals = @import("signals.zig");
pub const priority_event_buffer = @import("priority_event_buffer.zig");

// Convenience re-exports
pub const PtyOps = interfaces.PtyOps;
pub const EventLoopOps = interfaces.EventLoopOps;
pub const SignalOps = interfaces.SignalOps;
pub const Filter = interfaces.Filter;
pub const Event = interfaces.Event;
pub const EventTarget = interfaces.EventTarget;
pub const PriorityEventBuffer = priority_event_buffer.PriorityEventBuffer;
pub const PlatformContext = event_backend.platform.PlatformContext;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
