//! Serializes dirty rows into wire-format FrameUpdate messages and writes
//! them into a per-pane ring buffer. Bridges ghostty render state export
//! and the ring-based delivery pipeline.

const std = @import("std");
const protocol = @import("itshell3_protocol");
const ring_buffer_mod = @import("ring_buffer.zig");
const RingBuffer = ring_buffer_mod.RingBuffer;

const FrameHeader = protocol.frame_update.FrameHeader;
const FrameType = protocol.frame_update.FrameType;
const SectionFlags = protocol.frame_update.SectionFlags;
const DirtyRow = protocol.frame_update.DirtyRow;
const Header = protocol.header.Header;
const Flags = protocol.header.Flags;

/// Maximum serialized frame size (128 KB).
pub const MAX_FRAME_SIZE: usize = 128 * 1024;
/// Total scratch size = protocol header + max frame payload.
pub const SCRATCH_SIZE: usize = protocol.header.HEADER_SIZE + MAX_FRAME_SIZE;

/// Serialize dirty rows into a complete wire message (protocol Header +
/// FrameUpdate payload) and write to the ring buffer.
///
/// `scratch` is a shared scratch buffer (at least SCRATCH_SIZE bytes).
/// `next_sequence` is incremented on success; caller owns it.
///
/// Returns bytes written to ring, or null if nothing to serialize.
pub fn serializeAndWrite(
    scratch: []u8,
    ring: *RingBuffer,
    session_id: u32,
    pane_id: u32,
    frame_type: FrameType,
    dirty_rows: []const DirtyRow,
    next_sequence: *u64,
) ?usize {
    return serializeAndWriteWithMetadata(
        scratch,
        ring,
        session_id,
        pane_id,
        frame_type,
        dirty_rows,
        null,
        next_sequence,
    );
}

/// Serialize dirty rows with optional JSON metadata blob into a complete
/// wire message and write to the ring buffer.
///
/// When `json_metadata` is non-null, section_flags bit 7 is set and the
/// JSON blob (already length-prefixed) is appended after the DirtyRows
/// section. Per protocol 04 Section 3.1.
pub fn serializeAndWriteWithMetadata(
    scratch: []u8,
    ring: *RingBuffer,
    session_id: u32,
    pane_id: u32,
    frame_type: FrameType,
    dirty_rows: []const DirtyRow,
    json_metadata: ?[]const u8,
    next_sequence: *u64,
) ?usize {
    if (dirty_rows.len == 0 and frame_type == .p_frame and json_metadata == null) return null;
    std.debug.assert(scratch.len >= SCRATCH_SIZE);

    var fbs = std.io.fixedBufferStream(scratch[protocol.header.HEADER_SIZE..]);
    const writer = fbs.writer();

    var section_flags: u16 = 0;
    if (dirty_rows.len > 0) section_flags |= SectionFlags.dirty_rows;
    if (json_metadata != null) section_flags |= SectionFlags.json_metadata;

    const fh = FrameHeader{
        .session_id = session_id,
        .pane_id = pane_id,
        .frame_sequence = next_sequence.*,
        .frame_type = frame_type,
        .screen = .primary,
        .section_flags = section_flags,
    };
    var fh_buf: [protocol.frame_update.FRAME_HEADER_SIZE]u8 = undefined;
    fh.encode(&fh_buf);
    writer.writeAll(&fh_buf) catch return null;

    if (dirty_rows.len > 0) {
        protocol.frame_update.encodeDirtyRows(dirty_rows, writer) catch return null;
    }

    if (json_metadata) |metadata| {
        writer.writeAll(metadata) catch return null;
    }

    const payload_len = fbs.getWritten().len;

    const hdr = Header{
        .msg_type = 0x0300,
        .flags = Flags{ .encoding = .binary },
        .payload_length = @intCast(payload_len),
        .sequence = next_sequence.*,
    };
    hdr.encode(scratch[0..protocol.header.HEADER_SIZE]);

    const total = protocol.header.HEADER_SIZE + payload_len;
    const is_i_frame = frame_type == .i_frame;

    ring.writeFrame(scratch[0..total], is_i_frame, next_sequence.*) catch return null;
    next_sequence.* += 1;
    return total;
}

// --- Tests ---

const CellData = protocol.cell.CellData;

test "serializeAndWrite: I-frame produces valid protocol message" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch: [SCRATCH_SIZE]u8 = @splat(0);
    var seq: u64 = 0;

    var cells: [3]CellData = @splat(std.mem.zeroes(CellData));
    for (&cells, 0..) |*c, i| {
        c.codepoint = @intCast('X' + i);
    }
    const row = DirtyRow{
        .header = .{ .y = 0, .num_cells = 3, .row_flags = 0, .selection_start = 0, .selection_end = 0 },
        .cells = &cells,
    };
    const rows = [_]DirtyRow{row};

    const n = serializeAndWrite(&scratch, &ring, 42, 100, .i_frame, &rows, &seq);
    try std.testing.expect(n != null);
    try std.testing.expectEqual(@as(u64, 1), seq);

    // Read back via iovecs and decode protocol header
    var cursor = ring_buffer_mod.RingCursor.init();
    const p = ring.pendingIovecs(&cursor).?;
    // Flatten iovecs into a contiguous buffer for decoding
    var read_buf: [8192]u8 = @splat(0);
    var off: usize = 0;
    for (p.iov[0..p.count]) |v| {
        @memcpy(read_buf[off..][0..v.len], v.base[0..v.len]);
        off += v.len;
    }
    const hdr = try Header.decode(read_buf[0..protocol.header.HEADER_SIZE]);
    try std.testing.expectEqual(@as(u16, 0x0300), hdr.msg_type);
    try std.testing.expectEqual(.binary, hdr.flags.encoding);

    const fh = FrameHeader.decode(
        read_buf[protocol.header.HEADER_SIZE..][0..protocol.frame_update.FRAME_HEADER_SIZE],
    );
    try std.testing.expectEqual(@as(u32, 42), fh.session_id);
    try std.testing.expectEqual(@as(u32, 100), fh.pane_id);
    try std.testing.expectEqual(FrameType.i_frame, fh.frame_type);
    try std.testing.expect(fh.hasDirtyRows());
    try std.testing.expectEqual(n.?, off);
}

test "serializeAndWrite: empty P-frame returns null" {
    var backing: [4096]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch: [SCRATCH_SIZE]u8 = @splat(0);
    var seq: u64 = 0;

    const n = serializeAndWrite(&scratch, &ring, 1, 1, .p_frame, &.{}, &seq);
    try std.testing.expect(n == null);
    try std.testing.expectEqual(@as(u64, 0), seq); // NOT incremented
    try std.testing.expectEqual(@as(usize, 0), ring.frame_count);
}

test "serializeAndWrite: sequence increments monotonically" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch: [SCRATCH_SIZE]u8 = @splat(0);
    var seq: u64 = 0;

    var cells: [1]CellData = .{std.mem.zeroes(CellData)};
    const row = DirtyRow{
        .header = .{ .y = 0, .num_cells = 1, .row_flags = 0, .selection_start = 0, .selection_end = 0 },
        .cells = &cells,
    };
    const rows = [_]DirtyRow{row};

    _ = serializeAndWrite(&scratch, &ring, 1, 1, .i_frame, &rows, &seq);
    _ = serializeAndWrite(&scratch, &ring, 1, 1, .p_frame, &rows, &seq);
    _ = serializeAndWrite(&scratch, &ring, 1, 1, .p_frame, &rows, &seq);

    try std.testing.expectEqual(@as(u64, 3), seq);
    try std.testing.expectEqual(@as(usize, 3), ring.frame_count);
}

test "serializeAndWrite: I-frame correctly marks ring index" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch: [SCRATCH_SIZE]u8 = @splat(0);
    var seq: u64 = 0;

    var cells: [1]CellData = .{std.mem.zeroes(CellData)};
    const row = DirtyRow{
        .header = .{ .y = 0, .num_cells = 1, .row_flags = 0, .selection_start = 0, .selection_end = 0 },
        .cells = &cells,
    };
    const rows = [_]DirtyRow{row};

    _ = serializeAndWrite(&scratch, &ring, 1, 1, .p_frame, &rows, &seq);
    _ = serializeAndWrite(&scratch, &ring, 1, 1, .i_frame, &rows, &seq);
    _ = serializeAndWrite(&scratch, &ring, 1, 1, .p_frame, &rows, &seq);

    try std.testing.expect(ring.hasValidIFrame());
    try std.testing.expect(ring.frame_index[ring.latest_i_frame_idx].is_i_frame);
    try std.testing.expectEqual(@as(u64, 1), ring.frame_index[ring.latest_i_frame_idx].frame_sequence);
}

test "serializeAndWrite: I-frame with no dirty rows still writes (full state export)" {
    var backing: [256 * 1024]u8 = @splat(0);
    var ring = RingBuffer.init(&backing);
    var scratch: [SCRATCH_SIZE]u8 = @splat(0);
    var seq: u64 = 0;

    // I-frame with zero rows is valid (represents empty screen state)
    const n = serializeAndWrite(&scratch, &ring, 1, 1, .i_frame, &.{}, &seq);
    try std.testing.expect(n != null);
    try std.testing.expectEqual(@as(u64, 1), seq);
    try std.testing.expectEqual(@as(usize, 1), ring.frame_count);
    try std.testing.expect(ring.has_i_frame);
}
