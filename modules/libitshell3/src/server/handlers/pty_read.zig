const std = @import("std");
const os = @import("itshell3_os");
const interfaces = os.interfaces;
const core = @import("itshell3_core");
const pane_mod = core.pane;
const session_mod = core.session;
const types = core.types;
const event_loop_mod = @import("../event_loop.zig");
const terminal_mod = @import("itshell3_ghostty").terminal;

/// Handle PTY read event: drain all available PTY output, feed to ghostty
/// terminal, mark pane dirty after reading, and mark EOF when done.
/// Reads in a loop until EAGAIN/0 to avoid requiring one event-loop round-trip
/// per read.
pub fn handlePtyRead(
    pty_ops: *const interfaces.PtyOps,
    pane: *pane_mod.Pane,
    session_entry: *session_mod.SessionEntry,
    _: []?event_loop_mod.ClientEntry,
    _: types.SessionId,
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
        if (pane.vt_stream) |stream_ptr| {
            // SAFETY: vt_stream is always *ReadonlyStream, set by server/
            // during pane creation via terminal_mod.createVtStream().
            const stream: *terminal_mod.ReadonlyStream = @ptrCast(@alignCast(stream_ptr));
            terminal_mod.feedStream(stream, buf[0..n]) catch {};
        }

        // Partial read means no more data available right now
        if (n < buf.len) break;
    }

    if (did_read) {
        session_entry.markDirty(pane.slot_index);
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

    const s = session_mod.Session.init(1, "test", 0, testImeEngine());
    var entry = session_mod.SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    var pane = pane_mod.Pane.init(1, slot, 10, 1234, 80, 24);
    entry.setPaneAtSlot(slot, pane_mod.Pane.init(1, slot, 10, 1234, 80, 24));
    var clients = [_]?event_loop_mod.ClientEntry{null} ** 4;

    try testing.expect(!entry.isDirty(slot));
    handlePtyRead(&pty_ops, &pane, &entry, &clients, 1);
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

    const s = session_mod.Session.init(1, "test", 0, testImeEngine());
    var entry = session_mod.SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    var pane = pane_mod.Pane.init(1, slot, 10, 1234, 80, 24);
    entry.setPaneAtSlot(slot, pane_mod.Pane.init(1, slot, 10, 1234, 80, 24));
    var clients = [_]?event_loop_mod.ClientEntry{null} ** 4;

    handlePtyRead(&pty_ops, &pane, &entry, &clients, 1);

    try testing.expect(pane.pty_eof);
    // No dirty mark on EOF (no data was actually processed)
    try testing.expect(!entry.isDirty(slot));
}

test "handlePtyRead: isFullyDead when both flags set" {
    var mock_pty = mock_os.MockPtyOps{
        .read_data = null,
    };
    const pty_ops = mock_pty.ops();

    const s = session_mod.Session.init(1, "test", 0, testImeEngine());
    var entry = session_mod.SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    var pane = pane_mod.Pane.init(1, slot, 10, 1234, 80, 24);
    entry.setPaneAtSlot(slot, pane_mod.Pane.init(1, slot, 10, 1234, 80, 24));
    pane.markExited(0); // SIGCHLD already handled
    var clients = [_]?event_loop_mod.ClientEntry{null} ** 4;

    handlePtyRead(&pty_ops, &pane, &entry, &clients, 1);

    try testing.expect(pane.pty_eof);
    try testing.expect(pane.isFullyDead());
}

test "handlePtyRead: marks pane dirty after reading data" {
    var mock_pty = mock_os.MockPtyOps{ .read_data = "terminal output" };
    const pty_ops = mock_pty.ops();

    const s = session_mod.Session.init(1, "test", 0, testImeEngine());
    var entry = session_mod.SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, pane_mod.Pane.init(1, slot, 10, 1234, 80, 24));
    var clients = [_]?event_loop_mod.ClientEntry{null} ** 4;

    try testing.expect(!entry.isDirty(slot));
    handlePtyRead(&pty_ops, entry.getPaneAtSlot(slot).?, &entry, &clients, 1);
    try testing.expect(entry.isDirty(slot));
}

test "handlePtyRead: does not mark dirty on EOF" {
    var mock_pty = mock_os.MockPtyOps{ .read_data = null };
    const pty_ops = mock_pty.ops();

    const s = session_mod.Session.init(1, "test", 0, testImeEngine());
    var entry = session_mod.SessionEntry.init(s);
    const slot = try entry.allocPaneSlot();
    entry.setPaneAtSlot(slot, pane_mod.Pane.init(1, slot, 10, 1234, 80, 24));
    var clients = [_]?event_loop_mod.ClientEntry{null} ** 4;

    handlePtyRead(&pty_ops, entry.getPaneAtSlot(slot).?, &entry, &clients, 1);
    try testing.expect(!entry.isDirty(slot));
}
