## Example 6: OS ↔ OS Conflict

### What

The daemon's event loop uses kqueue's `EVFILT_TIMER` for per-client heartbeat
timers (each connected client gets a kernel timer that fires every 30 seconds).
On Linux, epoll has no built-in timer mechanism — the equivalent requires
`timerfd_create()` file descriptors registered with `epoll_ctl()`. The timer
abstraction layer uses `u16` timer IDs that map directly to kqueue filter
identifiers, but on Linux timer IDs must map to `fd_t` values (i32) with a
completely different lifecycle. The cleanup path calls `cancelTimer(timer_id)`
which removes the kqueue filter but does not `close()` the timerfd on Linux,
leaking file descriptors on every client disconnect.

### Why

Per-client heartbeat timers are required by the protocol spec for liveness
detection. If a client misses three consecutive heartbeat responses, the daemon
disconnects it and releases session attachment state. On macOS with kqueue, this
works correctly — kernel timers are lightweight and cancel cleanly. On Linux,
each timer is a real file descriptor that counts against `RLIMIT_NOFILE`
(default 1024 on most distributions). A daemon serving a long-running session
with frequent client reconnections (SSH drops, laptop sleep/wake cycles)
accumulates leaked timerfd descriptors until it hits the fd limit and can no
longer accept new client connections or open PTYs.

### Who

The event loop abstraction (`modules/libitshell3/src/server/event_loop.zig`) on
macOS vs. the same abstraction compiled for Linux. Both are the same source file
with `comptime` platform branching.

### When

Introduced during Plan 3 implementation. The event loop was developed and tested
exclusively on macOS. Linux support was added later via `comptime` branches for
`epoll_ctl`/`epoll_wait`, but the timer subsystem was ported mechanically
without accounting for timerfd lifecycle semantics.

### Where

**kqueue timer registration** — clean, single kevent64 call
(`modules/libitshell3/src/server/event_loop.zig`, lines 156-168):

```zig
fn registerHeartbeatTimer(self: *EventLoop, client_id: ClientId) !TimerId {
    const timer_id: u16 = self.next_timer_id;
    self.next_timer_id += 1;

    var event = std.posix.Kevent64{
        .ident = timer_id,
        .filter = std.posix.system.EVFILT_TIMER,
        .flags = std.posix.system.EV_ADD,
        .fflags = std.posix.system.NOTE_SECONDS,
        .data = 30,  // fire every 30 seconds
        .udata = @intCast(client_id),
        .ext = .{ 0, 0 },
    };
    try std.posix.kevent64(self.kqueue_fd, &.{event}, &.{}, null);
    self.timer_to_client.put(timer_id, client_id);
    return timer_id;
}
```

**Linux timerfd equivalent** — requires create, configure, register, plus
cleanup (`modules/libitshell3/src/server/event_loop.zig`, lines 172-198):

```zig
fn registerHeartbeatTimer(self: *EventLoop, client_id: ClientId) !TimerId {
    const timer_id: u16 = self.next_timer_id;
    self.next_timer_id += 1;

    const tfd = try std.posix.timerfd_create(.MONOTONIC, .{ .CLOEXEC = true });
    // tfd is an i32 file descriptor — NOT a u16 identifier

    const interval = std.os.linux.itimerspec{
        .it_interval = .{ .tv_sec = 30, .tv_nsec = 0 },
        .it_value = .{ .tv_sec = 30, .tv_nsec = 0 },
    };
    try std.posix.timerfd_settime(tfd, .{}, &interval, null);

    var epoll_event = std.os.linux.epoll_event{
        .events = std.os.linux.EPOLL.IN,
        .data = .{ .fd = tfd },
    };
    try std.posix.epoll_ctl(self.epoll_fd, .ADD, tfd, &epoll_event);

    // BUG: timer_id is u16 but tfd is i32 — truncation on cast
    self.timer_to_client.put(timer_id, client_id);
    self.timer_to_fd.put(timer_id, tfd);  // mapping exists but cancelTimer ignores it
    return timer_id;
}
```

**Abstraction layer interface** showing where it breaks
(`modules/libitshell3/src/server/event_loop.zig`, lines 210-224):

```zig
pub const TimerId = u16;  // <-- assumes kqueue's identifier space

pub fn cancelTimer(self: *EventLoop, timer_id: TimerId) void {
    if (comptime builtin.os.tag == .macos) {
        // kqueue: delete the filter — no resource leak, kernel cleans up
        var event = std.posix.Kevent64{
            .ident = timer_id,
            .filter = std.posix.system.EVFILT_TIMER,
            .flags = std.posix.system.EV_DELETE,
            // ...
        };
        _ = std.posix.kevent64(self.kqueue_fd, &.{event}, &.{}, null);
    } else {
        // Linux: removes from epoll but DOES NOT close the timerfd
        const tfd = self.timer_to_fd.get(timer_id) orelse return;
        _ = std.posix.epoll_ctl(self.epoll_fd, .DEL, tfd, null);
        // MISSING: std.posix.close(tfd);
    }
    _ = self.timer_to_client.remove(timer_id);
}
```

**Resource cleanup on client disconnect — platform comparison:**

| Cleanup step             | macOS (kqueue)             | Linux (epoll + timerfd)           |
| ------------------------ | -------------------------- | --------------------------------- |
| Remove timer from loop   | `EV_DELETE` kevent         | `epoll_ctl(.DEL)` — done          |
| Release kernel resource  | Automatic (no fd)          | Requires `close(tfd)` — MISSING   |
| Free timer-to-client map | `timer_to_client.remove()` | `timer_to_client.remove()` — done |
| Free timer-to-fd map     | N/A                        | `timer_to_fd.remove()` — MISSING  |
| Inherited by fork        | No (kernel timer)          | Yes (fd inherited unless CLOEXEC) |
| Counts against RLIMIT    | No                         | Yes (one fd per timer)            |

**Concrete impact:** Timer leak on Linux because `cancelTimer(timer_id: u16)`
removes the epoll registration but never calls `close()` on the timerfd. Each
client disconnect leaks one file descriptor. After ~1000 connect/disconnect
cycles the daemon hits `RLIMIT_NOFILE` and fails with
`error.SystemFdQuotaExceeded` on the next `timerfd_create`, `accept`, or
`openpty` call. On macOS, `EVFILT_TIMER` is a kernel-internal timer with no file
descriptor, so `EV_DELETE` fully cleans up.

### How

The owner needs to decide how the timer abstraction handles platform-divergent
resource lifecycles. Options include but are not limited to: changing `TimerId`
to a tagged union that holds either `u16` (kqueue) or `fd_t` (timerfd) so the
type system enforces correct cleanup, adding `close(tfd)` and
`timer_to_fd.remove()` to the Linux branch of `cancelTimer`, or replacing
per-client kernel timers with a single timer wheel (one `EVFILT_TIMER` or one
timerfd) that multiplexes all client heartbeats internally, eliminating the
per-client fd problem on Linux entirely.
