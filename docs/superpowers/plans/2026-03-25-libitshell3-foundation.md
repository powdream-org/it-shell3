# libitshell3 Foundation Implementation Plan

> **Execution model (actual):** Executed via subagent-driven-development — fresh
> implementer subagent per task (sonnet for mechanical, opus for architectural),
> with inline review by team lead. 15/15 tasks complete, 152 tests passing.
> Future plans use the `/implementation` skill with persistent impl-team agents.

**Goal:** Build the foundational layer of libitshell3 — core types, event loop,
PTY management, Unix socket listener, and basic daemon lifecycle — producing a
minimal daemon that starts, creates a session with one pane (shell), accepts a
client connection, and shuts down cleanly.

**Architecture:** Four-module diamond (core/ ← ghostty/, input/; server/ ← all
three) per ADR 00048. This plan implements core/ and server/ only. Single-
threaded kqueue event loop, no locks. All state in fixed-size arrays (no heap
pointers in core types). daemon/main.zig is a thin ~100-line orchestrator.

**Tech Stack:** Zig 0.15+, POSIX (kqueue, forkpty, Unix sockets), vendored
libghostty (stubbed in this plan — real integration in Plan 2).

**Mocking strategy:** All OS primitives (PTY, kqueue, Unix sockets, signals) are
behind vtable interfaces in `os/interfaces.zig`. Real implementations in
`os/pty.zig`, `os/kqueue.zig`, etc. Mock implementations in
`testing/mock_os.zig`. Unit tests use mocks for deterministic behavior;
integration tests use real implementations. This enables testing event loop
dispatch, signal handling, and client lifecycle without real child processes or
sockets.

**Scope boundary:** This plan does NOT implement: ghostty Terminal/RenderState
integration, wire protocol serialization, ring buffer, IME integration, adaptive
coalescing, or client message handling beyond handshake stub. Those are
subsequent plans.

**Design spec references:**

- `docs/modules/libitshell3/02-design-docs/daemon-architecture/draft/v1.0-r8/`
  (01-module-structure, 02-state-and-types, 03-integration-boundaries)
- `docs/modules/libitshell3/02-design-docs/daemon-behavior/draft/v1.0-r8/`
  (01-daemon-lifecycle, 02-event-handling)
- `docs/modules/libitshell3/02-design-docs/daemon-architecture/draft/v1.0-r8/impl-constraints/state-and-types.md`
- `docs/modules/libitshell3/02-design-docs/daemon-behavior/draft/v1.0-r8/impl-constraints/daemon-lifecycle.md`
- `docs/modules/libitshell3/02-design-docs/daemon-behavior/draft/v1.0-r8/impl-constraints/pane-exit-cascade.md`
- `docs/adr/00048-daemon-binary-vs-library-responsibility-separation.md`

---

## File Structure

```
modules/libitshell3/
├── build.zig                          # Build system (static lib + tests)
├── src/
│   ├── root.zig                       # Public module interface
│   ├── core/
│   │   ├── types.zig                  # Core types: PaneId, PaneSlot, SessionId, constants
│   │   ├── session.zig                # Session struct + methods
│   │   ├── pane.zig                   # Pane struct + two-phase exit flags
│   │   ├── split_tree.zig             # SplitNodeData, tree[31] operations
│   │   ├── navigation.zig             # findPaneInDirection() geometric algorithm
│   │   ├── preedit_state.zig          # PreeditState (owner, session_id)
│   │   └── session_manager.zig        # SessionManager: sessions array, CRUD
│   ├── os/
│   │   ├── interfaces.zig             # OS abstraction interfaces (vtable structs)
│   │   ├── pty.zig                    # Real PTY impl (forkpty, TIOCSWINSZ, close)
│   │   ├── kqueue.zig                 # Real kqueue impl (kevent64, register, wait)
│   │   ├── socket.zig                 # Real Unix socket impl (bind, accept, close)
│   │   └── signals.zig               # Real signal impl (sigprocmask, registration)
│   ├── server/
│   │   ├── event_loop.zig             # Event loop (uses os.interfaces, not raw syscalls)
│   │   ├── listener.zig               # Socket listener (uses os.interfaces)
│   │   ├── client.zig                 # ClientState + connection state machine
│   │   ├── signal_handler.zig         # Signal handler (uses os.interfaces)
│   │   └── handlers/
│   │       ├── signal.zig             # Signal event handlers
│   │       ├── pty_read.zig           # PTY read handler (raw passthrough for now)
│   │       ├── client_accept.zig      # New client accept handler
│   │       └── client_read.zig        # Client message handler (stub)
│   └── testing/
│       ├── helpers.zig                # Test utilities (temp socket paths, etc.)
│       └── mock_os.zig               # Mock OS implementations for deterministic tests

daemon/
├── build.zig                          # Daemon binary build
└── src/
    └── main.zig                       # Thin orchestrator (~100 lines)
```

---

## Task 1: Build System + Root Module

**Files:**

- Create: `modules/libitshell3/build.zig`
- Create: `modules/libitshell3/src/root.zig`

- [ ] **Step 1: Create build.zig**

```zig
// modules/libitshell3/build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "itshell3",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
```

- [ ] **Step 2: Create root.zig with empty public interface**

```zig
// modules/libitshell3/src/root.zig
pub const core = @import("core/types.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
```

- [ ] **Step 3: Create minimal types.zig so build passes**

```zig
// modules/libitshell3/src/core/types.zig
// Core type definitions — placeholder for Task 2
```

- [ ] **Step 4: Verify build**

Run: `(cd modules/libitshell3 && zig build test)` Expected: PASS (empty test
suite)

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/
git commit -m "feat(libitshell3): add build system and root module"
```

---

## Task 2: Core Types

**Files:**

- Create: `modules/libitshell3/src/core/types.zig`
- Create: `modules/libitshell3/src/core/preedit_state.zig`

Reference: `impl-constraints/state-and-types.md`

- [ ] **Step 1: Write tests for core constants and types**

```zig
// In types.zig
test "constants" {
    try std.testing.expectEqual(@as(u4, 16), MAX_PANES);
    try std.testing.expectEqual(@as(u5, 31), MAX_TREE_NODES);
}

test "PaneSlot fits in u4" {
    const slot: PaneSlot = 15;
    _ = slot;
}

test "SessionId is u32" {
    const id: SessionId = 42;
    _ = id;
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `(cd modules/libitshell3 && zig build test)` Expected: FAIL — types not
defined

- [ ] **Step 3: Implement core types**

Define in `types.zig`:

- `PaneId` (u32, monotonically increasing)
- `PaneSlot` (u4, 0..15 index into pane_slots array)
- `SessionId` (u32)
- `ClientId` (u32)
- `MAX_PANES` = 16
- `MAX_TREE_NODES` = 31
- `MAX_TREE_DEPTH` = 4
- `Orientation` enum (horizontal, vertical)
- `Direction` enum (up, down, left, right)
- `FreeMask` = u16 (bitfield for pane slot availability)
- `DirtyMask` = u16 (bitfield for dirty pane tracking)

Define in `preedit_state.zig`:

- `PreeditState` struct: `owner: ?ClientId`, `session_id: u32`
- `init()`, `clear()`, `incrementSessionId()`

- [ ] **Step 4: Run tests to verify they pass**

Run: `(cd modules/libitshell3 && zig build test)` Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/src/core/
git commit -m "feat(libitshell3): add core types and constants"
```

---

## Task 3: Split Tree

**Files:**

- Create: `modules/libitshell3/src/core/split_tree.zig`

Reference: `impl-constraints/state-and-types.md` (SplitNodeData),
`02-state-and-types.md` §1

- [ ] **Step 1: Write tests for split tree operations**

Test cases:

- Single leaf (root = leaf with pane slot 0)
- Split root horizontally → two leaves
- Find leaf by pane slot
- Remove leaf and compact tree
- Reject split at max depth (4)
- Reject split when tree is full (31 nodes)

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement SplitNodeData and tree operations**

`SplitNodeData` is a tagged union:

- `leaf: PaneSlot`
- `split: struct { orientation: Orientation, ratio: f32, left: u5, right: u5 }`
- `empty: void`

Tree stored as `tree_nodes: [MAX_TREE_NODES]SplitNodeData` (index 0 = root).

Operations:

- `initSingleLeaf(slot: PaneSlot) -> [MAX_TREE_NODES]SplitNodeData`
- `splitLeaf(tree, node_idx, orientation, ratio, new_slot) -> error{TreeFull, MaxDepth}!void`
- `removeLeaf(tree, node_idx) -> void` (compact: promote sibling to parent)
- `findLeafBySlot(tree, slot) -> ?u5`
- `depth(tree, node_idx) -> u5`
- `leafCount(tree) -> u5`

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/src/core/split_tree.zig
git commit -m "feat(libitshell3): add split tree with insert/remove/compact"
```

---

## Task 4: Pane Struct

**Files:**

- Create: `modules/libitshell3/src/core/pane.zig`

Reference: `impl-constraints/state-and-types.md` (Pane struct)

- [ ] **Step 1: Write tests for Pane**

Test cases:

- Create pane with valid fields
- Two-phase exit: mark PANE_EXITED, then PTY_EOF (or reverse)
- `isFullyDead()` returns true only when both flags set
- Pane metadata defaults

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement Pane struct**

Fields from impl-constraints:

- `pane_id: PaneId`
- `slot_index: PaneSlot`
- `pty_fd: std.posix.fd_t` (master side)
- `child_pid: std.posix.pid_t`
- `terminal: ?*anyopaque` (opaque — ghostty Terminal*, null in this plan)
- `render_state: ?*anyopaque` (opaque — ghostty RenderState*, null in this plan)
- `cols: u16, rows: u16`
- `title: [256]u8, title_len: u16`
- `cwd: [4096]u8, cwd_len: u16`
- `is_running: bool`
- `exit_status: ?u8`
- `pane_exited: bool` (SIGCHLD reap flag)
- `pty_eof: bool` (PTY EOF flag)

Methods:

- `init(pane_id, slot_index, pty_fd, child_pid, cols, rows) -> Pane`
- `isFullyDead() -> bool` (both flags set)
- `markExited(exit_status)`, `markPtyEof()`

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/src/core/pane.zig
git commit -m "feat(libitshell3): add Pane struct with two-phase exit"
```

---

## Task 5: Session Struct

**Files:**

- Create: `modules/libitshell3/src/core/session.zig`

Reference: `impl-constraints/state-and-types.md` (Session, SessionEntry)

- [ ] **Step 1: Write tests for Session**

Test cases:

- Create session with one pane (default state)
- `allocPaneSlot()` returns lowest free slot
- `allocPaneSlot()` returns error when all 16 slots used
- `freePaneSlot()` releases a slot
- `focusedPane()` returns the pane at `focused_pane` slot
- Dirty mask tracking: mark dirty, clear, check

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement Session and SessionEntry**

`Session`:

- `session_id: SessionId`
- `name: [64]u8, name_len: u8`
- `active_input_method: [32]u8, aim_len: u8` (default: "direct")
- `keyboard_layout: [32]u8, kl_len: u8` (default: "us")
- `tree_nodes: [MAX_TREE_NODES]SplitNodeData`
- `focused_pane: PaneSlot`
- `preedit: PreeditState`

`SessionEntry` (server-side wrapper):

- `session: Session`
- `pane_slots: [MAX_PANES]?Pane`
- `free_mask: FreeMask` (1 = available)
- `dirty_mask: DirtyMask`
- `allocPaneSlot() -> error{NoFreeSlots}!PaneSlot`
- `freePaneSlot(slot)`
- `focusedPane() -> ?*Pane`
- `markDirty(slot)`, `clearDirty()`, `isDirty(slot) -> bool`

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/src/core/session.zig
git commit -m "feat(libitshell3): add Session and SessionEntry with slot management"
```

---

## Task 6: Session Manager

**Files:**

- Create: `modules/libitshell3/src/core/session_manager.zig`

- [ ] **Step 1: Write tests for SessionManager**

Test cases:

- Create session → returns SessionId
- Get session by ID
- Destroy session by ID
- Session count
- Create fails when max sessions reached (reasonable limit, e.g., 64)

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement SessionManager**

Simple array-based manager:

- `sessions: [MAX_SESSIONS]?SessionEntry`
- `next_session_id: SessionId`
- `next_pane_id: PaneId`
- `createSession(name, cols, rows) -> error{...}!SessionId` (allocates
  SessionEntry, creates initial pane via `forkPty` callback or deferred init)
- `destroySession(id) -> ?SessionEntry`
- `getSession(id) -> ?*SessionEntry`
- `sessionCount() -> u32`

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/src/core/session_manager.zig
git commit -m "feat(libitshell3): add SessionManager with create/destroy/lookup"
```

---

## Task 7: Pane Navigation

**Files:**

- Create: `modules/libitshell3/src/core/navigation.zig`

Reference: `02-state-and-types.md` §2 (geometric edge-adjacency algorithm)

- [ ] **Step 1: Write tests for pane navigation**

Test cases:

- Two panes side-by-side (horizontal split): navigate left/right
- Two panes stacked (vertical split): navigate up/down
- Navigate in direction with no adjacent pane → returns null
- Three panes: L-shape layout, navigate across splits
- Tie-break: lowest pane slot index (per G1-09 fix)

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement findPaneInDirection()**

Pure geometric function (no side effects, no server/ dependency):

- Input: tree_nodes, pane dimensions (computed from cols/rows + split ratios),
  focused pane slot, direction
- Algorithm: compute bounding rectangles, find adjacent panes in given direction
  using edge overlap, tie-break by lowest slot index
- Output: ?PaneSlot

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/src/core/navigation.zig
git commit -m "feat(libitshell3): add geometric pane navigation algorithm"
```

---

## Task 8: PTY Management

**Files:**

- Create: `modules/libitshell3/src/server/pty.zig`

Reference: `impl-constraints/daemon-lifecycle.md` (startup step 6),
`02-state-and-types.md` §1.4 (PTY lifecycle)

- [ ] **Step 1: Write tests for PTY operations**

Test cases:

- `forkPty()` returns valid master fd and child pid
- Child process is running after fork
- `resize()` applies TIOCSWINSZ
- `close()` closes master fd
- Read from master fd after child writes

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement PTY module**

Functions:

- `forkPty(cols, rows, shell) -> error{...}!struct { master_fd: fd_t, child_pid: pid_t }`
  Wraps `std.posix.forkpty()` or raw `openpty` + `fork`. Child execs shell
  (default: user's $SHELL or /bin/sh).
- `resize(master_fd, cols, rows) -> error{...}!void`
  `ioctl(master_fd, TIOCSWINSZ, &winsize)`
- `close(master_fd) -> void`

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/src/server/pty.zig
git commit -m "feat(libitshell3): add PTY fork/resize/close"
```

---

## Task 9: Unix Socket Listener

**Files:**

- Create: `modules/libitshell3/src/server/listener.zig`

Reference: `impl-constraints/daemon-lifecycle.md` (startup step 4)

- [ ] **Step 1: Write tests for listener**

Test cases:

- Bind to temp socket path → succeeds
- Accept connection → returns client fd
- Stale socket cleanup (unlink existing socket, rebind)
- Socket permissions (chmod 0600)
- Close listener removes socket file

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement Listener**

```zig
pub const Listener = struct {
    fd: std.posix.fd_t,
    socket_path: []const u8,

    pub fn init(socket_path: []const u8) -> error{...}!Listener
    // bind AF_UNIX, listen, chmod 0600
    // stale cleanup: try connect → if succeeds, another daemon running (error)
    //                             → if fails, unlink and rebind

    pub fn accept() -> error{...}!std.posix.fd_t

    pub fn deinit(self: *Listener) -> void
    // close fd, unlink socket_path
};
```

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/src/server/listener.zig
git commit -m "feat(libitshell3): add Unix socket listener with stale cleanup"
```

---

## Task 10: Signal Handler Setup

**Files:**

- Create: `modules/libitshell3/src/server/signal_handler.zig`
- Create: `modules/libitshell3/src/server/handlers/signal.zig`

Reference: `impl-constraints/daemon-lifecycle.md` (startup step 3, SIGCHLD
handling)

- [ ] **Step 1: Write tests for signal registration**

Test cases:

- Register SIGCHLD with kqueue → filter registered
- Register SIGTERM/SIGINT → filters registered
- Signal mask blocks default handling

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement signal setup and handlers**

`signal_handler.zig`:

- `registerSignals(kq: fd_t) -> error{...}!void` Registers EVFILT_SIGNAL for
  SIGTERM, SIGINT, SIGHUP, SIGCHLD. Masks signals with `sigprocmask` so they
  only arrive via kqueue.

`handlers/signal.zig`:

- `handleSigchld(session_manager) -> void` Calls `waitpid(-1, WNOHANG)` in loop,
  marks pane_exited + exit_status on matching panes. Does NOT trigger cascade
  (PTY EOF does that).
- `handleSigterm(shutdown_flag) -> void` Sets `shutdown_requested = true`.

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/src/server/signal_handler.zig \
       modules/libitshell3/src/server/handlers/signal.zig
git commit -m "feat(libitshell3): add kqueue signal handlers (SIGCHLD, SIGTERM)"
```

---

## Task 11: Client State Machine

**Files:**

- Create: `modules/libitshell3/src/server/client.zig`

Reference: `03-integration-boundaries.md` §6 (client state machine),
`03-policies-and-procedures.md` §12 (state transitions)

- [ ] **Step 1: Write tests for client state machine**

Test cases:

- New client starts in HANDSHAKING
- HANDSHAKING → READY on successful handshake
- HANDSHAKING → closed on timeout/invalid
- READY → OPERATING on attach
- OPERATING → READY on detach
- OPERATING → READY on DestroySessionRequest (own session)

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement ClientState**

```zig
pub const ClientState = struct {
    client_id: ClientId,
    conn_fd: std.posix.fd_t,
    state: State,
    attached_session: ?SessionId,

    pub const State = enum {
        handshaking,
        ready,
        operating,
        disconnecting,
    };

    pub fn init(client_id: ClientId, conn_fd: fd_t) -> ClientState
    pub fn completeHandshake(self: *ClientState) -> void  // → ready
    pub fn attach(self: *ClientState, session_id: SessionId) -> void  // → operating
    pub fn detach(self: *ClientState) -> void  // → ready
    pub fn beginDisconnect(self: *ClientState) -> void  // → disconnecting
};
```

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/src/server/client.zig
git commit -m "feat(libitshell3): add client connection state machine"
```

---

## Task 12: Event Loop

**Files:**

- Create: `modules/libitshell3/src/server/event_loop.zig`
- Create: `modules/libitshell3/src/server/handlers/pty_read.zig`
- Create: `modules/libitshell3/src/server/handlers/client_accept.zig`
- Create: `modules/libitshell3/src/server/handlers/client_read.zig`

Reference: `01-module-structure.md` §2 (event loop model),
`impl-constraints/daemon-lifecycle.md` (step 7)

- [ ] **Step 1: Write tests for event loop dispatch**

Test cases:

- Event loop processes signal events (SIGCHLD → handler called)
- Event loop accepts new client connection
- Event loop reads from PTY fd
- Event loop exits on shutdown flag
- Two-level dispatch: filter type → domain handler

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement EventLoop**

```zig
pub const EventLoop = struct {
    kq: std.posix.fd_t,
    listener: *Listener,
    session_manager: *SessionManager,
    clients: [MAX_CLIENTS]?ClientState,
    next_client_id: ClientId,
    shutdown_requested: bool,

    pub fn init(listener, session_manager) -> error{...}!EventLoop
    pub fn run(self: *EventLoop) -> error{...}!void
    // kevent64 loop:
    //   EVFILT_SIGNAL → signal handler
    //   EVFILT_READ on listen_fd → accept client
    //   EVFILT_READ on pty_fd → read PTY output
    //   EVFILT_READ on client_fd → read client message
    //   shutdown_requested → break
};
```

Handler stubs:

- `pty_read.zig`: Read from PTY, write raw bytes to all attached clients
  (temporary — will be replaced by RenderState pipeline in Plan 2)
- `client_accept.zig`: Accept connection, create ClientState, register with
  kqueue
- `client_read.zig`: Read from client fd, stub handler (log and discard for now)

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add modules/libitshell3/src/server/
git commit -m "feat(libitshell3): add kqueue event loop with two-level dispatch"
```

---

## Task 13: Daemon Binary

**Files:**

- Create: `daemon/build.zig`
- Create: `daemon/src/main.zig`

Reference: ADR 00048, `impl-constraints/daemon-lifecycle.md`

- [ ] **Step 1: Create daemon build.zig**

Links libitshell3 as dependency. Produces `it-shell3-daemon` executable.

- [ ] **Step 2: Implement main.zig (~100 lines)**

Thin orchestrator per ADR 00048:

1. Parse args (`--socket-path`, `--foreground`)
2. Block signals (sigprocmask)
3. Stale socket probe
4. Init listener
5. Init session manager + create default session
6. Init event loop
7. Run event loop
8. Cleanup (shutdown sequence)

- [ ] **Step 3: Verify build and manual smoke test**

Run: `(cd daemon && zig build)` Then:
`./zig-out/bin/it-shell3-daemon --socket-path /tmp/test-itshell3.sock --foreground`
Expected: Daemon starts, creates socket, runs shell in PTY.

- [ ] **Step 4: Commit**

```bash
git add daemon/
git commit -m "feat(daemon): add thin binary orchestrator (main.zig)"
```

---

## Task 14: Integration Test

**Files:**

- Create: `modules/libitshell3/src/testing/helpers.zig`
- Add integration test in `modules/libitshell3/src/root.zig`

- [ ] **Step 1: Write integration test**

Test: Start daemon (in-process), connect via Unix socket, verify session exists,
send shutdown signal, verify clean exit.

```zig
test "daemon lifecycle: start, connect, shutdown" {
    const allocator = std.testing.allocator;
    const socket_path = try helpers.tempSocketPath(allocator);
    defer allocator.free(socket_path);
    defer std.posix.unlink(socket_path) catch {};

    // Start daemon components
    var listener = try Listener.init(socket_path);
    defer listener.deinit();

    var sm = SessionManager.init();
    const session_id = try sm.createSession("default", 80, 24);
    try std.testing.expect(session_id > 0);

    // Connect as client
    const client_fd = try connectUnix(socket_path);
    defer std.posix.close(client_fd);

    // Verify session exists
    const entry = sm.getSession(session_id);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(@as(u32, 1), sm.sessionCount());
}
```

- [ ] **Step 2: Run integration test**

Run: `(cd modules/libitshell3 && zig build test)` Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add modules/libitshell3/src/testing/ modules/libitshell3/src/root.zig
git commit -m "test(libitshell3): add integration test for daemon lifecycle"
```

---

## Task 15: Wire Up Root Module Exports

**Files:**

- Modify: `modules/libitshell3/src/root.zig`

- [ ] **Step 1: Export all public interfaces**

Update `root.zig` to export:

- `core.types`, `core.Session`, `core.SessionEntry`, `core.Pane`
- `core.SplitTree`, `core.Navigation`, `core.SessionManager`
- `server.EventLoop`, `server.Listener`, `server.ClientState`
- `server.Pty`

- [ ] **Step 2: Run full test suite**

Run: `(cd modules/libitshell3 && zig build test)` Expected: ALL PASS

- [ ] **Step 3: Final commit**

```bash
git add modules/libitshell3/src/root.zig
git commit -m "feat(libitshell3): wire up public module exports"
```

---

## Summary

| Task | Component            | Files | Estimated Complexity |
| ---- | -------------------- | ----- | -------------------- |
| 1    | Build system         | 2     | Low                  |
| 2    | Core types           | 2     | Low                  |
| 3    | Split tree           | 1     | Medium               |
| 4    | Pane struct          | 1     | Low                  |
| 5    | Session struct       | 1     | Medium               |
| 6    | Session manager      | 1     | Low                  |
| 7    | Navigation           | 1     | Medium               |
| 8    | PTY management       | 1     | Medium               |
| 9    | Socket listener      | 1     | Medium               |
| 10   | Signal handlers      | 2     | Medium               |
| 11   | Client state machine | 1     | Low                  |
| 12   | Event loop           | 4     | High                 |
| 13   | Daemon binary        | 2     | Low                  |
| 14   | Integration test     | 2     | Medium               |
| 15   | Root exports         | 1     | Low                  |

**Total**: ~23 source files, ~15 commits, foundation for all subsequent plans.
