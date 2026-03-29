//! Spec compliance tests closing coverage gaps in protocol message types.
//!
//! Covers: auxiliary.zig, session.zig, input.zig, handshake.zig, cell.zig,
//! pane.zig, preedit.zig, testing/helpers.zig -- JSON round-trip for
//! uncovered types, default values, optional fields, error cases.

const std = @import("std");
const auxiliary = @import("../../auxiliary.zig");
const session = @import("../../session.zig");
const input = @import("../../input.zig");
const handshake = @import("../../handshake.zig");
const cell = @import("../../cell.zig");
const pane = @import("../../pane.zig");
const preedit = @import("../../preedit.zig");

const json_mod = @import("../helpers.zig");
const allocator = std.testing.allocator;

// ── auxiliary.zig gaps ──────────────────────────────────────────────────────

test "spec: auxiliary -- ClientDisplayInfoAck JSON round-trip" {
    const original = auxiliary.ClientDisplayInfoAck{ .status = 1, .effective_max_fps = 30 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.ClientDisplayInfoAck, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.status);
    try std.testing.expectEqual(@as(u32, 30), parsed.value.effective_max_fps);
}

test "spec: auxiliary -- PausePane JSON round-trip" {
    const original = auxiliary.PausePane{ .pane_id = 5, .ring_lag_percent = 75, .ring_lag_bytes = 102400 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.PausePane, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 5), parsed.value.pane_id);
    try std.testing.expectEqual(@as(u32, 75), parsed.value.ring_lag_percent);
}

test "spec: auxiliary -- ContinuePane JSON round-trip" {
    const original = auxiliary.ContinuePane{ .pane_id = 3 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.ContinuePane, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 3), parsed.value.pane_id);
}

test "spec: auxiliary -- FlowControlConfigAck JSON round-trip" {
    const original = auxiliary.FlowControlConfigAck{
        .status = 0,
        .effective_max_age_ms = 3000,
        .effective_stale_ms = 30000,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.FlowControlConfigAck, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 3000), parsed.value.effective_max_age_ms);
}

test "spec: auxiliary -- OutputQueueStatus with panes JSON round-trip" {
    const panes = [_]auxiliary.PaneQueueStatus{
        .{ .pane_id = 1, .ring_lag_bytes = 1024, .ring_lag_percent = 10, .paused = false },
        .{ .pane_id = 2, .ring_lag_bytes = 4096, .ring_lag_percent = 40, .paused = true },
    };
    const original = auxiliary.OutputQueueStatus{ .panes = &panes };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.OutputQueueStatus, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.panes.len);
    try std.testing.expect(parsed.value.panes[1].paused);
}

test "spec: auxiliary -- ClipboardRead JSON round-trip" {
    const original = auxiliary.ClipboardRead{ .pane_id = 1, .clipboard_type = "selection" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.ClipboardRead, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("selection", parsed.value.clipboard_type);
}

test "spec: auxiliary -- ClipboardReadResponse JSON round-trip" {
    const original = auxiliary.ClipboardReadResponse{
        .pane_id = 1,
        .status = 0,
        .data = "clipboard content",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.ClipboardReadResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("clipboard content", parsed.value.data);
}

test "spec: auxiliary -- ClipboardChanged JSON round-trip" {
    const original = auxiliary.ClipboardChanged{ .data = "new content" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.ClipboardChanged, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("new content", parsed.value.data);
}

test "spec: auxiliary -- ClipboardWriteFromClient JSON round-trip" {
    const original = auxiliary.ClipboardWriteFromClient{ .data = "paste this" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.ClipboardWriteFromClient, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("paste this", parsed.value.data);
}

test "spec: auxiliary -- SnapshotResponse with error JSON round-trip" {
    const original = auxiliary.SnapshotResponse{
        .status = 1,
        .@"error" = "disk full",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.SnapshotResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.status);
    try std.testing.expectEqualStrings("disk full", parsed.value.@"error".?);
}

test "spec: auxiliary -- RestoreSessionRequest JSON round-trip" {
    const original = auxiliary.RestoreSessionRequest{
        .path = "/tmp/snapshot.dat",
        .snapshot_session_name = "dev",
        .restore_scrollback = false,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.RestoreSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("/tmp/snapshot.dat", parsed.value.path);
    try std.testing.expect(!parsed.value.restore_scrollback);
}

test "spec: auxiliary -- RestoreSessionResponse JSON round-trip" {
    const original = auxiliary.RestoreSessionResponse{
        .status = 0,
        .session_id = 5,
        .pane_count = 3,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.RestoreSessionResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 5), parsed.value.session_id);
}

test "spec: auxiliary -- SnapshotListResponse with entries JSON round-trip" {
    const snapshots = [_]auxiliary.SnapshotInfo{
        .{ .path = "/tmp/s1.dat", .name = "dev", .has_scrollback = true },
    };
    const original = auxiliary.SnapshotListResponse{ .snapshots = &snapshots };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.SnapshotListResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.value.snapshots.len);
    try std.testing.expect(parsed.value.snapshots[0].has_scrollback);
}

test "spec: auxiliary -- SnapshotAutoSaveConfig JSON round-trip" {
    const original = auxiliary.SnapshotAutoSaveConfig{
        .interval_ms = 16000,
        .include_scrollback = false,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.SnapshotAutoSaveConfig, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 16000), parsed.value.interval_ms);
}

test "spec: auxiliary -- SnapshotAutoSaveConfigAck JSON round-trip" {
    const original = auxiliary.SnapshotAutoSaveConfigAck{ .effective_interval_ms = 10000 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.SnapshotAutoSaveConfigAck, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 10000), parsed.value.effective_interval_ms);
}

test "spec: auxiliary -- PaneTitleChanged JSON round-trip" {
    const original = auxiliary.PaneTitleChanged{ .pane_id = 1, .title = "vim /etc/hosts" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.PaneTitleChanged, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("vim /etc/hosts", parsed.value.title);
}

test "spec: auxiliary -- Bell JSON round-trip" {
    const original = auxiliary.Bell{ .pane_id = 1, .timestamp = 1234567890 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.Bell, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u64, 1234567890), parsed.value.timestamp);
}

test "spec: auxiliary -- PaneCwdChanged JSON round-trip" {
    const original = auxiliary.PaneCwdChanged{ .pane_id = 1, .cwd = "/home/user" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.PaneCwdChanged, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("/home/user", parsed.value.cwd);
}

test "spec: auxiliary -- ActivityDetected JSON round-trip" {
    const original = auxiliary.ActivityDetected{ .pane_id = 2, .timestamp = 99 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.ActivityDetected, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 2), parsed.value.pane_id);
}

test "spec: auxiliary -- SilenceDetected JSON round-trip" {
    const original = auxiliary.SilenceDetected{ .pane_id = 1, .silence_duration_ms = 5000 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.SilenceDetected, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 5000), parsed.value.silence_duration_ms);
}

test "spec: auxiliary -- Unsubscribe JSON round-trip" {
    const original = auxiliary.Unsubscribe{ .pane_id = 1, .event_mask = 0x07 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.Unsubscribe, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 0x07), parsed.value.event_mask);
}

test "spec: auxiliary -- UnsubscribeAck JSON round-trip" {
    const original = auxiliary.UnsubscribeAck{ .status = 0, .active_mask = 0x03 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.UnsubscribeAck, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 0x03), parsed.value.active_mask);
}

test "spec: auxiliary -- SubscribeAck JSON round-trip" {
    const original = auxiliary.SubscribeAck{ .status = 0, .active_mask = 0xFF };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.SubscribeAck, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 0xFF), parsed.value.active_mask);
}

test "spec: auxiliary -- ExtensionList JSON round-trip" {
    const entries = [_]auxiliary.ExtensionEntry{
        .{ .ext_id = 1, .version = "2.0", .name = "clipboard_ext" },
    };
    const original = auxiliary.ExtensionList{ .extensions = &entries };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.ExtensionList, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.value.extensions.len);
    try std.testing.expectEqualStrings("clipboard_ext", parsed.value.extensions[0].name);
}

test "spec: auxiliary -- ExtensionListAck JSON round-trip" {
    const results = [_]auxiliary.ExtensionResult{
        .{ .ext_id = 1, .status = 0, .accepted_version = "2.0" },
    };
    const original = auxiliary.ExtensionListAck{ .results = &results };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.ExtensionListAck, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.value.results.len);
    try std.testing.expectEqualStrings("2.0", parsed.value.results[0].accepted_version);
}

test "spec: auxiliary -- ExtensionMessage JSON round-trip" {
    const original = auxiliary.ExtensionMessage{ .ext_id = 5, .ext_msg_type = 10 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(auxiliary.ExtensionMessage, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 5), parsed.value.ext_id);
    try std.testing.expectEqual(@as(u32, 10), parsed.value.ext_msg_type);
}

// ── session.zig gaps ────────────────────────────────────────────────────────

test "spec: session -- CreateSessionRequest with all defaults JSON round-trip" {
    const original = session.CreateSessionRequest{};
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session.CreateSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.name == null);
    try std.testing.expect(parsed.value.shell == null);
    try std.testing.expect(parsed.value.cwd == null);
}

test "spec: session -- DestroySessionRequest JSON round-trip" {
    const original = session.DestroySessionRequest{ .session_id = 5, .force = true };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session.DestroySessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 5), parsed.value.session_id);
    try std.testing.expect(parsed.value.force);
}

test "spec: session -- DestroySessionResponse with error JSON round-trip" {
    const original = session.DestroySessionResponse{ .status = 1, .@"error" = "not found" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session.DestroySessionResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("not found", parsed.value.@"error".?);
}

test "spec: session -- RenameSessionRequest JSON round-trip" {
    const original = session.RenameSessionRequest{ .session_id = 1, .name = "new-name" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session.RenameSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("new-name", parsed.value.name);
}

test "spec: session -- RenameSessionResponse JSON round-trip" {
    const original = session.RenameSessionResponse{ .status = 0 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session.RenameSessionResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 0), parsed.value.status);
}

test "spec: session -- DetachSessionRequest JSON round-trip" {
    const original = session.DetachSessionRequest{ .session_id = 7 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session.DetachSessionRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 7), parsed.value.session_id);
}

test "spec: session -- DetachSessionResponse with error JSON round-trip" {
    const original = session.DetachSessionResponse{
        .status = 1,
        .reason = "server_shutdown",
        .@"error" = "session destroyed",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session.DetachSessionResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("server_shutdown", parsed.value.reason);
    try std.testing.expectEqualStrings("session destroyed", parsed.value.@"error".?);
}

test "spec: session -- AttachOrCreateRequest with cwd and shell" {
    const original = session.AttachOrCreateRequest{
        .session_name = "my-session",
        .shell = "/bin/zsh",
        .cwd = "/home/user",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session.AttachOrCreateRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("/bin/zsh", parsed.value.shell);
    try std.testing.expectEqualStrings("/home/user", parsed.value.cwd);
}

test "spec: session -- ListSessionsRequest empty struct JSON round-trip" {
    const original = session.ListSessionsRequest{};
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(session.ListSessionsRequest, allocator, j);
    defer parsed.deinit();
    // ListSessionsRequest is an empty struct -- verify parse succeeds
    try std.testing.expect(j.len > 0);
}

// ── input.zig gaps ──────────────────────────────────────────────────────────

test "spec: input -- TextInput JSON round-trip" {
    const original = input.TextInput{ .pane_id = 1, .text = "hello world" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(input.TextInput, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("hello world", parsed.value.text);
}

test "spec: input -- MouseMove JSON round-trip" {
    const original = input.MouseMove{ .pane_id = 1, .modifiers = 0, .buttons_held = 1, .x = 10.5, .y = 20.3 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(input.MouseMove, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u8, 1), parsed.value.buttons_held);
}

test "spec: input -- MouseScroll JSON round-trip" {
    const original = input.MouseScroll{ .pane_id = 1, .modifiers = 0, .dy = -3.0, .precise = true };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(input.MouseScroll, allocator, j);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.precise);
}

test "spec: input -- FocusEvent JSON round-trip" {
    const original = input.FocusEvent{ .pane_id = 2, .focused = true };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(input.FocusEvent, allocator, j);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.focused);
}

test "spec: input -- ScrollRequest JSON round-trip" {
    const original = input.ScrollRequest{ .pane_id = 1, .direction = 2, .lines = 100 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(input.ScrollRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u8, 2), parsed.value.direction);
    try std.testing.expectEqual(@as(u32, 100), parsed.value.lines);
}

test "spec: input -- ScrollPosition JSON round-trip" {
    const original = input.ScrollPosition{ .pane_id = 1, .viewport_top = 50, .total_lines = 500, .viewport_rows = 24 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(input.ScrollPosition, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 50), parsed.value.viewport_top);
}

test "spec: input -- SearchResult JSON round-trip" {
    const original = input.SearchResult{
        .pane_id = 1,
        .total_matches = 5,
        .current_match = 2,
        .match_row = 10,
        .match_start_col = 5,
        .match_end_col = 8,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(input.SearchResult, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 5), parsed.value.total_matches);
    try std.testing.expectEqual(@as(u16, 5), parsed.value.match_start_col);
}

test "spec: input -- SearchCancel JSON round-trip" {
    const original = input.SearchCancel{ .pane_id = 1 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(input.SearchCancel, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.pane_id);
}

test "spec: input -- KeyEvent with pane_id present JSON round-trip" {
    const original = input.KeyEvent{ .keycode = 0x41, .action = 0, .modifiers = 0, .pane_id = 5 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(input.KeyEvent, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?u32, 5), parsed.value.pane_id);
}

test "spec: input -- Action constants" {
    try std.testing.expectEqual(@as(u8, 0), input.Action.press);
    try std.testing.expectEqual(@as(u8, 1), input.Action.release);
    try std.testing.expectEqual(@as(u8, 2), input.Action.repeat);
}

// ── handshake.zig gaps ──────────────────────────────────────────────────────

test "spec: handshake -- ClientHello with input method preferences" {
    const prefs = [_]handshake.ClientHello.InputMethodPref{
        .{ .method = "korean_2set", .layout = "qwerty" },
        .{ .method = "direct" },
    };
    const original = handshake.ClientHello{
        .preferred_input_methods = &prefs,
        .client_name = "test",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(handshake.ClientHello, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.preferred_input_methods.len);
    try std.testing.expectEqualStrings("korean_2set", parsed.value.preferred_input_methods[0].method);
}

test "spec: handshake -- ClientHello client_type headless" {
    const original = handshake.ClientHello{ .client_type = .headless };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(handshake.ClientHello, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(handshake.ClientHello.ClientType.headless, parsed.value.client_type);
}

test "spec: handshake -- ClientHello client_type control" {
    const original = handshake.ClientHello{ .client_type = .control };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(handshake.ClientHello, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(handshake.ClientHello.ClientType.control, parsed.value.client_type);
}

test "spec: handshake -- ServerHello with sessions and input methods" {
    const sessions = [_]handshake.ServerHello.SessionSummary{
        .{ .session_id = 1, .name = "main", .attached_clients = 2 },
    };
    const ims = [_]handshake.ServerHello.InputMethodInfo{
        .{ .method = "direct" },
        .{ .method = "korean_2set" },
    };
    const original = handshake.ServerHello{
        .client_id = 1,
        .server_pid = 100,
        .sessions = &sessions,
        .supported_input_methods = &ims,
        .max_panes_per_session = 16,
        .max_sessions = 8,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(handshake.ServerHello, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.value.sessions.len);
    try std.testing.expectEqualStrings("main", parsed.value.sessions[0].name);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.supported_input_methods.len);
    try std.testing.expectEqual(@as(u16, 16), parsed.value.max_panes_per_session);
}

test "spec: handshake -- Disconnect with empty reason" {
    const original = handshake.Disconnect{};
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(handshake.Disconnect, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("", parsed.value.reason);
    try std.testing.expectEqualStrings("", parsed.value.detail);
}

// ── cell.zig gaps ───────────────────────────────────────────────────────────

test "spec: cell -- PackedColor non-default is not isDefault" {
    const p = cell.PackedColor.palette(0);
    try std.testing.expect(!p.isDefault());
    const r = cell.PackedColor.rgb(0, 0, 0);
    try std.testing.expect(!r.isDefault());
}

test "spec: cell -- RowHeader no-selection flags" {
    const rh = cell.RowHeader{
        .y = 5,
        .row_flags = 0,
        .selection_start = 0,
        .selection_end = 0,
        .num_cells = 80,
    };
    try std.testing.expect(!rh.hasSelection());
    try std.testing.expect(!rh.isRleEncoded());
    try std.testing.expectEqual(@as(u2, 0), rh.semanticPrompt());
    try std.testing.expect(!rh.hasHyperlink());
}

test "spec: cell -- CellData content_tag grapheme variant" {
    const c = cell.CellData{
        .codepoint = 0xAC00,
        .wide = cell.CellData.Wide.wide,
        .flags = 0,
        .content_tag = cell.CellData.ContentTag.codepoint_grapheme,
        .fg_color = cell.PackedColor.default_color,
        .bg_color = cell.PackedColor.default_color,
    };
    var buf: [16]u8 = undefined;
    cell.encodeCellData(c, &buf);
    const decoded = cell.decodeCellData(&buf);
    try std.testing.expectEqual(cell.CellData.ContentTag.codepoint_grapheme, decoded.content_tag);
}

test "spec: cell -- CellData bg_color_palette content_tag" {
    const c = cell.CellData{
        .codepoint = 0x20,
        .wide = 0,
        .flags = 0,
        .content_tag = cell.CellData.ContentTag.bg_color_palette,
        .fg_color = cell.PackedColor.default_color,
        .bg_color = cell.PackedColor.palette(200),
    };
    var buf: [16]u8 = undefined;
    cell.encodeCellData(c, &buf);
    const decoded = cell.decodeCellData(&buf);
    try std.testing.expectEqual(cell.CellData.ContentTag.bg_color_palette, decoded.content_tag);
    try std.testing.expectEqual(@as(u8, 200), decoded.bg_color.data[0]);
}

test "spec: cell -- CellData bg_color_rgb content_tag" {
    const c = cell.CellData{
        .codepoint = 0x20,
        .wide = 0,
        .flags = 0,
        .content_tag = cell.CellData.ContentTag.bg_color_rgb,
        .fg_color = cell.PackedColor.default_color,
        .bg_color = cell.PackedColor.rgb(10, 20, 30),
    };
    var buf: [16]u8 = undefined;
    cell.encodeCellData(c, &buf);
    const decoded = cell.decodeCellData(&buf);
    try std.testing.expectEqual(cell.CellData.ContentTag.bg_color_rgb, decoded.content_tag);
}

test "spec: cell -- CellData spacer_head variant" {
    const c = cell.CellData{
        .codepoint = 0,
        .wide = cell.CellData.Wide.spacer_head,
        .flags = 0,
        .content_tag = 0,
        .fg_color = cell.PackedColor.default_color,
        .bg_color = cell.PackedColor.default_color,
    };
    var buf: [16]u8 = undefined;
    cell.encodeCellData(c, &buf);
    const decoded = cell.decodeCellData(&buf);
    try std.testing.expectEqual(cell.CellData.Wide.spacer_head, decoded.wide);
}

test "spec: cell -- encodeUnderlineColorTable 0 entries" {
    var buf: [2]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try cell.encodeUnderlineColorTable(&.{}, fbs.writer());
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, buf[0..2], .little));
}

// ── pane.zig gaps ───────────────────────────────────────────────────────────

test "spec: pane -- CreatePaneRequest JSON round-trip" {
    const original = pane.CreatePaneRequest{ .session_id = 1, .shell = "/bin/bash" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.CreatePaneRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("/bin/bash", parsed.value.shell.?);
}

test "spec: pane -- CreatePaneResponse JSON round-trip" {
    const original = pane.CreatePaneResponse{ .status = 0, .pane_id = 5 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.CreatePaneResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 5), parsed.value.pane_id);
}

test "spec: pane -- FocusPaneRequest JSON round-trip" {
    const original = pane.FocusPaneRequest{ .session_id = 1, .pane_id = 3 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.FocusPaneRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 3), parsed.value.pane_id);
}

test "spec: pane -- FocusPaneResponse JSON round-trip" {
    const original = pane.FocusPaneResponse{ .status = 0, .previous_pane_id = 2 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.FocusPaneResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 2), parsed.value.previous_pane_id);
}

test "spec: pane -- NavigatePaneRequest JSON round-trip" {
    const original = pane.NavigatePaneRequest{ .session_id = 1, .direction = 2 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.NavigatePaneRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u8, 2), parsed.value.direction);
}

test "spec: pane -- NavigatePaneResponse JSON round-trip" {
    const original = pane.NavigatePaneResponse{ .status = 0, .focused_pane_id = 4 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.NavigatePaneResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 4), parsed.value.focused_pane_id);
}

test "spec: pane -- ResizePaneRequest JSON round-trip" {
    const original = pane.ResizePaneRequest{ .session_id = 1, .pane_id = 1, .direction = 1, .delta = -5 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.ResizePaneRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i16, -5), parsed.value.delta);
}

test "spec: pane -- ResizePaneResponse with error JSON round-trip" {
    const original = pane.ResizePaneResponse{ .status = 1, .@"error" = "min size" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.ResizePaneResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("min size", parsed.value.@"error".?);
}

test "spec: pane -- EqualizeSplitsRequest JSON round-trip" {
    const original = pane.EqualizeSplitsRequest{ .session_id = 3 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.EqualizeSplitsRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 3), parsed.value.session_id);
}

test "spec: pane -- EqualizeSplitsResponse JSON round-trip" {
    const original = pane.EqualizeSplitsResponse{ .status = 0 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.EqualizeSplitsResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 0), parsed.value.status);
}

test "spec: pane -- SwapPanesRequest JSON round-trip" {
    const original = pane.SwapPanesRequest{ .session_id = 1, .pane_a = 2, .pane_b = 3 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.SwapPanesRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 2), parsed.value.pane_a);
    try std.testing.expectEqual(@as(u32, 3), parsed.value.pane_b);
}

test "spec: pane -- SwapPanesResponse JSON round-trip" {
    const original = pane.SwapPanesResponse{ .status = 0 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.SwapPanesResponse, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 0), parsed.value.status);
}

test "spec: pane -- LayoutGetRequest JSON round-trip" {
    const original = pane.LayoutGetRequest{ .session_id = 1 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.LayoutGetRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.session_id);
}

test "spec: pane -- PaneMetadataChanged JSON round-trip" {
    const original = pane.PaneMetadataChanged{
        .session_id = 1,
        .pane_id = 2,
        .title = "vim",
        .exit_status = 0,
        .is_running = true,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.PaneMetadataChanged, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("vim", parsed.value.title.?);
    try std.testing.expectEqual(@as(?i32, 0), parsed.value.exit_status);
    try std.testing.expect(parsed.value.is_running.?);
}

test "spec: pane -- ClientAttached JSON round-trip" {
    const original = pane.ClientAttached{
        .session_id = 1,
        .client_id = 3,
        .client_name = "test-client",
        .attached_clients = 2,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.ClientAttached, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("test-client", parsed.value.client_name);
}

test "spec: pane -- ClientDetached JSON round-trip" {
    const original = pane.ClientDetached{
        .session_id = 1,
        .client_id = 3,
        .reason = "server_shutdown",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.ClientDetached, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("server_shutdown", parsed.value.reason);
}

test "spec: pane -- WindowResize with pixel fields JSON round-trip" {
    const original = pane.WindowResize{
        .session_id = 1,
        .cols = 120,
        .rows = 40,
        .pixel_width = 1920,
        .pixel_height = 1080,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.WindowResize, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?u16, 1920), parsed.value.pixel_width);
    try std.testing.expectEqual(@as(?u16, 1080), parsed.value.pixel_height);
}

test "spec: pane -- WindowResizeAck JSON round-trip" {
    const original = pane.WindowResizeAck{ .session_id = 1, .cols = 120, .rows = 40 };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.WindowResizeAck, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u16, 120), parsed.value.cols);
}

test "spec: pane -- ClosePaneRequest with force JSON round-trip" {
    const original = pane.ClosePaneRequest{ .session_id = 1, .pane_id = 5, .force = true };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(pane.ClosePaneRequest, allocator, j);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.force);
}

// ── preedit.zig gaps ────────────────────────────────────────────────────────

test "spec: preedit -- PreeditUpdate JSON round-trip" {
    const original = preedit.PreeditUpdate{ .pane_id = 1, .preedit_session_id = 5, .text = "\xed\x95\x9c\xea\xb8\x80" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(preedit.PreeditUpdate, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("\xed\x95\x9c\xea\xb8\x80", parsed.value.text);
}

test "spec: preedit -- PreeditSync JSON round-trip" {
    const original = preedit.PreeditSync{
        .pane_id = 1,
        .preedit_session_id = 42,
        .preedit_owner = 7,
        .active_input_method = "korean_2set",
        .text = "\xed\x95\x9c",
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(preedit.PreeditSync, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 7), parsed.value.preedit_owner);
    try std.testing.expectEqualStrings("\xed\x95\x9c", parsed.value.text);
}

test "spec: preedit -- InputMethodSwitch with keyboard_layout JSON round-trip" {
    const original = preedit.InputMethodSwitch{
        .pane_id = 1,
        .input_method = "korean_2set",
        .keyboard_layout = "dvorak",
        .commit_current = false,
    };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(preedit.InputMethodSwitch, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("dvorak", parsed.value.keyboard_layout.?);
    try std.testing.expect(!parsed.value.commit_current);
}

test "spec: preedit -- AmbiguousWidthConfig JSON round-trip" {
    const original = preedit.AmbiguousWidthConfig{ .pane_id = 1, .ambiguous_width = 2, .scope = "global" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(preedit.AmbiguousWidthConfig, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u8, 2), parsed.value.ambiguous_width);
    try std.testing.expectEqualStrings("global", parsed.value.scope);
}

test "spec: preedit -- IMEError JSON round-trip" {
    const original = preedit.IMEError{ .pane_id = 1, .error_code = 42, .detail = "unknown method" };
    const j = try json_mod.encode(allocator, original);
    defer allocator.free(j);
    const parsed = try json_mod.decode(preedit.IMEError, allocator, j);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 42), parsed.value.error_code);
    try std.testing.expectEqualStrings("unknown method", parsed.value.detail);
}

// ── testing/helpers.zig gaps ────────────────────────────────────────────────

test "spec: helpers -- decode with invalid JSON returns error" {
    const result = json_mod.decode(input.KeyEvent, allocator, "not json");
    try std.testing.expectError(error.SyntaxError, result);
}

test "spec: helpers -- decode with missing required field returns error" {
    // KeyEvent requires keycode, action, modifiers -- omitting keycode.
    // This should fail with a parse error.
    if (json_mod.decode(input.KeyEvent, allocator, "{\"action\":0,\"modifiers\":0}")) |parsed| {
        parsed.deinit();
        return error.TestUnexpectedResult;
    } else |_| {
        // Expected: parse error due to missing required field
    }
}
