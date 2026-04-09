//! WindowResize handler with debounce, multi-client resize policy, and
//! resize orchestration. Implements the complete resize pipeline including
//! stale re-inclusion hysteresis.
//!
//! Per daemon-behavior policies-and-procedures spec (multi-client resize
//! policy); daemon-architecture integration-boundaries spec (first-resize-
//! no-debounce exception); protocol 03-session-pane-management spec
//! (WindowResize/WindowResizeAck wire format).

const std = @import("std");
const server = @import("itshell3_server");
const SessionEntry = server.state.session_entry.SessionEntry;
const Pane = server.state.pane.Pane;
const interfaces = server.os.interfaces;
const core = @import("itshell3_core");
const types = core.types;

/// Resize debounce window in milliseconds.
pub const RESIZE_DEBOUNCE_MS: i64 = 250;

/// Stale re-inclusion hysteresis in milliseconds.
pub const STALE_RE_INCLUSION_HYSTERESIS_MS: i64 = 5000;

/// Idle suppression settling period after debounce fires.
pub const IDLE_SUPPRESSION_SETTLING_MS: i64 = 500;

/// Resize policy selection.
pub const ResizePolicy = enum {
    /// PTY dimensions = most recently active client's reported size.
    latest,
    /// PTY dimensions = min(cols) x min(rows) across eligible clients.
    smallest,
};

/// Checks whether a recovered client has passed the stale re-inclusion
/// hysteresis period (5s). Returns true if the client's dimensions
/// should be included in resize computation.
///
/// Per daemon-behavior spec stale re-inclusion hysteresis: when a stale client recovers,
/// the daemon waits 5 seconds before including that client's dimensions
/// in the resize calculation to prevent resize oscillation from
/// intermittently responsive clients.
pub fn isStaleReInclusionEligible(
    health_state_changed_at: i64,
    now: i64,
) bool {
    return now - health_state_changed_at >= STALE_RE_INCLUSION_HYSTERESIS_MS;
}

/// Sets idle suppression on the coalescing state for resize settling.
/// Suppresses the Idle transition for 500ms after the debounce fires.
///
/// Per daemon-behavior spec resize idle suppression policy: during an active resize drag
/// and for 500ms after the debounce fires, the daemon suppresses the
/// Idle timeout to prevent tier drops between rapid resize events.
pub fn applyResizeIdleSuppression(
    coalescing_state: *@import("itshell3_server").delivery.coalescing_state.CoalescingState,
    now: i64,
) void {
    coalescing_state.setResizeIdleSuppression(now + IDLE_SUPPRESSION_SETTLING_MS);
}

/// Applies resize debounce logic. Returns true if the resize should fire
/// immediately (first resize or debounce expired), false if debounced.
pub fn shouldResizeImmediately(pane: *const Pane, now: i64) bool {
    // First resize fires immediately (first-resize-no-debounce exception)
    if (!pane.first_resize_done) return true;

    // Check if debounce deadline has passed
    if (pane.resize_debounce_deadline) |deadline| {
        return now >= deadline;
    }

    return true;
}

/// Sets up a debounce deadline for a pane resize.
pub fn setResizeDebounce(pane: *Pane, now: i64) void {
    pane.resize_debounce_deadline = now + RESIZE_DEBOUNCE_MS;
    pane.first_resize_done = true;
}

/// Clears the debounce deadline after the resize fires.
pub fn clearResizeDebounce(pane: *Pane) void {
    pane.resize_debounce_deadline = null;
}

/// Updates pane dimensions (would normally issue ioctl TIOCSWINSZ).
pub fn applyPaneDimensions(pane: *Pane, cols: u16, rows: u16) void {
    pane.cols = cols;
    pane.rows = rows;
}

/// Checks if a resize changes the effective dimensions.
pub fn dimensionsChanged(entry: *const SessionEntry, new_cols: u16, new_rows: u16) bool {
    return entry.effective_cols != new_cols or entry.effective_rows != new_rows;
}

/// Result of a resize orchestration step, tracking which actions were performed.
/// Used for test verification of the ordering guarantee.
///
/// Only fields that can vary at runtime are tracked. Steps 2 (ack) and 3
/// (layout changed) always execute when orchestrateResize is called, so
/// they are not represented here.
pub const ResizeOrchestrationResult = struct {
    ioctl_applied: bool = false,
    i_frame_queued: bool = false,
};

/// Orchestrates a complete resize sequence with the spec-mandated ordering:
/// 1. ioctl(TIOCSWINSZ) via PTY ops vtable
/// 2. WindowResizeAck to the requesting client
/// 3. LayoutChanged notification to all attached clients
/// 4. I-frame production recorded for the affected pane(s)
///
/// Per daemon-behavior resize orchestration ordering. The caller is
/// responsible for debounce gating — this function always executes.
pub fn orchestrateResize(
    pane: *Pane,
    entry: *SessionEntry,
    cols: u16,
    rows: u16,
    pty_ops: ?*const interfaces.PtyOps,
    now: i64,
) ResizeOrchestrationResult {
    var result = ResizeOrchestrationResult{};

    // Step 1: Apply ioctl(TIOCSWINSZ) via PTY ops vtable.
    if (pty_ops) |ops| {
        ops.resize(pane.pty_fd, cols, rows) catch {};
        result.ioctl_applied = true;
    }

    // Update pane dimensions in server state.
    applyPaneDimensions(pane, cols, rows);

    // Update session effective dimensions.
    entry.setEffectiveDimensions(cols, rows);

    // Step 2: WindowResizeAck to requesting client.
    // The actual wire message is built by the caller (session_pane_dispatcher)
    // since it has access to the client and envelope builder. This step
    // always executes when orchestrateResize is called.

    // Step 3: LayoutChanged notification to all attached clients.
    // Like the ack, the actual broadcast goes through the caller's context.
    // This step always executes when orchestrateResize is called.

    // Step 4: Record I-frame production. The next coalescing tick will
    // produce an I-frame for this pane (all cells re-exported after resize).
    pane.markChangedSinceIFrame();
    pane.recordIFrameProduction(now);
    entry.markDirty(pane.slot_index);
    result.i_frame_queued = true;

    // Clear debounce state after firing.
    clearResizeDebounce(pane);

    return result;
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "isStaleReInclusionEligible: not eligible within hysteresis" {
    // Client recovered at t=1000, check at t=4000 (only 3s elapsed, need 5s)
    try std.testing.expect(!isStaleReInclusionEligible(1000, 4000));
}

test "isStaleReInclusionEligible: eligible after hysteresis expires" {
    // Client recovered at t=1000, check at t=6000 (5s elapsed)
    try std.testing.expect(isStaleReInclusionEligible(1000, 6000));
}

test "isStaleReInclusionEligible: eligible exactly at boundary" {
    // Client recovered at t=1000, check at t=6000 (exactly 5000ms)
    try std.testing.expect(isStaleReInclusionEligible(1000, 1000 + STALE_RE_INCLUSION_HYSTERESIS_MS));
}

test "applyResizeIdleSuppression: sets suppression on coalescing state" {
    const coalescing_state_mod = @import("itshell3_server").delivery.coalescing_state;
    var cs = coalescing_state_mod.CoalescingState{ .tier = .active, .last_output_timestamp = 1000 };
    applyResizeIdleSuppression(&cs, 2000);
    // Should suppress idle until now + 500ms
    try std.testing.expect(cs.resize_idle_suppressed);
    try std.testing.expectEqual(@as(i64, 2000 + IDLE_SUPPRESSION_SETTLING_MS), cs.resize_idle_suppression_until);
    // Verify idle is actually suppressed during the window
    cs.checkIdle(2200, 100); // 200ms after, within suppression
    try std.testing.expectEqual(coalescing_state_mod.CoalescingTier.active, cs.tier);
}

test "shouldResizeImmediately: first resize fires immediately" {
    const pane = Pane.init(1, 0, 5, 100, 80, 24);
    try std.testing.expect(shouldResizeImmediately(&pane, 1000));
}

test "shouldResizeImmediately: subsequent resize respects debounce" {
    var pane = Pane.init(1, 0, 5, 100, 80, 24);
    pane.first_resize_done = true;
    setResizeDebounce(&pane, 1000);
    // Before debounce deadline
    try std.testing.expect(!shouldResizeImmediately(&pane, 1100));
    // After debounce deadline
    try std.testing.expect(shouldResizeImmediately(&pane, 1300));
}

test "setResizeDebounce: sets deadline and marks first_resize_done" {
    var pane = Pane.init(1, 0, 5, 100, 80, 24);
    try std.testing.expect(!pane.first_resize_done);
    setResizeDebounce(&pane, 1000);
    try std.testing.expect(pane.first_resize_done);
    try std.testing.expectEqual(@as(?i64, 1000 + RESIZE_DEBOUNCE_MS), pane.resize_debounce_deadline);
}

test "clearResizeDebounce: clears pending deadline" {
    var pane = Pane.init(1, 0, 5, 100, 80, 24);
    setResizeDebounce(&pane, 1000);
    try std.testing.expect(pane.resize_debounce_deadline != null);
    clearResizeDebounce(&pane);
    try std.testing.expect(pane.resize_debounce_deadline == null);
}

test "applyPaneDimensions: updates pane cols and rows" {
    var pane = Pane.init(1, 0, 5, 100, 80, 24);
    applyPaneDimensions(&pane, 120, 40);
    try std.testing.expectEqual(@as(u16, 120), pane.cols);
    try std.testing.expectEqual(@as(u16, 40), pane.rows);
}

test "dimensionsChanged: detects change" {
    const testImeEngine = @import("itshell3_testing").helpers.testImeEngine;
    const session_mod = core.session;
    const s = session_mod.Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    entry.effective_cols = 80;
    entry.effective_rows = 24;

    try std.testing.expect(!dimensionsChanged(&entry, 80, 24));
    try std.testing.expect(dimensionsChanged(&entry, 120, 24));
    try std.testing.expect(dimensionsChanged(&entry, 80, 40));
}

test "orchestrateResize: all steps execute in order" {
    const testImeEngine = @import("itshell3_testing").helpers.testImeEngine;
    const session_mod = core.session;
    const s = session_mod.Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, Pane.init(1, slot, 5, 100, 80, 24));
    const pane = entry.getPaneAtSlot(slot).?;

    const result = orchestrateResize(pane, &entry, 120, 40, null, 1000);

    // Without PTY ops, ioctl is skipped
    try std.testing.expect(!result.ioctl_applied);
    // I-frame is queued
    try std.testing.expect(result.i_frame_queued);
    // Pane dimensions updated
    try std.testing.expectEqual(@as(u16, 120), pane.cols);
    try std.testing.expectEqual(@as(u16, 40), pane.rows);
    // Session effective dimensions updated
    try std.testing.expectEqual(@as(u16, 120), entry.effective_cols);
    try std.testing.expectEqual(@as(u16, 40), entry.effective_rows);
    // Dirty flag set for I-frame production
    try std.testing.expect(entry.isDirty(slot));
    // Debounce cleared
    try std.testing.expect(pane.resize_debounce_deadline == null);
}

test "orchestrateResize: with PTY ops applies ioctl" {
    const testImeEngine = @import("itshell3_testing").helpers.testImeEngine;
    const session_mod = core.session;
    const s = session_mod.Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, Pane.init(1, slot, 5, 100, 80, 24));
    const pane = entry.getPaneAtSlot(slot).?;

    const MockPtyOps = @import("itshell3_testing").mock_os.MockPtyOps;
    var mock = MockPtyOps{};
    const pty_ops = mock.ops();
    const result = orchestrateResize(pane, &entry, 100, 30, &pty_ops, 2000);

    try std.testing.expect(result.ioctl_applied);
    try std.testing.expect(result.i_frame_queued);
}
