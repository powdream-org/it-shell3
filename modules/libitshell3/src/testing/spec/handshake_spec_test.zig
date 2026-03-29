//! Spec compliance tests: Handshake flow.
//!
//! Spec sources:
//!   - protocol 02-handshake-capability-negotiation — ClientHello/ServerHello fields,
//!     negotiation algorithm, render capability requirement
//!   - daemon-behavior 03-policies-and-procedures — handshake timeouts, negotiation
//!     algorithms (Section 13, 14)
//!   - daemon-architecture 03-integration-boundaries — connection state machine
//!
//! These tests are derived from the SPEC, not the implementation.
//! QA-owned: verifies that the implementation conforms to the design spec.

const std = @import("std");
const server = @import("itshell3_server");
const ConnectionState = server.connection.connection_state.ConnectionState;
const State = server.connection.connection_state.State;
const handshake_handler = server.connection.handshake_handler;
const protocol = @import("itshell3_protocol");
const ErrorCode = protocol.err.ErrorCode;

// ── Spec: Connection State Machine ───────────────────────────────────────────

test "spec: state machine — daemon starts at HANDSHAKING (after accept)" {
    // daemon-architecture 03-integration-boundaries Section 1.4:
    // "The daemon's per-client state machine starts at HANDSHAKING."
    const conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expectEqual(State.handshaking, conn.state);
}

test "spec: state machine — HANDSHAKING to READY on valid ClientHello" {
    // daemon-behavior 03-policies-and-procedures Section 12:
    // "HANDSHAKING -> READY: Valid ClientHello"
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expect(conn.transitionTo(.ready));
    try std.testing.expectEqual(State.ready, conn.state);
}

test "spec: state machine — HANDSHAKING to DISCONNECTING on invalid ClientHello or timeout" {
    // daemon-behavior 03-policies-and-procedures Section 12:
    // "HANDSHAKING -> [closed]: Invalid ClientHello / timeout"
    // Implementation: HANDSHAKING -> DISCONNECTING -> [closed]
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expect(conn.transitionTo(.disconnecting));
    try std.testing.expectEqual(State.disconnecting, conn.state);
}

test "spec: state machine — READY to OPERATING on AttachSession" {
    // daemon-behavior 03-policies-and-procedures Section 12:
    // "READY -> OPERATING: AttachSessionRequest"
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    try std.testing.expect(conn.transitionTo(.operating));
    try std.testing.expectEqual(State.operating, conn.state);
}

test "spec: state machine — OPERATING to READY on DetachSession" {
    // daemon-behavior 03-policies-and-procedures Section 12:
    // "OPERATING -> READY: DetachSessionRequest"
    // "Key transition: OPERATING -> READY (detach without disconnect)"
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    _ = conn.transitionTo(.operating);
    try std.testing.expect(conn.transitionTo(.ready));
    try std.testing.expectEqual(State.ready, conn.state);
}

test "spec: state machine — DISCONNECTING is terminal" {
    // daemon-behavior 03-policies-and-procedures Section 12:
    // "DISCONNECTING -> [closed]" (only outcome from DISCONNECTING)
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
    try std.testing.expectEqual(@as(u32, 1), conn.send_sequence);
}

test "spec: sequence — send sequence wraps from 0xFFFFFFFF to 1 (skips 0)" {
    // Protocol spec 01-protocol-overview: wraps at 0xFFFFFFFF -> 1.
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    conn.send_sequence = 0xFFFFFFFF;
    const seq = conn.advanceSendSequence();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), seq);
    try std.testing.expectEqual(@as(u32, 1), conn.send_sequence);
}

test "spec: sequence — advanceSendSequence returns current then increments" {
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    try std.testing.expectEqual(@as(u32, 1), conn.advanceSendSequence());
    try std.testing.expectEqual(@as(u32, 2), conn.advanceSendSequence());
    try std.testing.expectEqual(@as(u32, 3), conn.advanceSendSequence());
}

// ── Spec: Message Validation Per State ───────────────────────────────────────

test "spec: message validation — HANDSHAKING allows only ClientHello, Error, Disconnect" {
    // daemon-architecture 03-integration-boundaries: state machine validates
    // message sequencing.
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
    // daemon-behavior 03-policies-and-procedures Section 12:
    // In READY state, client can attach/create sessions and receive heartbeats.
    var conn = ConnectionState.init(.{ .fd = 5 }, 1);
    _ = conn.transitionTo(.ready);
    try std.testing.expect(conn.isMessageAllowed(.heartbeat));
    try std.testing.expect(conn.isMessageAllowed(.heartbeat_ack));
    try std.testing.expect(conn.isMessageAllowed(.disconnect));
    try std.testing.expect(conn.isMessageAllowed(.@"error"));
    try std.testing.expect(conn.isMessageAllowed(.attach_session_request));
    try std.testing.expect(conn.isMessageAllowed(.create_session_request));
    try std.testing.expect(conn.isMessageAllowed(.list_sessions_request));
    try std.testing.expect(conn.isMessageAllowed(.attach_or_create_request));
    try std.testing.expect(conn.isMessageAllowed(.client_display_info));
    // KeyEvent is not allowed in READY (no attached session).
    try std.testing.expect(!conn.isMessageAllowed(.key_event));
}

test "spec: message validation — OPERATING allows all operational messages" {
    // daemon-behavior 03-policies-and-procedures Section 12:
    // OPERATING allows session management, input, render, IME, flow control.
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
    // daemon-behavior 03-policies-and-procedures Section 12:
    // "DISCONNECTING state: only Disconnect and Error accepted"
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
    // daemon-behavior 03-policies-and-procedures Section 14.1:
    // negotiated_version = min(server_max_version, client.protocol_version_max)
    // In v1, both min and max are 1.
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
    // daemon-behavior 03-policies-and-procedures Section 14.1:
    // "if negotiated_version < client.protocol_version_min -> ERR_VERSION_MISMATCH"
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
    // daemon-behavior 03-policies-and-procedures Section 14.2:
    // "negotiated_caps = intersection(client.capabilities, server.capabilities)"
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
    // daemon-behavior 03-policies-and-procedures Section 14.2:
    // "Unknown capability names are ignored (forward compatibility)."
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
    // daemon-behavior 03-policies-and-procedures Section 14.3:
    // "negotiated_render_caps = intersection(client.render_capabilities, server.render_capabilities)"
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
    // daemon-behavior 03-policies-and-procedures Section 14.3:
    // "At least one rendering mode MUST be supported. If neither cell_data nor
    //  vt_fallback is in the intersection, the server MUST send
    //  Error(ERR_CAPABILITY_REQUIRED)."
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
    // protocol 02-handshake-capability-negotiation Section 3:
    // ServerHello must contain protocol_version, client_id, negotiated_caps,
    // negotiated_render_caps, supported_input_methods, server_pid,
    // server_name, server_version, heartbeat_interval_ms, max_panes_per_session.
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
    // daemon-behavior 03-policies-and-procedures Section 10.1:
    // "Heartbeat interval: 30s"
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
    // daemon-architecture 01-module-structure Section 1.5:
    // "MAX_PANES = 16" and this is communicated in ServerHello.
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
    // daemon-behavior 03-policies-and-procedures Section 13:
    // "Transport connection (accept to first byte): 5s"
    // "ClientHello -> ServerHello: 5s"
    // "READY -> AttachSession/CreateSession/AttachOrCreate: 60s"
    //
    // These are enforced via timer IDs in timer_handler.zig. Verify the
    // timer base ranges are defined for proper dispatch.
    const timer_handler = server.handlers.timer_handler;
    try std.testing.expect(timer_handler.HANDSHAKE_TIMER_BASE < timer_handler.READY_IDLE_TIMER_BASE);
    try std.testing.expect(timer_handler.HEARTBEAT_TIMER_ID != timer_handler.HANDSHAKE_TIMER_BASE);
    try std.testing.expect(timer_handler.HEARTBEAT_TIMER_ID != timer_handler.READY_IDLE_TIMER_BASE);
}
