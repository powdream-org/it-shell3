//! Server module for the it-shell3 daemon. Contains the event loop, signal
//! handling, client management, session/pane management, IME consumer/lifecycle/
//! procedures, ring buffer frame delivery, and client writer.

pub const os = @import("os/root.zig");
pub const event_loop = @import("event_loop.zig");
pub const signal_handler = @import("signal_handler.zig");
pub const client_writer = @import("client_writer.zig");
pub const ring_buffer = @import("ring_buffer.zig");
pub const frame_serializer = @import("frame_serializer.zig");
pub const direct_queue = @import("direct_queue.zig");
pub const pane_delivery = @import("pane_delivery.zig");
pub const ime_consumer = @import("ime/consumer.zig");
pub const ime_lifecycle = @import("ime/lifecycle.zig");
pub const ime_procedures = @import("ime/procedures.zig");
pub const pane = @import("state/pane.zig");
pub const session_entry = @import("state/session_entry.zig");
pub const session_manager = @import("state/session_manager.zig");
pub const client_state = @import("client_state.zig");

// Handlers (flattened from former handlers/ subdirectory)
pub const pty_read = @import("pty_read.zig");
pub const client_accept = @import("client_accept.zig");
pub const client_read = @import("client_read.zig");

// Re-exports
pub const EventLoop = event_loop.EventLoop;
pub const ClientEntry = client_state.ClientEntry;
pub const ClientTracker = ime_lifecycle.ClientTracker;
pub const Pane = pane.Pane;
pub const SessionEntry = session_entry.SessionEntry;
pub const SessionManager = session_manager.SessionManager;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
