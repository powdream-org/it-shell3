//! Server module for the it-shell3 daemon. Contains the event loop, signal
//! handling, client management, session/pane management, IME consumer/lifecycle/
//! procedures, ring buffer frame delivery, and client writer.

pub const os = struct {
    pub const interfaces = @import("os/interfaces.zig");
    pub const pty = @import("os/pty.zig");
    pub const kqueue = @import("os/kqueue.zig");
    pub const epoll = @import("os/epoll.zig");
    pub const platform_queue = @import("os/platform_queue.zig");
    pub const signals = @import("os/signals.zig");
    pub const priority_event_buffer = @import("os/priority_event_buffer.zig");
    pub const PlatformContext = platform_queue.PlatformContext;
    pub const PriorityEventBuffer = priority_event_buffer.PriorityEventBuffer;
};

pub const delivery = struct {
    pub const ring_buffer = @import("delivery/ring_buffer.zig");
    pub const direct_queue = @import("delivery/direct_queue.zig");
    pub const frame_serializer = @import("delivery/frame_serializer.zig");
    pub const pane_delivery = @import("delivery/pane_delivery.zig");
    pub const client_writer = @import("delivery/client_writer.zig");
    pub const client_state = @import("delivery/client_state.zig");
    pub const client_read = @import("delivery/client_read.zig");
};

pub const ime = struct {
    pub const consumer = @import("ime/consumer.zig");
    pub const lifecycle = @import("ime/lifecycle.zig");
    pub const procedures = @import("ime/procedures.zig");
    pub const ClientTracker = lifecycle.ClientTracker;
};

pub const state = struct {
    pub const pane = @import("state/pane.zig");
    pub const session_entry = @import("state/session_entry.zig");
    pub const session_manager = @import("state/session_manager.zig");
    pub const Pane = pane.Pane;
    pub const SessionEntry = session_entry.SessionEntry;
    pub const SessionManager = session_manager.SessionManager;
};

pub const handlers = struct {
    pub const event_loop = @import("handlers/event_loop.zig");
    pub const signal_handler = @import("handlers/signal_handler.zig");
    pub const pty_read = @import("handlers/pty_read.zig");
    pub const client_accept = @import("handlers/client_accept.zig");
    pub const EventLoop = event_loop.EventLoop;
    pub const Handler = event_loop.Handler;
};

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
    // Inline namespace structs need explicit traversal for test discovery
    std.testing.refAllDecls(os);
    std.testing.refAllDecls(delivery);
    std.testing.refAllDecls(ime);
    std.testing.refAllDecls(state);
    std.testing.refAllDecls(handlers);
}
