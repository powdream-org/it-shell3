const std = @import("std");
const interfaces = @import("../../os/interfaces.zig");
const pane_mod = @import("../../core/pane.zig");
const client_mod = @import("../client.zig");
const types = @import("../../core/types.zig");
const terminal_mod = @import("../../ghostty/terminal.zig");

/// Handle PTY read event: drain all available PTY output, feed to ghostty
/// terminal, and mark EOF when done. Reads in a loop until EAGAIN/0 to
/// avoid requiring one event-loop round-trip per read.
pub fn handlePtyRead(
    pty_ops: *const interfaces.PtyOps,
    pane: *pane_mod.Pane,
    _: []?client_mod.ClientState,
    _: types.SessionId,
) void {
    var buf: [4096]u8 = undefined;

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

        // Feed PTY output through the persistent VT stream.
        // The stream holds parser state for split escape sequences.
        if (pane.vt_stream) |stream_ptr| {
            // SAFETY: vt_stream is always *ReadonlyStream, set by server/
            // during pane creation via terminal_mod.createVtStream().
            const stream: *terminal_mod.ReadonlyStream = @ptrCast(@alignCast(stream_ptr));
            terminal_mod.feedStream(stream, buf[0..n]);
        }

        // Partial read means no more data available right now
        if (n < buf.len) break;
    }
}

// --- Tests ---

const testing = std.testing;
const mock_os = @import("../../testing/mock_os.zig");

test "handlePtyRead: reads data from PTY (discard for now)" {
    var mock_pty = mock_os.MockPtyOps{
        .read_data = "hello world",
    };
    const pty_ops = mock_pty.ops();

    var pane = pane_mod.Pane.init(1, 0, 10, 1234, 80, 24);
    var clients = [_]?client_mod.ClientState{null} ** 4;

    handlePtyRead(&pty_ops, &pane, &clients, 1);

    // Pane should NOT be marked EOF (data was available)
    try testing.expect(!pane.pty_eof);
}

test "handlePtyRead: EOF marks pane pty_eof" {
    var mock_pty = mock_os.MockPtyOps{
        .read_data = null, // returns 0 bytes
    };
    const pty_ops = mock_pty.ops();

    var pane = pane_mod.Pane.init(1, 0, 10, 1234, 80, 24);
    var clients = [_]?client_mod.ClientState{null} ** 4;

    handlePtyRead(&pty_ops, &pane, &clients, 1);

    try testing.expect(pane.pty_eof);
}

test "handlePtyRead: isFullyDead when both flags set" {
    var mock_pty = mock_os.MockPtyOps{
        .read_data = null,
    };
    const pty_ops = mock_pty.ops();

    var pane = pane_mod.Pane.init(1, 0, 10, 1234, 80, 24);
    pane.markExited(0); // SIGCHLD already handled
    var clients = [_]?client_mod.ClientState{null} ** 4;

    handlePtyRead(&pty_ops, &pane, &clients, 1);

    try testing.expect(pane.pty_eof);
    try testing.expect(pane.isFullyDead());
}
