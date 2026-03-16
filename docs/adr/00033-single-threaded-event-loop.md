# 00033. Single-Threaded Event Loop for Daemon

- Date: 2026-03-16
- Status: Accepted

## Context

The daemon must handle multiple concurrent activities: PTY I/O for multiple
panes, client connections over Unix sockets, signal delivery (SIGCHLD, SIGTERM),
timer-based operations (heartbeat, health checks, resize debounce), and
per-session IME engine state management. A multi-threaded architecture could
parallelize these across CPU cores.

## Decision

The daemon uses a single-threaded event loop (kqueue on macOS, epoll on Linux)
for all I/O multiplexing. No worker threads, no thread pools, no concurrent
access to shared state.

Evidence supporting sufficiency:

- tmux has served decades of production use with a single-threaded libevent
  loop, handling hundreds of sessions and clients without thread-based scaling.
- ghostty's `bulkExport()` completes in ~22µs per frame (PoC 07), well within
  single-thread budget.
- The daemon's hot path (PTY read → VT parse → RenderState update → ring buffer
  write → client delivery) is I/O-bound, not CPU-bound.
- Single-threaded design eliminates all locking, race conditions, and concurrent
  access bugs around shared state (session tree, IME engines, ring buffers,
  client state).

## Consequences

- Zero synchronization overhead — no mutexes, atomics, or lock ordering
  concerns.
- All state access is sequential — the session tree, IME engine per session, and
  ring buffers need no concurrent access protection.
- Thread-safe boundaries exist only at the OS interface: kqueue/epoll syscalls,
  PTY I/O, and socket I/O.
- If profiling ever reveals a CPU bottleneck (unlikely given I/O-bound nature),
  the decision would require fundamental restructuring. This is accepted as
  extremely unlikely based on tmux's production evidence.
