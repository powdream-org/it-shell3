const std = @import("std");
const interfaces = @import("../os/interfaces.zig");
const event_loop_mod = @import("event_loop.zig");
const protocol = @import("itshell3_protocol");
const Listener = protocol.transport.Listener;
const UnixTransport = protocol.transport.UnixTransport;

const Handler = event_loop_mod.Handler;

/// Callback type for adding a newly accepted client transport.
/// The caller provides this callback when building the chain (Plan 6 will
/// provide a ClientManager-backed implementation).
pub const AddClientFn = *const fn (ut: UnixTransport) error{MaxClientsReached}!void;

/// Context for the client accept chain handler.
pub const ClientAcceptContext = struct {
    listener: *Listener,
    add_client_fn: AddClientFn,
};

/// Chain handler entry point for client accept events.
/// Matches on event.target == .listener. If the event is not for the listener,
/// forwards to the next handler in the chain.
pub fn chainHandle(context: *anyopaque, event: interfaces.Event, next: ?*const Handler) void {
    if (event.target) |target| {
        switch (target) {
            .listener => {
                const ctx: *ClientAcceptContext = @ptrCast(@alignCast(context));
                handleClientAccept(ctx);
                return;
            },
            else => {},
        }
    }
    if (next) |n| n.invoke(event);
}

/// Accept a new client connection from the listener and pass it to the
/// add_client callback.
fn handleClientAccept(ctx: *ClientAcceptContext) void {
    const ut = ctx.listener.accept() catch {
        // Accept failed — log and continue (non-fatal).
        return;
    };

    // TODO(Plan 6): Verify client UID via getpeereid (macOS) or SO_PEERCRED
    // (Linux) per daemon-architecture integration-boundaries spec. Reject
    // connections from mismatched UIDs.

    // TODO(Plan 6): Configure SO_SNDBUF and SO_RCVBUF on the accepted socket
    // per daemon-architecture integration-boundaries spec.

    ctx.add_client_fn(ut) catch {
        // Max clients reached — close the transport we just accepted.
        std.posix.close(ut.socket_fd);
        return;
    };
}

// --- Tests ---

const testing = std.testing;

test "chainHandle: non-listener event forwards to next handler" {
    var forwarded = false;
    const NextCtx = struct {
        flag: *bool,
        fn handle(context_ptr: *anyopaque, _: interfaces.Event, _: ?*const Handler) void {
            const self: *@This() = @ptrCast(@alignCast(context_ptr));
            self.flag.* = true;
        }
    };

    var next_ctx = NextCtx{ .flag = &forwarded };
    const next = Handler{
        .handleFn = NextCtx.handle,
        .context = @ptrCast(&next_ctx),
        .next = null,
    };

    // We do not need a valid ClientAcceptContext since the event is not .listener
    var dummy_ctx: u8 = 0;

    const pty_event = interfaces.Event{
        .fd = 42,
        .filter = .read,
        .target = .{ .pty = .{ .session_idx = 0, .pane_slot = 0 } },
    };

    chainHandle(@ptrCast(&dummy_ctx), pty_event, &next);
    try testing.expect(forwarded);
}
