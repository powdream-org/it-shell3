# EventLoop Redesign

- **Date**: 2026-03-28
- **Scope**: Refactoring `event_loop.zig` to be a minimal event iteration engine
  with middleware-based dispatch and priority-ordered event delivery

## 1. Problem

The current `EventLoop` (in `modules/libitshell3/src/server/event_loop.zig`) was
written during Plan 1-2 before the design spec verification chain existed. A
spec compliance audit found six violations:

1. **Owns client state.** The `clients` array, `next_client_id`,
   `addClientTransport()`, `removeClient()`, and `findClientByFd()` all live
   inside EventLoop. The spec assigns client lifecycle to a separate Client
   Manager (Plan 6).

2. **Directly imports handlers.** EventLoop imports `signal_handler.zig`,
   `pty_read.zig`, `client_accept.zig`, and `client_writer.zig`, creating
   bidirectional coupling. The dispatch function hard-codes which handler serves
   which event type.

3. **Handles signal registration.** `run()` calls `blockSignals()` and
   `registerSignals()`. The spec assigns signal setup to Daemon startup Step 3
   (Plan 12.2).

4. **Has `shutdown_requested: bool`.** The spec defines a 7-step graceful
   shutdown sequence (Plan 10). A simple boolean cannot express that state
   machine.

5. **Two-pass signal-first loop.** The spec defines 4-tier priority ordering:
   SIGNAL > TIMER > READ > WRITE. The current implementation only distinguishes
   signal vs. non-signal.

6. **`registerAllPtyFds()` bulk scan.** No spec basis exists for scanning all
   sessions at startup. PTY fds should be registered dynamically when panes are
   created (Plan 7).

These violations are not bugs today, but they block Plans 6, 7, 10, and 12.2
from being implemented cleanly. The refactoring must happen before those plans
begin.

## 2. Design Decisions

### 2.1 EventLoop is minimal

After refactoring, EventLoop has exactly four responsibilities:

- Call the OS wait function (via `EventLoopOps` vtable) to collect ready events
- Iterate returned events in priority order
- Call the handler chain for each event
- Provide `stop()` to exit the loop

EventLoop does NOT own:

- Client state (`clients` array, `addClientTransport`, `removeClient`,
  `findClientByFd`, `clientCount`)
- Session state or session manager reference
- Signal blocking/registration
- Listener socket or listener fd registration
- Shutdown state machine or `shutdown_requested`
- Dispatch routing logic or UDATA encoding/decoding
- PTY operations vtable or signal operations vtable

### 2.2 Middleware chain replaces hard-coded dispatch

Instead of a `dispatch()` function that switches on filter type and udata
ranges, EventLoop holds a single `Handler` that forms the head of a chain. Each
handler decides whether an event belongs to it; if not, it calls the next
handler.

### 2.5 EventTarget tagged union replaces raw udata

The current `Event.udata: usize` encodes listener/PTY/client identity as integer
ranges (`UDATA_LISTENER=0`, `UDATA_PTY_BASE+encoded`, `UDATA_CLIENT_BASE+idx`).
This requires range arithmetic and couples every handler to the encoding scheme.

Replace `udata: usize` with a tagged union:

```
pub const EventTarget = union(enum) {
    listener: void,
    pty: struct { session_idx: u16, pane_slot: PaneSlot },
    client: struct { client_idx: u16 },
    timer: struct { timer_id: u16 },
};

pub const Event = struct {
    fd: std.posix.fd_t,
    filter: Filter,
    target: EventTarget,
};
```

Handlers match on the variant instead of doing range arithmetic:

```
switch (event.target) {
    .pty => |pty| { /* use pty.session_idx, pty.pane_slot directly */ },
    else => next(event),
}
```

The kqueue/epoll `wait()` implementation is responsible for translating raw OS
udata to `EventTarget` on the way out, and translating `EventTarget` to raw
udata when registering FDs. Each OS backend encodes/decodes in whatever way is
convenient for its platform — the scheme is internal to the backend.

This eliminates all UDATA constants (`UDATA_LISTENER`, `UDATA_PTY_BASE`,
`UDATA_CLIENT_BASE`) from shared code.

### 2.3 PriorityEventBuffer enforces 4-tier ordering

A new data structure sorts raw OS events into four priority groups before
EventLoop iterates them. This makes the priority policy a property of the
buffer, not the loop.

### 2.4 Existing tests get migration annotations

Tests that depend on client management or UDATA routing are annotated with
`TODO(Plan 12.2)` comments rather than deleted, to preserve coverage metrics
until the replacement integration tests exist.

## 3. New EventLoop API

```
EventLoop {
    // Injected dependencies
    event_ops: *const EventLoopOps,
    event_ctx: *anyopaque,
    chain: Handler,
    running: bool,

    fn init(event_ops, event_ctx, chain) EventLoop
    fn run(self: *EventLoop) RunError!void
    fn stop(self: *EventLoop) void
}
```

**`init`**: Stores the ops vtable, context pointer, and handler chain head. Sets
`running = true`. No side effects.

**`run`**: Loops while `running` is true. Each iteration:

1. Calls `event_ops.wait()` to get a batch of raw events.
2. Passes the batch through `PriorityEventBuffer` to get a priority-ordered
   iterator (this happens inside the `wait()` implementation; see Section 4).
3. For each event from the iterator, calls
   `chain.handleFn(chain.context, event, chain.next)`.

**`stop`**: Sets `running = false`. The current `wait()` call completes, the
loop checks the flag, and `run()` returns. This replaces `shutdown_requested`.

**What run() does NOT do** (compared to current):

- No `registerRead()` for the listener fd
- No `registerAllPtyFds()` bulk scan
- No `blockSignals()` / `registerSignals()`
- No UDATA-based dispatch routing

All of those are the caller's responsibility (Daemon in Plan 12.2, test harness
in the interim).

## 4. PriorityEventBuffer

A fixed-capacity buffer that groups events by priority tier. The OS-level wait
implementation (`kqueue.zig` or future `epoll.zig`) fills this buffer instead of
returning a flat array.

```
Priority tiers (0 = highest):
  0: SIGNAL  — process lifecycle, must be handled first
  1: TIMER   — frame export coalescing, keepalive
  2: READ    — PTY output, client messages, listener accept
  3: WRITE   — client write readiness
```

### 4.1 Interface

The `Filter` enum in `os/interfaces.zig` is declared with explicit priority
ordering as its backing integer:

```
pub const Filter = enum(u2) {
    signal = 0,
    timer = 1,
    read = 2,
    write = 3,

    pub const count = @typeInfo(Filter).@"enum".fields.len;  // 4
};
```

`PriorityEventBuffer` derives its dimensions from `Filter`:

```
PriorityEventBuffer {
    const NUM_PRIORITIES = Filter.count;
    const CAPACITY = interfaces.MAX_EVENTS_PER_BATCH;

    buffers: [NUM_PRIORITIES][CAPACITY]Event,
    sizes: [NUM_PRIORITIES]u32,

    fn reset(self) void
        — Zeroes all sizes. Does not clear buffer contents.

    fn add(self, event: Event) void
        — Maps event.filter to a priority tier and appends to that tier's
          buffer. Drops the event silently if the tier is full (defensive;
          should not happen with reasonable CAPACITY).

    fn isEmpty(self) bool
        — Returns true if sum of all sizes is zero.

    fn iterator(self) Iterator
        — Returns an iterator that yields events in priority order:
          all tier-0 events first (in insertion order), then tier-1, etc.
}
```

### 4.2 Filter-to-priority mapping

The `Filter` enum's integer values ARE the priority order (0 = highest). The
`add()` method uses `@intFromEnum(event.filter)` as the bucket index directly —
no separate mapping table needed.

| `Filter` variant | `@intFromEnum` | Rationale                                        |
| ---------------- | -------------- | ------------------------------------------------ |
| `.signal`        | 0              | SIGCHLD/SIGTERM must preempt all I/O             |
| `.timer`         | 1              | Timers fire at known intervals, brief handling   |
| `.read`          | 2              | Bulk of event loop work (PTY + client data)      |
| `.write`         | 3              | Write readiness is demand-driven, lowest urgency |

### 4.3 Shared Capacity Constant

`os/interfaces.zig` defines a single constant shared by `PriorityEventBuffer`
and all OS wait implementations:

```
pub const MAX_EVENTS_PER_BATCH: usize = 64;
```

- `PriorityEventBuffer`: per-tier capacity = `MAX_EVENTS_PER_BATCH`
- kqueue `wait()`: raw kevent64 buffer = `[MAX_EVENTS_PER_BATCH]kevent64_s`
- epoll `wait()`: raw epoll buffer = `[MAX_EVENTS_PER_BATCH]epoll_event`

This ensures the PriorityEventBuffer can always hold every event from a single
OS wait call without overflow.

### 4.4 Location

`modules/libitshell3/src/server/os/priority_event_buffer.zig`

This lives alongside `kqueue.zig` and `interfaces.zig` in the `os/` directory
because the OS wait implementations are the producers. The buffer is an
implementation detail of how `wait()` delivers events, not a concern of
EventLoop itself.

### 4.5 Impact on EventLoopOps.wait()

The `wait()` function signature in `interfaces.zig` may change to return a
`PriorityEventBuffer.Iterator` instead of writing into a caller-provided
`[]Event` slice. Alternatively, the real kqueue implementation can fill a
`PriorityEventBuffer` internally and the mock can do the same. The exact
signature change is an implementation detail to resolve during coding.

The key contract: EventLoop receives events in priority order without needing to
know the priority scheme.

## 5. Handler Chain

### 5.1 Handler type

```
Handler = struct {
    handleFn: *const fn (context: *anyopaque, event: Event, next: ?Handler) void,
    context: *anyopaque,
    next: ?Handler,

    /// Convenience: calls handleFn with this handler's context and next.
    /// Used by EventLoop.run() and by handlers forwarding to the next in chain.
    pub fn invoke(self: Handler, event: Event) void {
        self.handleFn(self.context, event, self.next);
    }
};
```

Each handler receives:

- `context`: type-erased pointer to the handler's own state (e.g., a
  `*SignalContext`, `*ClientManager`, `*PtyManager`)
- `event`: the current event from the priority-ordered iterator
- `next`: the next handler in the chain, or `null` if this is the last one

`invoke()` hides the `handleFn(context, event, next)` expansion. Callers use:

- EventLoop: `self.handler.invoke(event)`
- Handler forwarding: `if (next) |n| n.invoke(event)`

### 5.2 Dispatch contract

A handler MUST do exactly one of:

1. Handle the event (consume it). It may optionally also call `next`.
2. Skip the event by calling `next.?.invoke(event)`.

If `next` is `null` and the handler does not recognize the event, the event is
silently dropped. This is intentional: unhandled events are a normal condition
during incremental plan implementation.

### 5.3 Chain assembly

The chain is assembled by the caller, not by EventLoop. In production (Plan
12.2), the Daemon builds the chain:

```
signal_handler -> client_accept -> pty_read -> client_write -> (end)
```

In tests, the test harness builds a minimal chain with only the handlers
relevant to the test scenario.

### 5.4 Why a chain, not a registry

A flat handler registry (map from filter+udata to handler) would be more
efficient for dispatch but would couple EventLoop to the UDATA scheme. The chain
pattern:

- Keeps EventLoop free of event identity encoding
- Allows handlers to match on `EventTarget` variants (type-safe, not range math)
- Supports handlers that need to see events they do not consume (e.g., logging)
- Is simple to test (build a chain of 1-2 handlers)

## 6. Migration Plan

### 6.1 What stays in event_loop.zig

- `EventLoop` struct (with the new minimal fields)
- `init()` (new signature: no listener, no session_manager, no client array)
- `run()` (new implementation: iterate + chain dispatch)
- `stop()` (replaces checking `shutdown_requested`)
- `RunError` type

### 6.2 What moves out of event_loop.zig

| Current location             | Destination                       | When          |
| ---------------------------- | --------------------------------- | ------------- |
| `clients` array + management | Client Manager (new module)       | Plan 6        |
| UDATA constants              | Eliminated by `EventTarget` union | This refactor |
| `dispatch()` routing logic   | Handler chain (per-handler)       | This refactor |
| `registerAllPtyFds()`        | PTY lifecycle (per-pane)          | Plan 7        |
| Signal blocking/registration | Daemon startup                    | Plan 12.2     |
| Listener fd registration     | Daemon startup                    | Plan 12.2     |
| `shutdown_requested`         | Shutdown state machine            | Plan 10       |

### 6.3 What is deleted

- `dispatchClientRead()`, `dispatchClientWrite()`, `dispatchPtyRead()`,
  `dispatchTimer()` — these are inline stubs or thin wrappers. Their logic moves
  into the respective chain handlers.
- `ClientEntry` re-export — EventLoop should not re-export client types.
- Direct imports of `signal_handler`, `pty_read`, `client_accept`,
  `client_writer`, `client_state`, `session_manager`, `pane`.

### 6.4 Interim state (before Plan 12.2)

Until the Daemon orchestrator exists, the test harness is the only caller of
`EventLoop.init()`. Tests build a handler chain manually and inject mock
`EventLoopOps`. This means:

- Signal registration happens in the test setup, not in `run()`.
- Listener fd registration happens in the test setup.
- Client management is done by the test's own context struct.

This is a feature, not a gap: it proves EventLoop works without owning any of
those concerns.

## 7. Impact on Existing Files

### 7.1 client_accept.zig

Currently imports `event_loop.zig` and takes `*EventLoop` as parameter. After
refactoring:

- Becomes a chain handler with its own context struct containing the listener
  reference and a client-add callback (or a `*ClientManager` pointer once Plan 6
  provides it).
- `handleClientAccept` signature changes from `(self: *EventLoop)` to
  `(context: *anyopaque, event: Event, next: ?Handler)`.

### 7.2 pty_read.zig

Already does not import `event_loop.zig`. Becomes a chain handler with a context
struct containing `pty_ops` and `session_manager`. The `handlePtyRead` signature
already takes decomposed parameters; the chain wrapper maps from
`(context, event, next)` to the existing call pattern.

### 7.3 signal_handler.zig

Currently takes `*bool` for `shutdown_requested`. After refactoring:

- Becomes a chain handler whose context includes a `*bool` (the EventLoop's
  `running` flag, passed as `&event_loop.running` with inverted sense, or a
  separate `stop_fn` callback).
- `handleSignalEvent` internal logic is unchanged; only the entry point wrapper
  changes.

### 7.4 os/interfaces.zig

Changes to `os/interfaces.zig`:

- `Event` struct: `udata: usize` replaced by `target: EventTarget`
- `EventTarget` tagged union added (see Section 2.5)
- `Filter` enum: gains explicit `enum(u2)` backing with priority-ordered values
  and `pub const count` (see Section 4.1)
- `MAX_EVENTS_PER_BATCH` constant added (see Section 4.3)
- `EventLoopOps.wait()` signature may change to return a
  `PriorityEventBuffer.Iterator` or to fill a `*PriorityEventBuffer`
- `EventLoopOps.registerRead()` signature changes to accept `EventTarget`
  instead of raw `udata: usize`

### 7.5 client_state.zig

No changes. It is no longer referenced from `event_loop.zig`, but its API
remains the same. It becomes a dependency of the Client Manager (Plan 6)
instead.

## 8. Test Strategy

### 8.1 New unit tests for PriorityEventBuffer

- `add` places events in correct priority tier
- Iterator yields events in SIGNAL > TIMER > READ > WRITE order
- Insertion order is preserved within each tier
- `reset` clears all tiers
- `isEmpty` returns correct state before and after adds
- Full tier silently drops (no crash)

### 8.2 New unit tests for EventLoop

- `run` with a single-handler chain that calls `stop()` on first event
- `run` with a multi-handler chain verifying chain traversal order
- `run` with an unhandled event (no handler consumes it) completes without error
- `stop` during iteration causes `run` to return after the current batch

### 8.3 Existing tests: annotation policy

Tests in the current `event_loop.zig` fall into three categories:

| Test                                                 | Action                                               |
| ---------------------------------------------------- | ---------------------------------------------------- |
| `init: clients all null, shutdown_requested = false` | Remove (tests deleted fields)                        |
| `addClientTransport` (3 tests)                       | `TODO(Plan 6)` annotation                            |
| `removeClient: nulls slot`                           | `TODO(Plan 6)` annotation                            |
| `findClientByFd` (2 tests)                           | `TODO(Plan 6)` annotation                            |
| `dispatch: signal-first ordering in mixed batch`     | Rewrite for chain + priority buffer                  |
| `udata ranges: PTY and client ranges do not overlap` | Remove (EventTarget union eliminates range encoding) |
| `dispatch: signal event sets shutdown_requested`     | Rewrite for chain pattern                            |
| `dispatch: read event on PTY fd triggers pty read`   | Rewrite for chain pattern                            |
| `run: single event then shutdown`                    | Rewrite for new `run()` + `stop()`                   |

Tests marked `TODO(Plan 6)` are moved to a separate file (e.g.,
`client_manager_test.zig` placeholder) or kept in `event_loop.zig` with `test`
blocks commented out and a TODO note. They are not deleted so that the coverage
gap is visible and tracked.

### 8.4 Handler tests stay in handler files

Each handler file (`signal_handler.zig`, `pty_read.zig`, `client_accept.zig`)
keeps its own unit tests. Those tests construct a minimal chain of one handler
and verify behavior. They do not depend on EventLoop.

## 9. What is NOT in Scope

This spec covers only the EventLoop refactoring. The following are explicitly
out of scope and belong to their respective plans:

- **Client Manager / ClientState redesign** — Plan 6
- **Dynamic PTY fd registration** — Plan 7
- **Graceful shutdown state machine** — Plan 10
- **Daemon orchestrator (startup sequence, chain assembly)** — Plan 12.2
- **Message dispatch router** — Plan 6
