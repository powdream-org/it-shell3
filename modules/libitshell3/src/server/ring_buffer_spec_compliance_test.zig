// server/ring_buffer_spec_compliance_test.zig
//
// Spec compliance tests for the ring buffer + frame delivery pipeline.
// Each test cites the spec section it verifies.
//
// Spec authority:
//   - daemon-architecture/draft/v1.0-r8/02-state-and-types.md (sections 4.1-4.11)
//   - daemon-behavior/draft/v1.0-r8/impl-constraints/policies.md (sections 5.3-5.5)
//
// These tests verify the SPEC, not the implementation. They are derived from
// spec requirements and will fail if the implementation deviates from the spec.

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
const PendingIovecs = ring_buffer_mod.PendingIovecs;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Check that a pointer falls within the ring buffer's backing memory range.
fn isInRingMemory(ring: *const RingBuffer, ptr: [*]const u8, len: usize) bool {
    const ring_start = @intFromPtr(ring.buf.ptr);
    const ring_end = ring_start + ring.buf.len;
    const slice_start = @intFromPtr(ptr);
    const slice_end = slice_start + len;
    return slice_start >= ring_start and slice_end <= ring_end;
}

/// Concatenate iovec data into a flat buffer. Returns total bytes copied.
fn flattenIovecs(p: *const PendingIovecs, out: []u8) usize {
    var off: usize = 0;
    for (p.iov[0..p.count]) |v| {
        @memcpy(out[off..][0..v.len], v.base[0..v.len]);
        off += v.len;
    }
    return off;
}

// ===========================================================================
// Spec §4.1 — Per-Pane Shared Ring Buffer
// ===========================================================================

test "spec 4.1: default ring size is 2 MB" {
    // "Each pane owns a single ring buffer (default 2 MB)"
    try testing.expectEqual(@as(usize, 2 * 1024 * 1024), ring_buffer_mod.DEFAULT_RING_SIZE);
}

test "spec 4.1: O(1) memory — frame written once, multiple cursors read same backing" {
    // "Each frame is written to the ring exactly once, regardless of how many
    //  clients are attached."
    // "Frame data is not duplicated per client."
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    try ring.writeFrame("shared-frame-data", true, 1);

    var cursor_a = RingCursor.init();
    var cursor_b = RingCursor.init();
    var cursor_c = RingCursor.init();

    // All three cursors see the same available bytes
    const avail_a = ring.available(&cursor_a);
    const avail_b = ring.available(&cursor_b);
    const avail_c = ring.available(&cursor_c);
    try testing.expectEqual(avail_a, avail_b);
    try testing.expectEqual(avail_b, avail_c);
    try testing.expect(avail_a > 0);

    // Get iovecs for each cursor — they must point into the SAME ring.buf memory
    const pa = ring.pendingIovecs(&cursor_a).?;
    const pb = ring.pendingIovecs(&cursor_b).?;

    // Both iovec sets must point into ring.buf (zero-copy from same backing)
    try testing.expect(isInRingMemory(&ring, pa.iov[0].base, pa.iov[0].len));
    try testing.expect(isInRingMemory(&ring, pb.iov[0].base, pb.iov[0].len));

    // The base addresses must be identical (same data in same location)
    try testing.expectEqual(@intFromPtr(pa.iov[0].base), @intFromPtr(pb.iov[0].base));
    try testing.expectEqual(pa.iov[0].len, pb.iov[0].len);

    // frame_count is 1 (written once, not per-cursor)
    try testing.expectEqual(@as(usize, 1), ring.frame_count);
}

test "spec 4.1: ring invariant — hasValidIFrame tracks I-frame presence" {
    // "The ring MUST always contain at least one complete I-frame for each pane."
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    try testing.expect(!ring.hasValidIFrame());

    try ring.writeFrame("i-frame-data", true, 1);
    try testing.expect(ring.hasValidIFrame());

    try ring.writeFrame("p-frame-data", false, 2);
    try testing.expect(ring.hasValidIFrame());
}

// ===========================================================================
// Spec §4.3 — Wire Format
// ===========================================================================

test "spec 4.3: wire format in ring — iovec data is valid protocol message" {
    // "The ring buffer stores pre-serialized wire-format frames"
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;
    var cursor = RingCursor.init();

    const CellData = protocol.cell.CellData;
    const DirtyRow = protocol.frame_update.DirtyRow;

    var cells: [2]CellData = @splat(std.mem.zeroes(CellData));
    cells[0].codepoint = 'A';
    cells[1].codepoint = 'B';
    const row = DirtyRow{
        .header = .{ .y = 0, .num_cells = 2, .row_flags = 0, .selection_start = 0, .selection_end = 0 },
        .cells = &cells,
    };

    _ = frame_serializer_mod.serializeAndWrite(
        &scratch.buf,
        &ring,
        7,
        42,
        .i_frame,
        &[_]DirtyRow{row},
        &seq,
    );

    // Read via iovecs — the data must be decodable.
    // Ring stores frame data directly (no prefix). Flatten iovecs to access bytes.
    const p = ring.pendingIovecs(&cursor).?;
    try testing.expect(p.totalLen() > 0);

    var flat: [8192]u8 = @splat(0);
    const flat_n = flattenIovecs(&p, &flat);
    try testing.expect(flat_n > protocol.header.HEADER_SIZE);

    // Bytes 0..HEADER_SIZE are the protocol header (no prefix).
    const hdr = try protocol.header.Header.decode(flat[0..protocol.header.HEADER_SIZE]);
    try testing.expectEqual(@as(u16, 0x0300), hdr.msg_type); // FrameUpdate

    // Decode frame header
    const fh_start = protocol.header.HEADER_SIZE;
    const fh_end = fh_start + protocol.frame_update.FRAME_HEADER_SIZE;
    try testing.expect(flat_n >= fh_end);
    const fh = protocol.frame_update.FrameHeader.decode(
        flat[fh_start..fh_end],
    );
    try testing.expectEqual(@as(u32, 7), fh.session_id);
    try testing.expectEqual(@as(u32, 42), fh.pane_id);
    try testing.expectEqual(protocol.frame_update.FrameType.i_frame, fh.frame_type);
}

// ===========================================================================
// Spec §4.4 — Two-Channel Socket Write Priority
// ===========================================================================

test "spec 4.4: two-channel priority — direct queue drained before ring" {
    // "the server drains the direct queue first, then writes ring buffer frames"
    var cw = client_writer_mod.ClientWriter.init();
    defer cw.deinit();
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    try cw.enqueueDirect("PreeditSync-msg");
    try ring.writeFrame("FrameUpdate-data", true, 1);

    // Both channels have data
    try testing.expect(cw.hasPending(&ring));
    try testing.expect(!cw.direct_queue.isEmpty());
    try testing.expect(ring.available(&cw.ring_cursor) > 0);

    // Direct queue data is accessible first (FIFO peek)
    const direct_data = cw.direct_queue.peek().?;
    try testing.expectEqualSlices(u8, "PreeditSync-msg", direct_data);
}

// ===========================================================================
// Spec §4.5 — Per-Client Cursors
// ===========================================================================

test "spec 4.5: RingCursor has last_i_frame field" {
    // "const RingCursor = struct {
    //     position: usize,
    //     last_i_frame: usize,
    // };"
    const cursor = RingCursor.init();
    _ = cursor.last_i_frame;
    try testing.expect(@hasField(RingCursor, "last_i_frame"));
}

test "spec 4.5: independent cursors — advancing one does not affect another" {
    // "Cursors are independent — clients at different frame rates ... read from
    //  the same ring at their own pace."
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    try ring.writeFrame("frame-1", true, 1);
    try ring.writeFrame("frame-2", false, 2);
    try ring.writeFrame("frame-3", false, 3);

    var cursor_a = RingCursor.init();
    var cursor_b = RingCursor.init();

    const total_avail = ring.available(&cursor_a);

    ring.advanceCursor(&cursor_a, 10);

    // Cursor B must be completely unaffected
    try testing.expectEqual(total_avail, ring.available(&cursor_b));
    try testing.expectEqual(@as(usize, 0), cursor_b.total_read);
    try testing.expectEqual(total_avail - 10, ring.available(&cursor_a));
}

test "spec 4.5: seekToLatestIFrame updates last_i_frame on cursor" {
    // Spec §4.5 defines last_i_frame as "position of last I-frame sent to this client"
    var backing: [1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("p-frame-1", false, 1);
    try ring.writeFrame("I-FRAME-DATA", true, 2);
    try ring.writeFrame("p-frame-2", false, 3);

    // Before seek, last_i_frame is 0
    try testing.expectEqual(@as(usize, 0), cursor.last_i_frame);

    ring.seekToLatestIFrame(&cursor);

    // After seek, last_i_frame should be updated to the I-frame's offset
    try testing.expect(cursor.last_i_frame > 0);
    // And it should equal total_read (cursor positioned at I-frame start)
    try testing.expectEqual(cursor.total_read, cursor.last_i_frame);
}

// ===========================================================================
// Spec §4.6 — Frame Delivery (zero-copy via iovecs)
// ===========================================================================

test "spec 4.6: zero-copy — iovecs point into ring.buf memory (non-wrapping)" {
    // "call conn.sendv(iovecs) for zero-copy delivery from ring buffer"
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("zero-copy-test-payload", false, 1);

    const p = ring.pendingIovecs(&cursor).?;
    try testing.expectEqual(@as(usize, 1), p.count);
    try testing.expect(p.iov[0].len > 0);
    try testing.expect(isInRingMemory(&ring, p.iov[0].base, p.iov[0].len));
}

test "spec 4.6: zero-copy — BOTH iovecs point into ring.buf (wrapping case)" {
    var backing: [64]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    // Fill ring and advance cursor to push write_pos near end.
    // 10 bytes per entry (no prefix): 2 frames = 20 bytes, write_pos at 20.
    const filler = [_]u8{'F'} ** 10;
    try ring.writeFrame(&filler, true, 1);
    try ring.writeFrame(&filler, false, 2); // write_pos at 20
    ring.advanceCursor(&cursor, ring.available(&cursor));

    // Write frames that wrap around
    try ring.writeFrame(&filler, false, 3);
    try ring.writeFrame(&filler, false, 4);

    const p = ring.pendingIovecs(&cursor).?;

    // Both iovecs must point into ring.buf
    for (p.iov[0..p.count]) |v| {
        if (v.len > 0) {
            try testing.expect(isInRingMemory(&ring, v.base, v.len));
        }
    }
}

test "spec 4.6: iovec byte lengths sum to available() bytes" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("test-data-1", true, 1);
    try ring.writeFrame("test-data-2", false, 2);

    const avail = ring.available(&cursor);
    const p = ring.pendingIovecs(&cursor).?;
    try testing.expectEqual(avail, p.totalLen());
}

test "spec 4.6: non-wrapping range produces count=1 iovec" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("small-frame", false, 1);

    const p = ring.pendingIovecs(&cursor).?;
    try testing.expectEqual(@as(usize, 1), p.count);
    try testing.expect(p.iov[0].len > 0);
    try testing.expectEqual(@as(usize, 0), p.iov[1].len);
}

test "spec 4.6: wrapping range produces count=2 iovecs" {
    var backing: [64]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    // Push write_pos near end and advance cursor.
    // 23 bytes per frame (no prefix): 2 frames = 46 bytes, write_pos at 46.
    const filler = [_]u8{'F'} ** 23;
    try ring.writeFrame(&filler, true, 1);
    try ring.writeFrame(&filler, false, 2); // write_pos at 46
    ring.advanceCursor(&cursor, ring.available(&cursor));

    // Write a frame that wraps (starts at 46, 23 bytes wraps past 64)
    try ring.writeFrame(&filler, false, 3);

    const p = ring.pendingIovecs(&cursor).?;
    try testing.expectEqual(@as(usize, 2), p.count);
    try testing.expect(p.iov[0].len > 0);
    try testing.expect(p.iov[1].len > 0);
}

test "spec 4.6: wrapping iovec concatenation reconstructs original frame data" {
    // backing=128, capacity/2=64. Two pad frames push write_pos to 70.
    // A payload frame of 60 bytes starts at 70 and wraps at 128:
    //   tail = 128 - 70 = 58 bytes, head = 2 bytes → count=2.
    var backing: [128]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    // Push write_pos to 70 using two frames: 50 + 20
    const pad1 = [_]u8{'P'} ** 50;
    const pad2 = [_]u8{'P'} ** 20;
    try ring.writeFrame(&pad1, true, 1);
    try ring.writeFrame(&pad2, false, 2);
    ring.advanceCursor(&cursor, ring.available(&cursor)); // cursor = 70

    // Write a frame that wraps (60 bytes starting at 70: 70+60=130 > 128)
    const payload = [_]u8{'W'} ** 60;
    try ring.writeFrame(&payload, false, 3);

    const p = ring.pendingIovecs(&cursor).?;
    try testing.expectEqual(@as(usize, 2), p.count);

    var reconstructed: [256]u8 = undefined;
    const total_len = flattenIovecs(&p, &reconstructed);

    // Ring stores frame data directly (no length prefix).
    // Concatenating both iovecs reconstructs the original payload.
    try testing.expectEqual(@as(usize, payload.len), total_len);
    try testing.expectEqualSlices(u8, &payload, reconstructed[0..total_len]);
}

test "spec 4.6: pendingIovecs returns null when no pending data" {
    var backing: [1024]u8 = @splat(0);
    const ring = RingBuffer.init(&backing);
    const cursor = RingCursor.init();
    try testing.expect(ring.pendingIovecs(&cursor) == null);
}

// ===========================================================================
// Spec §4.8 — Slow Client Recovery
// ===========================================================================

test "spec 4.8: overwritten cursor seeks to latest I-frame, then reads via iovecs" {
    // "the client's cursor skips to the latest I-frame"
    // Each frame is 8 bytes (no prefix). 13 frames × 8 = 104 > 96 → overwrites cursor.
    var backing: [96]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var slow = RingCursor.init();

    const frame = [_]u8{'X'} ** 8;
    // Write enough to overwrite slow cursor (13 × 8 = 104 > 96)
    var i: usize = 0;
    while (i < 13) : (i += 1) {
        try ring.writeFrame(&frame, i % 2 == 0, @intCast(i + 1));
    }

    try testing.expect(ring.isCursorOverwritten(&slow));

    ring.seekToLatestIFrame(&slow);
    try testing.expect(!ring.isCursorOverwritten(&slow));

    // After recovery, iovecs are readable from ring memory
    const p = ring.pendingIovecs(&slow).?;
    try testing.expect(p.iov[0].len > 0);
    try testing.expect(isInRingMemory(&ring, p.iov[0].base, p.iov[0].len));
}

// ===========================================================================
// Spec §4.9 — I-Frame Scheduling Algorithm
// ===========================================================================

test "spec 4.9: empty P-frame not written to ring (no-op when unchanged)" {
    // "When the I-frame timer fires and the pane has no changes since the last
    //  I-frame, no frame is written to the ring"
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;

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
}

test "spec 4.9: I-frame with no rows still written (represents empty screen state)" {
    // "Full state on change: When the timer fires and changes exist, the server
    //  writes frame_type=1 (I-frame) containing all rows."
    // Even an empty I-frame is valid — it represents an empty screen.
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;

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

// ===========================================================================
// Spec §4.11 — Multi-Client Ring Read
// ===========================================================================

test "spec 4.11: multi-client ring read — independent iovec ranges from same backing" {
    // "All clients attached to a session receive FrameUpdate messages for all
    //  panes in that session from the shared per-pane ring buffer"
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);

    try ring.writeFrame("frame-1", true, 1);
    try ring.writeFrame("frame-2", false, 2);
    try ring.writeFrame("frame-3", false, 3);

    var cursor_fast = RingCursor.init();
    var cursor_slow = RingCursor.init();

    // Fast client advances 11 bytes (past the 7-byte "frame-1" and 4 bytes into "frame-2")
    ring.advanceCursor(&cursor_fast, 11);

    const p_fast = ring.pendingIovecs(&cursor_fast).?;
    const p_slow = ring.pendingIovecs(&cursor_slow).?;

    // Fast client has less data
    try testing.expect(p_fast.totalLen() < p_slow.totalLen());

    // Both point into ring.buf
    try testing.expect(isInRingMemory(&ring, p_fast.iov[0].base, p_fast.iov[0].len));
    try testing.expect(isInRingMemory(&ring, p_slow.iov[0].base, p_slow.iov[0].len));
}

// ===========================================================================
// Spec §5.4 — Write-Ready and Backpressure
// ===========================================================================

test "spec 5.4: byte-granular cursor advancement — partial advance" {
    // "advance client cursor by n bytes"
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("hello-world-frame", false, 1);

    const total_avail = ring.available(&cursor);
    try testing.expect(total_avail > 0);

    // Advance by 5 bytes (partial)
    ring.advanceCursor(&cursor, 5);
    try testing.expectEqual(total_avail - 5, ring.available(&cursor));

    // Advance by 3 more bytes
    ring.advanceCursor(&cursor, 3);
    try testing.expectEqual(total_avail - 8, ring.available(&cursor));

    // Iovecs total matches remaining
    const p = ring.pendingIovecs(&cursor).?;
    try testing.expectEqual(total_avail - 8, p.totalLen());
}

test "spec 5.4: partial advance — iovecs start at correct byte position in ring" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    const payload = "ABCDEFGHIJKLMNOP"; // 16 bytes
    try ring.writeFrame(payload, false, 1);

    const p_before = ring.pendingIovecs(&cursor).?;
    const initial_base = @intFromPtr(p_before.iov[0].base);
    const initial_len = p_before.iov[0].len;

    // Advance by 7 bytes
    ring.advanceCursor(&cursor, 7);

    const p_after = ring.pendingIovecs(&cursor).?;
    // New base should be 7 bytes ahead in ring memory
    try testing.expectEqual(initial_base + 7, @intFromPtr(p_after.iov[0].base));
    try testing.expectEqual(initial_len - 7, p_after.iov[0].len);
}

test "spec 5.4: advanceCursor(0) is a no-op" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("data", false, 1);
    const before = cursor.total_read;
    const avail_before = ring.available(&cursor);

    ring.advanceCursor(&cursor, 0);

    try testing.expectEqual(before, cursor.total_read);
    try testing.expectEqual(avail_before, ring.available(&cursor));
}

test "spec 5.4: full delivery — advance all bytes, then no pending data" {
    // "if cursor == write_position: // fully caught up"
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("frame-1", true, 1);
    try ring.writeFrame("frame-2", false, 2);

    const total = ring.available(&cursor);
    ring.advanceCursor(&cursor, total);

    try testing.expectEqual(@as(usize, 0), ring.available(&cursor));
    try testing.expect(ring.pendingIovecs(&cursor) == null);
}

test "spec 5.4: would_block semantics — cursor position unchanged on retry" {
    // "socket send buffer full — keep EVFILT_WRITE armed
    //  cursor stays at current position, next EVFILT_WRITE will retry"
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var cursor = RingCursor.init();

    try ring.writeFrame("data-for-would-block-test", false, 1);

    const saved_read = cursor.total_read;
    const saved_avail = ring.available(&cursor);

    // Simulate would_block: get iovecs twice without advancing
    const p1 = ring.pendingIovecs(&cursor).?;
    const p2 = ring.pendingIovecs(&cursor).?;

    try testing.expectEqual(saved_read, cursor.total_read);
    try testing.expectEqual(saved_avail, ring.available(&cursor));
    try testing.expectEqual(p1.iov[0].len, p2.iov[0].len);
    try testing.expectEqual(@intFromPtr(p1.iov[0].base), @intFromPtr(p2.iov[0].base));
}

test "spec 5.4: WriteResult has three spec-required branches" {
    // Spec §5.4 pseudocode: bytes_written, would_block, peer_closed
    const WriteResult = client_writer_mod.WriteResult;
    _ = WriteResult.fully_caught_up; // bytes_written + cursor == write_pos
    _ = WriteResult.more_pending; // bytes_written + cursor != write_pos
    _ = WriteResult.would_block;
    _ = WriteResult.peer_closed;
}

// ===========================================================================
// Structural compliance: old API removed, new API present
// ===========================================================================

test "spec 4.6+5.4: RingBuffer has iovec API, old peekFrame/advancePastFrame removed" {
    // Spec §4.6 mandates sendv(iovecs) for zero-copy delivery.
    // Spec §5.4 mandates byte-granular cursor advancement.
    // The old peekFrame/advancePastFrame APIs copy into caller buffers (not zero-copy).
    try testing.expect(!@hasDecl(RingBuffer, "peekFrame"));
    try testing.expect(!@hasDecl(RingBuffer, "advancePastFrame"));
    try testing.expect(@hasDecl(RingBuffer, "pendingIovecs"));
    try testing.expect(@hasDecl(RingBuffer, "advanceCursor"));
}

test "spec 5.4: ClientWriter has no ring_frame_sent field (byte-granular model)" {
    // Spec §5.4 pseudocode: "advance client cursor by n bytes".
    // No per-frame partial send tracking. Cursor position is the only state.
    try testing.expect(!@hasField(client_writer_mod.ClientWriter, "ring_frame_sent"));
}

test "spec 5.4: ClientWriter uses writev, not write for ring delivery" {
    // Spec §5.4: "call conn.sendv(iovecs)"
    // The ClientWriter struct should have exactly 3 fields (no frame_buf).
    const field_count = comptime @typeInfo(client_writer_mod.ClientWriter).@"struct".fields.len;
    // direct_queue, ring_cursor, direct_partial_offset — no frame_buf
    try testing.expectEqual(@as(usize, 3), field_count);
}

// ===========================================================================
// Spec §5.5 — Slow Client Recovery via ring cursor skip
// ===========================================================================

test "spec 5.5: overwritten cursor + I-frame seek produces readable iovecs" {
    // "the ring buffer detects that the client's cursor would be overwritten"
    // "the client's cursor skips to the latest I-frame"
    // "receives a complete screen state (I-frame) and resumes normal P-frame delivery"
    var backing: [128]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var slow = RingCursor.init();
    var fast = RingCursor.init();

    // Write enough frames to overwrite slow cursor.
    // Fast cursor keeps up. I-frame every 4th write.
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const is_i = (i % 4 == 0);
        try ring.writeFrame("test-data-frame", is_i, @intCast(i));

        // Fast cursor keeps up
        if (ring.pendingIovecs(&fast)) |_| {
            ring.advanceCursor(&fast, ring.available(&fast));
        }
    }

    // Slow is overwritten, fast is caught up
    try testing.expect(ring.isCursorOverwritten(&slow));
    try testing.expect(!ring.isCursorOverwritten(&fast));
    try testing.expectEqual(@as(usize, 0), ring.available(&fast));

    // Recovery
    ring.seekToLatestIFrame(&slow);
    try testing.expect(!ring.isCursorOverwritten(&slow));
    try testing.expect(ring.available(&slow) > 0);

    // Recovered client can read via iovecs
    const p = ring.pendingIovecs(&slow).?;
    try testing.expect(p.totalLen() > 0);
}

// ===========================================================================
// Spec §5.3 — Frame Delivery (full pipeline with serializer)
// ===========================================================================

test "spec 5.3: serialize -> ring -> iovec delivery pipeline" {
    // "For each dirty pane: export frame data ... serialize into the ring buffer"
    // "If pending data exists ... call conn.sendv(iovecs) for zero-copy delivery"
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch = pane_delivery_mod.SharedScratch.init();
    var seq: u64 = 0;
    var cursor = RingCursor.init();

    const CellData = protocol.cell.CellData;
    const DirtyRow = protocol.frame_update.DirtyRow;
    const FrameHeader = protocol.frame_update.FrameHeader;
    const FrameType = protocol.frame_update.FrameType;
    const Header = protocol.header.Header;

    // Create CJK row (worst case from spec sizing analysis)
    var cells: [5]CellData = @splat(std.mem.zeroes(CellData));
    const codepoints = [_]u32{ 0x4E16, 0x754C, 0x4F60, 0x597D, '!' };
    for (&cells, &codepoints) |*c, cp| {
        c.codepoint = cp;
    }
    const row = DirtyRow{
        .header = .{ .y = 0, .num_cells = 5, .row_flags = 0, .selection_start = 0, .selection_end = 0 },
        .cells = &cells,
    };

    const written = frame_serializer_mod.serializeAndWrite(
        &scratch.buf,
        &ring,
        7,
        42,
        .i_frame,
        &[_]DirtyRow{row},
        &seq,
    ).?;
    try testing.expect(written > 0);

    // Read via iovecs and decode (full pipeline)
    const p = ring.pendingIovecs(&cursor).?;
    var flat: [8192]u8 = @splat(0);
    const total = flattenIovecs(&p, &flat);

    // Ring stores frame data directly (no length prefix). Protocol header starts at offset 0.
    try testing.expect(total >= protocol.header.HEADER_SIZE);

    const hdr = try Header.decode(flat[0..protocol.header.HEADER_SIZE]);
    try testing.expectEqual(@as(u16, 0x0300), hdr.msg_type);

    const fh = FrameHeader.decode(
        flat[protocol.header.HEADER_SIZE..][0..protocol.frame_update.FRAME_HEADER_SIZE],
    );
    try testing.expectEqual(@as(u32, 7), fh.session_id);
    try testing.expectEqual(@as(u32, 42), fh.pane_id);
    try testing.expectEqual(FrameType.i_frame, fh.frame_type);
}
