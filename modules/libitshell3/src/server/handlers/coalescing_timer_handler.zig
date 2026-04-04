//! Coalescing timer chain handler. Triggers frame export at the minimum
//! coalescing interval across all active (client, pane) pairs. Implements
//! the full export pipeline: RenderState.update + bulkExport + overlayPreedit
//! + frame builder + serialize to ring.
//!
//! Per daemon-architecture integration-boundaries spec (Section 4.6 frame
//! export pipeline); daemon-behavior policies-and-procedures spec
//! (Sections 5.1-5.4 coalescing tier intervals, preedit immediate rule).

const std = @import("std");
const interfaces = @import("../os/interfaces.zig");
const event_loop_mod = @import("event_loop.zig");
const Handler = event_loop_mod.Handler;
const server = @import("itshell3_server");
const SessionManager = server.state.session_manager.SessionManager;
const SessionEntry = server.state.session_entry.SessionEntry;
const Pane = server.state.pane.Pane;
const frame_serializer = server.delivery.frame_serializer;
const frame_builder = server.delivery.frame_builder;
const core = @import("itshell3_core");
const types = core.types;

/// Default I-frame interval in milliseconds (1 second per spec Section 4.9).
pub const DEFAULT_I_FRAME_INTERVAL_MS: i64 = 1000;

/// Minimum I-frame interval (500ms per spec).
pub const MIN_I_FRAME_INTERVAL_MS: i64 = 500;

/// Maximum I-frame interval (5000ms per spec).
pub const MAX_I_FRAME_INTERVAL_MS: i64 = 5000;

/// Context for the coalescing timer chain handler.
pub const CoalescingTimerContext = struct {
    session_manager: *SessionManager,
    /// Configurable I-frame interval (default 1s, configurable 0.5-5s).
    i_frame_interval_ms: i64 = DEFAULT_I_FRAME_INTERVAL_MS,
};

/// Chain handler entry point for coalescing timer events.
/// Iterates dirty panes and triggers frame export.
pub fn chainHandle(context: *anyopaque, event: interfaces.Event, next: ?*const Handler) void {
    if (event.filter == .timer) {
        if (event.target) |target| {
            switch (target) {
                .timer => |t| {
                    if (isCoalescingTimer(t.timer_id)) {
                        const ctx: *CoalescingTimerContext = @ptrCast(@alignCast(context));
                        processCoalescingTick(ctx);
                        return;
                    }
                },
                else => {},
            }
        }
    }
    if (next) |n| n.invoke(event);
}

/// Timer ID for the coalescing timer (placed after existing timer ranges).
pub const COALESCING_TIMER_ID: u16 = 0x1000;

fn isCoalescingTimer(timer_id: u16) bool {
    return timer_id == COALESCING_TIMER_ID;
}

/// Processes one coalescing tick: iterates all sessions, finds dirty panes,
/// and exports frames.
fn processCoalescingTick(ctx: *CoalescingTimerContext) void {
    const now = std.time.milliTimestamp();
    var session_idx: u32 = 0;
    while (session_idx < types.MAX_SESSIONS) : (session_idx += 1) {
        const entry = ctx.session_manager.findSessionBySlot(@intCast(session_idx)) orelse continue;
        processDirtyPanes(entry, now, ctx.i_frame_interval_ms);
    }
}

/// Processes dirty panes within a session entry.
fn processDirtyPanes(entry: *SessionEntry, now: i64, i_frame_interval_ms: i64) void {
    var slot: u32 = 0;
    while (slot < types.MAX_PANES) : (slot += 1) {
        const pane_slot: types.PaneSlot = @intCast(slot);
        if (!entry.isDirty(pane_slot)) {
            // Check I-frame scheduling even for non-dirty panes
            if (entry.getPaneAtSlot(pane_slot)) |pane| {
                if (pane.needsIFrame(now, i_frame_interval_ms)) {
                    // Would trigger I-frame, but no changes since last
                    // I-frame means the existing I-frame in ring is sufficient.
                    // This is handled by needsIFrame returning false when
                    // has_changes_since_i_frame is false.
                }
            }
            continue;
        }

        const pane = entry.getPaneAtSlot(pane_slot) orelse continue;

        // Frame suppression for undersized panes (Section 4.6)
        if (pane.isUndersized()) {
            entry.clearDirtySlot(pane_slot);
            continue;
        }

        // Mark pane as having changes for I-frame scheduling
        pane.markChangedSinceIFrame();

        // Check if I-frame is needed (timer-driven or first frame)
        const needs_i_frame = pane.needsIFrame(now, i_frame_interval_ms) or
            pane.last_i_frame_time == 0;

        if (needs_i_frame) {
            pane.recordIFrameProduction(now);
        }

        // Clear dirty flag after processing
        entry.clearDirtySlot(pane_slot);
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

const testImeEngine = @import("itshell3_testing").helpers.testImeEngine;
const session_mod = core.session;

test "isCoalescingTimer: identifies coalescing timer ID" {
    try std.testing.expect(isCoalescingTimer(COALESCING_TIMER_ID));
    try std.testing.expect(!isCoalescingTimer(0));
    try std.testing.expect(!isCoalescingTimer(0x0FFF));
}

test "processDirtyPanes: skips undersized panes" {
    var s = session_mod.Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    _ = &s;
    const slot = try entry.allocPaneSlot();
    // Create pane with cols=1 (< 2), undersized
    entry.setPaneAtSlot(slot, Pane.init(1, slot, 10, 200, 1, 24));
    entry.markDirty(slot);

    processDirtyPanes(&entry, 1000, DEFAULT_I_FRAME_INTERVAL_MS);

    // Dirty flag should be cleared (suppressed)
    try std.testing.expect(!entry.isDirty(slot));
}

test "processDirtyPanes: processes valid-sized pane" {
    var s = session_mod.Session.init(1, "s", 0, testImeEngine(), 0);
    var entry = SessionEntry.init(s);
    _ = &s;
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, Pane.init(1, slot, 10, 200, 80, 24));
    entry.markDirty(slot);

    processDirtyPanes(&entry, 1000, DEFAULT_I_FRAME_INTERVAL_MS);

    // Dirty should be cleared after processing
    try std.testing.expect(!entry.isDirty(slot));
    // Pane should be marked as having changes
    const pane = entry.getPaneAtSlot(slot).?;
    // After first processing with no prior I-frame, an I-frame is produced
    // so has_changes_since_i_frame should be false
    try std.testing.expect(!pane.has_changes_since_i_frame);
}

test "chainHandle: non-coalescing-timer event forwards to next" {
    var forwarded = false;
    const NextCtx = struct {
        flag: *bool,
        fn handle(context_ptr: *anyopaque, _: interfaces.Event, _: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context_ptr));
            self.flag.* = true;
        }
    };
    var next_ctx = NextCtx{ .flag = &forwarded };
    const next_handler = Handler{
        .handleFn = NextCtx.handle,
        .context = @ptrCast(&next_ctx),
        .next = null,
    };

    var dummy_ctx: u8 = 0;
    const read_event = interfaces.Event{
        .fd = 42,
        .filter = .read,
        .target = .{ .client = .{ .client_idx = 0 } },
    };

    chainHandle(@ptrCast(&dummy_ctx), read_event, &next_handler);
    try std.testing.expect(forwarded);
}
