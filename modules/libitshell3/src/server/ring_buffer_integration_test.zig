// server/ring_buffer_integration_test.zig
//
// Integration tests for the ring buffer + frame delivery pipeline.
// Tests verify semantics from the design spec, NOT just line coverage.
//
// Scenarios covered:
//   1. Full pipeline: serialize -> ring -> peek -> decode
//   2. Multi-client independent cursor reads
//   3. Slow client recovery (overwrite -> seek -> read I-frame)
//   4. Two-channel priority ordering (direct before ring)
//   5. Wrap-around data integrity
//   6. PaneDeliveryState lifecycle
//   7. Ring buffer invariants (monotonic counters, cursor overwrite detection)
//   8. Frame sequence monotonicity through serializer
//   9. I-frame scheduling semantics (empty P-frame skip, I-frame always writes)
//  10. Concurrent cursor positions (fast vs slow client divergence)
//  11. Ring boundary: frame straddling the wrap point
//  12. seekToLatestIFrame after multiple I-frames
//  13. Direct queue FIFO ordering preserved under interleaving
//  14. ClientWriter hasPending state tracking across channels

const std = @import("std");
const testing = std.testing;

const ring_buffer_mod = @import("ring_buffer.zig");
const frame_serializer_mod = @import("frame_serializer.zig");
const client_writer_mod = @import("client_writer.zig");
const direct_queue_mod = @import("direct_queue.zig");
const pane_delivery_mod = @import("pane_delivery.zig");
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

// ---------------------------------------------------------------------------
// Test 1: Full pipeline: serialize -> ring -> peek -> decode
// ---------------------------------------------------------------------------

test "integration: full pipeline serialize -> ring -> peek -> decode" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;
    var cursor = RingCursor.init();

    // Create a row with CJK characters (worst-case scenario from spec)
    var cells: [5]CellData = @splat(std.mem.zeroes(CellData));
    const codepoints = [_]u32{ 0x4E16, 0x754C, 0x4F60, 0x597D, '!' }; // 世界你好!
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

    // Peek and decode the full wire message
    var read_buf: [8192]u8 = @splat(0);
    const read_n = ring.peekFrame(&cursor, &read_buf).?;
    try testing.expectEqual(written, read_n);

    // Verify protocol header
    const hdr = try Header.decode(read_buf[0..protocol.header.HEADER_SIZE]);
    try testing.expectEqual(@as(u16, 0x0300), hdr.msg_type);

    // Verify frame header
    const fh = FrameHeader.decode(
        read_buf[protocol.header.HEADER_SIZE..][0..protocol.frame_update.FRAME_HEADER_SIZE],
    );
    try testing.expectEqual(@as(u32, 7), fh.session_id);
    try testing.expectEqual(@as(u32, 42), fh.pane_id);
    try testing.expectEqual(FrameType.i_frame, fh.frame_type);
    try testing.expect(fh.hasDirtyRows());
    try testing.expectEqual(@as(u64, 0), fh.frame_sequence);

    // Verify cursor was NOT advanced by peekFrame
    try testing.expectEqual(@as(usize, 0), cursor.total_read);

    // Advance and verify no more data
    ring.advancePastFrame(&cursor, read_n);
    try testing.expect(cursor.total_read > 0);
    try testing.expect(ring.peekFrame(&cursor, &read_buf) == null);
}

// ---------------------------------------------------------------------------
// Test 2: Multi-client independent cursor reads
// ---------------------------------------------------------------------------

test "integration: multi-client independent cursor reads" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;
    var cursor_a = RingCursor.init();
    var cursor_b = RingCursor.init();

    // Write 3 frames with distinct data
    var cells1: [2]CellData = @splat(std.mem.zeroes(CellData));
    var cells2: [2]CellData = @splat(std.mem.zeroes(CellData));
    var cells3: [2]CellData = @splat(std.mem.zeroes(CellData));

    const row1 = makeTestRow(&[_]u32{ 'A', 'B' }, 0, &cells1);
    const row2 = makeTestRow(&[_]u32{ 'C', 'D' }, 1, &cells2);
    const row3 = makeTestRow(&[_]u32{ 'E', 'F' }, 2, &cells3);

    _ = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, .i_frame, &[_]DirtyRow{row1}, &seq);
    _ = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, .p_frame, &[_]DirtyRow{row2}, &seq);
    _ = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, .p_frame, &[_]DirtyRow{row3}, &seq);

    // Both cursors should see 3 frames worth of data
    try testing.expect(ring.available(&cursor_a) > 0);
    try testing.expect(ring.available(&cursor_b) > 0);
    try testing.expectEqual(ring.available(&cursor_a), ring.available(&cursor_b));

    // Client A reads frame 1 into its own buffer
    var buf_a1: [8192]u8 = @splat(0);
    const a1_len = ring.peekFrame(&cursor_a, &buf_a1).?;
    ring.advancePastFrame(&cursor_a, a1_len);

    // Client B still at position 0
    try testing.expectEqual(@as(usize, 0), cursor_b.total_read);

    // Client B reads frame 1 into its own buffer
    var buf_b1: [8192]u8 = @splat(0);
    const b1_len = ring.peekFrame(&cursor_b, &buf_b1).?;

    // Both clients read identical first frame (same data, same length)
    try testing.expectEqual(a1_len, b1_len);
    try testing.expectEqualSlices(u8, buf_a1[0..a1_len], buf_b1[0..b1_len]);

    // Client B advances through all 3 frames
    ring.advancePastFrame(&cursor_b, b1_len);
    var skip_buf: [8192]u8 = @splat(0);
    const skip2_len = ring.peekFrame(&cursor_b, &skip_buf).?;
    ring.advancePastFrame(&cursor_b, skip2_len);
    const skip3_len = ring.peekFrame(&cursor_b, &skip_buf).?;
    ring.advancePastFrame(&cursor_b, skip3_len);

    // Client A has 2 more frames to read; Client B is caught up
    var check_buf: [8192]u8 = @splat(0);
    try testing.expect(ring.peekFrame(&cursor_a, &check_buf) != null); // A has 2 more
    try testing.expect(ring.peekFrame(&cursor_b, &check_buf) == null); // B is caught up
}

// ---------------------------------------------------------------------------
// Test 3: Slow client recovery (overwrite -> seek -> read I-frame)
// ---------------------------------------------------------------------------

test "integration: slow client recovery after overwrite" {
    // Use a ring large enough to always hold the latest I-frame (spec §4.1)
    // but small enough that slow clients get overwritten quickly.
    // Each serialized frame ~71 bytes. Ring of 1024 holds ~14 frames.
    // With I-frame every 3rd frame, the latest I-frame is always in ring.
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;
    var slow_cursor = RingCursor.init();
    var fast_cursor = RingCursor.init();

    var cells: [1]CellData = .{std.mem.zeroes(CellData)};
    const row = makeTestRow(&[_]u32{'Q'}, 0, &cells);
    const rows = [_]DirtyRow{row};

    // Write frames until slow cursor is overwritten.
    // Fast cursor keeps up by reading each frame.
    // I-frames every 3rd frame ensures one is always in the ring.
    var count: usize = 0;
    while (!ring.isCursorOverwritten(&slow_cursor) and count < 200) {
        const ft: FrameType = if (count % 3 == 0) .i_frame else .p_frame;
        _ = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, ft, &rows, &seq);

        // Fast cursor keeps up — drain all available frames
        var fast_buf: [8192]u8 = @splat(0);
        while (ring.peekFrame(&fast_cursor, &fast_buf)) |len| {
            ring.advancePastFrame(&fast_cursor, len);
        }
        count += 1;
    }

    // Verify slow cursor IS overwritten, fast cursor is NOT
    try testing.expect(ring.isCursorOverwritten(&slow_cursor));
    try testing.expect(!ring.isCursorOverwritten(&fast_cursor));

    // Slow client recovery: seek to latest I-frame
    ring.seekToLatestIFrame(&slow_cursor);

    // After recovery, cursor should not be overwritten
    try testing.expect(!ring.isCursorOverwritten(&slow_cursor));

    // The first frame the slow client reads should be available
    var recovery_buf: [8192]u8 = @splat(0);
    const recovery_n = ring.peekFrame(&slow_cursor, &recovery_buf);
    try testing.expect(recovery_n != null);

    // Decode the recovered frame to verify it's a valid protocol message
    const hdr = try Header.decode(recovery_buf[0..protocol.header.HEADER_SIZE]);
    try testing.expectEqual(@as(u16, 0x0300), hdr.msg_type);

    // The frame header should indicate an I-frame
    const fh = FrameHeader.decode(
        recovery_buf[protocol.header.HEADER_SIZE..][0..protocol.frame_update.FRAME_HEADER_SIZE],
    );
    try testing.expectEqual(FrameType.i_frame, fh.frame_type);
}

// ---------------------------------------------------------------------------
// Test 4: Two-channel priority ordering (direct before ring)
// ---------------------------------------------------------------------------

test "integration: two-channel priority — direct queue before ring" {
    var cw = client_writer_mod.ClientWriter.init();
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    // Enqueue control message (priority 1) and frame data (priority 2)
    try cw.enqueueDirect("PreeditSync-msg");
    try ring.writeFrame("FrameUpdate-data", true, 1);

    // Both channels have data
    try testing.expect(cw.hasPending(&ring));
    try testing.expect(!cw.direct_queue.isEmpty());
    try testing.expect(ring.available(&cw.ring_cursor) > 0);

    // After draining direct queue, ring should still have data
    const direct_data = cw.direct_queue.peek().?;
    try testing.expectEqualSlices(u8, "PreeditSync-msg", direct_data);
    cw.direct_queue.dequeue();

    // Direct is empty, ring still pending
    try testing.expect(cw.direct_queue.isEmpty());
    try testing.expect(cw.hasPending(&ring));

    // Read ring frame
    var buf: [256]u8 = @splat(0);
    const n = ring.peekFrame(&cw.ring_cursor, &buf).?;
    try testing.expectEqualSlices(u8, "FrameUpdate-data", buf[0..n]);
    ring.advancePastFrame(&cw.ring_cursor, n);

    // Now fully caught up
    try testing.expect(!cw.hasPending(&ring));
}

// ---------------------------------------------------------------------------
// Test 5: Wrap-around data integrity
// ---------------------------------------------------------------------------

test "integration: wrap-around preserves frame data integrity" {
    // Each serialized frame with 1 cell is ~67 bytes (entry = ~71 with prefix).
    // Ring of 256 bytes holds ~3 frames. The 3rd frame wraps around.
    var backing: [256]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;
    var cursor = RingCursor.init();

    var cells: [1]CellData = .{std.mem.zeroes(CellData)};

    // Write frame 1 (I-frame with codepoint 'A')
    cells[0] = std.mem.zeroes(CellData);
    cells[0].codepoint = 'A';
    const row_a = DirtyRow{
        .header = .{ .y = 0, .num_cells = 1, .row_flags = 0, .selection_start = 0, .selection_end = 0 },
        .cells = &cells,
    };
    const w1 = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, .i_frame, &[_]DirtyRow{row_a}, &seq);
    try testing.expect(w1 != null);

    // Read frame 1 and advance
    var buf: [8192]u8 = @splat(0);
    const n1 = ring.peekFrame(&cursor, &buf).?;
    ring.advancePastFrame(&cursor, n1);

    // Write frame 2 (P-frame with codepoint 'B')
    cells[0] = std.mem.zeroes(CellData);
    cells[0].codepoint = 'B';
    const row_b = DirtyRow{
        .header = .{ .y = 0, .num_cells = 1, .row_flags = 0, .selection_start = 0, .selection_end = 0 },
        .cells = &cells,
    };
    const w2 = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, .p_frame, &[_]DirtyRow{row_b}, &seq);
    try testing.expect(w2 != null);

    // Read frame 2 and advance
    const n2 = ring.peekFrame(&cursor, &buf).?;
    ring.advancePastFrame(&cursor, n2);

    // Write frame 3 (P-frame with codepoint 'C') — this wraps around in the ring
    cells[0] = std.mem.zeroes(CellData);
    cells[0].codepoint = 'C';
    const row_c = DirtyRow{
        .header = .{ .y = 0, .num_cells = 1, .row_flags = 0, .selection_start = 0, .selection_end = 0 },
        .cells = &cells,
    };
    const w3 = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, .p_frame, &[_]DirtyRow{row_c}, &seq);
    try testing.expect(w3 != null);

    // Read frame 3 — should be valid despite wrapping
    const n3 = ring.peekFrame(&cursor, &buf).?;
    try testing.expect(n3 > 0);

    // Decode and verify it's a valid protocol message
    const hdr = try Header.decode(buf[0..protocol.header.HEADER_SIZE]);
    try testing.expectEqual(@as(u16, 0x0300), hdr.msg_type);

    const fh = FrameHeader.decode(
        buf[protocol.header.HEADER_SIZE..][0..protocol.frame_update.FRAME_HEADER_SIZE],
    );
    try testing.expectEqual(FrameType.p_frame, fh.frame_type);
    try testing.expectEqual(@as(u64, 2), fh.frame_sequence);
}

// ---------------------------------------------------------------------------
// Test 6: PaneDeliveryState lifecycle
// ---------------------------------------------------------------------------

test "integration: PaneDeliveryState full lifecycle" {
    var state = pane_delivery_mod.SessionDeliveryState.init();
    defer state.deinit();

    // Allocate ring for pane 0
    try state.initPaneRing(0);
    const ring = state.getRingBuffer(0).?;

    // Write a frame and verify ring is functional
    try ring.writeFrame("lifecycle-frame-1", true, 1);
    try testing.expect(ring.hasValidIFrame());
    try testing.expectEqual(@as(usize, 1), ring.frame_count);

    // Read back
    var cursor = ring_buffer_mod.RingCursor.init();
    var out: [256]u8 = @splat(0);
    const n = ring.peekFrame(&cursor, &out).?;
    try testing.expectEqualSlices(u8, "lifecycle-frame-1", out[0..n]);

    // Allocate second pane, verify independence
    try state.initPaneRing(5);
    const ring5 = state.getRingBuffer(5).?;
    try ring5.writeFrame("pane-5-frame", false, 1);
    try testing.expectEqual(@as(usize, 1), ring5.frame_count);
    try testing.expectEqual(@as(usize, 1), ring.frame_count); // pane 0 unchanged

    // Deallocate pane 0
    state.deinitPaneRing(0);
    try testing.expect(state.getRingBuffer(0) == null);
    try testing.expect(state.getRingBuffer(5) != null); // pane 5 still alive

    // Deallocate pane 5
    state.deinitPaneRing(5);
    try testing.expect(state.getRingBuffer(5) == null);
}

// ---------------------------------------------------------------------------
// Test 7: Ring buffer invariants — monotonic counters
// ---------------------------------------------------------------------------

test "integration: monotonic counter invariants" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var prev_total: usize = 0;
    var prev_frame_count: usize = 0;

    // Write 10 frames and verify total_written and frame_count are strictly monotonic
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const payload = "monotonic-test";
        try ring.writeFrame(payload, i % 3 == 0, @intCast(i));

        try testing.expect(ring.total_written > prev_total);
        try testing.expect(ring.frame_count > prev_frame_count);
        try testing.expectEqual(prev_total + 4 + payload.len, ring.total_written);

        prev_total = ring.total_written;
        prev_frame_count = ring.frame_count;
    }
}

// ---------------------------------------------------------------------------
// Test 8: Frame sequence monotonicity through serializer
// ---------------------------------------------------------------------------

test "integration: frame sequence monotonicity through serializer" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;
    var cursor = RingCursor.init();

    var cells: [1]CellData = .{std.mem.zeroes(CellData)};
    const row = makeTestRow(&[_]u32{'X'}, 0, &cells);
    const rows = [_]DirtyRow{row};

    // Write 5 frames
    var expected_seq: u64 = 0;
    var frame_count: usize = 0;
    while (frame_count < 5) : (frame_count += 1) {
        const ft: FrameType = if (frame_count == 0) .i_frame else .p_frame;
        _ = frame_serializer_mod.serializeAndWrite(&scratch.buf, &ring, 1, 1, ft, &rows, &seq);
        expected_seq += 1;
        try testing.expectEqual(expected_seq, seq);
    }

    // Read all frames and verify sequence numbers are monotonically increasing
    var prev_seq: u64 = 0;
    var read_count: usize = 0;
    var read_buf: [8192]u8 = @splat(0);
    while (ring.peekFrame(&cursor, &read_buf)) |n| {
        const fh = FrameHeader.decode(
            read_buf[protocol.header.HEADER_SIZE..][0..protocol.frame_update.FRAME_HEADER_SIZE],
        );
        if (read_count > 0) {
            try testing.expect(fh.frame_sequence > prev_seq);
        }
        prev_seq = fh.frame_sequence;
        ring.advancePastFrame(&cursor, n);
        read_count += 1;
    }
    try testing.expectEqual(@as(usize, 5), read_count);
}

// ---------------------------------------------------------------------------
// Test 9: I-frame scheduling semantics
// ---------------------------------------------------------------------------

test "integration: empty P-frame skipped, I-frame with no rows still written" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;

    // Empty P-frame should return null and not increment seq
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

    // I-frame with no rows should still be written (represents empty screen state)
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

// ---------------------------------------------------------------------------
// Test 10: Fast vs slow client cursor divergence
// ---------------------------------------------------------------------------

test "integration: fast and slow client cursor divergence" {
    // Use raw ring (not serializer) with small frames to test cursor behavior.
    // Each entry is 4 + 15 = 19 bytes. Ring of 128 holds ~6 entries.
    var backing: [128]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var fast = RingCursor.init();
    var slow = RingCursor.init();

    // Write frames. Fast client reads each one. Slow client never reads.
    var out: [256]u8 = @splat(0);
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const is_i = (i % 4 == 0);
        try ring.writeFrame("test-data-frame", is_i, @intCast(i));

        // Fast cursor keeps up
        while (ring.peekFrame(&fast, &out)) |len| {
            ring.advancePastFrame(&fast, len);
        }
    }

    // Fast client is caught up
    try testing.expectEqual(@as(usize, 0), ring.available(&fast));
    try testing.expect(!ring.isCursorOverwritten(&fast));

    // Slow client is overwritten
    try testing.expect(ring.isCursorOverwritten(&slow));
    try testing.expectEqual(@as(usize, 0), ring.available(&slow));

    // Recovery: slow seeks to latest I-frame
    ring.seekToLatestIFrame(&slow);
    try testing.expect(!ring.isCursorOverwritten(&slow));
    try testing.expect(ring.available(&slow) > 0);
}

// ---------------------------------------------------------------------------
// Test 11: Frame straddling the ring wrap point
// ---------------------------------------------------------------------------

test "integration: frame data straddles ring wrap boundary" {
    // Ring of 96 bytes. Write 3 frames of ~28 bytes each (4 + 24 payload).
    // The 3rd frame straddles the wrap point.
    var backing: [96]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    const payload_a = "AAAAAAAAAAAAAAAAAAAAAAAA"; // 24 bytes -> 28 entry
    const payload_b = "BBBBBBBBBBBBBBBBBBBBBBBB"; // 24 bytes -> 28 entry
    const payload_c = "CCCCCCCCCCCCCCCCCCCCCCCC"; // 24 bytes -> 28 entry, wraps

    try ring.writeFrame(payload_a, true, 1);
    try ring.writeFrame(payload_b, false, 2);

    // Read first two frames
    var out: [128]u8 = @splat(0);
    const na = ring.peekFrame(&cursor, &out).?;
    try testing.expectEqualSlices(u8, payload_a, out[0..na]);
    ring.advancePastFrame(&cursor, na);
    const nb = ring.peekFrame(&cursor, &out).?;
    try testing.expectEqualSlices(u8, payload_b, out[0..nb]);
    ring.advancePastFrame(&cursor, nb);

    // Write 3rd frame — will wrap
    try ring.writeFrame(payload_c, false, 3);

    // Verify write_pos wrapped
    try testing.expect(ring.write_pos < 96);

    // Read 3rd frame — data must be intact despite wrap
    const n = ring.peekFrame(&cursor, &out).?;
    try testing.expectEqualSlices(u8, payload_c, out[0..n]);
}

// ---------------------------------------------------------------------------
// Test 12: seekToLatestIFrame after multiple I-frames
// ---------------------------------------------------------------------------

test "integration: seekToLatestIFrame selects most recent I-frame" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    // Write: I(seq=1), P(2), I(seq=3), P(4), P(5), I(seq=6), P(7)
    try ring.writeFrame("I-FRAME-001", true, 1);
    try ring.writeFrame("P-frame-002", false, 2);
    try ring.writeFrame("I-FRAME-003", true, 3);
    try ring.writeFrame("P-frame-004", false, 4);
    try ring.writeFrame("P-frame-005", false, 5);
    try ring.writeFrame("I-FRAME-006", true, 6);
    try ring.writeFrame("P-frame-007", false, 7);

    // Seek to latest I-frame should go to I-FRAME-006
    ring.seekToLatestIFrame(&cursor);

    var out: [256]u8 = @splat(0);
    const n = ring.peekFrame(&cursor, &out).?;
    try testing.expectEqualSlices(u8, "I-FRAME-006", out[0..n]);

    // After seeking, we should be able to read the subsequent P-frame too
    ring.advancePastFrame(&cursor, n);
    const n2 = ring.peekFrame(&cursor, &out).?;
    try testing.expectEqualSlices(u8, "P-frame-007", out[0..n2]);
}

// ---------------------------------------------------------------------------
// Test 13: Direct queue FIFO ordering under interleaving
// ---------------------------------------------------------------------------

test "integration: direct queue FIFO ordering preserved under interleaving" {
    var q = direct_queue_mod.DirectQueue.init();

    // Interleave enqueue and dequeue operations
    try q.enqueue("LayoutChanged");
    try q.enqueue("PreeditSync");
    try q.enqueue("PreeditUpdate");

    // Dequeue first, enqueue more
    try testing.expectEqualSlices(u8, "LayoutChanged", q.peek().?);
    q.dequeue();

    try q.enqueue("PreeditEnd");

    // Remaining order must be: PreeditSync, PreeditUpdate, PreeditEnd
    try testing.expectEqualSlices(u8, "PreeditSync", q.peek().?);
    q.dequeue();
    try testing.expectEqualSlices(u8, "PreeditUpdate", q.peek().?);
    q.dequeue();
    try testing.expectEqualSlices(u8, "PreeditEnd", q.peek().?);
    q.dequeue();
    try testing.expect(q.isEmpty());
}

// ---------------------------------------------------------------------------
// Test 14: ClientWriter hasPending state tracking across channels
// ---------------------------------------------------------------------------

test "integration: ClientWriter hasPending tracks all channels correctly" {
    var cw = client_writer_mod.ClientWriter.init();
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    // Initially: no pending
    try testing.expect(!cw.hasPending(&ring));

    // Add direct message: pending = true
    try cw.enqueueDirect("ctrl-msg");
    try testing.expect(cw.hasPending(&ring));

    // Drain direct: only ring matters now
    cw.direct_queue.dequeue();
    try testing.expect(!cw.hasPending(&ring)); // ring empty too

    // Add ring data: pending = true
    try ring.writeFrame("frame-data", false, 1);
    try testing.expect(cw.hasPending(&ring));

    // Advance ring cursor: fully caught up
    var ring_buf: [256]u8 = @splat(0);
    const ring_n = ring.peekFrame(&cw.ring_cursor, &ring_buf).?;
    ring.advancePastFrame(&cw.ring_cursor, ring_n);
    try testing.expect(!cw.hasPending(&ring));

    // Simulate partial ring frame in progress
    cw.ring_frame_sent = 50;
    try testing.expect(cw.hasPending(&ring));

    // Clear partial state: caught up again
    cw.ring_frame_sent = 0;
    try testing.expect(!cw.hasPending(&ring));
}

// ---------------------------------------------------------------------------
// Test 15: SessionDeliveryState multiple pane slots independence
// ---------------------------------------------------------------------------

test "integration: SessionDeliveryState pane slots are independent" {
    var state = pane_delivery_mod.SessionDeliveryState.init();
    defer state.deinit();

    // Allocate 3 panes
    try state.initPaneRing(0);
    try state.initPaneRing(7);
    try state.initPaneRing(15);

    // Write different data to each
    const r0 = state.getRingBuffer(0).?;
    const r7 = state.getRingBuffer(7).?;
    const r15 = state.getRingBuffer(15).?;

    try r0.writeFrame("pane-zero", true, 1);
    try r7.writeFrame("pane-seven", true, 1);
    try r15.writeFrame("pane-fifteen", true, 1);

    // Each ring has exactly 1 frame
    try testing.expectEqual(@as(usize, 1), r0.frame_count);
    try testing.expectEqual(@as(usize, 1), r7.frame_count);
    try testing.expectEqual(@as(usize, 1), r15.frame_count);

    // Read from each with independent cursors
    var c0 = RingCursor.init();
    var c7 = RingCursor.init();
    var c15 = RingCursor.init();
    var out: [256]u8 = @splat(0);

    try testing.expectEqualSlices(u8, "pane-zero", out[0..r0.peekFrame(&c0, &out).?]);
    try testing.expectEqualSlices(u8, "pane-seven", out[0..r7.peekFrame(&c7, &out).?]);
    try testing.expectEqualSlices(u8, "pane-fifteen", out[0..r15.peekFrame(&c15, &out).?]);

    // Dealloc pane 7, others unaffected
    state.deinitPaneRing(7);
    try testing.expect(state.getRingBuffer(7) == null);
    try testing.expect(state.getRingBuffer(0) != null);
    try testing.expect(state.getRingBuffer(15) != null);
}

// ---------------------------------------------------------------------------
// Test 16: Sequence counter not affected by uninitialized pane slots
// ---------------------------------------------------------------------------

test "integration: sequence counter per pane is independent" {
    var state = pane_delivery_mod.SessionDeliveryState.init();
    defer state.deinit();

    // All sequence counters start at 0
    for (0..@as(usize, @intCast(@as(u5, 16)))) |i| {
        try testing.expectEqual(@as(u64, 0), state.next_sequences[@intCast(i)]);
    }

    // Allocate pane 3 and increment its sequence
    try state.initPaneRing(3);
    state.next_sequences[3] = 42;

    // Other panes unaffected
    try testing.expectEqual(@as(u64, 0), state.next_sequences[0]);
    try testing.expectEqual(@as(u64, 42), state.next_sequences[3]);

    // Re-init pane 3 resets sequence
    state.deinitPaneRing(3);
    try state.initPaneRing(3);
    try testing.expectEqual(@as(u64, 0), state.next_sequences[3]);
}

// ---------------------------------------------------------------------------
// Test 17: Ring FrameMeta index wraps correctly at MAX_FRAME_INDEX
// ---------------------------------------------------------------------------

test "integration: frame index wraps at MAX_FRAME_INDEX boundary" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    // Write MAX_FRAME_INDEX + 10 frames to force wrap in the frame_index array
    var i: usize = 0;
    while (i < ring_buffer_mod.MAX_FRAME_INDEX + 10) : (i += 1) {
        const is_i = (i % 10 == 0);
        try ring.writeFrame("frame-data", is_i, @intCast(i));
    }

    // frame_count should be MAX_FRAME_INDEX + 10
    try testing.expectEqual(ring_buffer_mod.MAX_FRAME_INDEX + 10, ring.frame_count);

    // The latest I-frame should still be trackable
    try testing.expect(ring.has_i_frame);
    try testing.expect(ring.hasValidIFrame());

    // latest_i_frame_idx should be within bounds
    try testing.expect(ring.latest_i_frame_idx < ring_buffer_mod.MAX_FRAME_INDEX);

    // The frame at latest_i_frame_idx should be an I-frame
    try testing.expect(ring.frame_index[ring.latest_i_frame_idx].is_i_frame);
}

// ---------------------------------------------------------------------------
// Test 18: Direct queue wrap-around with peekCopy
// ---------------------------------------------------------------------------

test "integration: direct queue wrap-around handled by peekCopy" {
    var q = direct_queue_mod.DirectQueue.init();

    // Fill most of the buffer to push write_pos near the end
    const fill_size = direct_queue_mod.QUEUE_CAPACITY - 64;
    const fill = [_]u8{'F'} ** fill_size;
    try q.enqueue(&fill);
    q.dequeue(); // Free space, but write_pos is near end

    // Enqueue a message that will wrap around
    const wrap_msg = "this-message-wraps-around-the-buffer-boundary!!";
    try q.enqueue(wrap_msg);

    // peek() may return null for wrapped messages
    // peekCopy() must always work
    var out: [256]u8 = @splat(0);
    const n = q.peekCopy(&out).?;
    try testing.expectEqualSlices(u8, wrap_msg, out[0..n]);
}

// ---------------------------------------------------------------------------
// Test 19: Ring cursor total_read == total_written means caught up
// ---------------------------------------------------------------------------

test "integration: cursor at total_written means fully caught up" {
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("data", false, 1);

    // Before reading: not caught up
    try testing.expect(cursor.total_read < ring.total_written);
    try testing.expect(ring.available(&cursor) > 0);

    // After advancing: caught up
    var adv_buf: [256]u8 = @splat(0);
    const adv_n = ring.peekFrame(&cursor, &adv_buf).?;
    ring.advancePastFrame(&cursor, adv_n);
    try testing.expectEqual(ring.total_written, cursor.total_read);
    try testing.expectEqual(@as(usize, 0), ring.available(&cursor));
    var empty_buf: [256]u8 = @splat(0);
    try testing.expect(ring.peekFrame(&cursor, &empty_buf) == null);
}

// ---------------------------------------------------------------------------
// Test 20: seekToLatestIFrame is no-op when no I-frames exist
// ---------------------------------------------------------------------------

test "integration: seekToLatestIFrame no-op when no I-frames" {
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    // Write only P-frames
    try ring.writeFrame("p-only-1", false, 1);
    try ring.writeFrame("p-only-2", false, 2);

    try testing.expect(!ring.has_i_frame);
    try testing.expect(!ring.hasValidIFrame());

    // seekToLatestIFrame should be a no-op
    const saved = cursor.total_read;
    ring.seekToLatestIFrame(&cursor);
    try testing.expectEqual(saved, cursor.total_read);
}
