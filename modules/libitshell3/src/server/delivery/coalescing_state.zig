//! Per-(client, pane) coalescing tier state and transition logic.
//! Implements the 4-tier model (+ Idle) with hysteresis-based tier transitions,
//! WAN adjustments, and power-aware throttling.
//!
//! Per daemon-behavior policies-and-procedures spec (coalescing tier model).

const std = @import("std");
const server = @import("itshell3_server");
const ClientState = server.connection.client_state.ClientState;
const ClientDisplayInfo = ClientState.ClientDisplayInfo;

/// Coalescing tier per daemon-behavior spec coalescing tier model.
pub const CoalescingTier = enum(u8) {
    /// Tier 0: Preedit state change. 0ms (immediate).
    preedit = 0,
    /// Tier 1: Keystroke echo, cursor movement. 0ms (immediate).
    interactive = 1,
    /// Tier 2: Sustained PTY output. 16ms (~60 fps).
    active = 2,
    /// Tier 3: High-throughput PTY output sustained >500ms. 33ms (~30 fps).
    bulk = 3,
    /// No frames — no PTY output for >100ms.
    idle = 4,

    /// Returns the base interval in milliseconds for this tier.
    pub fn baseIntervalMs(self: CoalescingTier) u32 {
        return switch (self) {
            .preedit => 0,
            .interactive => 0,
            .active => 16,
            .bulk => 33,
            .idle => 0, // No frames emitted in Idle
        };
    }
};

/// Per-(client, pane) coalescing state.
pub const CoalescingState = struct {
    tier: CoalescingTier = .idle,

    /// Timestamp (ms) when the current tier was entered.
    tier_entered_at: i64 = 0,

    /// Timestamp of last PTY output for this (client, pane) pair.
    last_output_timestamp: i64 = 0,

    /// Whether this pane is in the resize idle-suppression window.
    /// Set during active resize drag + 500ms settling period.
    resize_idle_suppressed: bool = false,

    /// Timestamp when resize idle suppression ends.
    resize_idle_suppression_until: i64 = 0,

    /// Upgrades to the given tier if it's faster than the current tier.
    /// Upgrades are immediate per spec tier transition rules.
    pub fn upgradeTo(self: *CoalescingState, tier: CoalescingTier, now: i64) void {
        if (@intFromEnum(tier) < @intFromEnum(self.tier)) {
            self.tier = tier;
            self.tier_entered_at = now;
        }
    }

    /// Attempts to downgrade (slower tier) based on sustained conditions.
    /// Returns the effective tier after processing.
    pub fn processOutput(self: *CoalescingState, now: i64) void {
        self.last_output_timestamp = now;

        if (self.tier == .idle) {
            // Any output immediately upgrades from Idle to Interactive.
            self.tier = .interactive;
            self.tier_entered_at = now;
            return;
        }

        // Downgrade checks (tier transition rules):
        // Interactive -> Active: sustained output >100ms
        if (self.tier == .interactive) {
            if (now - self.tier_entered_at > 100) {
                self.tier = .active;
                self.tier_entered_at = now;
            }
        }
        // Active -> Bulk: sustained high throughput >500ms
        if (self.tier == .active) {
            if (now - self.tier_entered_at > 500) {
                self.tier = .bulk;
                self.tier_entered_at = now;
            }
        }
    }

    /// Checks for Idle transition: no output for >100ms.
    /// Per spec resize idle suppression rules, idle is suppressed during resize settling.
    pub fn checkIdle(self: *CoalescingState, now: i64, idle_threshold_ms: u32) void {
        if (self.tier == .preedit) return; // Never idle from preedit
        if (self.tier == .idle) return; // Already idle

        // Idle suppression during resize (resize idle suppression rules)
        if (self.resize_idle_suppressed and now < self.resize_idle_suppression_until) {
            return;
        }
        // Clear suppression flag if expired
        if (self.resize_idle_suppressed and now >= self.resize_idle_suppression_until) {
            self.resize_idle_suppressed = false;
        }

        if (self.last_output_timestamp > 0 and
            now - self.last_output_timestamp > @as(i64, idle_threshold_ms))
        {
            self.tier = .idle;
            self.tier_entered_at = now;
        }
    }

    /// Triggers preedit tier (Tier 0, immediate) regardless of current state.
    /// Per spec preedit immediate delivery rule: preedit is never throttled.
    pub fn triggerPreedit(self: *CoalescingState, now: i64) void {
        self.tier = .preedit;
        self.tier_entered_at = now;
    }

    /// Sets resize idle suppression window.
    /// Per spec resize idle suppression: suppressed during resize + 500ms settling.
    pub fn setResizeIdleSuppression(self: *CoalescingState, suppression_end: i64) void {
        self.resize_idle_suppressed = true;
        self.resize_idle_suppression_until = suppression_end;
    }

    /// Returns the effective interval in milliseconds, applying WAN and power
    /// adjustments from the client's display info.
    pub fn effectiveIntervalMs(
        self: *const CoalescingState,
        display_info: *const ClientDisplayInfo,
    ) u32 {
        // Preedit is never throttled (preedit immediate delivery rule)
        if (self.tier == .preedit) return 0;
        if (self.tier == .idle) return 0;

        var interval = self.tier.baseIntervalMs();

        // WAN adjustments (transport-aware tier adjustments)
        if (display_info.transport_type == .ssh_tunnel) {
            if (self.tier == .active) interval = @max(interval, 33);
            if (self.tier == .bulk) interval = @max(interval, 100);
        }

        // Low bandwidth forces Tier 3 for non-preedit (transport-aware tier adjustments)
        if (display_info.bandwidth_hint == .cellular) {
            interval = @max(interval, 33);
        }

        // Power-aware throttling
        switch (display_info.power_state) {
            .battery => interval = @max(interval, 16), // Cap at Tier 2
            .low_battery => interval = @max(interval, 33), // Cap at Tier 3
            .ac => {}, // No cap
        }

        return interval;
    }

    /// Computes the default idle threshold for this client's display info.
    /// Per spec WAN transport adjustments: >100ms RTT raises Idle threshold to 200ms.
    pub fn idleThresholdMs(display_info: *const ClientDisplayInfo) u32 {
        if (display_info.estimated_rtt_ms > 100) return 200;
        return 100;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

test "CoalescingState: default is idle" {
    const cs = CoalescingState{};
    try std.testing.expectEqual(CoalescingTier.idle, cs.tier);
}

test "CoalescingState.processOutput: idle to interactive on first output" {
    var cs = CoalescingState{};
    cs.processOutput(1000);
    try std.testing.expectEqual(CoalescingTier.interactive, cs.tier);
}

test "CoalescingState.processOutput: interactive to active after 100ms" {
    var cs = CoalescingState{};
    cs.processOutput(1000); // idle -> interactive
    cs.processOutput(1101); // 101ms > 100ms -> active
    try std.testing.expectEqual(CoalescingTier.active, cs.tier);
}

test "CoalescingState.processOutput: active to bulk after 500ms" {
    var cs = CoalescingState{};
    cs.processOutput(1000); // idle -> interactive
    cs.processOutput(1101); // -> active
    cs.processOutput(1602); // 501ms > 500ms -> bulk
    try std.testing.expectEqual(CoalescingTier.bulk, cs.tier);
}

test "CoalescingState.upgradeTo: immediate on faster tier" {
    var cs = CoalescingState{ .tier = .bulk, .tier_entered_at = 1000 };
    cs.upgradeTo(.interactive, 2000);
    try std.testing.expectEqual(CoalescingTier.interactive, cs.tier);
    try std.testing.expectEqual(@as(i64, 2000), cs.tier_entered_at);
}

test "CoalescingState.upgradeTo: no-op for slower tier" {
    var cs = CoalescingState{ .tier = .interactive, .tier_entered_at = 1000 };
    cs.upgradeTo(.bulk, 2000);
    try std.testing.expectEqual(CoalescingTier.interactive, cs.tier);
    try std.testing.expectEqual(@as(i64, 1000), cs.tier_entered_at);
}

test "CoalescingState.triggerPreedit: overrides any tier" {
    var cs = CoalescingState{ .tier = .bulk };
    cs.triggerPreedit(3000);
    try std.testing.expectEqual(CoalescingTier.preedit, cs.tier);
}

test "CoalescingState.checkIdle: transitions to idle after threshold" {
    var cs = CoalescingState{ .tier = .active, .last_output_timestamp = 1000 };
    cs.checkIdle(1101, 100);
    try std.testing.expectEqual(CoalescingTier.idle, cs.tier);
}

test "CoalescingState.checkIdle: does not transition during resize suppression" {
    var cs = CoalescingState{ .tier = .active, .last_output_timestamp = 1000 };
    cs.setResizeIdleSuppression(2000);
    cs.checkIdle(1200, 100); // Would be idle but suppressed
    try std.testing.expectEqual(CoalescingTier.active, cs.tier);
}

test "CoalescingState.checkIdle: idle resumes after suppression expires" {
    var cs = CoalescingState{ .tier = .active, .last_output_timestamp = 1000 };
    cs.setResizeIdleSuppression(1500);
    cs.checkIdle(1600, 100); // After suppression expiry
    try std.testing.expectEqual(CoalescingTier.idle, cs.tier);
}

test "CoalescingState.effectiveIntervalMs: WAN ssh raises tier 2 to 33ms" {
    const cs = CoalescingState{ .tier = .active };
    const info = ClientDisplayInfo{ .transport_type = .ssh_tunnel };
    try std.testing.expectEqual(@as(u32, 33), cs.effectiveIntervalMs(&info));
}

test "CoalescingState.effectiveIntervalMs: WAN ssh raises tier 3 to 100ms" {
    const cs = CoalescingState{ .tier = .bulk };
    const info = ClientDisplayInfo{ .transport_type = .ssh_tunnel };
    try std.testing.expectEqual(@as(u32, 100), cs.effectiveIntervalMs(&info));
}

test "CoalescingState.effectiveIntervalMs: cellular forces tier 3 minimum" {
    const cs = CoalescingState{ .tier = .interactive };
    const info = ClientDisplayInfo{ .bandwidth_hint = .cellular };
    try std.testing.expectEqual(@as(u32, 33), cs.effectiveIntervalMs(&info));
}

test "CoalescingState.effectiveIntervalMs: battery caps at tier 2" {
    const cs = CoalescingState{ .tier = .interactive };
    const info = ClientDisplayInfo{ .power_state = .battery };
    try std.testing.expectEqual(@as(u32, 16), cs.effectiveIntervalMs(&info));
}

test "CoalescingState.effectiveIntervalMs: low_battery caps at tier 3" {
    const cs = CoalescingState{ .tier = .interactive };
    const info = ClientDisplayInfo{ .power_state = .low_battery };
    try std.testing.expectEqual(@as(u32, 33), cs.effectiveIntervalMs(&info));
}

test "CoalescingState.effectiveIntervalMs: preedit never throttled" {
    const cs = CoalescingState{ .tier = .preedit };
    const info = ClientDisplayInfo{
        .power_state = .low_battery,
        .transport_type = .ssh_tunnel,
        .bandwidth_hint = .cellular,
    };
    try std.testing.expectEqual(@as(u32, 0), cs.effectiveIntervalMs(&info));
}

test "CoalescingState.idleThresholdMs: default 100ms" {
    const info = ClientDisplayInfo{};
    try std.testing.expectEqual(@as(u32, 100), CoalescingState.idleThresholdMs(&info));
}

test "CoalescingState.idleThresholdMs: high RTT raises to 200ms" {
    const info = ClientDisplayInfo{ .estimated_rtt_ms = 150 };
    try std.testing.expectEqual(@as(u32, 200), CoalescingState.idleThresholdMs(&info));
}
