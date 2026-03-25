const std = @import("std");
const interfaces = @import("../../os/interfaces.zig");
const pane_mod = @import("../../core/pane.zig");
const client_mod = @import("../client.zig");
const types = @import("../../core/types.zig");

/// Handle PTY read event: read output from PTY and mark EOF when done.
/// For now this is a raw passthrough stub — Plan 2 replaces with RenderState.
pub fn handlePtyRead(
    pty_ops: *const interfaces.PtyOps,
    pane: *pane_mod.Pane,
    _: []?client_mod.ClientState,
    _: types.SessionId,
) void {
    var buf: [4096]u8 = undefined;
    const n = pty_ops.read(pane.pty_fd, &buf) catch {
        // Read error — treat as EOF
        pane.markPtyEof();
        return;
    };
    if (n == 0) {
        pane.markPtyEof();
        return;
    }
    // Data read successfully. For now: discard (no client write yet — needs protocol).
    // Plan 2 will feed this into the ghostty VT parser and produce RenderState.
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
