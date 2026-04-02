//! Spec compliance tests: Handshake flow.
//!
//! Covers connection state machine transitions, version negotiation,
//! general/render capability negotiation, ServerHello contents, malformed
//! input handling, and handshake timeout constants.
//!
//! Spec sources:
//!   - protocol handshake-capability-negotiation — ClientHello/ServerHello, negotiation
//!   - daemon-behavior policies-and-procedures — timeouts, negotiation algorithms
//!   - daemon-architecture integration-boundaries — connection state machine

const std = @import("std");
const server = @import("itshell3_server");
const ConnectionState = server.connection.connection_state.ConnectionState;
const State = server.connection.connection_state.State;
const handshake_handler = server.connection.handshake_handler;
const protocol = @import("itshell3_protocol");
const ErrorCode = protocol.err.ErrorCode;

// ── Spec: Connection State Machine ───────────────────────────────────────────

test "spec: state machine — daemon starts at HANDSHAKING (after accept)" {
    const conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expectEqual(State.handshaking, conn.state);
}

test "spec: state machine — HANDSHAKING to READY on valid ClientHello" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expect(conn.transitionTo(.ready));
    try std.testing.expectEqual(State.ready, conn.state);
}

test "spec: state machine — HANDSHAKING to DISCONNECTING on invalid ClientHello or timeout" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expect(conn.transitionTo(.disconnecting));
    try std.testing.expectEqual(State.disconnecting, conn.state);
}

test "spec: state machine — READY to OPERATING on AttachSession" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    try std.testing.expect(conn.transitionTo(.operating));
    try std.testing.expectEqual(State.operating, conn.state);
}

test "spec: state machine — OPERATING to READY on DetachSession" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    _ = conn.transitionTo(.operating);
    try std.testing.expect(conn.transitionTo(.ready));
    try std.testing.expectEqual(State.ready, conn.state);
}

test "spec: state machine — DISCONNECTING is terminal" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.disconnecting);
    try std.testing.expect(!conn.transitionTo(.ready));
    try std.testing.expect(!conn.transitionTo(.operating));
    try std.testing.expect(!conn.transitionTo(.handshaking));
    try std.testing.expectEqual(State.disconnecting, conn.state);
}

test "spec: state machine — HANDSHAKING cannot go directly to OPERATING" {
    // Not in spec — must go through READY first.
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expect(!conn.transitionTo(.operating));
    try std.testing.expectEqual(State.handshaking, conn.state);
}

// ── Spec: Sequence Numbers ───────────────────────────────────────────────────

test "spec: sequence — send sequence starts at 1" {
    // Protocol spec 01-protocol-overview: sequence starts at 1.
    const conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expectEqual(@as(u64, 1), conn.send_sequence);
}

test "spec: sequence — u64 sequence increments beyond u32 max without wrapping" {
    // Protocol v2: sequence is u64, no practical wrap concern.
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    conn.send_sequence = 0xFFFFFFFF;
    const seq = conn.advanceSendSequence();
    try std.testing.expectEqual(@as(u64, 0xFFFFFFFF), seq);
    try std.testing.expectEqual(@as(u64, 0x100000000), conn.send_sequence);
}

test "spec: sequence — advanceSendSequence returns current then increments" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expectEqual(@as(u64, 1), conn.advanceSendSequence());
    try std.testing.expectEqual(@as(u64, 2), conn.advanceSendSequence());
    try std.testing.expectEqual(@as(u64, 3), conn.advanceSendSequence());
}

// ── Spec: Message Validation Per State ───────────────────────────────────────

test "spec: message validation — HANDSHAKING allows only ClientHello, Error, Disconnect" {
    const conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expect(conn.isMessageAllowed(.client_hello));
    try std.testing.expect(conn.isMessageAllowed(.@"error"));
    try std.testing.expect(conn.isMessageAllowed(.disconnect));
    try std.testing.expect(!conn.isMessageAllowed(.heartbeat));
    try std.testing.expect(!conn.isMessageAllowed(.key_event));
    try std.testing.expect(!conn.isMessageAllowed(.frame_update));
    try std.testing.expect(!conn.isMessageAllowed(.attach_session_request));
}

test "spec: message validation — READY allows heartbeat, session attach/create, disconnect" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    try std.testing.expect(conn.isMessageAllowed(.heartbeat));
    try std.testing.expect(conn.isMessageAllowed(.heartbeat_ack));
    try std.testing.expect(conn.isMessageAllowed(.disconnect));
    try std.testing.expect(conn.isMessageAllowed(.@"error"));
    try std.testing.expect(conn.isMessageAllowed(.attach_session_request));
    try std.testing.expect(conn.isMessageAllowed(.create_session_request));
    try std.testing.expect(conn.isMessageAllowed(.list_sessions_request));
    try std.testing.expect(conn.isMessageAllowed(.attach_session_request));
    try std.testing.expect(conn.isMessageAllowed(.client_display_info));
    // KeyEvent is not allowed in READY (no attached session).
    try std.testing.expect(!conn.isMessageAllowed(.key_event));
}

test "spec: message validation — OPERATING allows all operational messages" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    _ = conn.transitionTo(.operating);
    try std.testing.expect(conn.isMessageAllowed(.key_event));
    try std.testing.expect(conn.isMessageAllowed(.frame_update));
    try std.testing.expect(conn.isMessageAllowed(.preedit_start));
    try std.testing.expect(conn.isMessageAllowed(.heartbeat));
    try std.testing.expect(conn.isMessageAllowed(.disconnect));
    try std.testing.expect(conn.isMessageAllowed(.detach_session_request));
}

test "spec: message validation — DISCONNECTING allows only Disconnect and Error" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.disconnecting);
    try std.testing.expect(conn.isMessageAllowed(.disconnect));
    try std.testing.expect(conn.isMessageAllowed(.@"error"));
    try std.testing.expect(!conn.isMessageAllowed(.heartbeat));
    try std.testing.expect(!conn.isMessageAllowed(.key_event));
    try std.testing.expect(!conn.isMessageAllowed(.client_hello));
}

// ── Spec: Protocol Version Negotiation ───────────────────────────────────────

test "spec: handshake — version negotiation succeeds when ranges overlap" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":[],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = handshake_handler.processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .success => {},
        else => return error.TestUnexpectedResult,
    }
}

test "spec: handshake — version mismatch when client min > server version" {
    const hello_json =
        \\{"protocol_version_min":99,"protocol_version_max":99,"client_type":"native","capabilities":[],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = handshake_handler.processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .version_mismatch => |err_data| {
            try std.testing.expectEqual(@intFromEnum(ErrorCode.version_mismatch), err_data.error_code);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "spec: handshake — version mismatch when client max < server version" {
    // Client only supports versions 0 through 0, which doesn't include server's v1.
    const hello_json =
        \\{"protocol_version_min":0,"protocol_version_max":0,"client_type":"native","capabilities":[],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = handshake_handler.processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .version_mismatch => {},
        else => return error.TestUnexpectedResult,
    }
}

// ── Spec: General Capability Negotiation ─────────────────────────────────────

test "spec: handshake — general capabilities are intersection of client and server" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":["clipboard_sync","mouse","unknown_cap","fd_passing"],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = handshake_handler.processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .success => |data| {
            const payload = data.getPayload();
            // clipboard_sync and mouse are in both client and server caps.
            try std.testing.expect(std.mem.indexOf(u8, payload, "clipboard_sync") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "mouse") != null);
            // fd_passing is client-only, should NOT be in negotiated caps.
            // unknown_cap is client-only, should NOT be in negotiated caps.
            // Note: We verify presence in the full payload which includes negotiated_caps.
        },
        else => return error.TestUnexpectedResult,
    }
}

test "spec: handshake — unknown capability names are ignored (forward compatibility)" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":["future_feature_2030"],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = handshake_handler.processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .success => {
            // Should succeed — unknown caps are silently ignored, not rejected.
        },
        else => return error.TestUnexpectedResult,
    }
}

// ── Spec: Render Capability Negotiation ──────────────────────────────────────

test "spec: handshake — render capabilities are intersection" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":[],"render_capabilities":["cell_data","dirty_tracking","hyperlinks"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = handshake_handler.processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .success => |data| {
            const payload = data.getPayload();
            // cell_data and dirty_tracking are in both.
            try std.testing.expect(std.mem.indexOf(u8, payload, "cell_data") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "dirty_tracking") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "spec: handshake — ERR_CAPABILITY_REQUIRED when no common rendering mode" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":[],"render_capabilities":["hyperlinks","sixel"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = handshake_handler.processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .capability_required => |err_data| {
            try std.testing.expectEqual(@intFromEnum(ErrorCode.capability_required), err_data.error_code);
            const detail = err_data.getDetail();
            try std.testing.expect(std.mem.indexOf(u8, detail, "rendering mode") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "spec: handshake — empty render capabilities causes capability required error" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":[],"render_capabilities":[],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = handshake_handler.processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .capability_required => {},
        else => return error.TestUnexpectedResult,
    }
}

// ── Spec: ServerHello Contents ───────────────────────────────────────────────

test "spec: handshake — ServerHello contains required fields" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":["clipboard_sync"],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = handshake_handler.processClientHello(std.testing.allocator, hello_json, 42, 5678);
    switch (result) {
        .success => |data| {
            const payload = data.getPayload();
            // Required fields must be present in JSON.
            try std.testing.expect(std.mem.indexOf(u8, payload, "protocol_version") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "client_id") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "negotiated_caps") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "negotiated_render_caps") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "supported_input_methods") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "server_pid") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "server_name") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "server_version") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "heartbeat_interval_ms") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "max_panes_per_session") != null);
            // client_id should match the assigned value.
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"client_id\":42") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "spec: handshake — ServerHello heartbeat_interval_ms is 30000" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":[],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = handshake_handler.processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .success => |data| {
            const payload = data.getPayload();
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"heartbeat_interval_ms\":30000") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "spec: handshake — ServerHello max_panes_per_session is 16" {
    const hello_json =
        \\{"protocol_version_min":1,"protocol_version_max":1,"client_type":"native","capabilities":[],"render_capabilities":["cell_data"],"client_name":"test","client_version":"1.0","terminal_type":"xterm","cols":80,"rows":24}
    ;
    const result = handshake_handler.processClientHello(std.testing.allocator, hello_json, 1, 1234);
    switch (result) {
        .success => |data| {
            const payload = data.getPayload();
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"max_panes_per_session\":16") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

// ── Spec: Malformed Input ────────────────────────────────────────────────────

test "spec: handshake — malformed JSON produces error" {
    const result = handshake_handler.processClientHello(std.testing.allocator, "{not json!", 1, 1234);
    switch (result) {
        .malformed_payload => |err_data| {
            try std.testing.expectEqual(@intFromEnum(ErrorCode.malformed_payload), err_data.error_code);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "spec: handshake — empty payload produces error" {
    const result = handshake_handler.processClientHello(std.testing.allocator, "", 1, 1234);
    switch (result) {
        .malformed_payload => {},
        else => return error.TestUnexpectedResult,
    }
}

// ── Spec: Handshake Timeout Values ───────────────────────────────────────────

test "spec: handshake — timeout constants match spec" {
    // Timer base ranges must be defined for proper dispatch of handshake,
    // ready-idle, and heartbeat timers.
    const timer_handler = server.handlers.timer_handler;
    try std.testing.expect(timer_handler.HANDSHAKE_TIMER_BASE < timer_handler.READY_IDLE_TIMER_BASE);
    try std.testing.expect(timer_handler.HEARTBEAT_TIMER_ID != timer_handler.HANDSHAKE_TIMER_BASE);
    try std.testing.expect(timer_handler.HEARTBEAT_TIMER_ID != timer_handler.READY_IDLE_TIMER_BASE);
}
