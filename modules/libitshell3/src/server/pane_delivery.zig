const std = @import("std");
const types = @import("../core/types.zig");
const ring_buffer_mod = @import("ring_buffer.zig");
const frame_serializer_mod = @import("frame_serializer.zig");
const RingBuffer = ring_buffer_mod.RingBuffer;

/// Per-session delivery state — maps pane slots to ring buffers.
/// Lives in server/, NOT in core/session.zig.
pub const SessionDeliveryState = struct {
    /// Per-pane ring buffer backing (heap-allocated via page_allocator).
    /// null = slot not yet allocated.
    ring_backing: [types.MAX_PANES]?[]u8,
    ring_buffers: [types.MAX_PANES]RingBuffer,
    /// Per-pane frame sequence counters.
    next_sequences: [types.MAX_PANES]u64,

    pub fn init() SessionDeliveryState {
        var state: SessionDeliveryState = undefined;
        for (0..types.MAX_PANES) |i| {
            state.ring_backing[i] = null;
            state.next_sequences[i] = 0;
            state.ring_buffers[i] = RingBuffer.initInert();
        }
        return state;
    }

    /// Allocate ring buffer backing for a pane slot.
    pub fn initPaneRing(self: *SessionDeliveryState, slot: types.PaneSlot) !void {
        const backing = try std.heap.page_allocator.alloc(u8, ring_buffer_mod.DEFAULT_RING_SIZE);
        self.ring_backing[slot] = backing;
        self.ring_buffers[slot] = RingBuffer.init(backing);
        self.next_sequences[slot] = 0;
    }

    /// Free ring buffer backing for a pane slot.
    pub fn deinitPaneRing(self: *SessionDeliveryState, slot: types.PaneSlot) void {
        if (self.ring_backing[slot]) |backing| {
            std.heap.page_allocator.free(backing);
            self.ring_backing[slot] = null;
            self.ring_buffers[slot] = RingBuffer.initInert();
            self.next_sequences[slot] = 0;
        }
    }

    pub fn getRingBuffer(self: *SessionDeliveryState, slot: types.PaneSlot) ?*RingBuffer {
        if (self.ring_backing[slot] == null) return null;
        return &self.ring_buffers[slot];
    }

    pub fn deinit(self: *SessionDeliveryState) void {
        for (0..types.MAX_PANES) |i| {
            self.deinitPaneRing(@intCast(i));
        }
    }
};

/// Shared scratch buffer for frame serialization.
/// One per EventLoop (single-threaded — only one pane serialized at a time).
pub const SharedScratch = struct {
    buf: [frame_serializer_mod.SCRATCH_SIZE]u8,

    pub fn init() SharedScratch {
        return .{ .buf = @splat(0) };
    }
};

// --- Tests ---

test "init: all ring backing null" {
    var state = SessionDeliveryState.init();
    defer state.deinit();
    for (0..types.MAX_PANES) |i| {
        try std.testing.expect(state.ring_backing[i] == null);
        try std.testing.expect(state.getRingBuffer(@intCast(i)) == null);
    }
}

test "initPaneRing + getRingBuffer: allocates and returns ring" {
    var state = SessionDeliveryState.init();
    defer state.deinit();

    try state.initPaneRing(3);
    const ring = state.getRingBuffer(3).?;
    try std.testing.expectEqual(ring_buffer_mod.DEFAULT_RING_SIZE, ring.capacity);
    try std.testing.expectEqual(@as(usize, 0), ring.frame_count);
}

test "deinitPaneRing: frees and nulls" {
    var state = SessionDeliveryState.init();
    defer state.deinit();

    try state.initPaneRing(5);
    try std.testing.expect(state.getRingBuffer(5) != null);

    state.deinitPaneRing(5);
    try std.testing.expect(state.getRingBuffer(5) == null);
}

test "initPaneRing: ring buffer is functional after allocation" {
    var state = SessionDeliveryState.init();
    defer state.deinit();

    try state.initPaneRing(0);
    const ring = state.getRingBuffer(0).?;

    // Write and read back
    try ring.writeFrame("test-frame", true, 1);
    var cursor = ring_buffer_mod.RingCursor.init();
    var out: [256]u8 = @splat(0);
    const n = ring.peekFrame(&cursor, &out).?;
    try std.testing.expectEqualSlices(u8, "test-frame", out[0..n]);
}

test "multiple pane slots can coexist independently" {
    var state = SessionDeliveryState.init();
    defer state.deinit();

    try state.initPaneRing(0);
    try state.initPaneRing(7);
    try state.initPaneRing(15);

    const r0 = state.getRingBuffer(0).?;
    const r7 = state.getRingBuffer(7).?;
    const r15 = state.getRingBuffer(15).?;

    try r0.writeFrame("pane-0-frame", true, 1);
    try r7.writeFrame("pane-7-frame", false, 2);
    try r15.writeFrame("pane-15-frame", true, 3);

    var c: ring_buffer_mod.RingCursor = .{};
    var out: [256]u8 = @splat(0);

    const n0 = r0.peekFrame(&c, &out).?;
    try std.testing.expectEqualSlices(u8, "pane-0-frame", out[0..n0]);

    c = .{};
    const n7 = r7.peekFrame(&c, &out).?;
    try std.testing.expectEqualSlices(u8, "pane-7-frame", out[0..n7]);

    c = .{};
    const n15 = r15.peekFrame(&c, &out).?;
    try std.testing.expectEqualSlices(u8, "pane-15-frame", out[0..n15]);
}

test "SharedScratch: init produces zeroed buffer" {
    const scratch = SharedScratch.init();
    for (scratch.buf) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}
