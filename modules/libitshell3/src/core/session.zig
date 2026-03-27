const std = @import("std");
const types = @import("types.zig");
const split_tree = @import("split_tree.zig");
const preedit_state = @import("preedit_state.zig");
const ime_engine_mod = @import("ime_engine.zig");

pub const SessionId = types.SessionId;
pub const PaneSlot = types.PaneSlot;
pub const MAX_PANES = types.MAX_PANES;
pub const MAX_TREE_NODES = types.MAX_TREE_NODES;
pub const SplitNodeData = split_tree.SplitNodeData;
pub const PreeditState = preedit_state.PreeditState;
pub const ImeEngine = ime_engine_mod.ImeEngine;

pub const Session = struct {
    session_id: SessionId,
    name: [types.MAX_SESSION_NAME]u8,
    name_length: u8,
    active_input_method: [types.MAX_INPUT_METHOD_NAME]u8,
    active_input_method_length: u8,
    active_keyboard_layout: [types.MAX_KEYBOARD_LAYOUT_NAME]u8,
    active_keyboard_layout_length: u8,
    tree_nodes: [MAX_TREE_NODES]?SplitNodeData,
    focused_pane: ?PaneSlot,
    creation_timestamp: i64,
    ime_engine: ImeEngine,
    current_preedit: ?[]const u8,
    preedit_buf: [types.MAX_PREEDIT_BUF]u8,
    last_preedit_row: ?u16,
    preedit: PreeditState,

    pub fn init(
        session_id: SessionId,
        name: []const u8,
        initial_pane_slot: PaneSlot,
        ime_eng: ImeEngine,
    ) Session {
        // Copy name (truncate to MAX_SESSION_NAME).
        const name_length: u8 = @intCast(@min(name.len, types.MAX_SESSION_NAME));
        var name_buf: [types.MAX_SESSION_NAME]u8 = @splat(0);
        @memcpy(name_buf[0..name_length], name[0..name_length]);

        // Default input method: "direct".
        const default_input_method = "direct";
        var input_method_buf: [types.MAX_INPUT_METHOD_NAME]u8 = @splat(0);
        @memcpy(input_method_buf[0..default_input_method.len], default_input_method);

        // Default keyboard layout: "qwerty" (per spec).
        const default_keyboard_layout = "qwerty";
        var keyboard_layout_buf: [types.MAX_KEYBOARD_LAYOUT_NAME]u8 = @splat(0);
        @memcpy(keyboard_layout_buf[0..default_keyboard_layout.len], default_keyboard_layout);

        return Session{
            .session_id = session_id,
            .name = name_buf,
            .name_length = name_length,
            .active_input_method = input_method_buf,
            .active_input_method_length = default_input_method.len,
            .active_keyboard_layout = keyboard_layout_buf,
            .active_keyboard_layout_length = default_keyboard_layout.len,
            .tree_nodes = split_tree.initSingleLeaf(initial_pane_slot),
            .focused_pane = initial_pane_slot,
            // TODO(Plan 7): Caller must pass real timestamp (e.g., std.time.milliTimestamp()).
            // Session.init() is in core/ which has no OS dependency, so the server layer
            // must provide the value when creating sessions from CreateSessionRequest.
            .creation_timestamp = 0,
            .ime_engine = ime_eng,
            .current_preedit = null,
            .preedit_buf = @splat(0),
            .last_preedit_row = null,
            .preedit = PreeditState.init(),
        };
    }

    pub fn getName(self: *const Session) []const u8 {
        return self.name[0..self.name_length];
    }

    pub fn getActiveInputMethod(self: *const Session) []const u8 {
        return self.active_input_method[0..self.active_input_method_length];
    }

    pub fn getActiveKeyboardLayout(self: *const Session) []const u8 {
        return self.active_keyboard_layout[0..self.active_keyboard_layout_length];
    }

    /// Copy preedit text into session.preedit_buf and update current_preedit slice.
    /// If text is null, clears current_preedit.
    pub fn setPreedit(self: *Session, text: ?[]const u8) void {
        if (text) |t| {
            const len = @min(t.len, self.preedit_buf.len);
            @memcpy(self.preedit_buf[0..len], t[0..len]);
            self.current_preedit = self.preedit_buf[0..len];
        } else {
            self.current_preedit = null;
        }
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

const mock_ime = @import("itshell3_testing").mock_ime_engine;

// File-scope static mock engine. Persists across tests so the vtable pointer
// stored in sessions remains valid.
var test_mock_engine = mock_ime.MockImeEngine{};

fn testImeEngine() ImeEngine {
    return test_mock_engine.engine();
}

test "Session.init: sets correct defaults" {
    const s = Session.init(1, "myterm", 0, testImeEngine());
    try std.testing.expectEqual(@as(SessionId, 1), s.session_id);
    try std.testing.expectEqualSlices(u8, "myterm", s.getName());
    try std.testing.expectEqualSlices(u8, "direct", s.getActiveInputMethod());
    try std.testing.expectEqualSlices(u8, "qwerty", s.getActiveKeyboardLayout());
    try std.testing.expectEqual(@as(?PaneSlot, 0), s.focused_pane);
    try std.testing.expect(s.current_preedit == null);
    try std.testing.expect(s.last_preedit_row == null);
    try std.testing.expectEqual(@as(i64, 0), s.creation_timestamp);
}

test "Session.init: with initial_pane_slot sets focused_pane" {
    const s = Session.init(2, "test", 5, testImeEngine());
    try std.testing.expectEqual(@as(?PaneSlot, 5), s.focused_pane);
}

test "Session.getName: returns the name" {
    const s = Session.init(1, "hello", 0, testImeEngine());
    try std.testing.expectEqualSlices(u8, "hello", s.getName());
}

test "Session.init: truncates name longer than 64 bytes" {
    const long_name = "a" ** 100;
    const s = Session.init(1, long_name, 0, testImeEngine());
    try std.testing.expectEqual(@as(u8, 64), s.name_length);
    try std.testing.expectEqualSlices(u8, long_name[0..64], s.getName());
}

test "Session.preedit: initialized to null owner and session_id 0" {
    const s = Session.init(1, "s", 0, testImeEngine());
    try std.testing.expectEqual(@as(?types.ClientId, null), s.preedit.owner);
    try std.testing.expectEqual(@as(u32, 0), s.preedit.session_id);
}

test "Session.setPreedit: sets and clears preedit" {
    var s = Session.init(1, "s", 0, testImeEngine());

    // Set preedit.
    s.setPreedit("hello");
    try std.testing.expect(s.current_preedit != null);
    try std.testing.expectEqualSlices(u8, "hello", s.current_preedit.?);

    // Clear preedit.
    s.setPreedit(null);
    try std.testing.expect(s.current_preedit == null);
}

test "Session.setPreedit: truncates to MAX_PREEDIT_BUF" {
    var s = Session.init(1, "s", 0, testImeEngine());
    const long_text = "x" ** 100;
    s.setPreedit(long_text);
    try std.testing.expect(s.current_preedit != null);
    try std.testing.expectEqual(@as(usize, types.MAX_PREEDIT_BUF), s.current_preedit.?.len);
}

test "Session.init: tree_nodes uses optional SplitNodeData" {
    const s = Session.init(1, "s", 0, testImeEngine());
    // Root should be a leaf.
    try std.testing.expect(s.tree_nodes[0] != null);
    try std.testing.expect(s.tree_nodes[0].? == .leaf);
    // Other nodes should be null.
    try std.testing.expect(s.tree_nodes[1] == null);
}
