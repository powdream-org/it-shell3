## Example 6: OS <-> OS Conflict

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

Each client disconnect leaks one timerfd. After ~1000 reconnections, the daemon
hits `RLIMIT_NOFILE` and can't accept new connections, open PTYs, or create
timers. The daemon becomes unresponsive without crashing — a silent failure
mode. The error surfaces as `error.SystemFdQuotaExceeded` on whichever syscall
(`timerfd_create`, `accept`, or `openpty`) happens to run next, making root
cause diagnosis difficult in production.

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

The asymmetry between kqueue and epoll timer resource models:

```
macOS kqueue timer:
  register: one kevent64() call, no fd created
  cancel:   EV_DELETE, kernel cleans up automatically
  resource: zero fd cost per timer

Linux epoll timer:
  register: timerfd_create() → timerfd_settime() → epoll_ctl(ADD) — creates a REAL fd
  cancel:   epoll_ctl(DEL) — but MUST also close(tfd), which current code DOESN'T DO
  resource: 1 fd per timer, counts against RLIMIT_NOFILE (default 1024)

The abstraction uses TimerId = u16, which maps naturally to kqueue identifiers
but has no relationship to Linux fd values (i32).
```

The `cancelTimer` function on the Linux branch removes the timerfd from epoll
(`epoll_ctl(.DEL)`) but never calls `close(tfd)`. The `timer_to_fd` mapping that
could be used to find the fd is also never cleaned up. On macOS, `EV_DELETE` is
a complete cleanup because kqueue timers are kernel-internal with no fd.

**Resource cleanup on client disconnect — platform comparison:**

| Cleanup step             | macOS (kqueue)             | Linux (epoll + timerfd)           |
| ------------------------ | -------------------------- | --------------------------------- |
| Remove timer from loop   | `EV_DELETE` kevent         | `epoll_ctl(.DEL)` — done          |
| Release kernel resource  | Automatic (no fd)          | Requires `close(tfd)` — MISSING   |
| Free timer-to-client map | `timer_to_client.remove()` | `timer_to_client.remove()` — done |
| Free timer-to-fd map     | N/A                        | `timer_to_fd.remove()` — MISSING  |
| Inherited by fork        | No (kernel timer)          | Yes (fd inherited unless CLOEXEC) |
| Counts against RLIMIT    | No                         | Yes (one fd per timer)            |

### How

The owner needs to decide how the timer abstraction handles platform-divergent
resource lifecycles. Options include but are not limited to: changing `TimerId`
to a tagged union that holds either `u16` (kqueue) or `fd_t` (timerfd) so the
type system enforces correct cleanup, adding `close(tfd)` and
`timer_to_fd.remove()` to the Linux branch of `cancelTimer`, or replacing
per-client kernel timers with a single timer wheel (one `EVFILT_TIMER` or one
timerfd) that multiplexes all client heartbeats internally, eliminating the
per-client fd problem on Linux entirely.
