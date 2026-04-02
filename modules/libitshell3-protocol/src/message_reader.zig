//! Tiered-buffer message reader that accumulates partial protocol frames across
//! recv() calls. Uses a 64 KB fixed buffer for common messages and borrows
//! 16 MiB chunks from a ChunkPool for large payloads.

const std = @import("std");
const header_mod = @import("header.zig");

/// Vtable interface for borrowing and releasing large chunks. Implemented by
/// the daemon-side LargeChunkPool. Allows MessageReader to live in the
/// protocol library without depending on the daemon library.
pub const ChunkPool = struct {
    context: *anyopaque,
    borrow_fn: *const fn (context: *anyopaque) ?Chunk,
    release_fn: *const fn (context: *anyopaque, chunk: Chunk) void,

    /// Opaque handle to a borrowed chunk. The `ptr` field is the pool's
    /// internal pointer (used for release); `slice` is the usable buffer.
    pub const Chunk = struct {
        ptr: *anyopaque,
        slice: *[CHUNK_CAPACITY]u8,

        pub const CHUNK_CAPACITY: usize = 16 * 1024 * 1024;
    };

    pub fn borrowChunk(self: *ChunkPool) ?Chunk {
        return self.borrow_fn(self.context);
    }

    pub fn releaseChunk(self: *ChunkPool, chunk: Chunk) void {
        self.release_fn(self.context, chunk);
    }
};

/// Accumulates partial protocol frames across recv() calls.
///
/// Uses a tiered buffer strategy: a 64 KB internal fixed buffer handles the
/// vast majority of messages (control, heartbeat, input events). When a
/// message header indicates a payload larger than the fixed buffer, a 16 MiB
/// chunk is borrowed from the daemon-global ChunkPool for accumulation.
///
/// The caller must consume the payload from nextMessage() before the next
/// feed() or nextMessage() call, as the buffer contents may shift or the
/// borrowed chunk may be released.
pub const MessageReader = struct {
    /// Buffer size for the internal fixed buffer (Tier 1). Handles all
    /// common messages without any dynamic allocation.
    pub const BUFFER_SIZE: u32 = 65536;

    const ReaderState = enum {
        /// Accumulating in the fixed buffer. Either still reading the header,
        /// or the full message fits in the fixed buffer.
        reading_header_or_small,
        /// Header parsed and payload exceeds fixed buffer. Accumulating in a
        /// borrowed chunk.
        reading_large,
        /// A large message was returned by nextMessage() and the borrowed
        /// chunk has not yet been released. The chunk is released on the next
        /// call to nextMessage() or feed().
        large_pending_release,
    };

    /// A decoded message: header plus payload slice.
    ///
    /// The payload slice may point into either the fixed buffer or a borrowed
    /// chunk. The caller must consume the payload before the next feed() or
    /// nextMessage() call.
    pub const Message = struct {
        header: header_mod.Header,
        payload: []const u8,
    };

    pub const FeedError = error{ChunkPoolExhausted};

    buffer: [BUFFER_SIZE]u8 = [_]u8{0} ** BUFFER_SIZE,
    length: u32 = 0,
    pool: *ChunkPool,
    state: ReaderState = .reading_header_or_small,
    /// Borrowed chunk state (valid in reading_large and large_pending_release).
    borrowed_chunk: ?ChunkPool.Chunk = null,
    /// Number of bytes accumulated in the borrowed chunk.
    chunk_length: u32 = 0,
    /// Total frame size (header + payload) for the large message being
    /// accumulated. Known once the header is parsed.
    large_frame_size: u32 = 0,

    /// Feed received bytes into the reader.
    ///
    /// In normal (fixed buffer) mode, copies bytes into the internal buffer.
    /// In large message mode, copies bytes into the borrowed chunk. Returns
    /// the number of bytes consumed (always equal to data.len unless an error
    /// occurs).
    pub fn feed(self: *MessageReader, data: []const u8) FeedError!void {
        // Release any chunk pending from a previous large message.
        if (self.state == .large_pending_release) {
            self.releaseBorrowedChunk();
            self.state = .reading_header_or_small;
        }

        var remaining = data;

        while (remaining.len > 0) {
            switch (self.state) {
                .reading_header_or_small => {
                    const available = BUFFER_SIZE - self.length;
                    const copy_length: u32 = @intCast(@min(remaining.len, available));
                    @memcpy(self.buffer[self.length..][0..copy_length], remaining[0..copy_length]);
                    self.length += copy_length;
                    remaining = remaining[copy_length..];

                    // Check if we have a complete header and need to transition
                    // to large mode.
                    if (self.length >= header_mod.HEADER_SIZE) {
                        const hdr = header_mod.Header.decode(self.buffer[0..header_mod.HEADER_SIZE]) catch {
                            // Bad header; leave data in buffer for nextMessage()
                            // to report null (it will also fail decode).
                            return;
                        };
                        const frame_size: u32 = @intCast(header_mod.HEADER_SIZE + hdr.payload_length);
                        if (frame_size > BUFFER_SIZE) {
                            // Need a large chunk.
                            const chunk = self.pool.borrowChunk() orelse return error.ChunkPoolExhausted;
                            self.borrowed_chunk = chunk;
                            self.large_frame_size = frame_size;
                            self.state = .reading_large;

                            // Copy what we already have in the fixed buffer into the chunk.
                            const already_have = self.length;
                            @memcpy(chunk.slice[0..already_have], self.buffer[0..already_have]);
                            self.chunk_length = already_have;
                            self.length = 0;
                            // Continue the while loop to feed remaining bytes
                            // into the chunk.
                        }
                    }
                },
                .reading_large => {
                    const chunk = self.borrowed_chunk.?;
                    const needed = self.large_frame_size - self.chunk_length;
                    const copy_length: u32 = @intCast(@min(remaining.len, needed));
                    @memcpy(chunk.slice[self.chunk_length..][0..copy_length], remaining[0..copy_length]);
                    self.chunk_length += copy_length;
                    remaining = remaining[copy_length..];

                    if (self.chunk_length >= self.large_frame_size) {
                        // Large message is complete. Leave in reading_large
                        // state for nextMessage() to extract.
                        // Any remaining bytes belong to the next message and
                        // go back into the fixed buffer.
                        if (remaining.len > 0) {
                            const leftover: u32 = @intCast(@min(remaining.len, BUFFER_SIZE));
                            @memcpy(self.buffer[0..leftover], remaining[0..leftover]);
                            self.length = leftover;
                            remaining = remaining[leftover..];
                        }
                    }
                },
                .large_pending_release => unreachable, // Handled at the top.
            }
        }
    }

    /// Try to extract the next complete frame from accumulated data.
    ///
    /// Returns the header and payload slice, or null if incomplete.
    /// On success for small messages, consumed bytes are removed from the
    /// internal buffer. For large messages, the borrowed chunk transitions to
    /// pending-release state and is freed on the next feed() or nextMessage()
    /// call.
    pub fn nextMessage(self: *MessageReader) ?Message {
        // Release any chunk pending from a previous large message.
        if (self.state == .large_pending_release) {
            self.releaseBorrowedChunk();
            self.state = .reading_header_or_small;
        }

        switch (self.state) {
            .reading_header_or_small => {
                if (self.length < header_mod.HEADER_SIZE) return null;

                const hdr = header_mod.Header.decode(self.buffer[0..header_mod.HEADER_SIZE]) catch return null;

                const frame_end: u32 = @intCast(header_mod.HEADER_SIZE + hdr.payload_length);
                if (frame_end > BUFFER_SIZE) {
                    // This should have been caught by feed(), but if the
                    // caller calls nextMessage() before feed() fills in
                    // enough data, we can end up here. Return null to let
                    // the caller call feed() again.
                    return null;
                }
                if (frame_end > self.length) return null;

                const payload_slice = self.buffer[header_mod.HEADER_SIZE..frame_end];
                const result = Message{
                    .header = hdr,
                    .payload = payload_slice,
                };

                // Shift remaining bytes to the front.
                const remaining = self.length - frame_end;
                if (remaining > 0) {
                    std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[frame_end..self.length]);
                }
                self.length = remaining;

                return result;
            },
            .reading_large => {
                if (self.chunk_length < self.large_frame_size) return null;

                const chunk = self.borrowed_chunk.?;
                const hdr = header_mod.Header.decode(chunk.slice[0..header_mod.HEADER_SIZE]) catch return null;

                const frame_end = header_mod.HEADER_SIZE + hdr.payload_length;
                const payload_slice = chunk.slice[header_mod.HEADER_SIZE..frame_end];
                const result = Message{
                    .header = hdr,
                    .payload = payload_slice,
                };

                // Transition to pending release. The chunk will be freed on
                // the next call to feed() or nextMessage().
                self.state = .large_pending_release;

                return result;
            },
            .large_pending_release => unreachable, // Handled at the top.
        }
    }

    /// Discard all accumulated data and release any borrowed chunk.
    pub fn reset(self: *MessageReader) void {
        self.releaseBorrowedChunk();
        self.length = 0;
        self.state = .reading_header_or_small;
        self.chunk_length = 0;
        self.large_frame_size = 0;
    }

    fn releaseBorrowedChunk(self: *MessageReader) void {
        if (self.borrowed_chunk) |chunk| {
            self.pool.releaseChunk(chunk);
            self.borrowed_chunk = null;
            self.chunk_length = 0;
            self.large_frame_size = 0;
        }
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

/// Test-scoped chunk pool backed by the testing allocator.
const TestChunkPool = struct {
    pool: ChunkPool,
    chunks_borrowed: u32 = 0,
    chunks_released: u32 = 0,

    fn init() TestChunkPool {
        return .{
            .pool = .{
                .context = undefined, // Patched after init.
                .borrow_fn = borrowImpl,
                .release_fn = releaseImpl,
            },
        };
    }

    /// Must be called after init to wire up self-reference.
    fn selfWire(self: *TestChunkPool) *ChunkPool {
        self.pool.context = @ptrCast(self);
        return &self.pool;
    }

    fn borrowImpl(context: *anyopaque) ?ChunkPool.Chunk {
        const self: *TestChunkPool = @ptrCast(@alignCast(context));
        const chunk = std.testing.allocator.create([ChunkPool.Chunk.CHUNK_CAPACITY]u8) catch return null;
        self.chunks_borrowed += 1;
        return .{
            .ptr = @ptrCast(chunk),
            .slice = chunk,
        };
    }

    fn releaseImpl(context: *anyopaque, chunk: ChunkPool.Chunk) void {
        const self: *TestChunkPool = @ptrCast(@alignCast(context));
        const ptr: *[ChunkPool.Chunk.CHUNK_CAPACITY]u8 = @ptrCast(@alignCast(chunk.ptr));
        std.testing.allocator.destroy(ptr);
        self.chunks_released += 1;
    }
};

fn makeHeader(msg_type: u16, payload_length: u32, sequence: u64) [header_mod.HEADER_SIZE]u8 {
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    const hdr = header_mod.Header{
        .msg_type = msg_type,
        .flags = .{},
        .payload_length = payload_length,
        .sequence = sequence,
    };
    hdr.encode(&buf);
    return buf;
}

test "MessageReader: starts empty" {
    var test_pool = TestChunkPool.init();
    var reader = MessageReader{ .pool = test_pool.selfWire() };
    try std.testing.expectEqual(@as(u32, 0), reader.length);
    try std.testing.expect(reader.nextMessage() == null);
}

test "MessageReader: feed and extract complete frame" {
    var test_pool = TestChunkPool.init();
    var reader = MessageReader{ .pool = test_pool.selfWire() };

    var frame_buf: [header_mod.HEADER_SIZE + 5]u8 = undefined;
    const hdr_bytes = makeHeader(0x0100, 5, 1);
    @memcpy(frame_buf[0..header_mod.HEADER_SIZE], &hdr_bytes);
    @memcpy(frame_buf[header_mod.HEADER_SIZE..], "hello");

    try reader.feed(&frame_buf);
    const msg = reader.nextMessage();
    try std.testing.expect(msg != null);
    try std.testing.expectEqual(@as(u16, 0x0100), msg.?.header.msg_type);
    try std.testing.expectEqual(@as(u32, 5), msg.?.header.payload_length);
    try std.testing.expectEqualSlices(u8, "hello", msg.?.payload);
    // After extraction, buffer should be empty.
    try std.testing.expectEqual(@as(u32, 0), reader.length);
}

test "MessageReader: partial header returns null" {
    var test_pool = TestChunkPool.init();
    var reader = MessageReader{ .pool = test_pool.selfWire() };
    // Feed only 8 bytes of a 20-byte header.
    const partial = [_]u8{ 0x49, 0x54, 0x02, 0x00, 0x00, 0x01, 0x00, 0x00 };
    try reader.feed(&partial);
    try std.testing.expect(reader.nextMessage() == null);
    try std.testing.expectEqual(@as(u32, 8), reader.length);
}

test "MessageReader: partial payload returns null, completes on second feed" {
    var test_pool = TestChunkPool.init();
    var reader = MessageReader{ .pool = test_pool.selfWire() };

    const hdr_bytes = makeHeader(0x0200, 10, 1);

    // Feed header + only 5 bytes of payload.
    try reader.feed(&hdr_bytes);
    try reader.feed("hello");
    try std.testing.expect(reader.nextMessage() == null);

    // Feed remaining 5 bytes.
    try reader.feed("world");
    const msg = reader.nextMessage();
    try std.testing.expect(msg != null);
    try std.testing.expectEqual(@as(u32, 10), msg.?.header.payload_length);
    try std.testing.expectEqualSlices(u8, "helloworld", msg.?.payload);
}

test "MessageReader: two frames in one feed" {
    var test_pool = TestChunkPool.init();
    var reader = MessageReader{ .pool = test_pool.selfWire() };

    // Build two complete frames back-to-back.
    var buf: [2 * (header_mod.HEADER_SIZE + 3)]u8 = undefined;
    const hdr1 = makeHeader(0x0100, 3, 1);
    @memcpy(buf[0..header_mod.HEADER_SIZE], &hdr1);
    @memcpy(buf[header_mod.HEADER_SIZE..][0..3], "abc");

    const offset2 = header_mod.HEADER_SIZE + 3;
    const hdr2 = makeHeader(0x0200, 3, 2);
    @memcpy(buf[offset2..][0..header_mod.HEADER_SIZE], &hdr2);
    @memcpy(buf[offset2 + header_mod.HEADER_SIZE ..][0..3], "xyz");

    try reader.feed(&buf);

    const msg1 = reader.nextMessage();
    try std.testing.expect(msg1 != null);
    try std.testing.expectEqual(@as(u16, 0x0100), msg1.?.header.msg_type);
    // Consume payload before next nextMessage() call (payload slice is
    // invalidated by the shift in nextMessage).
    try std.testing.expectEqual(@as(u32, 3), msg1.?.header.payload_length);

    const msg2 = reader.nextMessage();
    try std.testing.expect(msg2 != null);
    try std.testing.expectEqual(@as(u16, 0x0200), msg2.?.header.msg_type);
    try std.testing.expectEqualSlices(u8, "xyz", msg2.?.payload);

    // No more messages.
    try std.testing.expect(reader.nextMessage() == null);
}

test "MessageReader.reset: clears all accumulated data" {
    var test_pool = TestChunkPool.init();
    var reader = MessageReader{ .pool = test_pool.selfWire() };
    try reader.feed("partial-data");
    reader.reset();
    try std.testing.expectEqual(@as(u32, 0), reader.length);
    try std.testing.expect(reader.nextMessage() == null);
}

test "MessageReader: large message borrows from pool and extracts" {
    var test_pool = TestChunkPool.init();
    var reader = MessageReader{ .pool = test_pool.selfWire() };

    // Create a message with payload larger than BUFFER_SIZE (64 KB).
    const payload_size: u32 = MessageReader.BUFFER_SIZE + 1024;
    const hdr_bytes = makeHeader(0x0300, payload_size, 1);

    // Feed the header first.
    try reader.feed(&hdr_bytes);
    try std.testing.expectEqual(MessageReader.ReaderState.reading_large, reader.state);
    try std.testing.expectEqual(@as(u32, 1), test_pool.chunks_borrowed);

    // Feed payload in chunks.
    const payload = try std.testing.allocator.alloc(u8, payload_size);
    defer std.testing.allocator.free(payload);
    for (payload, 0..) |*b, i| {
        b.* = @intCast(i % 256);
    }

    const chunk_size: usize = 8192;
    var offset: usize = 0;
    while (offset < payload.len) {
        const end = @min(offset + chunk_size, payload.len);
        try reader.feed(payload[offset..end]);
        offset = end;
    }

    // Extract the message.
    const msg = reader.nextMessage();
    try std.testing.expect(msg != null);
    try std.testing.expectEqual(@as(u16, 0x0300), msg.?.header.msg_type);
    try std.testing.expectEqual(payload_size, msg.?.header.payload_length);
    try std.testing.expectEqualSlices(u8, payload, msg.?.payload);

    // Chunk should still be held (pending release).
    try std.testing.expectEqual(MessageReader.ReaderState.large_pending_release, reader.state);
    try std.testing.expectEqual(@as(u32, 0), test_pool.chunks_released);

    // Next nextMessage() call releases the chunk.
    try std.testing.expect(reader.nextMessage() == null);
    try std.testing.expectEqual(@as(u32, 1), test_pool.chunks_released);
    try std.testing.expectEqual(MessageReader.ReaderState.reading_header_or_small, reader.state);
}

test "MessageReader: partial large message across multiple feed calls" {
    var test_pool = TestChunkPool.init();
    var reader = MessageReader{ .pool = test_pool.selfWire() };

    const payload_size: u32 = MessageReader.BUFFER_SIZE + 512;
    const hdr_bytes = makeHeader(0x0400, payload_size, 2);

    // Feed header in two parts.
    try reader.feed(hdr_bytes[0..8]);
    try std.testing.expectEqual(MessageReader.ReaderState.reading_header_or_small, reader.state);

    try reader.feed(hdr_bytes[8..]);
    // After the full header is fed and payload exceeds BUFFER_SIZE, should
    // have transitioned to reading_large.
    try std.testing.expectEqual(MessageReader.ReaderState.reading_large, reader.state);

    // Message not complete yet.
    try std.testing.expect(reader.nextMessage() == null);

    // Feed remaining payload.
    const payload = try std.testing.allocator.alloc(u8, payload_size);
    defer std.testing.allocator.free(payload);
    @memset(payload, 0xAB);

    try reader.feed(payload);

    const msg = reader.nextMessage();
    try std.testing.expect(msg != null);
    try std.testing.expectEqual(payload_size, msg.?.header.payload_length);

    // Clean up.
    reader.reset();
}

test "MessageReader.reset: releases borrowed chunk" {
    var test_pool = TestChunkPool.init();
    var reader = MessageReader{ .pool = test_pool.selfWire() };

    const payload_size: u32 = MessageReader.BUFFER_SIZE + 100;
    const hdr_bytes = makeHeader(0x0500, payload_size, 1);

    // Feed header to trigger chunk borrow.
    try reader.feed(&hdr_bytes);
    try std.testing.expectEqual(@as(u32, 1), test_pool.chunks_borrowed);

    // Reset should release the chunk.
    reader.reset();
    try std.testing.expectEqual(@as(u32, 1), test_pool.chunks_released);
    try std.testing.expectEqual(MessageReader.ReaderState.reading_header_or_small, reader.state);
    try std.testing.expectEqual(@as(u32, 0), reader.length);
}

test "MessageReader: message after large message reuses fixed buffer" {
    var test_pool = TestChunkPool.init();
    var reader = MessageReader{ .pool = test_pool.selfWire() };

    // First: a large message.
    const large_payload_size: u32 = MessageReader.BUFFER_SIZE + 256;
    const hdr1 = makeHeader(0x0600, large_payload_size, 1);
    try reader.feed(&hdr1);

    const large_payload = try std.testing.allocator.alloc(u8, large_payload_size);
    defer std.testing.allocator.free(large_payload);
    @memset(large_payload, 0xCC);
    try reader.feed(large_payload);

    const msg1 = reader.nextMessage();
    try std.testing.expect(msg1 != null);
    try std.testing.expectEqual(@as(u16, 0x0600), msg1.?.header.msg_type);

    // Second: a small message. The chunk should be released by feed().
    var small_frame: [header_mod.HEADER_SIZE + 4]u8 = undefined;
    const hdr2 = makeHeader(0x0700, 4, 2);
    @memcpy(small_frame[0..header_mod.HEADER_SIZE], &hdr2);
    @memcpy(small_frame[header_mod.HEADER_SIZE..], "test");

    try reader.feed(&small_frame);
    try std.testing.expectEqual(@as(u32, 1), test_pool.chunks_released);
    try std.testing.expectEqual(MessageReader.ReaderState.reading_header_or_small, reader.state);

    const msg2 = reader.nextMessage();
    try std.testing.expect(msg2 != null);
    try std.testing.expectEqual(@as(u16, 0x0700), msg2.?.header.msg_type);
    try std.testing.expectEqualSlices(u8, "test", msg2.?.payload);
}
