//! Test discovery root for libitshell3-ime testing module.

const std = @import("std");

pub const helpers = @import("helpers.zig");

// Mocks
pub const mock_engine = @import("mocks/mock_engine.zig");

// Spec tests
pub const hangul_engine_spec = @import("spec/hangul_engine_spec_test.zig");

test {
    std.testing.refAllDecls(@This());
}
