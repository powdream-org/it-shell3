//! PTY read chain handler. Drains available PTY output, feeds it through the
//! persistent ghostty VT stream, and marks the pane dirty for frame export.

const std = @import("std");
const interfaces = @import("../os/interfaces.zig");
const event_loop_mod = @import("event_loop.zig");
const core = @import("itshell3_core");
const session_mod = core.session;
const types = core.types;
const pane_mod = @import("../state/pane.zig");
const session_entry_mod = @import("../state/session_entry.zig");
const session_manager_mod = @import("../state/session_manager.zig");
const terminal_mod = @import("itshell3_ghostty").terminal;

const Handler = event_loop_mod.Handler;

/// Context for the PTY read chain handler.
pub const PtyReadContext = struct {
    pty_ops: *const interfaces.PtyOps,
    session_manager: *session_manager_mod.SessionManager,
};

/// Chain handler entry point for PTY read events.
/// Matches on event.target == .pty and extracts session_idx and pane_slot
/// directly (no range arithmetic).
pub fn chainHandle(context: *anyopaque, event: interfaces.Event, next: ?*const Handler) void {
    if (event.target) |target| {
        switch (target) {
            .pty => |pty| {
                const ctx: *PtyReadContext = @ptrCast(@alignCast(context));
                if (ctx.session_manager.findSessionBySlot(pty.session_idx)) |entry| {
                    if (entry.getPaneAtSlot(pty.pane_slot)) |pane| {
                        handlePtyRead(
                            ctx.pty_ops,
                            pane,
                            entry,
                        );
                    }
                }
                return;
            },
            else => {},
        }
    }
    if (next) |n| n.invoke(event);
}

/// Drains all available PTY output in a loop, feeds through the ghostty VT
/// stream, and marks the pane dirty. Reads until EAGAIN/0 to avoid requiring
/// one event-loop round-trip per read.
pub fn handlePtyRead(
    pty_ops: *const interfaces.PtyOps,
    pane: *pane_mod.Pane,
    session_entry: *session_entry_mod.SessionEntry,
) void {
    var buf: [4096]u8 = @splat(0);
    var did_read = false;

    while (true) {
        const n = pty_ops.read(pane.pty_fd, &buf) catch {
            // Read error — treat as EOF
            pane.markPtyEof();
            return;
        };
        if (n == 0) {
            pane.markPtyEof();
            return;
        }
        did_read = true;

        // Feed PTY output through the persistent VT stream.
        // The stream holds parser state for split escape sequences.
        if (pane.vt_stream) |stream| {
            terminal_mod.feedStream(stream, buf[0..n]) catch {};
        }

        // Partial read means no more data available right now
        if (n < buf.len) break;
    }

    if (did_read) {
        session_entry.markDirty(pane.slot_index);

        // Check for metadata changes after VT stream processing.
        // Title and CWD are updated by OSC sequences processed through
        // the ghostty terminal. Compare against previous values to detect
        // changes. Actual detection requires ghostty terminal pointers
        // (non-null) which are set during pane creation.
        // TODO(Plan 8): Implement actual title/cwd extraction from
        // ghostty terminal after vtStream processing, and broadcast
        // PaneMetadataChanged notification to session-scoped peers.
    }
}

// --- Tests ---

const testing = std.testing;
const test_mod = @import("itshell3_testing");
const mock_os = test_mod.mock_os;
const test_helpers = test_mod.helpers;

const testImeEngine = test_helpers.testImeEngine;

test "handlePtyRead: reads data from PTY and marks pane dirty" {
    var mock_pty = mock_os.MockPtyOps{
        .read_data = "hello world",
    };
    const pty_ops = mock_pty.ops();

    const s = session_mod.Session.init(1, "test", 0, testImeEngine(), 0);
    var entry = session_entry_mod.SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, pane_mod.Pane.init(1, slot, 10, 1234, 80, 24));
    const pane = entry.getPaneAtSlot(slot).?;

    try testing.expect(!entry.isDirty(slot));
    handlePtyRead(&pty_ops, pane, &entry);
    // Pane should NOT be marked EOF (data was available)
    try testing.expect(!pane.pty_eof);
    // Session entry should be marked dirty
    try testing.expect(entry.isDirty(slot));
}

test "handlePtyRead: EOF marks pane pty_eof, not dirty" {
    var mock_pty = mock_os.MockPtyOps{
        .read_data = null, // returns 0 bytes
    };
    const pty_ops = mock_pty.ops();

    const s = session_mod.Session.init(1, "test", 0, testImeEngine(), 0);
    var entry = session_entry_mod.SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, pane_mod.Pane.init(1, slot, 10, 1234, 80, 24));
    const pane = entry.getPaneAtSlot(slot).?;

    handlePtyRead(&pty_ops, pane, &entry);

    try testing.expect(pane.pty_eof);
    // No dirty mark on EOF (no data was actually processed)
    try testing.expect(!entry.isDirty(slot));
}

test "handlePtyRead: isFullyDead when both flags set" {
    var mock_pty = mock_os.MockPtyOps{
        .read_data = null,
    };
    const pty_ops = mock_pty.ops();

    const s = session_mod.Session.init(1, "test", 0, testImeEngine(), 0);
    var entry = session_entry_mod.SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, pane_mod.Pane.init(1, slot, 10, 1234, 80, 24));
    const pane = entry.getPaneAtSlot(slot).?;
    pane.markExited(0); // SIGCHLD already handled

    handlePtyRead(&pty_ops, pane, &entry);

    try testing.expect(pane.pty_eof);
    try testing.expect(pane.isFullyDead());
}

test "handlePtyRead: marks pane dirty after reading data" {
    var mock_pty = mock_os.MockPtyOps{ .read_data = "terminal output" };
    const pty_ops = mock_pty.ops();

    const s = session_mod.Session.init(1, "test", 0, testImeEngine(), 0);
    var entry = session_entry_mod.SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, pane_mod.Pane.init(1, slot, 10, 1234, 80, 24));

    try testing.expect(!entry.isDirty(slot));
    handlePtyRead(&pty_ops, entry.getPaneAtSlot(slot).?, &entry);
    try testing.expect(entry.isDirty(slot));
}

test "handlePtyRead: does not mark dirty on EOF" {
    var mock_pty = mock_os.MockPtyOps{ .read_data = null };
    const pty_ops = mock_pty.ops();

    const s = session_mod.Session.init(1, "test", 0, testImeEngine(), 0);
    var entry = session_entry_mod.SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, pane_mod.Pane.init(1, slot, 10, 1234, 80, 24));

    handlePtyRead(&pty_ops, entry.getPaneAtSlot(slot).?, &entry);
    try testing.expect(!entry.isDirty(slot));
}

test "chainHandle: non-pty event forwards to next handler" {
    var forwarded = false;
    const NextCtx = struct {
        flag: *bool,
        fn handle(context: *anyopaque, _: interfaces.Event, _: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.flag.* = true;
        }
    };

    var next_ctx = NextCtx{ .flag = &forwarded };
    const next = Handler{
        .handleFn = NextCtx.handle,
        .context = @ptrCast(&next_ctx),
        .next = null,
    };

    // We do not need a valid PtyReadContext since the event is not .pty
    var dummy_ctx: u8 = 0;

    const listener_event = interfaces.Event{
        .fd = 42,
        .filter = .read,
        .target = .{ .listener = {} },
    };

    chainHandle(@ptrCast(&dummy_ctx), listener_event, &next);
    try testing.expect(forwarded);
}
