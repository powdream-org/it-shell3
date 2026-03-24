# Daemon Internal Architecture

- **Date**: 2026-03-23
- **Scope**: libitshell3 daemon internal module structure, event loop, state
  tree, and ghostty Terminal integration

---

## 1. Module Decomposition

libitshell3 is organized into 4 module groups with a diamond dependency graph.
`ghostty/` and `input/` are sibling modules that both depend on `core/`;
`server/` depends on all three.

### 1.1 Dependency Graph

```
      core/
     /    \
ghostty/  input/
     \    /
     server/
```

Dependencies point inward: `server/` depends on everything; `ghostty/` and
`input/` depend only on `core/`; `core/` depends on nothing. Circular
dependencies are prohibited.

### 1.2 Module Definitions

#### `core/` — Pure State Types

Zero dependencies on ghostty, OS, or protocol.

| Type            | Purpose                                                                                   |
| --------------- | ----------------------------------------------------------------------------------------- |
| `Session`       | Config, name, ImeEngine interface, preedit cache, focused pane, tree layout               |
| `SplitNodeData` | Binary split tree node (tagged union: `.leaf` = PaneSlot, `.split` = orientation + ratio) |
| `PaneId`        | `u32` opaque wire identifier (global monotonic, never reused)                             |
| `PaneSlot`      | `u8` session-local slot index (0..15) for fixed-size array operations                     |
| `MAX_PANES`     | Compile-time constant: 16 panes per session                                               |
| `ImeEngine`     | Vtable interface for input method engines                                                 |
| `KeyEvent`      | Key input event type consumed by IME routing                                              |
| `ImeResult`     | Result of IME processing (committed text, preedit, forward key)                           |

`core/` is unit-testable in isolation with zero external dependencies.

#### `ghostty/` — Thin Helper Functions

Depends on `core/` only. Contains helper functions (NOT wrapper types) for
ghostty's internal Zig APIs.

| Helper               | Wraps                                            | Purpose                                                      |
| -------------------- | ------------------------------------------------ | ------------------------------------------------------------ |
| Terminal lifecycle   | `Terminal.init(alloc, .{.cols, .rows})`          | Create headless Terminal instance                            |
| VT stream processing | `terminal.vtStream(bytes)`                       | Feed PTY output into terminal                                |
| RenderState snapshot | `RenderState.update(alloc, &terminal)`           | Capture terminal state for export                            |
| Cell data export     | `bulkExport(alloc, &render_state, &terminal)`    | Produce FlatCell[] for wire transfer                         |
| Key encoding         | `key_encode.encode(writer, event, opts)`         | Encode key events for PTY (stateless, pure function)         |
| Terminal mode query  | `Options.fromTerminal(&terminal)`                | Read DEC modes, Kitty flags                                  |
| Preedit injection    | `overlayPreedit(export_result, preedit, cursor)` | Overlay preedit cells post-export (~20 lines in vendor fork) |

**Why helper functions, not wrapper types**: ghostty's API is not stable.
Wrapper types would create a maintenance trap — every upstream API change would
require updating both the wrapper and the call site. Helper functions are a thin
layer that adds value (e.g., error mapping, parameter defaults) without creating
false abstraction. We have no second implementation of ghostty, so an
abstraction layer violates YAGNI.

#### `input/` — Key Routing Orchestration

Depends on `core/` only. No ghostty dependency.

**Scope**: The `input/` module handles Phase 0+1 of the 3-phase key processing
pipeline: shortcut interception (Phase 0), ImeEngine dispatch (Phase 1), focus
change handling (`handleIntraSessionFocusChange`), and input method switching
(`handleInputMethodSwitch`). Mouse events and paste operations bypass this
module entirely — they are handled directly in `server/`.

| Function                        | Phase | Purpose                                             |
| ------------------------------- | ----- | --------------------------------------------------- |
| `handleKeyEvent`                | 0 + 1 | Route key through shortcut check, then to ImeEngine |
| `handleIntraSessionFocusChange` | —     | Flush engine, clear preedit on old pane             |
| `handleInputMethodSwitch`       | 0     | Switch active input method                          |

`input/` depends on the `ImeEngine` interface type (defined in `core/`), not on
the concrete `HangulImeEngine` (in libitshell3-ime). This is dependency
inversion: `input/` code is testable with a `MockImeEngine` without libhangul.

##### 3-Phase Key Processing Pipeline

Every key event from a client passes through three sequential phases:

```mermaid
flowchart TD
    INPUT["Client sends:<br/>HID keycode + modifiers + shift"]
    INPUT --> P0_check

    subgraph P0["Phase 0: Global Shortcut Check (input/)"]
        P0_check{"Language switch<br/>or app-level shortcut?"}
    end

    P0_check -- "consumed" --> STOP["STOP"]
    P0_check -- "not consumed" --> P1_process

    subgraph P1["Phase 1: IME Engine (libitshell3-ime)"]
        P1_process["processKey(KeyEvent)"]
        P1_result(["ImeResult"])
        P1_process --> P1_result
    end

    P1_result --> P2_committed
    P1_result --> P2_preedit
    P1_result --> P2_fwd

    subgraph P2["Phase 2: ghostty Integration (server/)"]
        P2_committed["committed_text"] --> P2_write_utf8["write(pty_fd, utf8)"]
        P2_committed --> P2_encode_committed["key_encode.encode()"]
        P2_preedit["preedit_text"] --> P2_memcpy["@memcpy to session.preedit_buf<br/>overlay at export time"]
        P2_fwd["forward_key"] --> P2_encode["key_encode.encode(event, opts)"] --> P2_write_fwd["write(pty_fd, encoded)"]
    end
```

**Why IME runs before keybindings**: When the user presses Ctrl+C during Korean
composition (preedit = "하"), Phase 0 checks — Ctrl+C is not a language toggle.
Phase 1: engine detects Ctrl modifier, flushes "하", returns
`{ committed: "하", forward_key: Ctrl+C }`. Phase 2: committed text "하" is
written to PTY, then Ctrl+C is encoded via `key_encode.encode()` and written to
PTY. This ensures the user's in-progress composition is preserved before any
control key action.

For the internal `processKey()` decision algorithm (modifier handling, printable
key dispatch, libhangul composition), see `01-processkey-algorithm.md` in the
`libitshell3-ime` behavior docs.

Phase 0 and Phase 1 execute in `input/` (depends only on `core/`). Phase 2
executes in `server/` (depends on `ghostty/` for key encoding and preedit
overlay). See Section 1.3 for the Phase 2 placement rationale.

#### `server/` — Event Loop and I/O

Depends on `core/`, `ghostty/`, `input/`, libitshell3-ime, and
libitshell3-protocol.

| Component           | Purpose                                                                                      |
| ------------------- | -------------------------------------------------------------------------------------------- |
| Event loop          | kqueue-based, single-threaded (see Section 2)                                                |
| SessionEntry        | Server-side wrapper: Session (core/) + pane_slots + free_mask + dirty_mask (see Section 3.2) |
| Client manager      | Per-client state, connection lifecycle                                                       |
| Ring buffer         | Per-pane frame delivery with per-client cursors                                              |
| Frame coalescing    | Adaptive timer for batching frame updates                                                    |
| PTY I/O             | Read/write handlers for pane PTY file descriptors                                            |
| Phase 2 integration | Consume ImeResult: PTY writes, preedit cache update, key encoding                            |
| Pane struct         | Owns Terminal + RenderState + pty_fd + child_pid (see Section 3.3)                           |
| Startup/shutdown    | Daemon initialization and graceful teardown                                                  |

Socket setup is delegated to libitshell3-protocol's transport layer (Layer 4).

### 1.3 Phase 2 Placement

Phase 2 consumes `ImeResult` and performs:

- **I/O**: `write(pty_fd, committed_text)`, `write(pty_fd, encoded_key)`
- **ghostty API calls**: `key_encode.encode()`, `overlayPreedit()`
- **State mutation**: `@memcpy` preedit text to `session.preedit_buf`

Both I/O and ghostty dependencies belong in `server/`, not `input/`. The
`input/` module handles Phase 0 and Phase 1 only — pure routing logic that
depends solely on `core/` types.

### 1.4 Ring Buffer Placement

The ring buffer lives in `server/`, not in the protocol library or `core/`. The
ring buffer is a server-side application-level delivery optimization
(multi-client cursor management, writev scheduling) with no client-side
analogue. The protocol library provides transport-level I/O (Layer 4), but
application-level delivery strategies are the consumer's responsibility.

### 1.5 Pane Struct Placement and Fixed-Size Lookup

The Pane struct lives in `server/` because it owns both ghostty types (Terminal,
RenderState) and OS resources (pty_fd, child_pid). Placing it in `core/` would
violate the `core/ <- ghostty/` dependency rule.

A compile-time constant limits panes per session:

```zig
pub const MAX_PANES = 16;
pub const MAX_TREE_NODES = MAX_PANES * 2 - 1; // 31
```

The 16-pane limit is a UX-driven constraint, not a performance optimization. On
a 374x74 terminal, 16 panes at 93x18 is minimum viable; 32 panes at 93x9 is
unusable. The limit is enforced server-side via ErrorResponse when a client
requests a split that would exceed 16 panes.

Each session's pane slots are managed by `SessionEntry` (in `server/`), a
server-side wrapper around `Session` (see Section 3.2):

```zig
// server/session_entry.zig
pane_slots: [MAX_PANES]?Pane,  // by value, indexed by PaneSlot (0..15)
free_mask: u16,                 // bitmap of available slots
dirty_mask: u16,                // one bit per pane slot, set on PTY read
```

**Pane slot allocation**: `@ctz(free_mask)` gives the next free slot in one
instruction.

**Dirty tracking**: Set via `dirty_mask |= (1 << pane.slot_index)` on PTY read.
Iterate via `@ctz(dirty_mask)` (single instruction on x86 `TZCNT` and ARM64
`RBIT+CLZ`). Clear each bit after export: `dirty_mask &= dirty_mask - 1`.

**PaneId semantics**: PaneId on the wire is a global monotonic `u32`, never
reused within daemon lifetime. Internally, sessions use a session-local
`PaneSlot: u8` (0..15) for all fixed-size array operations. Wire-to-Pane lookup
uses per-session linear scan of `pane_slots` (at most 16 entries) — cold path
only. Hot paths (frame export, dirty iteration, PTY read) use slot indices
exclusively.

**Why global monotonic PaneId (not session-local 0..15) on the wire**:

1. **Pane-reuse race condition**: In async IPC, a client can have an in-flight
   message targeting a slot the server has already recycled. Global monotonic
   PaneId ensures stale messages target non-existent IDs and receive
   ErrorResponse.
2. **Protocol constraint leak**: Session-local PaneId (0..15) exposes the
   16-pane limit to wire semantics. Global monotonic u32 keeps the limit
   invisible to the protocol.
3. **Hot-path equivalence**: Both options have identical hot-path performance —
   all hot paths use slot indices, never PaneId.

`SessionManager` uses `HashMap(u32, *SessionEntry)` for sessions (dynamic count,
few instances — no fixed limit for sessions).

### 1.6 Inter-Library Dependencies

libitshell3 and libitshell3-protocol are separate libraries with a clean,
acyclic dependency relationship:

```
libitshell3-protocol  (standalone — depends only on Zig std; libssh2 added in Phase 5)
libitshell3-ime       (standalone — depends on libhangul)
libitshell3/core/     (standalone — no external deps)
libitshell3/ghostty/  (depends on core/, vendored ghostty)
libitshell3/input/    (depends on core/)
libitshell3/server/   (depends on core/, ghostty/, input/, libitshell3-ime, libitshell3-protocol)
```

**libitshell3-protocol does NOT import any libitshell3 types.** The protocol
library uses Zig primitive types (`u32`, `[]const u8`, etc.) for all message
fields. On the wire, `pane_id` and `session_id` are `u32` values in JSON
payloads — the protocol library reflects what the wire carries.

**`server/` maps between wire primitives and domain types.** Since `server/`
imports both `core/` and `libitshell3-protocol`, it is the natural boundary for
converting protocol message fields (e.g., `msg.pane_id: u32`) to domain types
(e.g., `core.PaneId`). This is a trivial one-line cast at each protocol handler.

**No shared types library is needed.** The types that might be shared
(`PaneId = u32`, session_id as `u32`) are trivial aliases. Extracting a
`libitshell3-types` library for two `u32` aliases would be over-engineering.

**libitshell3-protocol's external dependencies:**

- **v1**: Zig `std` only (posix sockets via `std.posix` for Layer 4 transport)
- **Phase 5**: `libssh2` added for SSH transport in Layer 4

### 1.7 Prior Art

- **tmux**: Separates pure state (`window.h`, `session.h`) from I/O (`tty.c`,
  `server-client.c`).
- **ghostty**: Separates terminal logic (`Terminal.zig`) from renderer
  (`Metal.zig`) and I/O (`Termio.zig`).

---

## 2. Event Loop Model

### 2.1 Decision

Single-threaded kqueue event loop (tmux model). No threads, no locks, no
mutexes.

### 2.2 Event Sources

All event types are handled in a single `kevent64()` call:

| Filter          | Source                  | Purpose                                                    |
| --------------- | ----------------------- | ---------------------------------------------------------- |
| `EVFILT_READ`   | PTY fds                 | Read shell output from pane child processes                |
| `EVFILT_READ`   | Socket listen fd        | Accept new client connections                              |
| `EVFILT_READ`   | Client conn fds         | Read client messages (key events, commands)                |
| `EVFILT_WRITE`  | Client conn fds         | Resume sending when socket becomes writable (after EAGAIN) |
| `EVFILT_TIMER`  | Coalescing timer        | Trigger frame export and delivery at adaptive intervals    |
| `EVFILT_TIMER`  | I-frame keyframe timer  | Periodic full-frame keyframes for state recovery           |
| `EVFILT_SIGNAL` | SIGTERM, SIGINT, SIGHUP | Graceful shutdown signals                                  |
| `EVFILT_SIGNAL` | SIGCHLD                 | Child process reaping                                      |

kqueue timers are kernel-managed, more efficient than userspace timer wheels.

### 2.3 Why Single-Threaded

**Performance**: `bulkExport()` is 22 us for 80x24, 217 us for 300x80. Even 10
panes at 60fps = 1.3% of a single core. Threading provides no measurable
benefit.

**Thread safety**: ghostty Terminal is NOT thread-safe. It uses internal arena
allocators and mutable page state. In normal ghostty, a shared mutex
synchronizes the IO thread and renderer thread. Our single-threaded design
eliminates this entirely.

**Correctness**: Single-threaded eliminates all concurrency hazards: no lock
ordering, no deadlocks, no data races on pane state, ImeEngine access, or ring
buffer writes. The event loop provides implicit serialization. The critical
runtime invariant — ImeResult must be consumed before the next engine call — is
naturally satisfied.

**Scalability**: tmux proves single-threaded scales to hundreds of panes with a
single libevent/kqueue loop.

### 2.4 Prior Art

- **tmux**: Single-threaded libevent loop, proven at scale with hundreds of
  sessions and panes.

### 2.5 Input Processing Priority

When the event loop dequeues multiple pending client messages in one iteration,
the server processes them in the following priority order. Higher-priority
messages are dispatched first, ensuring user-visible feedback (key echo, cursor
movement) is never starved by bulk transfers.

| Priority | Message type(s)          | Rationale                                         |
| -------- | ------------------------ | ------------------------------------------------- |
| 1        | KeyEvent, TextInput      | Affects what the user sees immediately (key echo) |
| 2        | MouseButton, MouseScroll | User interaction requiring prompt visual feedback |
| 3        | MouseMove                | Bulk; can be coalesced across pending messages    |
| 4        | PasteData                | Bulk transfer; latency-tolerant                   |
| 5        | FocusEvent               | Advisory; no immediate visual consequence         |

### 2.6 Input Flow Diagram

The end-to-end input flow from user keypress through daemon processing to client
rendering:

```mermaid
flowchart TD
    subgraph Client
        A["User presses key"]
        B["KeyEvent<br/>(JSON: HID keycode, mods, input_method)"]
        K["CellData → RenderState population"]
        L["ghostty rendering pipeline<br/>(font shaping, atlas, GPU buffers)"]
        M["Metal drawFrame()"]
    end

    subgraph Server
        D["Input Dispatcher"]
        E["libitshell3-ime<br/>(Layout Mapper + Composition Engine)"]
        F{"Preedit?"}
        G["Update preedit state"]
        H{"Commit?"}
        I["Write to PTY"]
        J1["libghostty-vt<br/>Terminal.vtStream()"]
        J2["RenderState.update()"]
    end

    A --> B
    B -- "Unix socket" --> D
    D --> E
    E --> F
    E --> H
    F -- "Yes" --> G
    H -- "Yes" --> I
    G --> J1
    I --> J1
    J1 --> J2
    J2 -- "FrameUpdate<br/>(binary cells + JSON metadata)" --> K
    K --> L
    L --> M
```

---

## 3. State Tree

### 3.1 Decision

Session = Tab merge. No intermediate Tab entity. Each Session directly owns an
array-based binary split tree (`[31]?SplitNodeData`). Pane slots (`[16]?Pane`)
are managed by `SessionEntry`, a server-side wrapper around Session (see Section
3.2). 16-pane-per-session limit (see Section 1.5).

### 3.2 Hierarchy

```mermaid
classDiagram
    class SessionManager {
        +HashMap~u32, *SessionEntry~ sessions
    }

    class SessionEntry {
        <<server/session_entry.zig>>
        +Session session
        +Pane?[16] pane_slots
        +u16 free_mask
        +u16 dirty_mask
        +u32 latest_client_id
    }

    class Session {
        <<core/session.zig>>
        +u32 session_id
        +[]const u8 name
        +ImeEngine ime_engine
        +[]const u8 active_input_method
        +[]const u8 active_keyboard_layout
        +SplitNodeData?[31] tree_nodes
        +PaneSlot? focused_pane
        +i64 creation_timestamp
        +[]const u8? current_preedit
        +u8[64] preedit_buf
        +u16? last_preedit_row
        +PreeditState preedit
    }

    class PreeditState {
        <<core/session.zig>>
        +u32? owner
        +u32 session_id
    }

    class SplitNodeData {
        <<tagged union in core/>>
        +PaneSlot leaf
        +Orientation orientation
        +f32 ratio
        Navigation: parent = i-1 /2, left = 2*i+1, right = 2*i+2
    }

    class Pane {
        <<server/pane.zig>>
        +u32 pane_id
        +u8 slot_index
        +posix.fd_t pty_fd
        +posix.pid_t child_pid
        +*ghostty.Terminal terminal
        +*ghostty.RenderState render_state
        +u16 cols
        +u16 rows
        +[]const u8 title
        +[]const u8 cwd
        +[]const u8 foreground_process
        +posix.pid_t foreground_pid
        +bool is_running
        +u8? exit_status
    }

    SessionManager "1" *-- "*" SessionEntry : sessions
    SessionEntry "1" *-- "1" Session : session
    SessionEntry "1" *-- "1..16" Pane : pane_slots[16]
    Session "1" *-- "1..31" SplitNodeData : tree_nodes[31]
    Session "1" *-- "1" PreeditState : preedit
```

**Tree node array vs pane slot array**: These are separate index spaces. Tree
node indices (0..30) identify positions in the `[31]?SplitNodeData` array (in
`Session`). Pane slot indices (0..15) identify positions in the `[16]?Pane`
array (in `SessionEntry`). Leaf nodes store pane slot indices. Tree compaction
(subtree relocation during split/close) moves tree nodes but does not change the
pane slot indices stored in leaf values. Pane slot indices are stable across
tree mutations.

**Tree mutation complexity**: Split and close operations require subtree
relocation within the tree node array. With max depth 4 and 31 nodes, this is
bounded at ~15 node copies per operation — trivially fast on cache-hot data (the
entire tree fits in L1 cache).

### 3.3 Type Definitions

```zig
// core/constants.zig
pub const MAX_PANES = 16;
pub const MAX_TREE_NODES = MAX_PANES * 2 - 1; // 31

pub const PaneId = u32;
pub const PaneSlot = u8; // 0..15, indexes into pane_slots array

// core/session.zig — pane_slots, free_mask, dirty_mask removed (now in SessionEntry)
pub const Session = struct {
    session_id: u32,
    name: []const u8,
    ime_engine: ImeEngine,
    active_input_method: []const u8,
    active_keyboard_layout: []const u8,
    tree_nodes: [MAX_TREE_NODES]?SplitNodeData, // 31 entries, root at index 0
    focused_pane: ?PaneSlot,
    creation_timestamp: i64,
    current_preedit: ?[]const u8,
    preedit_buf: [64]u8,
    last_preedit_row: ?u16,
    preedit: PreeditState,          // multi-client ownership tracking
};

// core/session.zig — multi-client preedit ownership (replaces PanePreeditState)
pub const PreeditState = struct {
    owner: ?u32,       // client_id of composing client, null = no active composition
    session_id: u32,   // monotonic counter for PreeditStart/Update/End/Sync wire messages
};

// server/session_entry.zig — server-side wrapper bundling Session with pane-slot management
const SessionEntry = struct {
    session: Session,
    pane_slots: [MAX_PANES]?Pane,  // by value, indexed by PaneSlot (0..15)
    free_mask: u16,                 // bitmap of available pane slots
    dirty_mask: u16,                // one bit per pane slot
    latest_client_id: u32,          // client_id of the most recently active client (KeyEvent/WindowResize);
                                    // used by the `latest` resize policy (doc04 §2.2); 0 = no active client
};

// core/split_node.zig
pub const SplitNodeData = union(enum) {
    leaf: PaneSlot,
    split: struct {
        orientation: enum { horizontal, vertical },
        ratio: f32,
    },
};

// server/pane.zig — stored by value in SessionEntry.pane_slots
pub const Pane = struct {
    pane_id: PaneId,
    slot_index: PaneSlot, // position in owning SessionEntry's pane_slots
    pty_fd: posix.fd_t,
    child_pid: posix.pid_t,
    terminal: *ghostty.Terminal,
    render_state: *ghostty.RenderState,
    cols: u16,
    rows: u16,
    // Pane metadata — tracked via terminal.vtStream() processing
    title: []const u8,              // OSC 0/2 title sequences
    cwd: []const u8,                // shell integration CWD (OSC 7)
    foreground_process: []const u8, // foreground process name
    foreground_pid: posix.pid_t,    // foreground process PID
    is_running: bool,               // false after child process exits
    exit_status: ?u8,               // set on process exit
    // Two-phase SIGCHLD model flags (see doc03 Section 3.2).
    // Both flags must be set before executePaneDestroyCascade() triggers.
    pane_exited: bool,              // set by SIGCHLD handler after waitpid()
    pty_eof: bool,                  // set by PTY read handler on EV_EOF
    // Silence detection — see doc04 §11 for semantics
    silence_subscriptions: BoundedArray(SilenceSubscription, MAX_SILENCE_SUBSCRIBERS),
    silence_deadline: ?i64,  // now + min(thresholds), null = disarmed
};
```

### 3.4 PTY Lifecycle

Each Pane owns a PTY master fd (`pty_fd`) and a child process (`child_pid`). The
daemon manages the full PTY lifecycle:

**Process exit (two-phase SIGCHLD handling)**: When a pane's child process
exits, the daemon uses a two-phase handling model: reap and mark the process in
the SIGCHLD handler, then drain remaining PTY output before destroying the pane.
This ensures the user sees the child's final output before the pane disappears.
See Section 3.2 of the lifecycle doc (doc03) for the authoritative
specification, including the dual-flag model (`pane_exited` + `pty_eof`), event
processing priority, and the complete `executePaneDestroyCascade()` procedure.

When a pane is explicitly closed via `ClosePaneRequest`, the daemon sends SIGHUP
to the child process via the PTY. If the `force` flag is set and the process
does not terminate within a timeout, SIGKILL is sent.

When a session is destroyed (`DestroySessionRequest`), all panes are closed —
all child processes receive SIGHUP, all PTY fds are freed.

**Resize (TIOCSWINSZ + debounce)**: When pane dimensions change (due to window
resize, split adjustment, or client attach/detach), the daemon issues
`ioctl(pane.pty_fd, TIOCSWINSZ, &new_size)` to update the PTY dimensions. This
triggers SIGWINCH in the child process.

Resize is debounced at **250ms per pane**, matching tmux's approach. This
prevents SIGWINCH storms during rapid resize drags. Exception: the FIRST resize
after session creation or client attach fires immediately (no debounce).

During the debounce window and for 500ms after the debounce fires, the server
MUST NOT transition the pane's coalescing tier to Idle — the PTY application is
processing SIGWINCH and may briefly pause output, which is not true idleness.

### 3.5 Layout Enforcement

The server enforces the 16-pane limit (see Section 1.5) by rejecting
`SplitPaneRequest` with `ErrorResponse` status `PANE_LIMIT_EXCEEDED` when a
split would exceed `MAX_PANES`. This is validated server-side before the split
operation begins.

The tree depth is bounded by the pane limit: with `MAX_PANES = 16` and a binary
split tree, the maximum depth is 4 (a perfectly unbalanced tree of 16 panes has
depth 15, but such extreme imbalance requires 15 consecutive splits in the same
direction — practical layouts are much shallower). The `[31]?SplitNodeData`
array bounds the tree absolutely.

### 3.6 Pane Metadata Tracking

The daemon tracks per-pane metadata derived from terminal output and process
state. Changes are detected during `terminal.vtStream()` processing and SIGCHLD
handling, then broadcast to attached clients via `PaneMetadataChanged`.

| Metadata                     | Source                                              | Update mechanism                                                                   |
| ---------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `title`                      | OSC 0/2 escape sequences                            | ghostty's VT parser extracts title from escape sequences during `vtStream()`       |
| `cwd`                        | OSC 7 (shell integration)                           | Shell-integration-aware shells emit CWD via OSC 7; ghostty's VT parser extracts it |
| `foreground_process`         | `/proc/<pid>/cwd` polling or `kqueue` `EVFILT_PROC` | Daemon polls or monitors the foreground process group                              |
| `foreground_pid`             | Process group tracking                              | Updated when foreground process changes                                            |
| `is_running` / `exit_status` | SIGCHLD + `waitpid()`                               | Daemon reaps child and records exit status                                         |

Only changed fields are sent in `PaneMetadataChanged` — clients detect changes
by checking which fields are present in the JSON payload.

**Relationship between `PaneMetadataChanged` and `ProcessExited`**: These are
two complementary notification channels that serve different purposes and
operate on different subscription models (doc04 §9.1 and §9.2):

- **`PaneMetadataChanged`** (always-sent, §9.1): A field-update notification.
  When the process exits, the daemon sets `pane.is_running = false` and
  `pane.exit_status`, then sends `PaneMetadataChanged` with those updated field
  values. Every attached client receives this automatically regardless of any
  subscription state. The notification's purpose is to keep clients' cached pane
  state in sync with the daemon's pane state — the same mechanism used for title
  changes, CWD updates, and foreground-process changes.

- **`ProcessExited`** (opt-in, §9.2): An event notification. Clients that have
  subscribed via `Subscribe` (0x0810) receive `ProcessExited` in addition to the
  always-sent `PaneMetadataChanged`. `ProcessExited` provides an explicit, typed
  signal for process-exit events, enabling clients that care about lifecycle
  events (e.g., showing exit-status banners, playing a sound) to react without
  inspecting every `PaneMetadataChanged` payload.

On process exit, **both** fire: `PaneMetadataChanged` (always) carries the
updated `is_running` and `exit_status` field values; `ProcessExited` (if
subscribed) signals the event. Clients that only need current pane state use the
metadata update; clients that want event-driven lifecycle notifications
subscribe to `ProcessExited`.

### 3.7 Session = Tab Merge Rationale

- Session:Tab is 1:1 in v1. An intermediate Tab entity with no distinct behavior
  violates YAGNI. When Phase 3 needs multiple tabs per session, Tab can be
  introduced as an intermediate node between Session and SplitNode.
- Per-session ImeEngine maps cleanly: one engine per "thing the user switches
  between."
- The protocol already treats Sessions as the unit clients attach to. There is
  no Tab entity in the protocol — "tabs" are a client UI concept mapped to
  Sessions.

### 3.8 Preedit Cache

Session caches the current preedit text (`current_preedit: ?[]const u8`, backed
by a 64-byte `preedit_buf`) from the last `ImeResult` for use at export time.

**Why caching is necessary**: The ImeEngine vtable has no "get current preedit"
method. Preedit text is only available via `ImeResult` from mutating calls. Per
IME contract v0.8 Section 6, the engine's internal buffers are invalidated on
the next mutating call.

**Cache update flow**: When `ImeResult.preedit_changed == true`, the session
copies the preedit text into `preedit_buf` via `@memcpy` and points
`current_preedit` at the copied slice. `overlayPreedit()` reads from
`session.current_preedit`, never from the engine directly.

**Lifetime semantics**: The engine's buffer is ground truth at `processKey()`
time; the Session's copy is ground truth at export time. Different lifetimes,
different purposes — this is a necessary cache, not a DRY violation.

> **Normative note — Authoritative preedit source**: `Session.current_preedit`
> is the single authoritative source of preedit text for both rendering
> (`overlayPreedit()` at export time) and ownership operations (commit to PTY on
> focus transfer, client disconnect, or ownership transition per doc04 §6.2).
> All consumers — PreeditUpdate wire messages, commit-to-PTY operations, and
> preedit overlay rendering — read from `session.current_preedit`. There is no
> second copy of preedit text; the `PreeditState` struct (doc04 §6.1) tracks
> multi-client ownership metadata only, not preedit content.

### 3.9 Dirty Tracking for Preedit

`last_preedit_row: ?u16` tracks the cursor row where preedit was last overlaid.
When preedit changes or clears, the previous row must be marked dirty in the
next export so that the old preedit cells are repainted with the underlying
terminal content. Without this tracking, clearing preedit would leave stale
composed characters on screen until the next terminal output touched that row.

### 3.10 Prior Art

- **Array-based binary tree (heap data structure)**: Fixed-size tree with index
  arithmetic — standard CS data structure used for the `[31]?SplitNodeData`
  layout.
- **cmux**: Uses binary split tree (Bonsplit library).
- **ghostty**: Split API uses the same model.
- **tmux**: `layout_cell` tree is conceptually identical.
- **tmux**: 250ms TIOCSWINSZ debounce — battle-tested approach for preventing
  SIGWINCH storms.

### 3.11 Pane Navigation Algorithm

Pure geometric function in `core/navigation.zig` for directional pane
navigation. Depends only on `core/` types (`SplitNodeData`, `PaneSlot`,
`MAX_TREE_NODES`) and integer parameters — no ghostty, OS, or protocol
dependencies. Fully unit-testable in isolation with synthetic tree
configurations.

#### Function Signature

```zig
// core/navigation.zig
pub const Direction = enum { up, down, left, right };

pub fn findPaneInDirection(
    tree_nodes: *const [MAX_TREE_NODES]?SplitNodeData,
    total_cols: u16,
    total_rows: u16,
    focused: PaneSlot,
    direction: Direction,
) ?PaneSlot
```

Returns `null` only for single-pane sessions (no navigation possible). In
multi-pane sessions, wrap-around guarantees a non-null result.

#### Algorithm: Edge Adjacency with Overlap Filtering

```
findPaneInDirection(tree_nodes, total_cols, total_rows, focused, direction):

    // Step 1: Compute geometric rectangles
    //   Walk tree_nodes, recursively accumulate split ratios to produce
    //   (x, y, w, h) for each leaf node. Stack-allocated [MAX_PANES]Rect.
    //   With MAX_PANES=16, this is 16 multiply-accumulate operations —
    //   trivially fast, entirely in L1 cache.
    rects = computeLeafRects(tree_nodes, total_cols, total_rows)
    focused_rect = rects[focused]

    // Step 2: Direction filter
    //   Collect candidate panes whose adjacent edge is in the target direction.
    //   up:    candidate.bottom_edge <= focused_rect.top_edge
    //   down:  candidate.top_edge   >= focused_rect.bottom_edge
    //   left:  candidate.right_edge <= focused_rect.left_edge
    //   right: candidate.left_edge  >= focused_rect.right_edge
    candidates = filter by direction adjacency

    // Step 3: Overlap filter
    //   Keep only candidates whose perpendicular span overlaps with focused.
    //   For up/down: candidate [x, x+w) must overlap focused [x, x+w)
    //   For left/right: candidate [y, y+h) must overlap focused [y, y+h)
    //   This eliminates diagonally offset panes with no visual adjacency.
    candidates = filter by perpendicular overlap

    // Step 4: Nearest selection with MRU tie-break
    //   Select the candidate with the shortest edge distance (distance
    //   between focused edge and candidate's adjacent edge).
    //   Tie-break: prefer the most recently focused pane (MRU).
    if candidates is not empty:
        return nearest candidate (MRU on tie)

    // Step 5: Wrap-around
    //   No candidate in the target direction — search the opposite direction
    //   for the furthest pane with perpendicular overlap.
    //   Example: navigating up from the topmost pane selects the bottommost
    //   pane that has horizontal overlap.
    return furthest pane in opposite direction with overlap, or null
```

#### Example: 4-Pane Layout

```
+─────────────────+─────────────────+
│                 │                 │
│     Pane 0      │     Pane 1      │
│   (focused)     │                 │
│                 │                 │
+─────────────────+─────────────────+
│                 │                 │
│     Pane 2      │     Pane 3      │
│                 │                 │
│                 │                 │
+─────────────────+─────────────────+

Navigation from Pane 0 (focused):
  → right: Pane 1  (right edge adjacent, vertical overlap)
  → down:  Pane 2  (bottom edge adjacent, horizontal overlap)
  → left:  Pane 1  (wrap-around: furthest right with vertical overlap)
  → up:    Pane 2  (wrap-around: furthest down with horizontal overlap)
```

#### Design Decisions

**Wrap-around is always enabled (non-configurable in v1)**. tmux wraps, zellij
wraps — no terminal multiplexer provides a "no wrap" option. Adding
configurability would introduce a settings surface (per-session? global?
client-settable?) with no known user requirement. Deferred to post-v1 if
requested. Adding a `wrap: bool` parameter later is a trivial one-line change.

**No geometry caching in v1**. Recomputing 16 rectangles per
`NavigatePaneRequest` is trivially fast (bounded O(n) where n <= 16, cache-hot
data). Caching adds invalidation complexity (must invalidate on split, close,
resize) for no measurable benefit.

#### Integration

**Dual use**: `findPaneInDirection()` is used by both:

1. **`NavigatePaneRequest` handler** — explicit directional navigation triggered
   by client key binding.
2. **Pane-close focus transfer** (CTR-18 `executePaneDestroyCascade()` step 10a)
   — implicit "nearest neighbor after close" to select the new focused pane.

Both paths use the same geometric computation from `core/navigation.zig`.

**Caller responsibility**: The caller in `server/` MUST call
`handleIntraSessionFocusChange()` (defined in `input/`) before updating
`session.focused_pane`. This flushes any active IME composition to the old
pane's PTY. The navigation algorithm returns only a `PaneSlot` — all side
effects (IME flush, focus update, notifications) are the caller's
responsibility.

**Protocol ordering**: `NavigatePaneResponse` is sent before `LayoutChanged`
notification, per the standard response-before-notification rule defined in the
protocol docs.

---

## 4. ghostty Terminal Instance Management

### 4.1 Decision

Headless Terminal — no Surface, no App, no embedded apprt. The daemon uses
ghostty's internal Zig APIs exclusively.

This was validated by PoC 06 (headless Terminal extraction), PoC 07 (bulkExport
benchmark at 22 us/frame for 80x24), and PoC 08 (importFlatCells + GPU rendering
on client).

### 4.2 API Surface

The daemon uses the following ghostty internal Zig APIs:

| Operation             | API                                              | Notes                                                                |
| --------------------- | ------------------------------------------------ | -------------------------------------------------------------------- |
| Terminal lifecycle    | `Terminal.init(alloc, .{.cols, .rows})`          | No Surface, no App (PoC 06 validated)                                |
| PTY output processing | `terminal.vtStream(bytes)`                       | Zero Surface dependency                                              |
| RenderState snapshot  | `RenderState.update(alloc, &terminal)`           | Captures terminal state                                              |
| Cell data export      | `bulkExport(alloc, &render_state, &terminal)`    | Produces FlatCell[] (16 bytes each, C-ABI compatible, SIMD-friendly) |
| Key encoding          | `key_encode.encode(writer, event, opts)`         | Pure function, no Surface, stateless                                 |
| Terminal mode query   | `Options.fromTerminal(&terminal)`                | Reads DEC modes, Kitty keyboard flags                                |
| Preedit injection     | `overlayPreedit(export_result, preedit, cursor)` | ~20 lines in vendor fork (render_export.zig)                         |

### 4.3 Key Input Path

When the daemon receives a key event from a client, the IME routing pipeline
(Phase 0 -> 1 -> 2) produces an `ImeResult`. Phase 2 in `server/` consumes it:

| ImeResult field  | Action                                                                                     | API                                                              |
| ---------------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| `committed_text` | Write UTF-8 directly to PTY                                                                | `write(pty_fd, text)` (v1 legacy mode)                           |
| `forward_key`    | Encode key and write to PTY                                                                | `key_encode.encode()` + `write(pty_fd, encoded)`                 |
| `preedit_text`   | Copy to `session.preedit_buf` via `@memcpy` when `preedit_changed`; overlay at export time | `overlayPreedit(export_result, session.current_preedit, cursor)` |

**No press+release pairs needed**: Surface-based terminals require press+release
pairs for `ghostty_surface_key()` because Surface tracks key state internally.
Since we bypass Surface and use `key_encode.encode()` directly (stateless), no
release events are needed in v1 legacy mode. For future Kitty protocol support,
release events would go through the encoder.

#### ImeResult → ghostty API Mapping (Phase 2 Detail)

The following pseudocode shows the complete Phase 2 consumption of `ImeResult`
in `server/`. The engine is session-scoped — `entry.session.ime_engine` holds
the single shared engine. The server tracks `focused_pane` (on `Session`) and
directs output to that pane's PTY. Pane slot management (`pane_slots`,
`dirty_mask`, `free_mask`) is on `SessionEntry`.

```zig
fn handleKeyEventPhase2(entry: *SessionEntry, focused_pane: *Pane, result: ImeResult) void {
    // 1. Committed text → write directly to PTY
    //    For committed text, the key encoder is NOT used — the text is
    //    already final UTF-8 from the IME engine.
    if (result.committed_text) |text| {
        _ = posix.write(focused_pane.pty_fd, text) catch |err| {
            // Handle write error (broken pipe = process exited)
        };
    }

    // 2. Preedit update → cache for export-time overlay
    //    IMPORTANT: preedit is NOT written to the PTY. It is overlaid
    //    onto the exported FlatCell[] at frame generation time.
    if (result.preedit_changed) {
        if (result.preedit_text) |text| {
            @memcpy(entry.session.preedit_buf[0..text.len], text);
            entry.session.current_preedit = entry.session.preedit_buf[0..text.len];
        } else {
            entry.session.current_preedit = null;
        }
        // Mark dirty for preedit overlay change (dirty_mask is on SessionEntry)
        entry.dirty_mask |= (@as(u16, 1) << focused_pane.slot_index);
    }

    // 3. Forward key → encode via ghostty key encoder and write to PTY
    //    For forwarded keys, the key encoder is CRITICAL — it produces
    //    the correct escape sequences (Ctrl+C → 0x03, arrows → CSI, etc.)
    if (result.forward_key) |fwd| {
        var buf: [128]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        const opts = ghostty.Options.fromTerminal(focused_pane.terminal);
        key_encode.encode(stream.writer(), mapToKeyEvent(fwd), opts) catch {};
        const encoded = stream.getWritten();
        if (encoded.len > 0) {
            _ = posix.write(focused_pane.pty_fd, encoded) catch {};
        }
    }
}
```

**Keycode criticality by event type**:

| Event Type                      | Keycode Impact                                                                   |
| ------------------------------- | -------------------------------------------------------------------------------- |
| Committed text                  | **Not used** — text is written directly to PTY as UTF-8                          |
| Forwarded key (control/special) | **Critical** — `key_encode.encode()` uses keycode for escape sequence generation |
| Language switch flush           | **Not applicable** — committed text only, no forward key                         |
| Intra-session pane switch flush | **Not applicable** — committed text only, no forward key                         |

**Intra-session pane focus change**: When focus moves from pane A to pane B
within the same session, the server flushes the engine and routes the result to
pane A before switching focus:

```zig
fn handleIntraSessionFocusChange(entry: *SessionEntry, pane_a: *Pane, pane_b: *Pane) void {
    // 1. Flush composition — committed text goes to pane A's PTY
    const result = entry.session.ime_engine.flush();

    // 2. Consume committed text immediately
    if (result.committed_text) |text| {
        _ = posix.write(pane_a.pty_fd, text) catch {};
    }

    // 3. Clear preedit cache
    if (result.preedit_changed) {
        entry.session.current_preedit = null;
        entry.dirty_mask |= (@as(u16, 1) << pane_a.slot_index);
    }

    // 4. Send PreeditEnd(pane=A, reason="focus_changed") to all clients
    sendPreeditEnd(pane_a, "focus_changed");

    // 5. Clear preedit ownership and advance session_id (doc04 §8.1 steps 6-7)
    entry.session.preedit.session_id += 1;
    entry.session.preedit.owner = null;

    // 6. Update focused pane — subsequent results route to pane B
    entry.session.focused_pane = pane_b.slot_index;
}
```

**Input method switch**: When `setActiveInputMethod()` returns committed text
from flushing, it follows the same PTY write path. The committed text is written
directly to the focused pane's PTY.

#### NEVER Use `ghostty_surface_text()` for IME Output

`ghostty_surface_text()` is ghostty's **clipboard paste** API. It wraps text in
bracketed paste markers (`\e[200~...\e[201~`) when bracketed paste mode is
active. Using it for IME committed text causes the **Korean doubling bug**
discovered in the it-shell v1 project:

```
User types: 한글
ghostty_surface_text("한") → \e[200~한\e[201~
ghostty_surface_text("글") → \e[200~글\e[201~
Display: 하하한한구글글  ← DOUBLED
```

All IME committed text MUST go through `write(pty_fd, text)` (v1 legacy mode) or
`key_encode.encode()` for forwarded keys. Neither path uses bracketed paste.

#### Example: Typing Korean "한"

The following walkthrough shows how the daemon's IME processing pipeline handles
Korean Hangul composition through the 3-phase key processing pipeline. The
client sends identical `KeyEvent` messages regardless of whether composition is
active — the server's IME engine tracks composition state internally.

```
1. User presses 'H' key (HID 0x0B), input_method=korean_2set
   Client sends: KeyEvent {"keycode": 11, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Phase 0: not a shortcut — pass through
   Phase 1: engine.processKey() maps H → ㅎ, enters composing state
            ImeResult { preedit_text: "ㅎ", preedit_changed: true }
   Phase 2: @memcpy "ㅎ" → session.preedit_buf, mark pane dirty
            Next frame export: overlayPreedit() injects "ㅎ" at cursor

2. User presses 'A' key (HID 0x04)
   Client sends: KeyEvent {"keycode": 4, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Phase 1: engine.processKey() maps A → ㅏ, composes ㅎ+ㅏ=하
            ImeResult { preedit_text: "하", preedit_changed: true }
   Phase 2: @memcpy "하" → session.preedit_buf, mark pane dirty
            Next frame export: overlayPreedit() injects "하" at cursor

3. User presses 'N' key (HID 0x11)
   Client sends: KeyEvent {"keycode": 17, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Phase 1: engine.processKey() maps N → ㄴ, composes 하+ㄴ=한
            ImeResult { preedit_text: "한", preedit_changed: true }
   Phase 2: @memcpy "한" → session.preedit_buf, mark pane dirty
            Next frame export: overlayPreedit() injects "한" at cursor

4. User presses Space (HID 0x2C), commits composition
   Client sends: KeyEvent {"keycode": 44, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Phase 1: engine.processKey() commits "한", clears composition
            ImeResult { committed_text: "한", preedit_text: null, preedit_changed: true }
   Phase 2: write(pty_fd, "한") — committed text to PTY
            session.current_preedit = null, mark pane dirty
            Next frame export: overlayPreedit() skipped (no preedit)
            Terminal shows "한" from PTY output via vtStream()
```

### 4.4 Preedit Overlay Mechanism

Preedit lives on `renderer.State.preedit` (State.zig:27), NOT on
`terminal.RenderState`. In normal ghostty, the renderer clones preedit during
the critical section and applies it during `rebuildCells()`.

Since we are headless (no Surface, no renderer.State), we overlay preedit cells
post-`bulkExport()` via `overlayPreedit()` in render_export.zig. The function:

1. Takes ExportResult + preedit codepoints + cursor position
2. Overwrites FlatCells at the cursor position with preedit character data
3. Marks affected rows dirty in the bitmap

This is ~20 lines in our vendor fork, self-contained and testable in isolation.

**Explicit preedit clearing required**: When `preedit_changed == true` and
`preedit_text == null` (composition ended), the daemon MUST set
`session.current_preedit = null` and mark the pane dirty. At the next frame
export, `overlayPreedit()` is skipped (no preedit to overlay), and the
previously preedit-overlaid cells are repainted with the underlying terminal
content from the I/P-frame. The `last_preedit_row` tracking (Section 3.9)
ensures the correct row is marked dirty.

Failure to clear preedit state leaves stale composed characters on screen after
composition ends. This corresponds to the IME contract's rule that
`ghostty_surface_preedit(null, 0)` must be called on preedit end — in our
headless architecture, the equivalent is clearing `session.current_preedit` and
marking dirty.

### 4.5 Frame Export Pipeline

The complete export pipeline for a single pane:

```mermaid
flowchart TD
    S1["terminal.vtStream(pty_bytes)<br/>Process PTY output"]
    S2["RenderState.update(alloc, &terminal)<br/>Snapshot terminal state"]
    S3["bulkExport(alloc, &render_state, &terminal)<br/>Produce FlatCell[]"]
    S4["overlayPreedit(export_result, session.current_preedit, cursor)<br/>Inject preedit"]
    S5["serialize FrameUpdate → ring buffer<br/>Ready for client delivery"]
    S6["conn.sendv(iovecs)<br/>Zero-copy to socket"]

    S1 --> S2 --> S3 --> S4 --> S5 --> S6
```

**Frame suppression for undersized panes**: The server MUST NOT generate
`FrameUpdate` for panes with `cols < 2` or `rows < 1`. This occurs during resize
animations or aggressive pane splitting. When dimensions fall below these
minimums:

- The `bulkExport()` step is skipped entirely for that pane.
- The PTY continues operating normally — `TIOCSWINSZ` reflects the actual
  dimensions, I/O continues. Only the rendering pipeline is suppressed.
- Applications in the PTY (e.g., vim) receive the actual dimensions and may
  adapt their output.
- Pane liveness is maintained via the session/pane management protocol — the
  client knows the pane exists from `CreatePaneResponse` and layout state.
- When dimensions return to valid range, normal frame generation resumes.

### 4.6 Why Headless (No Surface)

- The IME contract v0.7 Phase 1/Phase 2 distinction was written before the
  headless decision. Phase 1 (`ghostty_surface_key()`) requires a Surface we
  don't have. Using `key_encode.encode()` from day one is the only viable path.
- The IME contract v0.7 Section 5 code examples should be understood as logical
  pseudocode describing the data flow (WHAT). This daemon spec specifies the API
  calls (HOW).
- Design principle A1 ("preedit is cell data") remains valid: preedit IS cell
  data on the wire; only the injection mechanism differs from normal ghostty.

### 4.7 Prior Art

- **PoC 06**: Headless Terminal extraction — proved Terminal works without
  Surface/App.
- **PoC 07**: bulkExport benchmark — 22 us for 80x24, 217 us for 300x80.
- **PoC 08**: importFlatCells + rebuildCells + Metal drawFrame — full GPU
  pipeline on client.

---

## 5. End-to-End Data Flow

### 5.1 Key Input Data Flow

The following shows the complete data path for a key input event, tying together
module decomposition (Section 1), event loop (Section 2), ghostty APIs (Section
4), and the protocol/IME integration defined in companion documents.

```mermaid
sequenceDiagram
    participant C as Client App
    participant S as Daemon (server/)
    participant I as input/
    participant E as libitshell3-ime
    participant G as ghostty/
    participant P as PTY Child

    Note over C: User presses key
    C->>S: KeyEvent (Unix socket)
    Note over S: EVFILT_READ on conn.fd<br/>conn.recv() → MessageReader.feed()<br/>→ KeyEvent parsed

    S->>I: Phase 0: shortcut check
    alt Language toggle
        I->>E: engine.setActiveInputMethod()
        Note over I: Consumed — STOP
    else Daemon shortcut
        Note over I: Handled — STOP
    else Normal key
        I->>E: Phase 1: engine.processKey(key_event)
        E-->>I: ImeResult
        I-->>S: ImeResult
    end

    Note over S: Phase 2: consume ImeResult

    opt committed_text present
        S->>P: write(pty_fd, utf8)
    end
    opt preedit_text changed
        Note over S: @memcpy → session.preedit_buf<br/>update session.current_preedit
    end
    opt forward_key present
        S->>G: key_encode.encode(event, opts)
        G-->>S: encoded bytes
        S->>P: write(pty_fd, encoded)
    end

    P-->>S: Shell output (PTY)
    Note over S: EVFILT_READ on pty_fd

    S->>G: terminal.vtStream(bytes)
    Note over S: mark pane dirty

    Note over S: EVFILT_TIMER (coalescing)
    S->>G: RenderState.update()
    S->>G: bulkExport()
    G-->>S: ExportResult (FlatCell[])
    S->>G: overlayPreedit(session.current_preedit)
    Note over S: serialize FrameUpdate<br/>to ring buffer

    Note over S: EVFILT_WRITE on conn.fd
    S->>C: conn.sendv() → FrameUpdate

    Note over C: importFlatCells()<br/>→ rebuildCells()<br/>→ Metal drawFrame()<br/>→ Screen update
```

### 5.2 Mouse Event Data Flow

Mouse tracking is only active when the terminal's DEC mode state has mouse
reporting enabled (determined by `Options.fromTerminal()`).

**MouseButton** events trigger a preedit flush before forwarding to the
terminal. If the session has an active preedit composition
(`session.preedit.owner != null`), the daemon commits the preedit via the doc04
§8.1 flush sequence, then processes the mouse button event. This ensures that
clicking (e.g., to reposition the cursor) does not silently discard in-progress
composition.

**MouseScroll** and **MouseMove** events have no IME involvement — they are
forwarded directly to the terminal without a preedit check.

```mermaid
sequenceDiagram
    participant C as Client App
    participant S as Daemon (server/)
    participant IME as ImeEngine
    participant P as PTY Child

    C->>S: MouseButton (Unix socket)
    Note over S: EVFILT_READ on conn.fd
    alt session.preedit.owner != null
        S->>IME: engine.flush()
        IME-->>S: ImeResult (committed_text)
        S->>P: write(pty_fd, committed_text)
        Note over S: Send PreeditEnd to clients<br/>Clear session.preedit.owner
    end
    Note over S: Check terminal DEC mouse mode
    S->>P: terminal.mousePress(button, coords)

    Note right of C: MouseScroll / MouseMove
    C->>S: MouseScroll or MouseMove (Unix socket)
    Note over S: EVFILT_READ on conn.fd<br/>Check terminal DEC mouse mode<br/>(no preedit check)
    S->>P: terminal.mouseScroll() / terminal.mousePos()
```

---

## 6. Preedit / RenderState Validity (Owner Q3)

### 6.1 Decision

Design principle A1 ("preedit is cell data") is VALID. No protocol or IME
contract changes are needed.

### 6.2 The Fact

Preedit lives on `renderer.State.preedit` (State.zig:27), NOT on
`terminal.RenderState`. In normal ghostty, the renderer clones preedit during
the critical section and applies it during `rebuildCells()`.

### 6.3 Our Approach

In headless mode (no Surface, no renderer.State), the daemon overlays preedit
cells during the export phase via `overlayPreedit()` in render_export.zig (~20
lines in vendor fork).

### 6.4 Why A1 Holds

From the protocol's perspective, preedit IS cell data — it arrives at the client
as ordinary FlatCells in FrameUpdate. The client never knows or cares which
cells are preedit. The injection mechanism (`overlayPreedit` vs
`ghostty_surface_preedit`) is a server-side implementation detail invisible to
the wire.

---

## 7. Ring Buffer Architecture

The daemon uses a shared per-pane ring buffer for frame delivery to clients.
This section defines the ring buffer's data structure, sizing, cursor model, and
interaction with the frame export pipeline. For ring buffer POLICIES (recovery
procedures, ContinuePane cursor reset, coalescing tier behavior), see the
runtime policies doc (doc04).

### 7.1 Per-Pane Shared Ring Buffer

Each pane owns a single ring buffer (default 2 MB, server-configurable). The
server serializes each frame (I-frame or P-frame) once into the ring. Per-client
read cursors track each client's delivery position within the ring.

**Key properties**:

- **O(1) frame serialization**: Each frame is written to the ring exactly once,
  regardless of how many clients are attached.
- **O(1) memory per frame**: Frame data is not duplicated per client. All
  clients read from the same ring at their own cursor positions.
- **Shared data, independent cursors**: Clients at different coalescing tiers
  receive different subsets of frames from the same sequence, but each frame's
  content is identical regardless of which client receives it.

**Ring buffer placement**: The ring buffer lives in `server/` (see Section 1.4)
— it is a server-side application-level delivery optimization with no
client-side analogue.

### 7.2 Per-Pane Dirty Tracking

The server maintains a single dirty bitmap per pane (the `dirty_mask` field on
`SessionEntry`, see Section 1.5). Frame data (I-frames and P-frames) is
serialized once per pane per frame interval and written to the shared per-pane
ring buffer. All clients viewing the same pane receive identical frame data from
the ring buffer.

### 7.3 Two-Channel Socket Write Priority

The server maintains two per-client output channels with strict priority
ordering:

| Priority | Channel              | Content                                                        |
| -------- | -------------------- | -------------------------------------------------------------- |
| 1        | Direct message queue | Control messages, PreeditSync, PreeditUpdate, PreeditEnd, etc. |
| 2        | Shared ring buffer   | FrameUpdate (I-frames and P-frames)                            |

When a socket becomes writable (`EVFILT_WRITE`), the server drains the direct
queue first, then writes ring buffer frames. This guarantees that context
messages (e.g., `PreeditSync`, `PreeditUpdate`, `PreeditEnd`) always arrive at
the client before the `FrameUpdate` that reflects the same state change —
enabling the client to interpret cell data with correct composition context.

### 7.4 I-Frame Scheduling Algorithm

I-frames (keyframes) are produced periodically for state recovery:

- **Default interval**: 1 second (configurable 0.5–5 seconds via server
  configuration).
- **No-op when unchanged**: When the I-frame timer fires and the pane has no
  changes since the last I-frame, no frame is written to the ring — the most
  recent I-frame already in the ring provides correct state for any seeking
  client.
- **Full state on change**: When the timer fires and changes exist, the server
  writes `frame_type=1` (I-frame) containing all rows.
- **Timer independence**: The I-frame timer fires at a fixed interval regardless
  of PTY throughput or coalescing tier state.

### 7.5 Preedit Delivery Path

All frames, including those containing preedit cell data, go through the ring
buffer. There are no bypass paths for preedit content. Coalescing Tier 0
(Preedit tier, immediate flush at 0ms) ensures preedit-containing frames are
written to the ring immediately upon keystroke, maintaining <33ms preedit
latency over Unix socket.

The dedicated preedit protocol messages (0x0400–0x0405) are sent separately via
the direct message queue (priority 1, outside the ring buffer). During
resync/recovery, `PreeditSync` is enqueued in the direct message queue, arriving
BEFORE the I-frame from the ring. This follows the "context before content"
principle — the client processes `PreeditSync` first (records composition
metadata), then processes the I-frame (renders the grid including preedit cells
with full context).

### 7.6 Multi-Client Ring Read

All clients attached to a session receive `FrameUpdate` messages for all panes
in that session from the shared per-pane ring buffer — not just the focused
pane. Each client reads from the ring at its own cursor position via
per-(client, pane) coalescing tiers. For coalescing tier definitions and
tier-transition policies, see the runtime policies doc (doc04).
