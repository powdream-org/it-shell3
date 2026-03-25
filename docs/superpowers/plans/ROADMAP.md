# libitshell3 Implementation Roadmap

> **For agentic workers:** This is the master index for all implementation
> plans. Start here to understand what exists, what's next, and how plans depend
> on each other. Each plan has its own file with task-level detail — this
> document is the map, not the territory.

**Goal:** Implement the full it-shell3 daemon ecosystem — from core types to
production-ready terminal multiplexer with CJK input support.

**Architecture:** Three libraries (`libitshell3`, `libitshell3-protocol`,
`libitshell3-ime`) + one daemon binary. Single-threaded kqueue/epoll event loop.
ghostty for headless VT processing. Native Zig IME engine (no OS IME
dependency). See `AGENTS.md` for full project overview.

**Tech Stack:** Zig 0.15+, vendored libghostty (v1.3.1-patch), vendored
libhangul, POSIX (kqueue/epoll, forkpty, Unix sockets).

---

## Current Status

| Module               | Source Files | Tests | Coverage (kcov)            |
| -------------------- | ------------ | ----- | -------------------------- |
| libitshell3          | 29           | 159   | 94.33%                     |
| libitshell3-protocol | 16           | 128   | 97.44%                     |
| libitshell3-ime      | 10           | 138   | exempted (scenario-matrix) |
| daemon               | 1            | —     | —                          |

Coverage measured via `mise run test:coverage` (Docker + kcov on Linux).

---

## Plan Index

| # | Name                         | Plan File                                       | Target Module        | Status      |
| - | ---------------------------- | ----------------------------------------------- | -------------------- | ----------- |
| 1 | Foundation                   | `2026-03-25-libitshell3-foundation.md`          | libitshell3          | **Done**    |
| 2 | ghostty Integration          | `2026-03-25-libitshell3-ghostty-integration.md` | libitshell3          | **Done**    |
| 3 | Wire Protocol                | `2026-03-25-libitshell3-protocol.md`            | libitshell3-protocol | **Done**    |
| 4 | Ring Buffer + Frame Delivery | (not yet written)                               | libitshell3          | Not started |
| 5 | IME Integration              | (not yet written)                               | libitshell3          | Not started |
| 6 | Runtime Policies             | (not yet written)                               | libitshell3          | Not started |
| 7 | Cascades                     | (not yet written)                               | libitshell3          | Not started |
| 8 | SSH Transport                | (not yet written)                               | libitshell3-protocol | Not started |

---

## Dependency Graph

```
Plan 1 (Foundation) ─────────────────────────────────── DONE
├── Plan 2 (ghostty Integration) ────────────────────── DONE
└── Plan 3 (Wire Protocol) ──────────────────────────── DONE
         │
    Plan 4 (Ring Buffer + Frame Delivery)
    │    Needs: ghostty bulkExport (Plan 2) + FrameUpdate encoding (Plan 3)
    │
    ├── Plan 5 (IME Integration) ──── can parallel with Plan 6
    │    Needs: ring buffer for preedit overlay in frames
    │
    ├── Plan 6 (Runtime Policies) ─── can parallel with Plan 5
    │    Needs: ring buffer + frame delivery for coalescing/flow control
    │         │
    │    Plan 7 (Cascades)
    │         Needs: IME deactivate (Plan 5) + health/flow cleanup (Plan 6)
    │
    Plan 8 (SSH Transport) ──── can parallel with Plans 4-7
         Needs: Plan 3 Transport vtable only (no daemon dependency)
```

**Parallelization opportunities:**

- Plans 2 + 3 ran in parallel (different modules, no file conflicts)
- Plans 5 + 6 can run in parallel (different subsystems within libitshell3)
- Plan 8 can run in parallel with Plans 4-7 (different module, only needs Plan
  3's Transport interface)

---

## Plan Summaries

### Plan 1: Foundation (Done)

Core types, event loop skeleton, PTY management, Unix socket listener, and basic
daemon lifecycle. Produced a minimal daemon that starts, creates a session,
accepts a client connection, and shuts down cleanly.

**Key deliverables:**

- `core/`: types, split tree, pane (two-phase exit), session, session manager,
  pane navigation (geometric edge-adjacency)
- `os/`: vtable interfaces for PTY, kqueue/epoll, socket, signals + real impls
  - mock impls for deterministic testing
- `server/`: event loop (two-level dispatch), listener, client state machine,
  signal handlers, handler stubs
- `daemon/src/main.zig`: thin ~100-line orchestrator per ADR 00048

**Key decisions:** ADR 00052 (static SessionManager allocation), OS vtable
interfaces from day one, named sub-modules (`itshell3_core`, `itshell3_os`).

### Plan 2: ghostty Integration (Done)

Integrated vendored ghostty headless VT engine. Helper functions (not wrapper
types per spec §1.2) for Terminal lifecycle, RenderState snapshots, key/mouse
encoding, cell data export, and preedit overlay.

**Key deliverables:**

- `ghostty/`: terminal.zig, render_state.zig, render_export.zig (FlatCell 16B
  - bulkExport), key_encoder.zig (256-entry HID-to-Key comptime table),
    preedit_overlay.zig (CJK wide char support)
- ghostty pinned to v1.3.1-patch with `-Dversion-string` bypass
- Persistent vtStream for split escape sequence handling

**Known gaps:** Mouse encoder not available in ghostty lib_vt.zig — must be
daemon-authored. Review note filed at
`daemon-architecture/.../review-notes/mouse-encode-api-gap.md`.

### Plan 3: Wire Protocol (Done)

Protocol message types, binary framing, JSON payloads, handshake orchestration,
transport layer, connection state machine.

**Key deliverables:**

- 16-byte fixed header (magic 0x4954 + version + flags + type + length + seq)
- All message types: handshake, session, pane, input, preedit, auxiliary
- CellData/RowHeader/FrameUpdate binary encoding for RenderState frames
- Frame reader/writer with sequence tracking
- Connection state machine (HANDSHAKING→READY→OPERATING→DISCONNECTING)
- UID authentication (getpeereid/SO_PEERCRED)
- Socket path resolution (XDG + TMPDIR + platform defaults)

### Plan 4: Ring Buffer + Frame Delivery (Not Started)

**Scope:** Per-pane ring buffer with pre-serialized wire-format frames,
per-client read cursors, writev zero-copy delivery, I-frame/P-frame
serialization, dirty tracking pipeline integration.

**Design spec refs:**

- `daemon-architecture/.../02-state-and-types.md` §4 (Ring Buffer Architecture)
- `daemon-behavior/.../03-policies-and-procedures.md` §9-11
- `daemon-behavior/.../impl-constraints/policies.md` (Ring Buffer Delivery,
  Socket Write Priority, Backpressure)

**Depends on:** Plan 2 (ghostty bulkExport for frame data) + Plan 3 (FrameUpdate
binary encoding for wire format)

### Plan 5: IME Integration (Not Started)

**Scope:** Wire libitshell3-ime (v0.7.0, already implemented) into the daemon
event loop. Per-session IME engine lifecycle (create/destroy), preedit routing
to focused pane, ownership transfer on client disconnect/focus change, all 8
ime-procedures from impl-constraints.

**Design spec refs:**

- `daemon-architecture/.../03-integration-boundaries.md` §5
- `daemon-architecture/.../impl-constraints/ime-responsibility-matrix.md`
- `daemon-behavior/.../impl-constraints/ime-procedures.md`
- `libitshell3-ime/` interface contract + behavior docs

**Depends on:** Plan 4 (ring buffer — preedit overlay applied to exported frames
before ring insertion)

### Plan 6: Runtime Policies (Not Started)

**Scope:** Adaptive coalescing (5-tier model with hysteresis), health escalation
timeline (T=0 → T=300s eviction), flow control (PausePane/ContinuePane), resize
debounce (250ms per pane, 5s hysteresis).

**Design spec refs:**

- `daemon-behavior/.../03-policies-and-procedures.md` §1-7
- `daemon-behavior/.../impl-constraints/policies.md` (all sections)

**Depends on:** Plan 4 (ring buffer + frame delivery for coalescing tiers and
backpressure)

### Plan 7: Cascades (Not Started)

**Scope:** Atomic multi-step cascades that must complete within a single event
loop iteration:

- Pane exit 12-step cascade (frame flush → metadata → IME cleanup → PTY close →
  Terminal.deinit → tree compact → new focus → layout notify)
- Session destroy 4-phase cascade (IME deactivate → resource cleanup → protocol
  notifications → free state)
- Client disconnect cascade

**Design spec refs:**

- `daemon-behavior/.../02-event-handling.md` §3-4
- `daemon-behavior/.../impl-constraints/pane-exit-cascade.md`
- `daemon-behavior/.../impl-constraints/session-destroy-cascade.md`

**Depends on:** Plan 5 (IME deactivate/flush in cascade) + Plan 6 (health/flow
state cleanup in cascade)

### Plan 8: SSH Transport (Not Started)

**Scope:** libssh2-based SSH client transport for libitshell3-protocol. Enables
remote connections from client apps to daemons on remote hosts. Implements the
same `Transport` vtable as `UnixTransport` so the rest of the protocol stack is
transport-agnostic.

Key components:

- `SshTransport` — Transport vtable impl over libssh2 channel
- SSH session management (connect, authenticate, channel open)
- `direct-streamlocal@openssh.com` channel forwarding to daemon's Unix socket
- SSH channel multiplexing (one TCP connection, multiple sessions)
- Remote daemon auto-start via SSH exec (`fork+exec` without LaunchAgent)
- `libssh2-wrapper` module (real + mock per ADR 00052 pattern, if adopted)

**Design spec refs:**

- `server-client-protocols/.../01-protocol-overview.md` §2.2 (SSH Tunneling)
- `server-client-protocols/.../01-protocol-overview.md` §5.5.2 (SSH Channel
  Multiplexing)
- `server-client-protocols/.../06-flow-control-and-auxiliary.md` §7.2 (Heartbeat
  over SSH)
- ADR 00010 (SSH tunneling over custom TCP/TLS)

**Depends on:** Plan 3 (Transport vtable interface). Can run in parallel with
Plans 4-7 (no daemon-side changes needed — SSH is client-side transport only).

---

## AGENTS.md Phase Mapping

| AGENTS.md Phase     | Plans                             | Status                               |
| ------------------- | --------------------------------- | ------------------------------------ |
| 1. Core daemon      | Plans 1-2                         | Done                                 |
| 2. Wire protocol    | Plan 3                            | Done                                 |
| 3. Frame pipeline   | Plan 4                            | Not started                          |
| 4. IME integration  | Plan 5 + libitshell3-ime (v0.7.0) | Engine done, integration not started |
| 5. Runtime policies | Plan 6                            | Not started                          |
| 6. Cascades         | Plan 7                            | Not started                          |
| 7. SSH transport    | Plan 8                            | Not started                          |
| 8. macOS client app | (no plan yet)                     | Not started                          |
| 9. iOS client       | (no plan yet)                     | Not started                          |
| 10. Polish          | (no plan yet)                     | Not started                          |

Session persistence deferred post-v1 per ADR 00036.

---

## Test & Coverage Commands

```bash
mise run test:macos                # macOS Debug tests (all modules)
mise run test:macos:release-safe   # macOS ReleaseSafe tests
mise run test:linux                # Linux Docker tests
mise run test:linux:release-safe   # Linux Docker ReleaseSafe tests
mise run test:coverage             # kcov in Docker (HTML report at coverage/merged/index.html)
mise run build:docker:zig-kcov     # Build the kcov Docker image
```

libitshell3 kcov workarounds: `-Dghostty-simd=false` (skip C++ simd) +
`-Doptimize=ReleaseSafe` (smaller DWARF for kcov parsing).
