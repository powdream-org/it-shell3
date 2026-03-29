//! Daemon-global pool of 16 MiB chunks for large message accumulation.
//! The first chunk is statically allocated in .bss (zero cost in binary size).
//! Additional chunks are dynamically allocated on demand and retained for reuse.
//!
//! Single-threaded; no locking required. Used by MessageReader when a message
//! exceeds the 64 KB fixed buffer.

const std = @import("std");
const client_manager_mod = @import("client_manager.zig");
const protocol = @import("itshell3_protocol");
const ChunkPool = protocol.message_reader.ChunkPool;

pub const CHUNK_SIZE: usize = ChunkPool.Chunk.CHUNK_CAPACITY;

/// Maximum number of pooled chunks (one per possible concurrent client).
const MAX_CHUNKS: u16 = client_manager_mod.MAX_CLIENTS;

/// Static first chunk in .bss. Zero-initialized by the OS loader, no binary
/// size impact. Guarantees at least one chunk is always available without
/// dynamic allocation.
var static_chunk: [CHUNK_SIZE]u8 = [_]u8{0} ** CHUNK_SIZE;

pub const LargeChunkPool = struct {
    /// Free list of available chunk pointers. Index 0 is always the static chunk
    /// when available. Dynamic chunks occupy subsequent slots.
    free_list: [MAX_CHUNKS]*[CHUNK_SIZE]u8 = undefined,
    free_count: u16 = 0,

    /// Whether the static chunk is currently in the free list or was never
    /// borrowed. Starts true because the static chunk is always available.
    static_available: bool = true,

    /// Allocator for dynamic chunks.
    allocator: std.mem.Allocator,

    /// Initializes the pool. The static chunk is implicitly available via
    /// `static_available` and does not occupy a free list slot.
    pub fn init(allocator: std.mem.Allocator) LargeChunkPool {
        return .{
            .allocator = allocator,
        };
    }

    /// Borrows a chunk from the pool. Returns the static chunk if available,
    /// then checks the free list for released chunks, then allocates a new
    /// dynamic chunk. Returns null if allocation fails.
    pub fn borrow(self: *LargeChunkPool) ?*[CHUNK_SIZE]u8 {
        // Prefer the static chunk (no allocation, always page-resident).
        if (self.static_available) {
            self.static_available = false;
            return &static_chunk;
        }

        // Check the free list for previously released chunks.
        if (self.free_count > 0) {
            self.free_count -= 1;
            return self.free_list[self.free_count];
        }

        // Allocate a new dynamic chunk.
        const chunk = self.allocator.create([CHUNK_SIZE]u8) catch return null;
        return chunk;
    }

    /// Returns a chunk to the pool for reuse. Dynamic chunks are retained
    /// (not freed) to avoid repeated alloc/free cycles.
    pub fn release(self: *LargeChunkPool, chunk: *[CHUNK_SIZE]u8) void {
        if (chunk == &static_chunk) {
            self.static_available = true;
            return;
        }

        // Add dynamic chunk to the free list.
        if (self.free_count < MAX_CHUNKS) {
            self.free_list[self.free_count] = chunk;
            self.free_count += 1;
        }
        // If free list is full (should not happen in practice), the chunk
        // is leaked. This is acceptable given MAX_CHUNKS == MAX_CLIENTS.
    }

    /// Returns a ChunkPool vtable interface backed by this pool.
    pub fn chunkPool(self: *LargeChunkPool) ChunkPool {
        return .{
            .context = @ptrCast(self),
            .borrow_fn = borrowVtable,
            .release_fn = releaseVtable,
        };
    }

    fn borrowVtable(context: *anyopaque) ?ChunkPool.Chunk {
        const self: *LargeChunkPool = @ptrCast(@alignCast(context));
        const chunk = self.borrow() orelse return null;
        return .{
            .ptr = chunk,
            .slice = chunk,
        };
    }

    fn releaseVtable(context: *anyopaque, chunk: ChunkPool.Chunk) void {
        const self: *LargeChunkPool = @ptrCast(@alignCast(context));
        self.release(@ptrCast(@alignCast(chunk.ptr)));
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

test "LargeChunkPool.borrow: returns static chunk first" {
    var pool = LargeChunkPool.init(std.testing.allocator);
    const chunk = pool.borrow();
    try std.testing.expect(chunk != null);
    try std.testing.expect(chunk.? == &static_chunk);
    pool.release(chunk.?);
}

test "LargeChunkPool.borrow: returns dynamic chunk when static in use" {
    var pool = LargeChunkPool.init(std.testing.allocator);
    const first = pool.borrow().?;
    try std.testing.expect(first == &static_chunk);

    const second = pool.borrow();
    try std.testing.expect(second != null);
    try std.testing.expect(second.? != &static_chunk);

    pool.release(second.?);
    // Free the dynamic chunk to avoid leak in test.
    std.testing.allocator.destroy(second.?);
    // Remove from free list since we destroyed it.
    pool.free_count = 0;
    pool.release(first);
}

test "LargeChunkPool.release: returns chunk to pool for reuse" {
    var pool = LargeChunkPool.init(std.testing.allocator);
    // Borrow static chunk.
    const first = pool.borrow().?;
    // Borrow dynamic chunk.
    const second = pool.borrow().?;
    // Release dynamic chunk.
    pool.release(second);
    try std.testing.expectEqual(@as(u16, 1), pool.free_count);

    // Borrow again: should reuse the released dynamic chunk.
    const third = pool.borrow().?;
    try std.testing.expect(third == second);
    try std.testing.expectEqual(@as(u16, 0), pool.free_count);

    // Cleanup.
    pool.release(first);
    // Destroy the dynamic chunk.
    std.testing.allocator.destroy(second);
}

test "LargeChunkPool.borrow: reuse after release avoids new allocation" {
    var pool = LargeChunkPool.init(std.testing.allocator);
    const first = pool.borrow().?; // static
    const second = pool.borrow().?; // dynamic

    pool.release(second); // return dynamic to free list
    pool.release(first); // return static

    // Borrow two again: should get static + reused dynamic.
    const a = pool.borrow().?;
    try std.testing.expect(a == &static_chunk);
    const b = pool.borrow().?;
    try std.testing.expect(b == second); // reused, no new alloc

    pool.release(a);
    pool.release(b);

    // Cleanup dynamic chunk.
    std.testing.allocator.destroy(second);
    // Clear free list so allocator doesn't see a leak.
    pool.free_count = 0;
}

test "LargeChunkPool.borrow: multiple dynamic borrows" {
    var pool = LargeChunkPool.init(std.testing.allocator);
    const first = pool.borrow().?; // static
    const second = pool.borrow().?; // dynamic 1
    const third = pool.borrow().?; // dynamic 2

    try std.testing.expect(first == &static_chunk);
    try std.testing.expect(second != &static_chunk);
    try std.testing.expect(third != &static_chunk);
    try std.testing.expect(second != third);

    pool.release(first);
    pool.release(second);
    pool.release(third);

    // Cleanup dynamic chunks.
    std.testing.allocator.destroy(second);
    std.testing.allocator.destroy(third);
    pool.free_count = 0;
}

test "LargeChunkPool.chunkPool: vtable interface works" {
    var pool = LargeChunkPool.init(std.testing.allocator);
    var iface = pool.chunkPool();

    const chunk = iface.borrowChunk();
    try std.testing.expect(chunk != null);

    iface.releaseChunk(chunk.?);
    try std.testing.expect(pool.static_available);
}
