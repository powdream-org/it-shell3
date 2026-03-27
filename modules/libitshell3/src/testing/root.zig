pub const helpers = @import("helpers.zig");
pub const mock_os = @import("mock_os.zig");
pub const mock_ime_engine = @import("mock_ime_engine.zig");
pub const mock_pty_writer = @import("mock_pty_writer.zig");

// Spec compliance test files
pub const ime_types_spec_test = @import("ime_types_spec_test.zig");
pub const session_ime_spec_test = @import("session_ime_spec_test.zig");
pub const wire_decompose_spec_test = @import("wire_decompose_spec_test.zig");
pub const key_router_spec_test = @import("key_router_spec_test.zig");
pub const ime_consumer_spec_test = @import("ime_consumer_spec_test.zig");
pub const ime_lifecycle_spec_test = @import("ime_lifecycle_spec_test.zig");
pub const ime_procedures_spec_test = @import("ime_procedures_spec_test.zig");
pub const mock_ime_engine_spec_test = @import("mock_ime_engine_spec_test.zig");

// Re-exports
pub const MockImeEngine = mock_ime_engine.MockImeEngine;
pub const MockPtyWriter = mock_pty_writer.MockPtyWriter;
pub const testImeEngine = helpers.testImeEngine;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
