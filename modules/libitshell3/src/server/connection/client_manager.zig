//! Fixed-size client slot array manager. Handles client_id assignment,
//! add/remove lifecycle, lookup, and iteration over connected clients.
//!
//! Per ADR 00052 (static allocation) and daemon-architecture state-and-types spec.

const std = @import("std");
const client_state_mod = @import("client_state.zig");
const ClientState = client_state_mod.ClientState;
const connection_state_mod = @import("connection_state.zig");
const State = connection_state_mod.State;
const transport = @import("itshell3_transport");
const SocketConnection = transport.transport.SocketConnection;
const protocol = @import("itshell3_protocol");
const ChunkPool = protocol.message_reader.ChunkPool;

/// Maximum concurrent client connections.
pub const MAX_CLIENTS: u16 = 64;

pub const AddError = error{MaxClientsReached};

/// Manages a fixed-size array of ClientState slots.
/// Client IDs are monotonically increasing and never reused within daemon lifetime.
pub const ClientManager = struct {
    /// Client slots. Only the `occupied` field is meaningful for uninitialized
    /// slots; all other fields are set by ClientState.init() when a client
    /// connects. Initialized via initSlots() to set `occupied = false` without
    /// requiring zeroing of the full struct (which fails for non-nullable pointers).
    slots: [MAX_CLIENTS]ClientState = initSlots(),
    /// Next client_id to assign. Monotonically increasing, never reused.
    next_client_id: u32 = 1,
    /// Current count of occupied slots.
    active_count: u16 = 0,
    /// Shared chunk pool reference for MessageReader large message support.
    chunk_pool: *ChunkPool,

    fn initSlots() [MAX_CLIENTS]ClientState {
        var result: [MAX_CLIENTS]ClientState = undefined;
        for (&result) |*slot| {
            slot.occupied = false;
        }
        return result;
    }

    /// Add a new client connection. Returns the slot index.
    pub fn addClient(self: *ClientManager, socket: SocketConnection) AddError!u16 {
        const slot_idx = self.findFreeSlot() orelse return error.MaxClientsReached;
        const client_id = self.next_client_id;
        self.next_client_id += 1;
        self.slots[slot_idx] = ClientState.init(socket, client_id, self.chunk_pool);
        self.active_count += 1;
        return slot_idx;
    }

    /// Remove a client by slot index. Marks the slot as unoccupied.
    pub fn removeClient(self: *ClientManager, slot_idx: u16) void {
        if (slot_idx >= MAX_CLIENTS) return;
        if (!self.slots[slot_idx].occupied) return;
        self.slots[slot_idx].deinit();
        self.active_count -= 1;
    }

    /// Look up a client by slot index.
    pub fn getClient(self: *ClientManager, slot_idx: u16) ?*ClientState {
        if (slot_idx >= MAX_CLIENTS) return null;
        if (!self.slots[slot_idx].occupied) return null;
        return &self.slots[slot_idx];
    }

    /// Look up a client by slot index (const version).
    pub fn getClientConst(self: *const ClientManager, slot_idx: u16) ?*const ClientState {
        if (slot_idx >= MAX_CLIENTS) return null;
        if (!self.slots[slot_idx].occupied) return null;
        return &self.slots[slot_idx];
    }

    /// Find a client slot index by client_id.
    pub fn findByClientId(self: *const ClientManager, client_id: u32) ?u16 {
        var i: u32 = 0;
        while (i < MAX_CLIENTS) : (i += 1) {
            const idx: u16 = @intCast(i);
            if (self.slots[idx].occupied and self.slots[idx].connection.client_id == client_id) {
                return idx;
            }
        }
        return null;
    }

    /// Find a client slot index by socket fd.
    pub fn findByFd(self: *const ClientManager, fd: std.posix.fd_t) ?u16 {
        var i: u32 = 0;
        while (i < MAX_CLIENTS) : (i += 1) {
            const idx: u16 = @intCast(i);
            if (self.slots[idx].occupied and self.slots[idx].connection.socket.fd == fd) {
                return idx;
            }
        }
        return null;
    }

    /// Iterate over all occupied client slots in OPERATING state attached to a
    /// given session. Calls the callback for each matching client.
    pub fn forEachOperatingInSession(
        self: *ClientManager,
        session_id: u32,
        context: anytype,
        callback: fn (@TypeOf(context), *ClientState, u16) void,
    ) void {
        var i: u32 = 0;
        while (i < MAX_CLIENTS) : (i += 1) {
            const idx: u16 = @intCast(i);
            const slot = &self.slots[idx];
            if (slot.occupied and slot.connection.state == .operating and slot.connection.attached_session_id == session_id) {
                callback(context, slot, idx);
            }
        }
    }

    /// Iterate over all occupied client slots in READY or OPERATING state.
    pub fn forEachActive(
        self: *ClientManager,
        context: anytype,
        callback: fn (@TypeOf(context), *ClientState, u16) void,
    ) void {
        var i: u32 = 0;
        while (i < MAX_CLIENTS) : (i += 1) {
            const idx: u16 = @intCast(i);
            const slot = &self.slots[idx];
            if (slot.occupied and (slot.connection.state == .ready or slot.connection.state == .operating)) {
                callback(context, slot, idx);
            }
        }
    }

    /// Number of currently occupied slots.
    pub fn count(self: *const ClientManager) u16 {
        return self.active_count;
    }

    fn findFreeSlot(self: *const ClientManager) ?u16 {
        var i: u32 = 0;
        while (i < MAX_CLIENTS) : (i += 1) {
            const idx: u16 = @intCast(i);
            if (!self.slots[idx].occupied) return idx;
        }
        return null;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

/// Minimal no-op chunk pool for tests that do not exercise large messages.
const TestChunkPoolContext = struct {
    pool: ChunkPool = undefined,

    fn init() TestChunkPoolContext {
        var ctx = TestChunkPoolContext{};
        ctx.pool = .{
            .context = @ptrCast(&ctx),
            .borrow_fn = borrowNoop,
            .release_fn = releaseNoop,
        };
        return ctx;
    }

    fn chunkPool(self: *TestChunkPoolContext) *ChunkPool {
        self.pool.context = @ptrCast(self);
        return &self.pool;
    }

    fn borrowNoop(_: *anyopaque) ?ChunkPool.Chunk {
        return null;
    }

    fn releaseNoop(_: *anyopaque, _: ChunkPool.Chunk) void {}
};

test "ClientManager: addClient assigns monotonic client_id" {
    var pool_ctx = TestChunkPoolContext.init();
    var mgr = ClientManager{ .chunk_pool = pool_ctx.chunkPool() };
    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const c1 = mgr.getClient(idx1).?;
    const c2 = mgr.getClient(idx2).?;
    try std.testing.expectEqual(@as(u32, 1), c1.getClientId());
    try std.testing.expectEqual(@as(u32, 2), c2.getClientId());
    try std.testing.expectEqual(@as(u16, 2), mgr.count());
}

test "ClientManager: removeClient frees slot for reuse" {
    var pool_ctx = TestChunkPoolContext.init();
    var mgr = ClientManager{ .chunk_pool = pool_ctx.chunkPool() };
    const idx = try mgr.addClient(.{ .fd = 10 });
    try std.testing.expectEqual(@as(u16, 1), mgr.count());
    mgr.removeClient(idx);
    try std.testing.expectEqual(@as(u16, 0), mgr.count());
    // Slot is reusable
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    try std.testing.expectEqual(idx, idx2); // Reuses same slot
    // But client_id is NOT reused
    try std.testing.expectEqual(@as(u32, 2), mgr.getClient(idx2).?.getClientId());
}

test "ClientManager: getClient returns null for empty slot" {
    var pool_ctx = TestChunkPoolContext.init();
    var mgr = ClientManager{ .chunk_pool = pool_ctx.chunkPool() };
    try std.testing.expect(mgr.getClient(0) == null);
    try std.testing.expect(mgr.getClient(MAX_CLIENTS) == null);
}

test "ClientManager: findByClientId locates correct slot" {
    var pool_ctx = TestChunkPoolContext.init();
    var mgr = ClientManager{ .chunk_pool = pool_ctx.chunkPool() };
    _ = try mgr.addClient(.{ .fd = 10 });
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    const found = mgr.findByClientId(2);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(idx2, found.?);
}

test "ClientManager: findByClientId returns null for unknown id" {
    var pool_ctx = TestChunkPoolContext.init();
    var mgr = ClientManager{ .chunk_pool = pool_ctx.chunkPool() };
    try std.testing.expect(mgr.findByClientId(999) == null);
}

test "ClientManager: findByFd locates correct slot" {
    var pool_ctx = TestChunkPoolContext.init();
    var mgr = ClientManager{ .chunk_pool = pool_ctx.chunkPool() };
    const idx = try mgr.addClient(.{ .fd = 42 });
    const found = mgr.findByFd(42);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(idx, found.?);
}

test "ClientManager: addClient returns MaxClientsReached when full" {
    var pool_ctx = TestChunkPoolContext.init();
    var mgr = ClientManager{ .chunk_pool = pool_ctx.chunkPool() };
    var i: u32 = 0;
    while (i < MAX_CLIENTS) : (i += 1) {
        _ = try mgr.addClient(.{ .fd = @intCast(i + 100) });
    }
    try std.testing.expectEqual(@as(u16, MAX_CLIENTS), mgr.count());
    try std.testing.expectError(error.MaxClientsReached, mgr.addClient(.{ .fd = 999 }));
}

test "ClientManager: forEachActive iterates ready and operating clients" {
    var pool_ctx = TestChunkPoolContext.init();
    var mgr = ClientManager{ .chunk_pool = pool_ctx.chunkPool() };
    const idx1 = try mgr.addClient(.{ .fd = 10 });
    const idx2 = try mgr.addClient(.{ .fd = 11 });
    // Transition idx1 to READY
    _ = mgr.getClient(idx1).?.connection.transitionTo(.ready);
    // idx2 stays in handshaking (should not be iterated)
    _ = idx2;

    var count: u32 = 0;
    const Counter = struct {
        fn cb(counter: *u32, _: *ClientState, _: u16) void {
            counter.* += 1;
        }
    };
    mgr.forEachActive(&count, Counter.cb);
    try std.testing.expectEqual(@as(u32, 1), count);
}
