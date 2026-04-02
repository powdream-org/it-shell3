//! Preedit inactivity timeout tracking. Detects stale compositions when
//! no input arrives from the preedit owner within 30 seconds, triggering
//! a commit-and-end sequence.
//!
//! Per daemon-behavior event-handling (preedit inactivity timeout) and
//! daemon-behavior policies-and-procedures (inactivity timeout 30s).

const std = @import("std");

/// Inactivity timeout in milliseconds. If no input arrives from the preedit
/// owner within this duration, the composition is committed and ended.
pub const PREEDIT_INACTIVITY_TIMEOUT_MS: u32 = 30_000;

/// Tracks preedit inactivity state for a single session. The event loop is
/// responsible for calling `checkTimeout` at appropriate intervals; this
/// module provides the state tracking and timeout detection logic.
pub const InactivityTimer = struct {
    /// Timestamp of the last input from the preedit owner, in milliseconds
    /// since epoch. null = no active composition being tracked.
    last_input_timestamp: ?i64,

    /// Whether the timer is currently active (tracking a composition).
    active: bool,

    pub fn init() InactivityTimer {
        return .{
            .last_input_timestamp = null,
            .active = false,
        };
    }

    /// Starts or resets the timer. Called on every KeyEvent from the preedit owner.
    pub fn reset(self: *InactivityTimer, timestamp: i64) void {
        self.last_input_timestamp = timestamp;
        self.active = true;
    }

    /// Cancels the timer. Called when preedit ends for any reason.
    pub fn cancel(self: *InactivityTimer) void {
        self.last_input_timestamp = null;
        self.active = false;
    }

    /// Whether the inactivity timeout has elapsed. Returns true if the
    /// timer is active and `current_time - last_input_timestamp >= 30s`.
    pub fn isTimedOut(self: *const InactivityTimer, current_time: i64) bool {
        if (!self.active) return false;
        const last = self.last_input_timestamp orelse return false;
        return (current_time - last) >= PREEDIT_INACTIVITY_TIMEOUT_MS;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

test "InactivityTimer.init: starts inactive" {
    const timer = InactivityTimer.init();
    try std.testing.expect(!timer.active);
    try std.testing.expect(timer.last_input_timestamp == null);
}

test "InactivityTimer.reset: activates and sets timestamp" {
    var timer = InactivityTimer.init();
    timer.reset(1000);
    try std.testing.expect(timer.active);
    try std.testing.expectEqual(@as(?i64, 1000), timer.last_input_timestamp);
}

test "InactivityTimer.cancel: deactivates and clears timestamp" {
    var timer = InactivityTimer.init();
    timer.reset(1000);
    timer.cancel();
    try std.testing.expect(!timer.active);
    try std.testing.expect(timer.last_input_timestamp == null);
}

test "InactivityTimer.isTimedOut: returns false when inactive" {
    const timer = InactivityTimer.init();
    try std.testing.expect(!timer.isTimedOut(100_000));
}

test "InactivityTimer.isTimedOut: returns false before 30s" {
    var timer = InactivityTimer.init();
    timer.reset(1000);
    // 29999 ms later = not yet timed out.
    try std.testing.expect(!timer.isTimedOut(1000 + PREEDIT_INACTIVITY_TIMEOUT_MS - 1));
}

test "InactivityTimer.isTimedOut: returns true at exactly 30s" {
    var timer = InactivityTimer.init();
    timer.reset(1000);
    try std.testing.expect(timer.isTimedOut(1000 + PREEDIT_INACTIVITY_TIMEOUT_MS));
}

test "InactivityTimer.isTimedOut: returns true after 30s" {
    var timer = InactivityTimer.init();
    timer.reset(1000);
    try std.testing.expect(timer.isTimedOut(1000 + PREEDIT_INACTIVITY_TIMEOUT_MS + 5000));
}

test "InactivityTimer.reset: resets the timeout window" {
    var timer = InactivityTimer.init();
    timer.reset(1000);
    // After 20s, reset again.
    timer.reset(21_000);
    // 20s after the second reset = not timed out.
    try std.testing.expect(!timer.isTimedOut(41_000));
    // 30s after the second reset = timed out.
    try std.testing.expect(timer.isTimedOut(51_000));
}
