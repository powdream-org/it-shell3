pub const MessageType = enum(u16) {
    // Handshake & Lifecycle (0x0001-0x00FF)
    client_hello = 0x0001,
    server_hello = 0x0002,
    heartbeat = 0x0003,
    heartbeat_ack = 0x0004,
    disconnect = 0x0005,
    @"error" = 0x00FF,

    // Session Management (0x0100-0x013F)
    create_session_request = 0x0100,
    create_session_response = 0x0101,
    list_sessions_request = 0x0102,
    list_sessions_response = 0x0103,
    attach_session_request = 0x0104,
    attach_session_response = 0x0105,
    detach_session_request = 0x0106,
    detach_session_response = 0x0107,
    destroy_session_request = 0x0108,
    destroy_session_response = 0x0109,
    rename_session_request = 0x010A,
    rename_session_response = 0x010B,
    attach_or_create_request = 0x010C,
    attach_or_create_response = 0x010D,

    // Pane Management (0x0140-0x017F)
    create_pane_request = 0x0140,
    create_pane_response = 0x0141,
    split_pane_request = 0x0142,
    split_pane_response = 0x0143,
    close_pane_request = 0x0144,
    close_pane_response = 0x0145,
    focus_pane_request = 0x0146,
    focus_pane_response = 0x0147,
    navigate_pane_request = 0x0148,
    navigate_pane_response = 0x0149,
    resize_pane_request = 0x014A,
    resize_pane_response = 0x014B,
    equalize_splits_request = 0x014C,
    equalize_splits_response = 0x014D,
    zoom_pane_request = 0x014E,
    zoom_pane_response = 0x014F,
    swap_panes_request = 0x0150,
    swap_panes_response = 0x0151,
    layout_get_request = 0x0152,
    layout_get_response = 0x0153,

    // Notifications (0x0180-0x019F)
    layout_changed = 0x0180,
    pane_metadata_changed = 0x0181,
    session_list_changed = 0x0182,
    client_attached = 0x0183,
    client_detached = 0x0184,
    client_health_changed = 0x0185,
    window_resize = 0x0190,
    window_resize_ack = 0x0191,

    // Input (0x0200-0x02FF)
    key_event = 0x0200,
    text_input = 0x0201,
    mouse_button = 0x0202,
    mouse_move = 0x0203,
    mouse_scroll = 0x0204,
    paste_data = 0x0205,
    focus_event = 0x0206,

    // RenderState (0x0300-0x03FF)
    frame_update = 0x0300,
    scroll_request = 0x0301,
    scroll_position = 0x0302,
    search_request = 0x0303,
    search_result = 0x0304,
    search_cancel = 0x0305,

    // CJK & IME (0x0400-0x04FF)
    preedit_start = 0x0400,
    preedit_update = 0x0401,
    preedit_end = 0x0402,
    preedit_sync = 0x0403,
    input_method_switch = 0x0404,
    input_method_ack = 0x0405,
    ambiguous_width_config = 0x0406,
    ime_error = 0x04FF,

    // Flow Control (0x0500-0x05FF)
    pause_pane = 0x0500,
    continue_pane = 0x0501,
    flow_control_config = 0x0502,
    flow_control_config_ack = 0x0503,
    output_queue_status = 0x0504,
    client_display_info = 0x0505,
    client_display_info_ack = 0x0506,

    // Clipboard (0x0600-0x06FF)
    clipboard_write = 0x0600,
    clipboard_read = 0x0601,
    clipboard_read_response = 0x0602,
    clipboard_changed = 0x0603,
    clipboard_write_from_client = 0x0604,

    // Persistence (0x0700-0x07FF)
    snapshot_request = 0x0700,
    snapshot_response = 0x0701,
    restore_session_request = 0x0702,
    restore_session_response = 0x0703,
    snapshot_list_request = 0x0704,
    snapshot_list_response = 0x0705,
    snapshot_auto_save_config = 0x0706,
    snapshot_auto_save_config_ack = 0x0707,

    // Notifications & Subscriptions (0x0800-0x08FF)
    pane_title_changed = 0x0800,
    process_exited = 0x0801,
    bell = 0x0802,
    renderer_health = 0x0803,
    pane_cwd_changed = 0x0804,
    activity_detected = 0x0805,
    silence_detected = 0x0806,
    subscribe = 0x0810,
    subscribe_ack = 0x0811,
    unsubscribe = 0x0812,
    unsubscribe_ack = 0x0813,

    // Extensions (0x0A00-0x0AFF)
    extension_list = 0x0A00,
    extension_list_ack = 0x0A01,
    extension_message = 0x0A02,
    _,

    /// Returns the expected encoding for this message type.
    pub fn expectedEncoding(self: MessageType) Encoding {
        return switch (self) {
            .frame_update => .binary,
            else => .json,
        };
    }

    pub const Encoding = enum { json, binary };
};

const std = @import("std");

test "MessageType: spot-check enum values" {
    try std.testing.expectEqual(@as(u16, 0x0001), @intFromEnum(MessageType.client_hello));
    try std.testing.expectEqual(@as(u16, 0x0300), @intFromEnum(MessageType.frame_update));
    try std.testing.expectEqual(@as(u16, 0x04FF), @intFromEnum(MessageType.ime_error));
    try std.testing.expectEqual(@as(u16, 0x00FF), @intFromEnum(MessageType.@"error"));
}

test "MessageType.expectedEncoding: returns correct encoding" {
    try std.testing.expectEqual(MessageType.Encoding.binary, MessageType.frame_update.expectedEncoding());
    try std.testing.expectEqual(MessageType.Encoding.json, MessageType.client_hello.expectedEncoding());
    try std.testing.expectEqual(MessageType.Encoding.json, MessageType.key_event.expectedEncoding());
    try std.testing.expectEqual(MessageType.Encoding.json, MessageType.preedit_start.expectedEncoding());
}
