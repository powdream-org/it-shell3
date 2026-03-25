const std = @import("std");
const event_loop_mod = @import("../event_loop.zig");

/// Handle a new client connection: accept from listener and add to event loop.
pub fn handleClientAccept(
    ev: *event_loop_mod.EventLoop,
) void {
    const ut = ev.listener.accept() catch {
        // Accept failed — log and continue (non-fatal)
        return;
    };
    ev.addClientTransport(ut) catch {
        // Max clients reached — close the transport we just accepted
        std.posix.close(ut.socket_fd);
        return;
    };
}

// --- Tests ---
// Note: client_accept tests require real sockets (protocol Listener uses
// real bind/accept). Covered by integration tests in helpers.zig.
