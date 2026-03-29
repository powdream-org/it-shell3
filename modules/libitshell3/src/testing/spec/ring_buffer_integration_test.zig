//! Integration tests: Ring buffer and frame delivery pipeline.
//!
//! End-to-end tests covering the full serialize-to-ring-to-iovec-to-decode
//! pipeline, including multi-cursor sharing, two-channel priority, slow client
//! recovery, byte-granular advancement, frame sequence monotonicity,
//! SessionDeliveryState pane lifecycle, and direct queue FIFO ordering.
//!
//! Spec sources:
//!   - daemon-architecture state-and-types — ring buffer, wire format, cursors
//!   - daemon-behavior policies — frame delivery, write-ready, backpressure

const std = @import("std");
const testing = std.testing;

const server = @import("itshell3_server");
const ring_buffer_mod = server.delivery.ring_buffer;
const frame_serializer_mod = server.delivery.frame_serializer;
const client_writer_mod = server.delivery.client_writer;
const direct_queue_mod = server.delivery.direct_queue;
const pane_delivery_mod = server.delivery.pane_delivery;
const protocol = @import("itshell3_protocol");

const RingBuffer = ring_buffer_mod.RingBuffer;
const RingCursor = ring_buffer_mod.RingCursor;
const CellData = protocol.cell.CellData;
const DirtyRow = protocol.frame_update.DirtyRow;
const FrameHeader = protocol.frame_update.FrameHeader;
const FrameType = protocol.frame_update.FrameType;
const Header = protocol.header.Header;

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

fn makeTestRow(codepoints: []const u32, row_index: u16, cells_buf: []CellData) DirtyRow {
    for (cells_buf[0..codepoints.len], codepoints) |*c, cp| {
        c.* = std.mem.zeroes(CellData);
        c.codepoint = cp;
    }
    return .{
        .header = .{
            .y = row_index,
            .num_cells = @intCast(codepoints.len),
            .row_flags = 0,
            .selection_start = 0,
            .selection_end = 0,
        },
        .cells = cells_buf[0..codepoints.len],
    };
}

/// Read all pending bytes from iovecs into a flat buffer. Returns bytes read.
fn flattenIovecs(p: ring_buffer_mod.PendingIovecs, out: []u8) usize {
    var off: usize = 0;
    for (p.iov[0..p.count]) |v| {
        @memcpy(out[off..][0..v.len], v.base[0..v.len]);
        off += v.len;
    }
    return off;
}

test "spec: ring buffer sharing — multiple cursors share single ring backing" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    try ring.writeFrame("single-frame-payload", false, 1);

    var c1 = RingCursor.init();
    var c2 = RingCursor.init();
    var c3 = RingCursor.init();

    const p1 = ring.pendingIovecs(&c1).?;
    const p2 = ring.pendingIovecs(&c2).?;
    const p3 = ring.pendingIovecs(&c3).?;

    // All three iovecs point into the same backing buffer — zero duplication
    const buf_start = @intFromPtr(ring.buf.ptr);
    const buf_end = buf_start + ring.capacity;

    for (&[_]ring_buffer_mod.PendingIovecs{ p1, p2, p3 }) |p| {
        for (p.iov[0..p.count]) |v| {
            try testing.expect(@intFromPtr(v.base) >= buf_start);
            try testing.expect(@intFromPtr(v.base) < buf_end);
        }
    }

    // All see the same total byte count
    try testing.expectEqual(p1.totalLen(), p2.totalLen());
    try testing.expectEqual(p2.totalLen(), p3.totalLen());
}

test "spec: wire format — iovecs yield decodable protocol message" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;

    var cells: [3]CellData = @splat(std.mem.zeroes(CellData));
    const codepoints = [_]u32{ 0x4E16, 0x754C, '!' }; // 世界!
    const row = makeTestRow(&codepoints, 0, &cells);
    const rows = [_]DirtyRow{row};

    const written = frame_serializer_mod.serializeAndWrite(
        &scratch.buf,
        &ring,
        7,
        42,
        .i_frame,
        &rows,
        &seq,
    ).?;
    try testing.expect(written > 0);

    var cursor = RingCursor.init();
    const p = ring.pendingIovecs(&cursor).?;
    var flat: [8192]u8 = @splat(0);
    const n = flattenIovecs(p, &flat);
    try testing.expectEqual(written, n); // ring stores frame directly, no prefix

    // Decode the wire message from the ring (starts at byte 0)
    const wire = flat[0..written];
    const hdr = try Header.decode(wire[0..protocol.header.HEADER_SIZE]);
    try testing.expectEqual(@as(u16, 0x0300), hdr.msg_type);

    const fh = FrameHeader.decode(
        wire[protocol.header.HEADER_SIZE..][0..protocol.frame_update.FRAME_HEADER_SIZE],
    );
    try testing.expectEqual(@as(u32, 7), fh.session_id);
    try testing.expectEqual(@as(u32, 42), fh.pane_id);
    try testing.expectEqual(FrameType.i_frame, fh.frame_type);
    try testing.expectEqual(@as(u64, 0), fh.frame_sequence);
}

test "spec: two-channel priority — direct queue drained before ring buffer" {
    var cw = client_writer_mod.ClientWriter.init();
    defer cw.deinit();
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    // Both channels have data
    try cw.enqueueDirect("PreeditSync-msg");
    try ring.writeFrame("FrameUpdate-data", true, 1);

    try testing.expect(!cw.direct_queue.isEmpty());
    try testing.expect(ring.available(&cw.ring_cursor) > 0);

    // Drain direct queue
    try testing.expectEqualSlices(u8, "PreeditSync-msg", cw.direct_queue.peek().?);
    cw.direct_queue.dequeue();

    // Direct empty; ring still has data
    try testing.expect(cw.direct_queue.isEmpty());
    try testing.expect(cw.hasPending(&ring));

    // Read ring data via iovecs
    const p = ring.pendingIovecs(&cw.ring_cursor).?;
    var flat: [256]u8 = @splat(0);
    const n = flattenIovecs(p, &flat);
    try testing.expect(n > 0);
    // Payload in ring entry is "FrameUpdate-data" directly (no prefix)
    try testing.expectEqualSlices(u8, "FrameUpdate-data", flat[0.."FrameUpdate-data".len]);
    ring.advanceCursor(&cw.ring_cursor, p.totalLen());

    // Now fully caught up
    try testing.expect(!cw.hasPending(&ring));
}

test "spec: independent cursors — positions and available are orthogonal" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    try ring.writeFrame("frame-1", false, 1);
    try ring.writeFrame("frame-2", false, 2);
    try ring.writeFrame("frame-3", false, 3);

    var ca = RingCursor.init();
    var cb = RingCursor.init();

    // Both see equal available bytes
    try testing.expectEqual(ring.available(&ca), ring.available(&cb));

    // Advance A by one frame (7 bytes = "frame-1" payload)
    ring.advanceCursor(&ca, 7);

    // A sees fewer bytes; B unchanged
    try testing.expect(ring.available(&ca) < ring.available(&cb));
    try testing.expectEqual(@as(usize, 0), cb.position);

    // Advance A to full; B still at 0
    ring.advanceCursor(&ca, ring.available(&ca));
    try testing.expectEqual(@as(usize, 0), ring.available(&ca));
    try testing.expect(ring.available(&cb) > 0);
}

test "spec: zero-copy delivery — single iovec points into ring.buf address range" {
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("zero-copy-payload", false, 1);

    const p = ring.pendingIovecs(&cursor).?;
    try testing.expectEqual(@as(usize, 1), p.count);

    const buf_start = @intFromPtr(ring.buf.ptr);
    const buf_end = buf_start + ring.capacity;
    const iov_base = @intFromPtr(p.iov[0].base);
    try testing.expect(iov_base >= buf_start and iov_base < buf_end);
    try testing.expectEqual(ring.available(&cursor), p.totalLen());
}

test "spec: zero-copy delivery — wrap-around 2 iovecs both in ring.buf with correct concatenation" {
    // 32-byte ring. 3 frames of 11 bytes each (no prefix, entry = 11 bytes).
    // After advancing past first 2 entries (22 bytes), the 3rd entry
    // starts at position 22 and wraps at 32: 10 bytes tail + 1 byte head.
    var backing: [32]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    const payload = [_]u8{'W'} ** 11;
    try ring.writeFrame(&payload, false, 1);
    try ring.writeFrame(&payload, false, 2);
    // Advance cursor past first two entries
    ring.advanceCursor(&cursor, 11);
    ring.advanceCursor(&cursor, 11);
    // Write third entry — wraps
    try ring.writeFrame(&payload, true, 3);

    const p = ring.pendingIovecs(&cursor).?;
    try testing.expectEqual(@as(usize, 2), p.count);

    const buf_start = @intFromPtr(ring.buf.ptr);
    const buf_end = buf_start + ring.capacity;
    for (p.iov[0..2]) |v| {
        try testing.expect(@intFromPtr(v.base) >= buf_start and @intFromPtr(v.base) < buf_end);
    }

    // Concatenation must equal: the payload bytes directly (all 'W')
    var combined: [32]u8 = @splat(0);
    const n = flattenIovecs(p, &combined);
    try testing.expectEqual(@as(usize, 11), n);
    try testing.expectEqualSlices(u8, &payload, combined[0..11]);
}

test "spec: byte-granular cursor — partial advance remaining iovec starts at correct position" {
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    // Write two frames: "hello" (5 bytes) and "world" (5 bytes) = 10 total
    try ring.writeFrame("hello", false, 1);
    try ring.writeFrame("world", false, 2);
    try testing.expectEqual(@as(usize, 10), ring.available(&cursor));

    // Simulate partial write: kernel accepted 3 bytes
    ring.advanceCursor(&cursor, 3);
    try testing.expectEqual(@as(usize, 3), cursor.position);
    try testing.expectEqual(@as(usize, 7), ring.available(&cursor));

    // Next iovec starts at ring position 3
    const p = ring.pendingIovecs(&cursor).?;
    const expected_pos = @intFromPtr(ring.buf.ptr) + 3;
    try testing.expectEqual(expected_pos, @intFromPtr(p.iov[0].base));
    try testing.expectEqual(@as(usize, 7), p.totalLen());
}

test "spec: full delivery — cursor catches up with available zero and no iovecs" {
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("frame-A", false, 1);
    try ring.writeFrame("frame-B", false, 2);

    const total = ring.available(&cursor);
    ring.advanceCursor(&cursor, total);

    try testing.expectEqual(@as(usize, 0), ring.available(&cursor));
    try testing.expect(ring.pendingIovecs(&cursor) == null);
}

test "spec: would_block semantics — cursor unchanged and same iovecs returned on retry" {
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("retry-me", false, 1);

    const avail_before = ring.available(&cursor);
    const pos_before = cursor.position;

    // Simulate would_block: cursor NOT advanced (spec policies write-ready and backpressure .would_block branch)
    // (In real code, writev returns EAGAIN. Here we verify cursor stays put.)
    _ = ring.pendingIovecs(&cursor); // call but don't advance

    try testing.expectEqual(pos_before, cursor.position);
    try testing.expectEqual(avail_before, ring.available(&cursor));

    // Retry: same data available
    const p = ring.pendingIovecs(&cursor).?;
    var flat: [256]u8 = @splat(0);
    const n = flattenIovecs(p, &flat);
    try testing.expectEqual(avail_before, n);
    // First 8 bytes = "retry-me" directly (no prefix)
    try testing.expectEqualSlices(u8, "retry-me", flat[0..8]);
}

test "spec: slow client recovery — overwritten cursor seeks to latest I-frame" {
    var backing: [96]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var slow = RingCursor.init();

    // Fill ring past capacity: 13 entries of 8 bytes each = 104 > 96
    const frame = [_]u8{'Q'} ** 8;
    try ring.writeFrame(&frame, true, 1);
    try ring.writeFrame(&frame, false, 2);
    try ring.writeFrame(&frame, true, 3);
    try ring.writeFrame(&frame, false, 4);
    try ring.writeFrame(&frame, true, 5);
    try ring.writeFrame(&frame, false, 6);
    try ring.writeFrame(&frame, true, 7);
    try ring.writeFrame(&frame, false, 8);
    try ring.writeFrame(&frame, true, 9);
    try ring.writeFrame(&frame, false, 10);
    try ring.writeFrame(&frame, true, 11);
    try ring.writeFrame(&frame, false, 12);
    try ring.writeFrame(&frame, true, 13); // seq=13, latest I-frame

    try testing.expect(ring.isCursorOverwritten(&slow));

    // Recovery: seek to latest I-frame
    ring.seekToLatestIFrame(&slow);
    try testing.expect(!ring.isCursorOverwritten(&slow));
    try testing.expect(ring.available(&slow) > 0);

    // Read via iovecs — must be valid and start at latest I-frame
    const p = ring.pendingIovecs(&slow).?;
    var flat: [256]u8 = @splat(0);
    _ = flattenIovecs(p, &flat);
    // The I-frame payload is 8 bytes of 'Q' directly (no prefix)
    try testing.expectEqualSlices(u8, &frame, flat[0..8]);
}

test "spec: I-frame scheduling — empty P-frame skipped and I-frame written" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;

    // Empty P-frame: serializeAndWrite returns null, ring unchanged
    const p_result = frame_serializer_mod.serializeAndWrite(
        &scratch.buf,
        &ring,
        1,
        1,
        .p_frame,
        &.{},
        &seq,
    );
    try testing.expect(p_result == null);
    try testing.expectEqual(@as(u64, 0), seq);
    try testing.expectEqual(@as(usize, 0), ring.frame_count);

    // I-frame with no dirty rows: written (ring_count increases)
    const i_result = frame_serializer_mod.serializeAndWrite(
        &scratch.buf,
        &ring,
        1,
        1,
        .i_frame,
        &.{},
        &seq,
    );
    try testing.expect(i_result != null);
    try testing.expectEqual(@as(u64, 1), seq);
    try testing.expectEqual(@as(usize, 1), ring.frame_count);
    try testing.expect(ring.has_i_frame);
}

test "spec: multi-client ring read — independent cursor positions with same backing" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;

    var cells: [2]CellData = @splat(std.mem.zeroes(CellData));
    const row = makeTestRow(&[_]u32{ 'A', 'B' }, 0, &cells);

    _ = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, .i_frame, &[_]DirtyRow{row}, &seq);
    _ = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, .p_frame, &[_]DirtyRow{row}, &seq);
    _ = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, .p_frame, &[_]DirtyRow{row}, &seq);

    var ca = RingCursor.init();
    var cb = RingCursor.init();

    try testing.expectEqual(ring.available(&ca), ring.available(&cb));

    // Advance A through all frames
    ring.advanceCursor(&ca, ring.available(&ca));
    try testing.expectEqual(@as(usize, 0), ring.available(&ca));

    // B is unchanged
    try testing.expect(ring.available(&cb) > 0);
    try testing.expectEqual(@as(usize, 0), cb.position);

    // Both cursors' iovecs (when available) point into same ring backing
    const pb = ring.pendingIovecs(&cb).?;
    const buf_start = @intFromPtr(ring.buf.ptr);
    const buf_end = buf_start + ring.capacity;
    for (pb.iov[0..pb.count]) |v| {
        try testing.expect(@intFromPtr(v.base) >= buf_start and @intFromPtr(v.base) < buf_end);
    }
}

test "spec: pane delivery lifecycle — SessionDeliveryState allocates and frees rings" {
    var state = pane_delivery_mod.SessionDeliveryState.init();
    defer state.deinit();

    // Initially all slots null
    for (0..16) |i| {
        try testing.expect(state.getRingBuffer(@intCast(i)) == null);
    }

    try state.initPaneRing(0);
    try state.initPaneRing(5);

    const r0 = state.getRingBuffer(0).?;
    const r5 = state.getRingBuffer(5).?;

    try r0.writeFrame("pane-zero", true, 1);
    try r5.writeFrame("pane-five", true, 1);

    // Each ring independent
    try testing.expectEqual(@as(usize, 1), r0.frame_count);
    try testing.expectEqual(@as(usize, 1), r5.frame_count);

    // Verify data via iovecs
    var c0 = RingCursor.init();
    var c5 = RingCursor.init();
    const p0 = r0.pendingIovecs(&c0).?;
    const p5 = r5.pendingIovecs(&c5).?;
    var f0: [256]u8 = @splat(0);
    var f5: [256]u8 = @splat(0);
    const n0 = flattenIovecs(p0, &f0);
    const n5 = flattenIovecs(p5, &f5);
    // Ring stores frame data directly (no length prefix)
    try testing.expectEqual(@as(usize, 9), n0); // len("pane-zero") = 9
    try testing.expectEqual(@as(usize, 9), n5); // len("pane-five") = 9
    try testing.expectEqualSlices(u8, "pane-zero", f0[0..9]);
    try testing.expectEqualSlices(u8, "pane-five", f5[0..9]);

    // Free pane 0, pane 5 survives
    state.deinitPaneRing(0);
    try testing.expect(state.getRingBuffer(0) == null);
    try testing.expect(state.getRingBuffer(5) != null);
}

test "spec: cursor edge cases — advanceCursor zero no-op and cursor at write_pos yields null iovecs" {
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("data", false, 1);

    // advanceCursor(0) must not move cursor
    const before = cursor.position;
    ring.advanceCursor(&cursor, 0);
    try testing.expectEqual(before, cursor.position);

    // Advance to caught-up position
    ring.advanceCursor(&cursor, ring.available(&cursor));
    try testing.expectEqual(ring.total_written, cursor.position);
    try testing.expect(ring.pendingIovecs(&cursor) == null);
}

test "spec: full pipeline — serialize to ring to iovecs to decoded protocol message" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;
    var cursor = RingCursor.init();

    var cells: [5]CellData = @splat(std.mem.zeroes(CellData));
    const codepoints = [_]u32{ 0x4E16, 0x754C, 0x4F60, 0x597D, '!' };
    const row = makeTestRow(&codepoints, 0, &cells);
    const rows = [_]DirtyRow{row};

    const written = frame_serializer_mod.serializeAndWrite(
        &scratch.buf,
        &ring,
        7,
        42,
        .i_frame,
        &rows,
        &seq,
    ).?;
    try testing.expect(written > 0);
    try testing.expectEqual(@as(u64, 1), seq);

    // Cursor NOT advanced yet
    try testing.expectEqual(@as(usize, 0), cursor.position);

    const p = ring.pendingIovecs(&cursor).?;
    var flat: [8192]u8 = @splat(0);
    const n = flattenIovecs(p, &flat);
    // Ring stores wire frame directly (no prefix): total bytes in ring = written
    try testing.expectEqual(written, n);

    // Decode wire message (starts at byte 0, no prefix to skip)
    const wire = flat[0..written];
    const hdr = try Header.decode(wire[0..protocol.header.HEADER_SIZE]);
    try testing.expectEqual(@as(u16, 0x0300), hdr.msg_type);

    const fh = FrameHeader.decode(
        wire[protocol.header.HEADER_SIZE..][0..protocol.frame_update.FRAME_HEADER_SIZE],
    );
    try testing.expectEqual(@as(u32, 7), fh.session_id);
    try testing.expectEqual(@as(u32, 42), fh.pane_id);
    try testing.expectEqual(FrameType.i_frame, fh.frame_type);
    try testing.expect(fh.hasDirtyRows());

    // Advance cursor by all bytes — fully caught up
    ring.advanceCursor(&cursor, n);
    try testing.expect(ring.pendingIovecs(&cursor) == null);
}

test "spec: slow client recovery — fast vs slow client divergence and iovec recovery" {
    var backing: [128]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var fast = RingCursor.init();
    var slow = RingCursor.init();

    // Write frames. Fast cursor keeps up. Slow cursor never reads.
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const is_i = (i % 4 == 0);
        try ring.writeFrame("test-data-frame", is_i, @intCast(i));

        // Fast cursor drains via byte-granular advanceCursor
        const avail = ring.available(&fast);
        if (avail > 0) ring.advanceCursor(&fast, avail);
    }

    // Fast is caught up
    try testing.expectEqual(@as(usize, 0), ring.available(&fast));
    try testing.expect(!ring.isCursorOverwritten(&fast));

    // Slow is overwritten
    try testing.expect(ring.isCursorOverwritten(&slow));

    // Recovery: seek to latest I-frame
    ring.seekToLatestIFrame(&slow);
    try testing.expect(!ring.isCursorOverwritten(&slow));
    try testing.expect(ring.available(&slow) > 0);

    // Read recovered data via iovecs — must be non-empty
    const p = ring.pendingIovecs(&slow).?;
    try testing.expect(p.totalLen() > 0);
    const buf_start = @intFromPtr(ring.buf.ptr);
    const buf_end = buf_start + ring.capacity;
    for (p.iov[0..p.count]) |v| {
        try testing.expect(@intFromPtr(v.base) >= buf_start and @intFromPtr(v.base) < buf_end);
    }
}

test "spec: write-ready delivery — single writev spanning all pending frames" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    // Write 5 frames
    try ring.writeFrame("frame-1", false, 1);
    try ring.writeFrame("frame-2", false, 2);
    try ring.writeFrame("frame-3", false, 3);
    try ring.writeFrame("frame-4", false, 4);
    try ring.writeFrame("frame-5", false, 5);

    const total_avail = ring.available(&cursor);

    // pendingIovecs spans ALL pending bytes (not just one frame)
    const p = ring.pendingIovecs(&cursor).?;
    try testing.expectEqual(total_avail, p.totalLen());

    // Single advanceCursor by total — equivalent to writev return value
    ring.advanceCursor(&cursor, total_avail);
    try testing.expectEqual(@as(usize, 0), ring.available(&cursor));
}

test "spec: I-frame seek — seekToLatestIFrame selects most recent I-frame" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("I-FRAME-001", true, 1);
    try ring.writeFrame("P-frame-002", false, 2);
    try ring.writeFrame("I-FRAME-003", true, 3);
    try ring.writeFrame("P-frame-004", false, 4);
    try ring.writeFrame("I-FRAME-006", true, 6);
    try ring.writeFrame("P-frame-007", false, 7);

    ring.seekToLatestIFrame(&cursor);

    // Read from cursor: first bytes are "I-FRAME-006" directly (no prefix)
    const p = ring.pendingIovecs(&cursor).?;
    var flat: [256]u8 = @splat(0);
    _ = flattenIovecs(p, &flat);
    try testing.expectEqualSlices(u8, "I-FRAME-006", flat[0..11]);
}

test "spec: cursor I-frame tracking — last_i_frame field updated on seekToLatestIFrame" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try testing.expectEqual(@as(usize, 0), cursor.last_i_frame);

    try ring.writeFrame("I-FRAME-A", true, 1);
    ring.seekToLatestIFrame(&cursor);

    // last_i_frame should be updated to the I-frame's offset
    const meta = ring.frame_index[ring.latest_i_frame_idx];
    try testing.expectEqual(meta.total_offset, cursor.last_i_frame);
}

test "spec: frame delivery — frame sequence monotonicity through serializer and iovecs" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;
    var cursor = RingCursor.init();

    var cells: [1]CellData = .{std.mem.zeroes(CellData)};
    const row = makeTestRow(&[_]u32{'X'}, 0, &cells);
    const rows = [_]DirtyRow{row};

    // Write 5 frames
    for (0..5) |i| {
        const ft: FrameType = if (i == 0) .i_frame else .p_frame;
        _ = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, ft, &rows, &seq);
    }
    try testing.expectEqual(@as(u64, 5), seq);

    // Read all frames via byte-granular advancement and verify monotonic sequences.
    // Each frame is a complete wire message: [16-byte header][payload].
    // The protocol header's payload_length tells us the total frame size.
    var prev_fseq: u64 = 0;
    var count: usize = 0;
    while (ring.available(&cursor) > 0) {
        const min_read = protocol.header.HEADER_SIZE + protocol.frame_update.FRAME_HEADER_SIZE;
        if (ring.available(&cursor) < min_read) break;

        const p = ring.pendingIovecs(&cursor).?;
        var flat: [8192]u8 = @splat(0);
        _ = flattenIovecs(p, &flat);

        // Parse the protocol header to get payload_length
        const hdr = try Header.decode(flat[0..protocol.header.HEADER_SIZE]);
        const frame_total = protocol.header.HEADER_SIZE + hdr.payload_length;

        const fh = FrameHeader.decode(
            flat[protocol.header.HEADER_SIZE..][0..protocol.frame_update.FRAME_HEADER_SIZE],
        );
        if (count > 0) {
            try testing.expect(fh.frame_sequence > prev_fseq);
        }
        prev_fseq = fh.frame_sequence;
        count += 1;

        // Advance past this frame (protocol header + payload)
        ring.advanceCursor(&cursor, frame_total);
    }
    try testing.expectEqual(@as(usize, 5), count);
}

test "spec: two-channel priority — direct queue FIFO ordering preserved under interleaving" {
    var q = direct_queue_mod.DirectQueue.init();

    try q.enqueue("LayoutChanged");
    try q.enqueue("PreeditSync");
    try q.enqueue("PreeditUpdate");

    try testing.expectEqualSlices(u8, "LayoutChanged", q.peek().?);
    q.dequeue();

    try q.enqueue("PreeditEnd");

    try testing.expectEqualSlices(u8, "PreeditSync", q.peek().?);
    q.dequeue();
    try testing.expectEqualSlices(u8, "PreeditUpdate", q.peek().?);
    q.dequeue();
    try testing.expectEqualSlices(u8, "PreeditEnd", q.peek().?);
    q.dequeue();
    try testing.expect(q.isEmpty());
}

// ---------------------------------------------------------------------------
// Test 22: Ring FrameMeta index wraps correctly at MAX_FRAME_INDEX.
// ---------------------------------------------------------------------------

test "spec: frame index wrapping — wraps at MAX_FRAME_INDEX boundary with valid latest I-frame" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    var i: usize = 0;
    while (i < ring_buffer_mod.MAX_FRAME_INDEX + 10) : (i += 1) {
        try ring.writeFrame("frame-data", i % 10 == 0, @intCast(i));
    }

    try testing.expectEqual(ring_buffer_mod.MAX_FRAME_INDEX + 10, ring.frame_count);
    try testing.expect(ring.has_i_frame);
    try testing.expect(ring.hasValidIFrame());
    try testing.expect(ring.latest_i_frame_idx < ring_buffer_mod.MAX_FRAME_INDEX);
    try testing.expect(ring.frame_index[ring.latest_i_frame_idx].is_i_frame);
}

// ---------------------------------------------------------------------------
// Test 23: state-and-types per-pane ring buffer — O(1) write: frame_count and total_written are monotonic.
// ---------------------------------------------------------------------------

test "spec: monotonic invariants — frame_count and total_written always increase" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var prev_total: usize = 0;
    var prev_count: usize = 0;

    for (0..10) |i| {
        try ring.writeFrame("monotonic-test", i % 3 == 0, @intCast(i));
        try testing.expect(ring.total_written > prev_total);
        try testing.expect(ring.frame_count > prev_count);
        try testing.expectEqual(prev_total + "monotonic-test".len, ring.total_written);
        prev_total = ring.total_written;
        prev_count = ring.frame_count;
    }
}

// ---------------------------------------------------------------------------
// Test 24: state-and-types per-pane ring buffer1 — Multi-pane independent rings via SessionDeliveryState.
// ---------------------------------------------------------------------------

test "spec: multi-pane delivery — SessionDeliveryState pane slots are independent" {
    var state = pane_delivery_mod.SessionDeliveryState.init();
    defer state.deinit();

    try state.initPaneRing(0);
    try state.initPaneRing(7);
    try state.initPaneRing(15);

    const r0 = state.getRingBuffer(0).?;
    const r7 = state.getRingBuffer(7).?;
    const r15 = state.getRingBuffer(15).?;

    try r0.writeFrame("pane-zero", true, 1);
    try r7.writeFrame("pane-seven", true, 1);
    try r15.writeFrame("pane-fifteen", true, 1);

    try testing.expectEqual(@as(usize, 1), r0.frame_count);
    try testing.expectEqual(@as(usize, 1), r7.frame_count);
    try testing.expectEqual(@as(usize, 1), r15.frame_count);

    // Read from each pane with separate cursors via iovecs
    var c0 = RingCursor.init();
    var c7 = RingCursor.init();
    var c15 = RingCursor.init();
    var out: [256]u8 = @splat(0);

    const p0 = r0.pendingIovecs(&c0).?;
    _ = flattenIovecs(p0, &out);
    try testing.expectEqualSlices(u8, "pane-zero", out[0..9]); // "pane-zero" directly

    const p7 = r7.pendingIovecs(&c7).?;
    _ = flattenIovecs(p7, &out);
    try testing.expectEqualSlices(u8, "pane-seven", out[0..10]); // "pane-seven" directly

    const p15 = r15.pendingIovecs(&c15).?;
    _ = flattenIovecs(p15, &out);
    try testing.expectEqualSlices(u8, "pane-fifteen", out[0..12]); // "pane-fifteen" directly

    // Dealloc pane 7; 0 and 15 unaffected
    state.deinitPaneRing(7);
    try testing.expect(state.getRingBuffer(7) == null);
    try testing.expect(state.getRingBuffer(0) != null);
    try testing.expect(state.getRingBuffer(15) != null);
}

// ---------------------------------------------------------------------------
// Test 25: Per-pane sequence counters in SessionDeliveryState are independent.
// ---------------------------------------------------------------------------

test "spec: per-pane sequence — counters independent via SessionDeliveryState" {
    var state = pane_delivery_mod.SessionDeliveryState.init();
    defer state.deinit();

    for (0..16) |i| {
        try testing.expectEqual(@as(u64, 0), state.next_sequences[@intCast(i)]);
    }

    try state.initPaneRing(3);
    state.next_sequences[3] = 42;
    try testing.expectEqual(@as(u64, 0), state.next_sequences[0]);
    try testing.expectEqual(@as(u64, 42), state.next_sequences[3]);

    state.deinitPaneRing(3);
    try state.initPaneRing(3);
    try testing.expectEqual(@as(u64, 0), state.next_sequences[3]);
}

// ---------------------------------------------------------------------------
// Test 26: Direct queue wrap-around — peekCopy handles wrapped messages.
// ---------------------------------------------------------------------------

test "spec: direct queue — wrap-around handled by peekCopy" {
    var q = direct_queue_mod.DirectQueue.init();

    const fill_size = direct_queue_mod.QUEUE_CAPACITY - 64;
    const fill = [_]u8{'F'} ** fill_size;
    try q.enqueue(&fill);
    q.dequeue();

    const wrap_msg = "this-message-wraps-around-the-buffer-boundary!!";
    try q.enqueue(wrap_msg);

    var out: [256]u8 = @splat(0);
    const n = q.peekCopy(&out).?;
    try testing.expectEqualSlices(u8, wrap_msg, out[0..n]);
}

// ---------------------------------------------------------------------------
// Test 27: policies write-ready and backpressure — cursor at total_written means fully caught up; no iovecs.
// ---------------------------------------------------------------------------

test "spec: caught-up cursor — cursor at total_written yields zero available and null pendingIovecs" {
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("data", false, 1);
    try testing.expect(cursor.position < ring.total_written);

    ring.advanceCursor(&cursor, ring.available(&cursor));
    try testing.expectEqual(ring.total_written, cursor.position);
    try testing.expectEqual(@as(usize, 0), ring.available(&cursor));
    try testing.expect(ring.pendingIovecs(&cursor) == null);
}

// ---------------------------------------------------------------------------
// Test 28: seekToLatestIFrame no-op when no I-frames exist.
// ---------------------------------------------------------------------------

test "spec: I-frame seek — no-op when no I-frames have been written" {
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("p-only-1", false, 1);
    try ring.writeFrame("p-only-2", false, 2);

    try testing.expect(!ring.has_i_frame);
    try testing.expect(!ring.hasValidIFrame());

    const saved = cursor.position;
    ring.seekToLatestIFrame(&cursor);
    try testing.expectEqual(saved, cursor.position);
}
