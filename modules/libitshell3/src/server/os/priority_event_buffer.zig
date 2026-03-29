//! Fixed-capacity event buffer that groups events by priority tier
//! (SIGNAL > TIMER > READ > WRITE). OS-level wait implementations fill this
//! buffer, and the EventLoop iterates events in priority order.

const std = @import("std");
const interfaces = @import("interfaces.zig");
const Filter = interfaces.Filter;
const Event = interfaces.Event;

pub const PriorityEventBuffer = struct {
    const NUM_PRIORITIES = Filter.count;
    const CAPACITY = interfaces.MAX_EVENTS_PER_BATCH;

    buffers: [NUM_PRIORITIES][CAPACITY]Event = [_][CAPACITY]Event{
        [_]Event{.{ .fd = 0, .filter = .signal, .target = null }} ** CAPACITY,
    } ** NUM_PRIORITIES,
    sizes: [NUM_PRIORITIES]u32 = [_]u32{0} ** NUM_PRIORITIES,

    /// Zeroes all sizes. Does not clear buffer contents.
    pub fn reset(self: *PriorityEventBuffer) void {
        self.sizes = [_]u32{0} ** NUM_PRIORITIES;
    }

    /// Maps event.filter to a priority tier and appends to that tier's buffer.
    /// Drops the event silently if the tier is full.
    pub fn add(self: *PriorityEventBuffer, event: Event) void {
        const tier: usize = @intFromEnum(event.filter);
        const size = self.sizes[tier];
        if (size >= CAPACITY) return;
        self.buffers[tier][size] = event;
        self.sizes[tier] = size + 1;
    }

    /// Returns true if sum of all sizes is zero.
    pub fn isEmpty(self: *const PriorityEventBuffer) bool {
        for (self.sizes) |size| {
            if (size != 0) return false;
        }
        return true;
    }

    /// Returns an iterator that yields events in priority order:
    /// all tier-0 events first (in insertion order), then tier-1, etc.
    pub fn iterator(self: *const PriorityEventBuffer) Iterator {
        return .{ .buffer = self, .tier = 0, .index = 0 };
    }

    pub const Iterator = struct {
        buffer: *const PriorityEventBuffer,
        tier: usize,
        index: u32,

        pub fn next(self: *Iterator) ?Event {
            while (self.tier < NUM_PRIORITIES) {
                if (self.index < self.buffer.sizes[self.tier]) {
                    const event = self.buffer.buffers[self.tier][self.index];
                    self.index += 1;
                    return event;
                }
                self.tier += 1;
                self.index = 0;
            }
            return null;
        }
    };
};

// ── Tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "PriorityEventBuffer.add: places events in correct priority tier" {
    var buf = PriorityEventBuffer{};

    const read_event = Event{ .fd = 1, .filter = .read, .target = .{ .listener = {} } };
    const signal_event = Event{ .fd = 2, .filter = .signal, .target = .{ .listener = {} } };
    const write_event = Event{ .fd = 3, .filter = .write, .target = .{ .listener = {} } };
    const timer_event = Event{ .fd = 4, .filter = .timer, .target = .{ .listener = {} } };

    buf.add(read_event);
    buf.add(signal_event);
    buf.add(write_event);
    buf.add(timer_event);

    // signal tier (0) has 1 event
    try testing.expectEqual(@as(u32, 1), buf.sizes[0]);
    // timer tier (1) has 1 event
    try testing.expectEqual(@as(u32, 1), buf.sizes[1]);
    // read tier (2) has 1 event
    try testing.expectEqual(@as(u32, 1), buf.sizes[2]);
    // write tier (3) has 1 event
    try testing.expectEqual(@as(u32, 1), buf.sizes[3]);
}

test "PriorityEventBuffer.iterator: yields events in SIGNAL > TIMER > READ > WRITE order" {
    var buf = PriorityEventBuffer{};

    buf.add(.{ .fd = 10, .filter = .write, .target = .{ .listener = {} } });
    buf.add(.{ .fd = 20, .filter = .read, .target = .{ .listener = {} } });
    buf.add(.{ .fd = 30, .filter = .signal, .target = .{ .listener = {} } });
    buf.add(.{ .fd = 40, .filter = .timer, .target = .{ .listener = {} } });

    var iter = buf.iterator();

    // Signal first
    try testing.expectEqual(@as(std.posix.fd_t, 30), iter.next().?.fd);
    // Timer second
    try testing.expectEqual(@as(std.posix.fd_t, 40), iter.next().?.fd);
    // Read third
    try testing.expectEqual(@as(std.posix.fd_t, 20), iter.next().?.fd);
    // Write last
    try testing.expectEqual(@as(std.posix.fd_t, 10), iter.next().?.fd);
    // Done
    try testing.expect(iter.next() == null);
}

test "PriorityEventBuffer.iterator: preserves insertion order within a tier" {
    var buf = PriorityEventBuffer{};

    buf.add(.{ .fd = 1, .filter = .read, .target = .{ .listener = {} } });
    buf.add(.{ .fd = 2, .filter = .read, .target = .{ .listener = {} } });
    buf.add(.{ .fd = 3, .filter = .read, .target = .{ .listener = {} } });

    var iter = buf.iterator();
    try testing.expectEqual(@as(std.posix.fd_t, 1), iter.next().?.fd);
    try testing.expectEqual(@as(std.posix.fd_t, 2), iter.next().?.fd);
    try testing.expectEqual(@as(std.posix.fd_t, 3), iter.next().?.fd);
    try testing.expect(iter.next() == null);
}

test "PriorityEventBuffer.reset: clears all tiers" {
    var buf = PriorityEventBuffer{};
    buf.add(.{ .fd = 1, .filter = .read, .target = .{ .listener = {} } });
    buf.add(.{ .fd = 2, .filter = .signal, .target = .{ .listener = {} } });

    try testing.expect(!buf.isEmpty());
    buf.reset();
    try testing.expect(buf.isEmpty());

    for (buf.sizes) |size| {
        try testing.expectEqual(@as(u32, 0), size);
    }
}

test "PriorityEventBuffer.isEmpty: correct state before and after adds" {
    var buf = PriorityEventBuffer{};
    try testing.expect(buf.isEmpty());

    buf.add(.{ .fd = 1, .filter = .timer, .target = .{ .listener = {} } });
    try testing.expect(!buf.isEmpty());
}

test "PriorityEventBuffer.add: silently drops when tier is full" {
    var buf = PriorityEventBuffer{};

    // Fill the read tier to capacity
    for (0..interfaces.MAX_EVENTS_PER_BATCH) |i| {
        buf.add(.{ .fd = @intCast(i), .filter = .read, .target = .{ .listener = {} } });
    }
    try testing.expectEqual(@as(u32, interfaces.MAX_EVENTS_PER_BATCH), buf.sizes[2]);

    // This should be silently dropped
    buf.add(.{ .fd = 999, .filter = .read, .target = .{ .listener = {} } });
    try testing.expectEqual(@as(u32, interfaces.MAX_EVENTS_PER_BATCH), buf.sizes[2]);

    // Other tiers are unaffected
    try testing.expectEqual(@as(u32, 0), buf.sizes[0]);
}
