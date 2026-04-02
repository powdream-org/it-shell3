//! Spec compliance tests for connection_state.zig.
//!
//! Tests verify: isMessageAllowed branches for each state against the
//! complete message type taxonomy, isOperationalMessageType range coverage
//! for all operational ranges (0x0100-0x08FF).

const std = @import("std");
const server = @import("itshell3_server");
const connection_state_mod = server.connection.connection_state;
const ConnectionState = connection_state_mod.ConnectionState;
const State = connection_state_mod.State;
const transport = @import("itshell3_transport");
const SocketConnection = transport.transport.SocketConnection;
const protocol = @import("itshell3_protocol");
const MessageType = protocol.message_type.MessageType;

fn makeConn(state: State) ConnectionState {
    var conn = ConnectionState.init(SocketConnection{ .fd = 5 }, 1);
    switch (state) {
        .handshaking => {},
        .ready => {
            _ = conn.transitionTo(.ready);
        },
        .operating => {
            _ = conn.transitionTo(.ready);
            _ = conn.transitionTo(.operating);
        },
        .disconnecting => {
            _ = conn.transitionTo(.disconnecting);
        },
    }
    return conn;
}

// ── HANDSHAKING state tests ─────────────────────────────────────────────────

test "spec: connection state -- handshaking rejects heartbeat" {
    const conn = makeConn(.handshaking);
    try std.testing.expect(!conn.isMessageAllowed(.heartbeat));
}

test "spec: connection state -- handshaking rejects heartbeat_ack" {
    const conn = makeConn(.handshaking);
    try std.testing.expect(!conn.isMessageAllowed(.heartbeat_ack));
}

test "spec: connection state -- handshaking rejects session management" {
    const conn = makeConn(.handshaking);
    try std.testing.expect(!conn.isMessageAllowed(.create_session_request));
    try std.testing.expect(!conn.isMessageAllowed(.list_sessions_request));
    try std.testing.expect(!conn.isMessageAllowed(.attach_session_request));
    try std.testing.expect(!conn.isMessageAllowed(.detach_session_request));
}

test "spec: connection state -- handshaking rejects input messages" {
    const conn = makeConn(.handshaking);
    try std.testing.expect(!conn.isMessageAllowed(.key_event));
    try std.testing.expect(!conn.isMessageAllowed(.text_input));
    try std.testing.expect(!conn.isMessageAllowed(.mouse_button));
    try std.testing.expect(!conn.isMessageAllowed(.paste_data));
}

test "spec: connection state -- handshaking rejects preedit messages" {
    const conn = makeConn(.handshaking);
    try std.testing.expect(!conn.isMessageAllowed(.preedit_start));
    try std.testing.expect(!conn.isMessageAllowed(.preedit_update));
    try std.testing.expect(!conn.isMessageAllowed(.preedit_end));
    try std.testing.expect(!conn.isMessageAllowed(.input_method_switch));
}

// ── READY state tests ───────────────────────────────────────────────────────

test "spec: connection state -- ready allows session creation" {
    const conn = makeConn(.ready);
    try std.testing.expect(conn.isMessageAllowed(.create_session_request));
    try std.testing.expect(conn.isMessageAllowed(.list_sessions_request));
    try std.testing.expect(conn.isMessageAllowed(.attach_session_request));
}

test "spec: connection state -- ready allows client_display_info" {
    const conn = makeConn(.ready);
    try std.testing.expect(conn.isMessageAllowed(.client_display_info));
}

test "spec: connection state -- ready rejects operational messages" {
    const conn = makeConn(.ready);
    try std.testing.expect(!conn.isMessageAllowed(.key_event));
    try std.testing.expect(!conn.isMessageAllowed(.frame_update));
    try std.testing.expect(!conn.isMessageAllowed(.preedit_start));
    try std.testing.expect(!conn.isMessageAllowed(.mouse_button));
}

test "spec: connection state -- ready rejects detach_session_request" {
    const conn = makeConn(.ready);
    try std.testing.expect(!conn.isMessageAllowed(.detach_session_request));
}

test "spec: connection state -- ready rejects server_hello" {
    const conn = makeConn(.ready);
    try std.testing.expect(!conn.isMessageAllowed(.server_hello));
}

// ── OPERATING state tests ───────────────────────────────────────────────────

test "spec: connection state -- operating allows detach_session_request" {
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.detach_session_request));
}

test "spec: connection state -- operating allows client_display_info" {
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.client_display_info));
}

test "spec: connection state -- operating allows all input range (0x0200-0x02FF)" {
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.key_event));
    try std.testing.expect(conn.isMessageAllowed(.text_input));
    try std.testing.expect(conn.isMessageAllowed(.mouse_button));
    try std.testing.expect(conn.isMessageAllowed(.mouse_move));
    try std.testing.expect(conn.isMessageAllowed(.mouse_scroll));
    try std.testing.expect(conn.isMessageAllowed(.paste_data));
    try std.testing.expect(conn.isMessageAllowed(.focus_event));
}

test "spec: connection state -- operating allows all renderstate range (0x0300-0x03FF)" {
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.frame_update));
    try std.testing.expect(conn.isMessageAllowed(.scroll_request));
    try std.testing.expect(conn.isMessageAllowed(.scroll_position));
    try std.testing.expect(conn.isMessageAllowed(.search_request));
    try std.testing.expect(conn.isMessageAllowed(.search_result));
    try std.testing.expect(conn.isMessageAllowed(.search_cancel));
}

test "spec: connection state -- operating allows all CJK/IME range (0x0400-0x04FF)" {
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.preedit_start));
    try std.testing.expect(conn.isMessageAllowed(.preedit_update));
    try std.testing.expect(conn.isMessageAllowed(.preedit_end));
    try std.testing.expect(conn.isMessageAllowed(.preedit_sync));
    try std.testing.expect(conn.isMessageAllowed(.input_method_switch));
    try std.testing.expect(conn.isMessageAllowed(.input_method_ack));
    try std.testing.expect(conn.isMessageAllowed(.ambiguous_width_config));
    try std.testing.expect(conn.isMessageAllowed(.ime_error));
}

test "spec: connection state -- operating allows flow control range (0x0500-0x05FF)" {
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.pause_pane));
    try std.testing.expect(conn.isMessageAllowed(.continue_pane));
    try std.testing.expect(conn.isMessageAllowed(.flow_control_config));
    try std.testing.expect(conn.isMessageAllowed(.flow_control_config_ack));
    try std.testing.expect(conn.isMessageAllowed(.output_queue_status));
    try std.testing.expect(conn.isMessageAllowed(.client_display_info));
}

test "spec: connection state -- operating allows clipboard range (0x0600-0x06FF)" {
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.clipboard_write));
    try std.testing.expect(conn.isMessageAllowed(.clipboard_read));
    try std.testing.expect(conn.isMessageAllowed(.clipboard_read_response));
    try std.testing.expect(conn.isMessageAllowed(.clipboard_changed));
    try std.testing.expect(conn.isMessageAllowed(.clipboard_write_from_client));
}

test "spec: connection state -- operating allows persistence range (0x0700-0x07FF)" {
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.snapshot_request));
    try std.testing.expect(conn.isMessageAllowed(.snapshot_response));
    try std.testing.expect(conn.isMessageAllowed(.restore_session_request));
    try std.testing.expect(conn.isMessageAllowed(.restore_session_response));
    try std.testing.expect(conn.isMessageAllowed(.snapshot_list_request));
    try std.testing.expect(conn.isMessageAllowed(.snapshot_list_response));
}

test "spec: connection state -- operating allows notification range (0x0800-0x08FF)" {
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.pane_title_changed));
    try std.testing.expect(conn.isMessageAllowed(.process_exited));
    try std.testing.expect(conn.isMessageAllowed(.bell));
    try std.testing.expect(conn.isMessageAllowed(.renderer_health));
    try std.testing.expect(conn.isMessageAllowed(.subscribe));
    try std.testing.expect(conn.isMessageAllowed(.unsubscribe));
}

test "spec: connection state -- operating allows session management range (0x0100-0x01FF)" {
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.create_session_request));
    try std.testing.expect(conn.isMessageAllowed(.create_session_response));
    try std.testing.expect(conn.isMessageAllowed(.list_sessions_request));
    try std.testing.expect(conn.isMessageAllowed(.attach_session_response));
    try std.testing.expect(conn.isMessageAllowed(.create_pane_request));
    try std.testing.expect(conn.isMessageAllowed(.split_pane_request));
    try std.testing.expect(conn.isMessageAllowed(.close_pane_request));
    try std.testing.expect(conn.isMessageAllowed(.layout_changed));
    try std.testing.expect(conn.isMessageAllowed(.window_resize));
}

test "spec: connection state -- operating rejects client_hello" {
    const conn = makeConn(.operating);
    try std.testing.expect(!conn.isMessageAllowed(.client_hello));
}

test "spec: connection state -- operating rejects server_hello" {
    const conn = makeConn(.operating);
    try std.testing.expect(!conn.isMessageAllowed(.server_hello));
}

// ── DISCONNECTING state tests ───────────────────────────────────────────────

test "spec: connection state -- disconnecting rejects all operational messages" {
    const conn = makeConn(.disconnecting);
    try std.testing.expect(!conn.isMessageAllowed(.key_event));
    try std.testing.expect(!conn.isMessageAllowed(.frame_update));
    try std.testing.expect(!conn.isMessageAllowed(.preedit_start));
    try std.testing.expect(!conn.isMessageAllowed(.client_hello));
    try std.testing.expect(!conn.isMessageAllowed(.create_session_request));
}

test "spec: connection state -- disconnecting rejects heartbeat" {
    const conn = makeConn(.disconnecting);
    try std.testing.expect(!conn.isMessageAllowed(.heartbeat));
    try std.testing.expect(!conn.isMessageAllowed(.heartbeat_ack));
}

// ── isOperationalMessageType range coverage ─────────────────────────────────

test "spec: connection state -- extension range (0x0A00-0x0AFF) operational in OPERATING" {
    const conn = makeConn(.operating);
    try std.testing.expect(conn.isMessageAllowed(.extension_list));
    try std.testing.expect(conn.isMessageAllowed(.extension_list_ack));
    try std.testing.expect(conn.isMessageAllowed(.extension_message));
}

test "spec: connection state -- reserved ranges rejected in OPERATING" {
    const conn = makeConn(.operating);
    // 0x0900-0x09FF (Connection Health reserved) and 0x0B00-0x0FFF (reserved)
    // are not defined in the MessageType enum, so test with raw values via
    // the internal isOperationalMessageType logic boundary.
    // Lifecycle range (0x0000-0x00FF) should also be rejected by the operational check.
    try std.testing.expect(!conn.isMessageAllowed(@enumFromInt(0x0900)));
    try std.testing.expect(!conn.isMessageAllowed(@enumFromInt(0x09FF)));
    try std.testing.expect(!conn.isMessageAllowed(@enumFromInt(0x0B00)));
    try std.testing.expect(!conn.isMessageAllowed(@enumFromInt(0x0FFF)));
}

// ── Capability management ───────────────────────────────────────────────────

test "spec: connection state -- addCapability overflow is silently ignored" {
    var conn = ConnectionState.init(SocketConnection{ .fd = 5 }, 1);
    // Fill all capability slots
    var i: u32 = 0;
    while (i < ConnectionState.MAX_CAPABILITIES) : (i += 1) {
        conn.addCapability("cap");
    }
    try std.testing.expectEqual(ConnectionState.MAX_CAPABILITIES, conn.negotiated_caps_count);
    // Adding one more should not crash or change count
    conn.addCapability("overflow");
    try std.testing.expectEqual(ConnectionState.MAX_CAPABILITIES, conn.negotiated_caps_count);
}

test "spec: connection state -- addCapability rejects name exceeding MAX_CAPABILITY_NAME" {
    var conn = ConnectionState.init(SocketConnection{ .fd = 5 }, 1);
    const long_name = "x" ** (ConnectionState.MAX_CAPABILITY_NAME + 1);
    conn.addCapability(long_name);
    try std.testing.expectEqual(@as(u8, 0), conn.negotiated_caps_count);
}

test "spec: connection state -- addRenderCapability overflow is silently ignored" {
    var conn = ConnectionState.init(SocketConnection{ .fd = 5 }, 1);
    var i: u32 = 0;
    while (i < ConnectionState.MAX_RENDER_CAPABILITIES) : (i += 1) {
        conn.addRenderCapability("rcap");
    }
    try std.testing.expectEqual(ConnectionState.MAX_RENDER_CAPABILITIES, conn.negotiated_render_caps_count);
    conn.addRenderCapability("overflow");
    try std.testing.expectEqual(ConnectionState.MAX_RENDER_CAPABILITIES, conn.negotiated_render_caps_count);
}
