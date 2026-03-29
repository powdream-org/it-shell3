//! RLIMIT_NOFILE advisory check. Reads the soft limit at startup and attempts
//! to raise it to the hard limit if possible.
//!
//! Per daemon-behavior impl-constraints daemon-lifecycle spec.

const std = @import("std");
const builtin = @import("builtin");

/// Minimum recommended file descriptor limit for the daemon.
/// Accounts for: listen fd + max clients (64) + max PTYs (16 * 8 sessions)
/// + signal fds + timer fds + headroom.
pub const RECOMMENDED_MIN_FDS: u64 = 256;

/// Result of checking and adjusting the file descriptor limit.
pub const ResourceCheckResult = struct {
    /// Original soft limit before adjustment.
    original_soft: u64,
    /// Current soft limit after adjustment (may be same as original).
    current_soft: u64,
    /// Hard limit.
    hard: u64,
    /// Whether the limit was raised.
    raised: bool,
    /// Whether the current limit is below recommended minimum.
    below_recommended: bool,
};

/// Check the current RLIMIT_NOFILE and attempt to raise the soft limit
/// to the hard limit if possible. Pure utility function with no side effects
/// beyond the setrlimit syscall.
pub fn checkAndAdjustFileDescriptorLimit() ResourceCheckResult {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) {
        return .{
            .original_soft = 0,
            .current_soft = 0,
            .hard = 0,
            .raised = false,
            .below_recommended = false,
        };
    }

    var rlim = std.posix.getrlimit(.NOFILE) catch {
        return .{
            .original_soft = 0,
            .current_soft = 0,
            .hard = 0,
            .raised = false,
            .below_recommended = true,
        };
    };

    const original_soft = rlim.cur;
    const hard = rlim.max;
    var raised = false;

    if (original_soft < hard) {
        rlim.cur = hard;
        if (std.posix.setrlimit(.NOFILE, rlim)) {
            raised = true;
        } else |_| {}
    }

    const current_soft = if (raised) hard else original_soft;

    return .{
        .original_soft = original_soft,
        .current_soft = current_soft,
        .hard = hard,
        .raised = raised,
        .below_recommended = current_soft < RECOMMENDED_MIN_FDS,
    };
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "checkAndAdjustFileDescriptorLimit: returns valid result" {
    if (comptime builtin.os.tag != .macos and builtin.os.tag != .linux) return;

    const result = checkAndAdjustFileDescriptorLimit();
    // On any real system, the hard limit should be > 0.
    try std.testing.expect(result.hard > 0);
    // current_soft should be >= original_soft (we only raise, never lower).
    try std.testing.expect(result.current_soft >= result.original_soft);
    // current_soft should be <= hard.
    try std.testing.expect(result.current_soft <= result.hard);
}

test "RECOMMENDED_MIN_FDS: is reasonable" {
    try std.testing.expect(RECOMMENDED_MIN_FDS >= 128);
    try std.testing.expect(RECOMMENDED_MIN_FDS <= 4096);
}
