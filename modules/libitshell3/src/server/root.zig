pub const event_loop = @import("event_loop.zig");
pub const signal_handler = @import("signal_handler.zig");
pub const client_writer = @import("client_writer.zig");
pub const ring_buffer = @import("ring_buffer.zig");
pub const frame_serializer = @import("frame_serializer.zig");
pub const direct_queue = @import("direct_queue.zig");
pub const pane_delivery = @import("pane_delivery.zig");
pub const ime_consumer = @import("ime_consumer.zig");
pub const ime_lifecycle = @import("ime_lifecycle.zig");
pub const ime_procedures = @import("ime_procedures.zig");

// Handlers
pub const handlers = struct {
    pub const pty_read = @import("handlers/pty_read.zig");
    pub const client_accept = @import("handlers/client_accept.zig");
    pub const client_read = @import("handlers/client_read.zig");
    pub const signal = @import("handlers/signal.zig");
};

// Test files (imported for test discovery)
pub const ring_buffer_integration_test = @import("ring_buffer_integration_test.zig");
pub const ring_buffer_spec_compliance_test = @import("ring_buffer_spec_compliance_test.zig");

// Re-exports
pub const EventLoop = event_loop.EventLoop;
pub const ClientEntry = event_loop.ClientEntry;
pub const ClientTracker = ime_lifecycle.ClientTracker;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
