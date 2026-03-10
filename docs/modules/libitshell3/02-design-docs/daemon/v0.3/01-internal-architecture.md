# Daemon Internal Architecture

**Status**: Draft v0.2
**Date**: 2026-03-10
**Scope**: libitshell3 daemon internal module structure, event loop, state tree, and ghostty Terminal integration
**Source resolutions**: R1 (Module Decomposition), R2 (Event Loop Model), R3 (State Tree), R4 (ghostty Terminal Instance Management), Owner Q3 (Preedit/RenderState Validity)
**v0.2 changes**: Applied v0.2 review note resolutions R1 (16-pane limit, fixed-size data structures), R2 (ime/ -> input/ rename), R3 (protocol scope fix)

---

## 1. Module Decomposition

libitshell3 is organized into 4 module groups with a diamond dependency graph. `ghostty/` and `input/` are sibling modules that both depend on `core/`; `server/` depends on all three.

### 1.1 Dependency Graph

```
          core/
         /    \
    ghostty/  input/
         \    /
         server/
```

Dependencies point inward: `server/` depends on everything; `ghostty/` and `input/` depend only on `core/`; `core/` depends on nothing. Circular dependencies are prohibited.

### 1.2 Module Definitions

#### `core/` — Pure State Types

Zero dependencies on ghostty, OS, or protocol.

| Type | Purpose |
|------|---------|
| `Session` | Config, name, ImeEngine interface, preedit cache, focused pane, fixed-size pane slots and tree |
| `SplitNodeData` | Binary split tree node (tagged union: `.leaf` = PaneSlot, `.split` = orientation + ratio) |
| `PaneId` | `u32` opaque wire identifier (global monotonic, never reused) |
| `PaneSlot` | `u8` session-local slot index (0..15) for fixed-size array operations |
| `MAX_PANES` | Compile-time constant: 16 panes per session |
| `ImeEngine` | Vtable interface for input method engines |
| `KeyEvent` | Key input event type consumed by IME routing |
| `ImeResult` | Result of IME processing (committed text, preedit, forward key) |

`core/` is unit-testable in isolation with zero external dependencies.

#### `ghostty/` — Thin Helper Functions

Depends on `core/` only. Contains helper functions (NOT wrapper types) for ghostty's internal Zig APIs.

| Helper | Wraps | Purpose |
|--------|-------|---------|
| Terminal lifecycle | `Terminal.init(alloc, .{.cols, .rows})` | Create headless Terminal instance |
| VT stream processing | `terminal.vtStream(bytes)` | Feed PTY output into terminal |
| RenderState snapshot | `RenderState.update(alloc, &terminal)` | Capture terminal state for export |
| Cell data export | `bulkExport(alloc, &render_state, &terminal)` | Produce FlatCell[] for wire transfer |
| Key encoding | `key_encode.encode(writer, event, opts)` | Encode key events for PTY (stateless, pure function) |
| Terminal mode query | `Options.fromTerminal(&terminal)` | Read DEC modes, Kitty flags |
| Preedit injection | `overlayPreedit(export_result, preedit, cursor)` | Overlay preedit cells post-export (~20 lines in vendor fork) |

**Why helper functions, not wrapper types**: ghostty's API is not stable. Wrapper types would create a maintenance trap — every upstream API change would require updating both the wrapper and the call site. Helper functions are a thin layer that adds value (e.g., error mapping, parameter defaults) without creating false abstraction. We have no second implementation of ghostty, so an abstraction layer violates YAGNI.

#### `input/` — Key Routing Orchestration

Depends on `core/` only. No ghostty dependency.

**Scope**: The `input/` module handles Phase 0+1 key input processing: shortcut interception (Phase 0), ImeEngine dispatch (Phase 1), focus change handling (`handleIntraSessionFocusChange`), and input method switching (`handleInputMethodSwitch`). Mouse events and paste operations bypass this module entirely — they are handled directly in `server/`.

| Function | Phase | Purpose |
|----------|-------|---------|
| `handleKeyEvent` | 0 + 1 | Route key through shortcut check, then to ImeEngine |
| `handleIntraSessionFocusChange` | — | Flush engine, clear preedit on old pane |
| `handleInputMethodSwitch` | 0 | Switch active input method |

`input/` depends on the `ImeEngine` interface type (defined in `core/`), not on the concrete `HangulImeEngine` (in libitshell3-ime). This is dependency inversion: `input/` code is testable with a `MockImeEngine` without libhangul.

#### `server/` — Event Loop and I/O

Depends on `core/`, `ghostty/`, `input/`, libitshell3-ime, and libitshell3-protocol.

| Component | Purpose |
|-----------|---------|
| Event loop | kqueue-based, single-threaded (see Section 2) |
| Client manager | Per-client state, connection lifecycle |
| Ring buffer | Per-pane frame delivery with per-client cursors |
| Frame coalescing | Adaptive timer for batching frame updates |
| PTY I/O | Read/write handlers for pane PTY file descriptors |
| Phase 2 integration | Consume ImeResult: PTY writes, preedit cache update, key encoding |
| Pane struct | Owns Terminal + RenderState + pty_fd + child_pid (see Section 3.3) |
| Startup/shutdown | Daemon initialization and graceful teardown |

Socket setup is delegated to libitshell3-protocol's transport layer (Layer 4).

### 1.3 Phase 2 Placement

Phase 2 consumes `ImeResult` and performs:
- **I/O**: `write(pty_fd, committed_text)`, `write(pty_fd, encoded_key)`
- **ghostty API calls**: `key_encode.encode()`, `overlayPreedit()`
- **State mutation**: `@memcpy` preedit text to `session.preedit_buf`

Both I/O and ghostty dependencies belong in `server/`, not `input/`. The `input/` module handles Phase 0 and Phase 1 only — pure routing logic that depends solely on `core/` types.

### 1.4 Ring Buffer Placement

The ring buffer lives in `server/`, not in the protocol library or `core/`. The ring buffer is a server-side application-level delivery optimization (multi-client cursor management, writev scheduling) with no client-side analogue. The protocol library provides transport-level I/O (Layer 4), but application-level delivery strategies are the consumer's responsibility.

### 1.5 Pane Struct Placement and Fixed-Size Lookup

The Pane struct lives in `server/` because it owns both ghostty types (Terminal, RenderState) and OS resources (pty_fd, child_pid). Placing it in `core/` would violate the `core/ <- ghostty/` dependency rule.

A compile-time constant limits panes per session:

```zig
pub const MAX_PANES = 16;
pub const MAX_TREE_NODES = MAX_PANES * 2 - 1; // 31
```

The 16-pane limit is a UX-driven constraint, not a performance optimization. On a 374x74 terminal, 16 panes at 93x18 is minimum viable; 32 panes at 93x9 is unusable. The limit is enforced server-side via ErrorResponse when a client requests a split that would exceed 16 panes.

Each session maintains a fixed-size pane slot array instead of a dynamic HashMap:

```zig
pane_slots: [MAX_PANES]?*Pane, // indexed by PaneSlot (0..15)
free_mask: u16,                 // bitmap of available slots
dirty_mask: u16,                // one bit per pane slot, set on PTY read
```

**Pane slot allocation**: `@ctz(free_mask)` gives the next free slot in one instruction.

**Dirty tracking**: Set via `dirty_mask |= (1 << pane.slot_index)` on PTY read. Iterate via `@ctz(dirty_mask)` (single instruction on x86 `TZCNT` and ARM64 `RBIT+CLZ`). Clear each bit after export: `dirty_mask &= dirty_mask - 1`.

**PaneId semantics**: PaneId on the wire is a global monotonic `u32`, never reused within daemon lifetime. Internally, sessions use a session-local `PaneSlot: u8` (0..15) for all fixed-size array operations. Wire-to-Pane lookup uses per-session linear scan of `pane_slots` (at most 16 entries) — cold path only. Hot paths (frame export, dirty iteration, PTY read) use slot indices exclusively.

**Why global monotonic PaneId (not session-local 0..15) on the wire**:

1. **Pane-reuse race condition**: In async IPC, a client can have an in-flight message targeting a slot the server has already recycled. Global monotonic PaneId ensures stale messages target non-existent IDs and receive ErrorResponse.
2. **Protocol constraint leak**: Session-local PaneId (0..15) exposes the 16-pane limit to wire semantics. Global monotonic u32 keeps the limit invisible to the protocol.
3. **Hot-path equivalence**: Both options have identical hot-path performance — all hot paths use slot indices, never PaneId.

`SessionManager` continues to use `HashMap(u32, *Session)` for sessions (dynamic count, few instances — no fixed limit for sessions).

### 1.6 Inter-Library Dependencies

libitshell3 and libitshell3-protocol are separate libraries with a clean, acyclic dependency relationship:

```
libitshell3-protocol  (standalone — depends only on Zig std; libssh2 added in Phase 5)
libitshell3-ime       (standalone — depends on libhangul)
libitshell3/core/     (standalone — no external deps)
libitshell3/ghostty/  (depends on core/, vendored ghostty)
libitshell3/input/    (depends on core/)
libitshell3/server/   (depends on core/, ghostty/, input/, libitshell3-ime, libitshell3-protocol)
```

**libitshell3-protocol does NOT import any libitshell3 types.** The protocol library uses Zig primitive types (`u32`, `[]const u8`, etc.) for all message fields. On the wire, `pane_id` and `session_id` are `u32` values in JSON payloads — the protocol library reflects what the wire carries.

**`server/` maps between wire primitives and domain types.** Since `server/` imports both `core/` and `libitshell3-protocol`, it is the natural boundary for converting protocol message fields (e.g., `msg.pane_id: u32`) to domain types (e.g., `core.PaneId`). This is a trivial one-line cast at each protocol handler.

**No shared types library is needed.** The types that might be shared (`PaneId = u32`, session_id as `u32`) are trivial aliases. Extracting a `libitshell3-types` library for two `u32` aliases would be over-engineering.

**libitshell3-protocol's external dependencies:**
- **v1**: Zig `std` only (posix sockets via `std.posix` for Layer 4 transport)
- **Phase 5**: `libssh2` added for SSH transport in Layer 4

### 1.7 Prior Art

- **tmux**: Separates pure state (`window.h`, `session.h`) from I/O (`tty.c`, `server-client.c`).
- **ghostty**: Separates terminal logic (`Terminal.zig`) from renderer (`Metal.zig`) and I/O (`Termio.zig`).

---

## 2. Event Loop Model

### 2.1 Decision

Single-threaded kqueue event loop (tmux model). No threads, no locks, no mutexes.

### 2.2 Event Sources

All event types are handled in a single `kevent64()` call:

| Filter | Source | Purpose |
|--------|--------|---------|
| `EVFILT_READ` | PTY fds | Read shell output from pane child processes |
| `EVFILT_READ` | Socket listen fd | Accept new client connections |
| `EVFILT_READ` | Client conn fds | Read client messages (key events, commands) |
| `EVFILT_WRITE` | Client conn fds | Resume sending when socket becomes writable (after EAGAIN) |
| `EVFILT_TIMER` | Coalescing timer | Trigger frame export and delivery at adaptive intervals |
| `EVFILT_TIMER` | I-frame keyframe timer | Periodic full-frame keyframes for state recovery |
| `EVFILT_SIGNAL` | SIGTERM, SIGINT, SIGHUP | Graceful shutdown signals |
| `EVFILT_SIGNAL` | SIGCHLD | Child process reaping |

kqueue timers are kernel-managed, more efficient than userspace timer wheels.

### 2.3 Why Single-Threaded

**Performance**: `bulkExport()` is 22 us for 80x24, 217 us for 300x80. Even 10 panes at 60fps = 1.3% of a single core. Threading provides no measurable benefit.

**Thread safety**: ghostty Terminal is NOT thread-safe. It uses internal arena allocators and mutable page state. In normal ghostty, a shared mutex synchronizes the IO thread and renderer thread. Our single-threaded design eliminates this entirely.

**Correctness**: Single-threaded eliminates all concurrency hazards: no lock ordering, no deadlocks, no data races on pane state, ImeEngine access, or ring buffer writes. The event loop provides implicit serialization. The critical runtime invariant — ImeResult must be consumed before the next engine call — is naturally satisfied.

**Scalability**: tmux proves single-threaded scales to hundreds of panes with a single libevent/kqueue loop.

### 2.4 Prior Art

- **tmux**: Single-threaded libevent loop, proven at scale with hundreds of sessions and panes.

---

## 3. State Tree

### 3.1 Decision

Session = Tab merge. No intermediate Tab entity. Each Session directly owns an array-based binary split tree (`[31]?SplitNodeData`) and a fixed pane slot array (`[16]?*Pane`). 16-pane-per-session limit (see Section 1.5).

### 3.2 Hierarchy

```
SessionManager (in server/)
  +-- HashMap(u32, *Session)
  |
  +-- Session (in core/)
  |     session_id: u32
  |     name: []const u8
  |     ime_engine: ImeEngine
  |     active_input_method: []const u8
  |     keyboard_layout: []const u8
  |     tree_nodes: [31]?SplitNodeData       // array-based binary tree (root = index 0)
  |     pane_slots: [16]?*Pane               // per-session fixed pane array
  |     free_mask: u16                        // bitmap of available pane slots
  |     dirty_mask: u16                       // bitmap of dirty panes (set on PTY read)
  |     focused_pane: ?PaneSlot
  |     creation_timestamp: i64
  |     current_preedit: ?[]const u8          // cached from last ImeResult
  |     preedit_buf: [64]u8                   // backing storage for current_preedit
  |     last_preedit_row: ?u16               // cursor row of last overlaid preedit
  |     |
  |     +-- SplitNodeData (tagged union in core/)
  |           .leaf => PaneSlot (u8, 0..15)
  |           .split => { orientation, ratio }
  |           Navigation: parent(i) = (i-1)/2, left(i) = 2*i+1, right(i) = 2*i+2
  |
  +-- Pane (in server/, referenced via pane_slots)
        pane_id: u32                          // global monotonic wire identity
        slot_index: u8                        // position in owning session's pane_slots
        pty_fd: posix.fd_t
        child_pid: posix.pid_t
        terminal: *ghostty.Terminal
        render_state: *ghostty.RenderState
        cols: u16
        rows: u16
        title: []const u8
```

**Tree node array vs pane slot array**: These are separate index spaces. Tree node indices (0..30) identify positions in the `[31]?SplitNodeData` array. Pane slot indices (0..15) identify positions in the `[16]?*Pane` array. Leaf nodes store pane slot indices. Tree compaction (subtree relocation during split/close) moves tree nodes but does not change the pane slot indices stored in leaf values. Pane slot indices are stable across tree mutations.

**Tree mutation complexity**: Split and close operations require subtree relocation within the tree node array. With max depth 4 and 31 nodes, this is bounded at ~15 node copies per operation — trivially fast on cache-hot data (the entire tree fits in L1 cache).

### 3.3 Type Definitions

```zig
// core/constants.zig
pub const MAX_PANES = 16;
pub const MAX_TREE_NODES = MAX_PANES * 2 - 1; // 31

pub const PaneId = u32;
pub const PaneSlot = u8; // 0..15, indexes into pane_slots array

// core/session.zig
pub const Session = struct {
    session_id: u32,
    name: []const u8,
    ime_engine: ImeEngine,
    active_input_method: []const u8,
    keyboard_layout: []const u8,
    tree_nodes: [MAX_TREE_NODES]?SplitNodeData, // 31 entries, root at index 0
    pane_slots: [MAX_PANES]?*Pane,              // indexed by PaneSlot (0..15)
    free_mask: u16,                              // bitmap of available pane slots
    dirty_mask: u16,                             // one bit per pane slot
    focused_pane: ?PaneSlot,
    creation_timestamp: i64,
    current_preedit: ?[]const u8,
    preedit_buf: [64]u8,
    last_preedit_row: ?u16,
};

// core/split_node.zig
pub const SplitNodeData = union(enum) {
    leaf: PaneSlot,
    split: struct {
        orientation: enum { horizontal, vertical },
        ratio: f32,
    },
};

// server/pane.zig
pub const Pane = struct {
    pane_id: PaneId,
    slot_index: PaneSlot, // position in owning session's pane_slots
    pty_fd: posix.fd_t,
    child_pid: posix.pid_t,
    terminal: *ghostty.Terminal,
    render_state: *ghostty.RenderState,
    cols: u16,
    rows: u16,
    title: []const u8,
};
```

### 3.4 Session = Tab Merge Rationale

- Session:Tab is 1:1 in v1. An intermediate Tab entity with no distinct behavior violates YAGNI. When Phase 3 needs multiple tabs per session, Tab can be introduced as an intermediate node between Session and SplitNode.
- Per-session ImeEngine maps cleanly: one engine per "thing the user switches between."
- The protocol already treats Sessions as the unit clients attach to. There is no Tab entity in the protocol — "tabs" are a client UI concept mapped to Sessions.

### 3.5 Preedit Cache

Session caches the current preedit text (`current_preedit: ?[]const u8`, backed by a 64-byte `preedit_buf`) from the last `ImeResult` for use at export time.

**Why caching is necessary**: The ImeEngine vtable has no "get current preedit" method. Preedit text is only available via `ImeResult` from mutating calls. Per IME contract v0.7 Section 6, the engine's internal buffers are invalidated on the next mutating call.

**Cache update flow**: When `ImeResult.preedit_changed == true`, the session copies the preedit text into `preedit_buf` via `@memcpy` and points `current_preedit` at the copied slice. `overlayPreedit()` reads from `session.current_preedit`, never from the engine directly.

**Lifetime semantics**: The engine's buffer is ground truth at `processKey()` time; the Session's copy is ground truth at export time. Different lifetimes, different purposes — this is a necessary cache, not a DRY violation.

### 3.6 Dirty Tracking for Preedit

`last_preedit_row: ?u16` tracks the cursor row where preedit was last overlaid. When preedit changes or clears, the previous row must be marked dirty in the next export so that the old preedit cells are repainted with the underlying terminal content. Without this tracking, clearing preedit would leave stale composed characters on screen until the next terminal output touched that row.

### 3.7 Prior Art

- **Array-based binary tree (heap data structure)**: Fixed-size tree with index arithmetic — standard CS data structure used for the `[31]?SplitNodeData` layout.
- **cmux**: Uses binary split tree (Bonsplit library).
- **ghostty**: Split API uses the same model.
- **tmux**: `layout_cell` tree is conceptually identical.

---

## 4. ghostty Terminal Instance Management

### 4.1 Decision

Headless Terminal — no Surface, no App, no embedded apprt. The daemon uses ghostty's internal Zig APIs exclusively.

This was validated by PoC 06 (headless Terminal extraction), PoC 07 (bulkExport benchmark at 22 us/frame for 80x24), and PoC 08 (importFlatCells + GPU rendering on client).

### 4.2 API Surface

The daemon uses the following ghostty internal Zig APIs:

| Operation | API | Notes |
|-----------|-----|-------|
| Terminal lifecycle | `Terminal.init(alloc, .{.cols, .rows})` | No Surface, no App (PoC 06 validated) |
| PTY output processing | `terminal.vtStream(bytes)` | Zero Surface dependency |
| RenderState snapshot | `RenderState.update(alloc, &terminal)` | Captures terminal state |
| Cell data export | `bulkExport(alloc, &render_state, &terminal)` | Produces FlatCell[] (16 bytes each, C-ABI compatible, SIMD-friendly) |
| Key encoding | `key_encode.encode(writer, event, opts)` | Pure function, no Surface, stateless |
| Terminal mode query | `Options.fromTerminal(&terminal)` | Reads DEC modes, Kitty keyboard flags |
| Preedit injection | `overlayPreedit(export_result, preedit, cursor)` | ~20 lines in vendor fork (render_export.zig) |

### 4.3 Key Input Path

When the daemon receives a key event from a client, the IME routing pipeline (Phase 0 -> 1 -> 2) produces an `ImeResult`. Phase 2 in `server/` consumes it:

| ImeResult field | Action | API |
|-----------------|--------|-----|
| `committed_text` | Write UTF-8 directly to PTY | `write(pty_fd, text)` (v1 legacy mode) |
| `forward_key` | Encode key and write to PTY | `key_encode.encode()` + `write(pty_fd, encoded)` |
| `preedit_text` | Copy to `session.preedit_buf` via `@memcpy` when `preedit_changed`; overlay at export time | `overlayPreedit(export_result, session.current_preedit, cursor)` |

**No press+release pairs needed**: The IME contract v0.7 Section 5 requires press+release pairs for `ghostty_surface_key()` because Surface tracks key state internally. Since we bypass Surface and use `key_encode.encode()` directly (stateless), no release events are needed in v1 legacy mode. For future Kitty protocol support, release events would go through the encoder.

### 4.4 Preedit Overlay Mechanism

Preedit lives on `renderer.State.preedit` (State.zig:27), NOT on `terminal.RenderState`. In normal ghostty, the renderer clones preedit during the critical section and applies it during `rebuildCells()`.

Since we are headless (no Surface, no renderer.State), we overlay preedit cells post-`bulkExport()` via `overlayPreedit()` in render_export.zig. The function:

1. Takes ExportResult + preedit codepoints + cursor position
2. Overwrites FlatCells at the cursor position with preedit character data
3. Marks affected rows dirty in the bitmap

This is ~20 lines in our vendor fork, self-contained and testable in isolation.

### 4.5 Frame Export Pipeline

The complete export pipeline for a single pane:

```
terminal.vtStream(pty_bytes)        // Process PTY output
    |
    v
RenderState.update(alloc, &terminal)  // Snapshot terminal state
    |
    v
bulkExport(alloc, &render_state, &terminal)  // Produce FlatCell[]
    |
    v
overlayPreedit(export_result, session.current_preedit, cursor)  // Inject preedit
    |
    v
serialize FrameUpdate -> ring buffer  // Ready for client delivery
    |
    v
conn.sendv(iovecs)                    // Zero-copy to socket
```

### 4.6 Why Headless (No Surface)

- The IME contract v0.7 Phase 1/Phase 2 distinction was written before the headless decision. Phase 1 (`ghostty_surface_key()`) requires a Surface we don't have. Using `key_encode.encode()` from day one is the only viable path.
- The IME contract v0.7 Section 5 code examples should be understood as logical pseudocode describing the data flow (WHAT). This daemon spec specifies the API calls (HOW).
- Design principle A1 ("preedit is cell data") remains valid: preedit IS cell data on the wire; only the injection mechanism differs from normal ghostty.

### 4.7 Prior Art

- **PoC 06**: Headless Terminal extraction — proved Terminal works without Surface/App.
- **PoC 07**: bulkExport benchmark — 22 us for 80x24, 217 us for 300x80.
- **PoC 08**: importFlatCells + rebuildCells + Metal drawFrame — full GPU pipeline on client.

---

## 5. End-to-End Data Flow

### 5.1 Key Input Data Flow

The following shows the complete data path for a key input event, tying together module decomposition (Section 1), event loop (Section 2), ghostty APIs (Section 4), and the protocol/IME integration defined in companion documents.

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

Mouse events follow a simpler path — no IME involvement. Mouse tracking is only active when the terminal's DEC mode state has mouse reporting enabled (determined by `Options.fromTerminal()`).

```mermaid
sequenceDiagram
    participant C as Client App
    participant S as Daemon (server/)
    participant P as PTY Child

    C->>S: MouseEvent (Unix socket)
    Note over S: EVFILT_READ on conn.fd<br/>Check terminal DEC mouse mode
    S->>P: write(pty_fd, mouse escape sequence)
```

---

## 6. Preedit / RenderState Validity (Owner Q3)

### 6.1 Decision

Design principle A1 ("preedit is cell data") is VALID. No protocol or IME contract changes are needed.

### 6.2 The Fact

Preedit lives on `renderer.State.preedit` (State.zig:27), NOT on `terminal.RenderState`. In normal ghostty, the renderer clones preedit during the critical section and applies it during `rebuildCells()`.

### 6.3 Our Approach

In headless mode (no Surface, no renderer.State), the daemon overlays preedit cells during the export phase via `overlayPreedit()` in render_export.zig (~20 lines in vendor fork).

### 6.4 Why A1 Holds

From the protocol's perspective, preedit IS cell data — it arrives at the client as ordinary FlatCells in FrameUpdate. The client never knows or cares which cells are preedit. The injection mechanism (`overlayPreedit` vs `ghostty_surface_preedit`) is a server-side implementation detail invisible to the wire.

---

## 7. Items Deferred to Future Versions

| Item | Deferred to | Rationale |
|------|-------------|-----------|
| Multiple tabs per session (Session:Tab 1:N) | Phase 3 | v1 is Session:Tab 1:1. Tab entity introduced when use case arrives. |
| Floating panes | Post-v1 | YAGNI for v1. Binary split tree covers all layout needs. |
| Kitty keyboard protocol support | Post-v1 | v1 uses legacy mode only. `key_encode.encode()` supports Kitty natively; would need release events when Kitty mode is negotiated. |
| Multi-threaded event loop | Not planned | Single-threaded is sufficient (Section 2.3). Revisit only if profiling proves otherwise. |

---

## 8. Prior Art Summary

| Reference | Used for | Sections |
|-----------|----------|----------|
| Array-based binary tree (heap data structure) | Fixed-size tree with index arithmetic | 1.5, 3 |
| tmux (`window.h`, `session.h`, `tty.c`, `server-client.c`) | Pure state / I/O separation | 1 |
| tmux (single-threaded libevent loop) | Event loop model, scaling evidence | 2 |
| tmux `layout_cell` tree | Binary split tree model | 3 |
| ghostty (`Terminal.zig`, `Metal.zig`, `Termio.zig`) | Terminal / renderer / I/O separation | 1 |
| ghostty `Terminal.init()` (PoC 06) | Headless Terminal validation | 4 |
| ghostty `bulkExport()` (PoC 07) | Export performance (22 us/frame) | 2, 4 |
| ghostty `importFlatCells()` (PoC 08) | Client-side RenderState population | 4 |
| ghostty `renderer.State.preedit` (State.zig:27) | Preedit storage location | 4, 6 |
| ghostty `key_encode.encode()` (key_encode.zig:75) | Stateless key encoding | 4 |
| cmux (Bonsplit binary split tree) | Layout tree model | 3 |
| IME contract v0.7 | Per-session ImeEngine, Phase 0-1-2 routing | 3, 4 |
| Protocol spec v0.10 | Wire format, PaneId as u32 on wire | 1.5 |
