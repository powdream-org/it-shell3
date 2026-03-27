//! Test discovery root for libitshell3-protocol testing module.

const std = @import("std");

pub const helpers = @import("helpers.zig");

// Spec tests
pub const integration_spec = @import("spec/integration_spec_test.zig");

test {
    std.testing.refAllDecls(@This());
}
