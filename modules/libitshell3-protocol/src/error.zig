const std = @import("std");

/// Per-response status codes. See the server-client-protocols session/pane management spec.
pub const StatusCode = enum(u32) {
    ok = 0,
    not_found = 1,
    already_exists = 2,
    too_small = 3,
    processes_running = 4,
    access_denied = 5,
    invalid_argument = 6,
    internal_error = 7,
    pane_limit_exceeded = 8,
    _,
};

/// Protocol-level error codes. See the server-client-protocols handshake spec.
pub const ErrorCode = enum(u32) {
    // Protocol errors (0x01-0xFF)
    bad_magic = 0x00000001,
    unsupported_version = 0x00000002,
    bad_msg_type = 0x00000003,
    payload_too_large = 0x00000004,
    invalid_state = 0x00000005,
    malformed_payload = 0x00000006,
    protocol_error = 0x00000007,
    bad_encoding = 0x00000008,

    // Handshake errors (0x100-0x1FF)
    version_mismatch = 0x00000100,
    auth_failed = 0x00000101,
    capability_required = 0x00000102,

    // Session errors (0x200-0x2FF)
    session_not_found = 0x00000200,
    session_already_attached = 0x00000201,
    session_limit = 0x00000202,
    access_denied = 0x00000203,

    // Pane errors (0x300-0x3FF)
    pane_not_found = 0x00000300,
    pane_exited = 0x00000301,
    split_failed = 0x00000302,

    // Resource errors (0x600-0x6FF)
    resource_exhausted = 0x00000600,
    rate_limited = 0x00000601,

    internal = 0xFFFFFFFF,
    _,

    pub fn isFatal(self: ErrorCode) bool {
        const code = @intFromEnum(self);
        // Protocol errors (0x01-0xFF) and handshake errors (0x100-0x1FF) are fatal
        return (code >= 0x01 and code <= 0xFF) or (code >= 0x100 and code <= 0x1FF);
    }
};

/// Error message payload (0x00FF)
pub const ErrorResponse = struct {
    error_code: u32,
    ref_sequence: u32 = 0,
    detail: []const u8 = "",
};

test "ErrorCode.isFatal: protocol errors are fatal" {
    try std.testing.expect(ErrorCode.bad_magic.isFatal());
    try std.testing.expect(ErrorCode.unsupported_version.isFatal());
    try std.testing.expect(ErrorCode.malformed_payload.isFatal());
}

test "ErrorCode.isFatal: handshake errors are fatal" {
    try std.testing.expect(ErrorCode.version_mismatch.isFatal());
    try std.testing.expect(ErrorCode.auth_failed.isFatal());
    try std.testing.expect(ErrorCode.capability_required.isFatal());
}

test "ErrorCode.isFatal: session and pane errors are not fatal" {
    try std.testing.expect(!ErrorCode.session_not_found.isFatal());
    try std.testing.expect(!ErrorCode.pane_not_found.isFatal());
    try std.testing.expect(!ErrorCode.resource_exhausted.isFatal());
}
