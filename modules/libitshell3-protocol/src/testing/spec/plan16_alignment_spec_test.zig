//! Spec compliance tests for Plan 16 post-design code alignment.
//!
//! Work items covered:
//!   WI-1: ADR 00015 -- 20-byte header with u64 sequence
//!     Spec: protocol overview header layout
//!   WI-2: ADR 00062 -- Fixed-point ratio for resize and split
//!     Spec: session-pane-management split/resize/equalize procedures
//!   WI-3: ADR 00003 -- AttachOrCreate merged into AttachSession
//!     Spec: session-pane-management AttachSession request/response

const std = @import("std");
const header_mod = @import("../../header.zig");
const Header = header_mod.Header;
const session_mod = @import("../../session.zig");
const pane_mod = @import("../../pane.zig");
const message_type_mod = @import("../../message_type.zig");
const MessageType = message_type_mod.MessageType;
const json_mod = @import("../helpers.zig");
const allocator = std.testing.allocator;

// ============================================================================
// WI-1: ADR 00015 -- 20-byte header with u64 sequence
// Spec: protocol overview header layout
// ============================================================================

test "spec: header layout -- total size is exactly 20 bytes" {
    // Spec: protocol overview header layout: total header size is 20 bytes.
    try std.testing.expectEqual(@as(usize, 20), header_mod.HEADER_SIZE);
}

test "spec: header layout -- VERSION field is 2" {
    // Spec: protocol overview header layout version field: currently 2.
    try std.testing.expectEqual(@as(u8, 2), header_mod.VERSION);
}

test "spec: header layout -- magic bytes are 0x49 0x54 (ASCII IT)" {
    // Spec: protocol overview header layout: magic bytes are 0x49 0x54 (ASCII "IT").
    try std.testing.expectEqual(@as(u8, 0x49), header_mod.MAGIC[0]);
    try std.testing.expectEqual(@as(u8, 0x54), header_mod.MAGIC[1]);
}

test "spec: header layout -- sequence field at offset 12 is u64 (8 bytes)" {
    // Spec: protocol overview header layout: offset 12, size 8, sequence.
    // Verify by encoding a header and checking the wire bytes directly.
    const hdr = Header{
        .msg_type = 0x0001,
        .flags = .{},
        .payload_length = 0,
        .sequence = 0xDEAD_BEEF_CAFE_BABE,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);

    // Offset 12..20 should contain the u64 sequence in little-endian
    const seq_on_wire = std.mem.readInt(u64, buf[12..20], .little);
    try std.testing.expectEqual(@as(u64, 0xDEAD_BEEF_CAFE_BABE), seq_on_wire);
}

test "spec: header layout -- round-trip preserves u64 sequence values beyond u32 max" {
    // Spec: protocol overview header layout: sequence is u64, must handle values > 2^32.
    const large_sequences = [_]u64{
        0x1_0000_0000, // u32 max + 1
        0xFFFF_FFFF_FFFF_FFFF, // u64 max
        0x0000_0001_0000_0001, // high and low bits set
    };
    for (large_sequences) |seq| {
        const hdr = Header{
            .msg_type = 0x0100,
            .flags = .{},
            .payload_length = 42,
            .sequence = seq,
        };
        var buf: [header_mod.HEADER_SIZE]u8 = undefined;
        hdr.encode(&buf);
        const decoded = try Header.decode(&buf);
        try std.testing.expectEqual(seq, decoded.sequence);
    }
}

test "spec: header layout -- reserved field at offset 6 must be zero" {
    // Spec: protocol overview header layout: reserved field must be 0 (alignment padding).
    // Encoder must write 0; decoder must reject non-zero.
    const hdr = Header{
        .msg_type = 0x0001,
        .flags = .{},
        .payload_length = 0,
        .sequence = 1,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);

    // Verify encoder writes 0 at offset 6..8
    const reserved_on_wire = std.mem.readInt(u16, buf[6..8], .little);
    try std.testing.expectEqual(@as(u16, 0), reserved_on_wire);

    // Verify decoder rejects non-zero reserved
    std.mem.writeInt(u16, buf[6..8], 0x0001, .little);
    try std.testing.expectError(error.ReservedFieldNonZero, Header.decode(&buf));
}

test "spec: header layout -- payload_length at offset 8 is u32" {
    // Spec: protocol overview header layout: offset 8, size 4, payload_len.
    const hdr = Header{
        .msg_type = 0x0001,
        .flags = .{},
        .payload_length = 0x00ABCDEF,
        .sequence = 0,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);

    const plen_on_wire = std.mem.readInt(u32, buf[8..12], .little);
    try std.testing.expectEqual(@as(u32, 0x00ABCDEF), plen_on_wire);
}

test "spec: header layout -- msg_type at offset 4 is u16" {
    // Spec: protocol overview header layout: offset 4, size 2, msg_type.
    const hdr = Header{
        .msg_type = 0x0104,
        .flags = .{},
        .payload_length = 0,
        .sequence = 0,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);

    const mtype_on_wire = std.mem.readInt(u16, buf[4..6], .little);
    try std.testing.expectEqual(@as(u16, 0x0104), mtype_on_wire);
}

test "spec: header layout -- version byte at offset 2" {
    // Spec: protocol overview header layout: offset 2, size 1, version.
    const hdr = Header{
        .msg_type = 0x0001,
        .flags = .{},
        .payload_length = 0,
        .sequence = 0,
    };
    var buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&buf);

    try std.testing.expectEqual(header_mod.VERSION, buf[2]);
}

// ============================================================================
// WI-2: ADR 00062 -- Fixed-point ratio for resize and split
// Spec: session-pane-management split/resize/equalize procedures, layout tree
// ============================================================================

test "spec: split ratio -- SplitPaneRequest ratio 5000 round-trips as integer" {
    // Spec: session-pane-management split procedure + conventions: ratios are
    // fixed-point u32 integers (x10^4, range 0-10000, where 5000 = 50%).
    const req = pane_mod.SplitPaneRequest{
        .session_id = 1,
        .pane_id = 1,
        .direction = 1,
        .ratio = 5000,
    };
    // Verify ratio value is exactly 5000 (integer, not float approximation).
    try std.testing.expectEqual(@as(@TypeOf(req.ratio), 5000), req.ratio);
}

test "spec: split ratio -- SplitPaneRequest ratio 5000 round-trips via JSON" {
    // Spec: session-pane-management split procedure: ratio value 5000 = 50.00%.
    const req = pane_mod.SplitPaneRequest{
        .session_id = 1,
        .pane_id = 1,
        .direction = 1,
        .ratio = 5000,
    };
    const j = try json_mod.encode(allocator, req);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane_mod.SplitPaneRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(@TypeOf(parsed.value.ratio), 5000), parsed.value.ratio);
}

test "spec: resize -- ResizePaneRequest orientation field round-trips via JSON" {
    // Spec: session-pane-management resize procedure: orientation indicates
    // the split axis to resize (0 = horizontal, 1 = vertical).
    const req = pane_mod.ResizePaneRequest{
        .session_id = 1,
        .pane_id = 1,
        .orientation = 1,
        .delta_ratio = 500,
    };
    const j = try json_mod.encode(allocator, req);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane_mod.ResizePaneRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u8, 1), parsed.value.orientation);
}

test "spec: resize -- ResizePaneRequest delta_ratio field round-trips via JSON" {
    // Spec: session-pane-management resize procedure: delta_ratio is a signed
    // fixed-point ratio delta (x10^4).
    const req = pane_mod.ResizePaneRequest{
        .session_id = 1,
        .pane_id = 1,
        .orientation = 0,
        .delta_ratio = -500,
    };
    const j = try json_mod.encode(allocator, req);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane_mod.ResizePaneRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, -500), parsed.value.delta_ratio);
}

test "spec: resize -- ResizePaneRequest delta_ratio accepts negative values" {
    // Spec: session-pane-management resize procedure: delta_ratio is i32 signed,
    // supporting both positive (grow) and negative (shrink) deltas.
    const req = pane_mod.ResizePaneRequest{
        .session_id = 1,
        .pane_id = 1,
        .orientation = 0,
        .delta_ratio = -1000,
    };
    try std.testing.expectEqual(@as(i32, -1000), req.delta_ratio);

    const req_pos = pane_mod.ResizePaneRequest{
        .session_id = 1,
        .pane_id = 1,
        .orientation = 0,
        .delta_ratio = 1000,
    };
    try std.testing.expectEqual(@as(i32, 1000), req_pos.delta_ratio);
}

test "spec: resize -- ResizePaneRequest orientation distinguishes horizontal and vertical" {
    // Spec: session-pane-management resize procedure: orientation u8,
    // 0 = horizontal, 1 = vertical.
    const req_h = pane_mod.ResizePaneRequest{
        .session_id = 1,
        .pane_id = 1,
        .orientation = 0,
        .delta_ratio = 500,
    };
    const req_v = pane_mod.ResizePaneRequest{
        .session_id = 1,
        .pane_id = 1,
        .orientation = 1,
        .delta_ratio = 500,
    };
    try std.testing.expectEqual(@as(u8, 0), req_h.orientation);
    try std.testing.expectEqual(@as(u8, 1), req_v.orientation);
}

test "spec: equalize -- EqualizeSplitsRequest only needs session_id" {
    // Spec: session-pane-management equalize-splits procedure: sets all split
    // ratios to 5000 (equal distribution). Only needs session_id.
    const req = pane_mod.EqualizeSplitsRequest{ .session_id = 1 };
    const j = try json_mod.encode(allocator, req);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane_mod.EqualizeSplitsRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.session_id);
}

test "spec: layout tree -- LayoutNode ratio round-trips integer value via JSON" {
    // Spec: session-pane-management layout tree: JSON representation uses
    // integer values (e.g., "ratio": 5000). The ratio must be integer, not float.
    const node = pane_mod.LayoutNode{
        .type = .split,
        .ratio = 5000,
        .orientation = "horizontal",
    };
    const j = try json_mod.encode(allocator, node);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane_mod.LayoutNode, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(@TypeOf(parsed.value.ratio.?), 5000), parsed.value.ratio.?);
}

// ============================================================================
// WI-3: ADR 00003 -- AttachOrCreate merged into AttachSession
// Spec: session-pane-management AttachSession request/response
// ============================================================================

test "spec: message types -- no 0x010C or 0x010D type codes exist" {
    // Spec: session-pane-management message type table: codes 0x010C and 0x010D are absent.
    // ADR 00003 merged AttachOrCreate into AttachSession.
    // The enum should not have these values as named variants.
    const val_010c: u16 = 0x010C;
    const val_010d: u16 = 0x010D;

    // Converting these to MessageType should produce the catch-all "_" variant,
    // not a named variant.
    const mt_c: MessageType = @enumFromInt(val_010c);
    const mt_d: MessageType = @enumFromInt(val_010d);

    // They should not match any named session management variant
    try std.testing.expect(mt_c != MessageType.attach_session_request);
    try std.testing.expect(mt_c != MessageType.attach_session_response);
    try std.testing.expect(mt_d != MessageType.attach_session_request);
    try std.testing.expect(mt_d != MessageType.attach_session_response);

    // Verify they fall into the non-exhaustive catch-all (no named tag)
    const tag_name_c = std.enums.tagName(MessageType, mt_c);
    const tag_name_d = std.enums.tagName(MessageType, mt_d);
    try std.testing.expect(tag_name_c == null);
    try std.testing.expect(tag_name_d == null);
}

test "spec: AttachSessionRequest -- supports lookup by session_id" {
    // Spec: session-pane-management AttachSessionRequest: session_id for attaching by ID.
    const req = session_mod.AttachSessionRequest{
        .session_id = 42,
        .cols = 80,
        .rows = 24,
    };
    const j = try json_mod.encode(allocator, req);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session_mod.AttachSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 42), parsed.value.session_id);
}

test "spec: AttachSessionRequest -- supports lookup by session_name" {
    // Spec: session-pane-management AttachSessionRequest: session_name to attach to.
    const req = session_mod.AttachSessionRequest{
        .session_name = "main",
        .cols = 120,
        .rows = 40,
    };
    const j = try json_mod.encode(allocator, req);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session_mod.AttachSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("main", parsed.value.session_name.?);
}

test "spec: AttachSessionRequest -- create_if_missing field exists and defaults to false" {
    // Spec: session-pane-management AttachSessionRequest: create_if_missing defaults to false.
    const req = session_mod.AttachSessionRequest{
        .session_id = 1,
    };
    try std.testing.expect(!req.create_if_missing);

    // With create_if_missing=true
    const req_create = session_mod.AttachSessionRequest{
        .session_name = "dev",
        .create_if_missing = true,
    };
    const j = try json_mod.encode(allocator, req_create);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session_mod.AttachSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.create_if_missing);
}

test "spec: AttachSessionResponse -- action_taken indicates attached or created" {
    // Spec: session-pane-management AttachSessionResponse: action_taken is "attached" or "created".
    // Test "attached"
    {
        const resp = session_mod.AttachSessionResponse{
            .status = 0,
            .action_taken = "attached",
            .session_id = 1,
        };
        const j = try json_mod.encode(allocator, resp);
        defer allocator.free(j);
        const parsed = try json_mod.decode(session_mod.AttachSessionResponse, allocator, j);
        defer parsed.deinit();
        try std.testing.expectEqualStrings("attached", parsed.value.action_taken);
    }
    // Test "created"
    {
        const resp = session_mod.AttachSessionResponse{
            .status = 0,
            .action_taken = "created",
            .session_id = 2,
            .pane_id = 1,
        };
        const j = try json_mod.encode(allocator, resp);
        defer allocator.free(j);
        const parsed = try json_mod.decode(session_mod.AttachSessionResponse, allocator, j);
        defer parsed.deinit();
        try std.testing.expectEqualStrings("created", parsed.value.action_taken);
    }
}

test "spec: AttachSessionResponse -- includes session metadata fields" {
    // Spec: session-pane-management AttachSessionResponse: includes session_id,
    // name, active_pane_id, active_input_method, active_keyboard_layout, resize_policy.
    const resp = session_mod.AttachSessionResponse{
        .status = 0,
        .action_taken = "attached",
        .session_id = 5,
        .name = "my-session",
        .active_pane_id = 3,
        .active_input_method = "korean_2set",
        .active_keyboard_layout = "qwerty",
        .resize_policy = "latest",
    };
    const j = try json_mod.encode(allocator, resp);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session_mod.AttachSessionResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 5), parsed.value.session_id);
    try std.testing.expectEqualStrings("my-session", parsed.value.name);
    try std.testing.expectEqual(@as(u32, 3), parsed.value.active_pane_id);
    try std.testing.expectEqualStrings("korean_2set", parsed.value.active_input_method);
    try std.testing.expectEqualStrings("qwerty", parsed.value.active_keyboard_layout);
    try std.testing.expectEqualStrings("latest", parsed.value.resize_policy);
}

test "spec: AttachSessionRequest -- shell and cwd fields for session creation" {
    // Spec: session-pane-management AttachSessionRequest: shell and cwd are
    // used only when creating a new session.
    const req = session_mod.AttachSessionRequest{
        .session_name = "dev",
        .create_if_missing = true,
        .shell = "/bin/zsh",
        .cwd = "/home/user",
        .cols = 80,
        .rows = 24,
    };
    const j = try json_mod.encode(allocator, req);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session_mod.AttachSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("/bin/zsh", parsed.value.shell.?);
    try std.testing.expectEqualStrings("/home/user", parsed.value.cwd.?);
}

test "spec: AttachSessionRequest -- detach_others field exists" {
    // Spec: session-pane-management AttachSessionRequest: detach_others force-detaches all other clients.
    const req = session_mod.AttachSessionRequest{
        .session_id = 1,
        .detach_others = true,
    };
    const j = try json_mod.encode(allocator, req);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session_mod.AttachSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.detach_others);
}
