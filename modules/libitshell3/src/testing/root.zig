//! Testing module. Mock implementations and spec compliance test files for
//! deterministic unit testing of the libitshell3 daemon.

pub const helpers = @import("helpers.zig");

// Mocks
pub const mock_os = @import("mocks/mock_os.zig");
pub const mock_ime_engine = @import("mocks/mock_ime_engine.zig");

// Spec compliance tests
pub const ime_types_spec_test = @import("spec/ime_types_spec_test.zig");
pub const session_ime_spec_test = @import("spec/session_ime_spec_test.zig");
pub const wire_decompose_spec_test = @import("spec/wire_decompose_spec_test.zig");
pub const key_router_spec_test = @import("spec/key_router_spec_test.zig");
pub const ime_consumer_spec_test = @import("spec/ime_consumer_spec_test.zig");
pub const ime_lifecycle_spec_test = @import("spec/ime_lifecycle_spec_test.zig");
pub const ime_procedures_spec_test = @import("spec/ime_procedures_spec_test.zig");
pub const mock_ime_engine_spec_test = @import("spec/mock_ime_engine_spec_test.zig");
pub const ring_buffer_spec_compliance_test = @import("spec/ring_buffer_spec_compliance_test.zig");
pub const ring_buffer_integration_test = @import("spec/ring_buffer_integration_test.zig");
pub const event_loop_spec_test = @import("spec/event_loop_spec_test.zig");
pub const client_manager_spec_test = @import("spec/client_manager_spec_test.zig");
pub const handshake_spec_test = @import("spec/handshake_spec_test.zig");
pub const heartbeat_spec_test = @import("spec/heartbeat_spec_test.zig");
pub const message_dispatch_spec_test = @import("spec/message_dispatch_spec_test.zig");
pub const broadcast_spec_test = @import("spec/broadcast_spec_test.zig");
pub const client_read_spec_test = @import("spec/client_read_spec_test.zig");
pub const timer_handler_spec_test = @import("spec/timer_handler_spec_test.zig");
pub const connection_state_spec_test = @import("spec/connection_state_spec_test.zig");
pub const notification_spec_test = @import("spec/notification_spec_test.zig");
pub const pane_crud_spec_test = @import("spec/pane_crud_spec_test.zig");
pub const protocol_envelope_spec_test = @import("spec/protocol_envelope_spec_test.zig");
pub const session_attachment_spec_test = @import("spec/session_attachment_spec_test.zig");
pub const session_crud_spec_test = @import("spec/session_crud_spec_test.zig");
pub const category_dispatch_spec_test = @import("spec/category_dispatch_spec_test.zig");

// Re-exports
pub const MockImeEngine = mock_ime_engine.MockImeEngine;
pub const MockPtyOps = mock_os.MockPtyOps;
pub const testImeEngine = helpers.testImeEngine;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
