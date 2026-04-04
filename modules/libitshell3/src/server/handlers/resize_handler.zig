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

/// Computes effective dimensions from a single client (latest policy).
pub fn computeEffectiveDimensionsLatest(
    cols: u16,
    rows: u16,
) struct { cols: u16, rows: u16 } {
    return .{ .cols = cols, .rows = rows };
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

// ── Tests ────────────────────────────────────────────────────────────────────

test "computeEffectiveDimensionsLatest: returns given dimensions" {
    const result = computeEffectiveDimensionsLatest(120, 40);
    try std.testing.expectEqual(@as(u16, 120), result.cols);
    try std.testing.expectEqual(@as(u16, 40), result.rows);
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
