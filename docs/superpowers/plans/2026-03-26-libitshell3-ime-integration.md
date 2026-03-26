# IME Integration Implementation Plan

**Goal:** Wire libitshell3-ime (v0.7.0, already implemented) into the daemon
event loop. Per-session IME engine lifecycle, 3-phase key routing pipeline,
ImeResult consumption, preedit overlay integration, and all 8 ime-procedures
from the behavior spec.

**Architecture:** The IME engine interface (vtable) is defined in `core/` for
dependency inversion. A new `input/` module handles Phase 0 (shortcut
interception) and Phase 1 (engine.processKey). Phase 2 (I/O + ghostty) lives in
`server/`. The `server/` module is the composition root — it creates the
concrete HangulImeEngine (from libitshell3-ime) and stores it behind the
ImeEngine vtable in Session. MockImeEngine enables testing all routing logic
without libhangul.

**Tech Stack:** Zig 0.15+, libitshell3-ime (vendored, v0.7.0), libhangul
(vendored, LGPL-2.1), ghostty key_encode + preedit_overlay APIs.

**Spec references:**

- daemon-architecture v1.0-r8: `03-integration-boundaries.md` §5 (IME
  Integration Architecture)
- daemon-architecture v1.0-r8: `impl-constraints/ime-responsibility-matrix.md`
- daemon-architecture v1.0-r8: `impl-constraints/state-and-types.md`
  (Session/SessionEntry type definitions)
- daemon-behavior v1.0-r8: `impl-constraints/ime-procedures.md` (8 procedures)
- libitshell3-ime interface-contract v1.0-r10: `02-types.md` (KeyEvent,
  ImeResult), `03-engine-interface.md` (ImeEngine vtable)
- libitshell3-ime behavior v1.0-r2 (composition rules — referenced by
  implementer, not reimplemented)

---

## Scope

**In scope:**

1. ImeEngine vtable + KeyEvent/ImeResult types in `core/` (§5.3)
2. IME fields on Session: `ime_engine`, `current_preedit`, `preedit_buf`,
   `last_preedit_row` (§5.1, state-and-types)
3. `input/` module: Phase 0 shortcut check + Phase 1 processKey + wire-to-
   KeyEvent decomposition (§5.2, §5.2 Wire-to-KeyEvent table)
4. Phase 2 ImeResult consumer in `server/` (§5.6)
5. Per-session ImeEngine lifecycle: create on session create, destroy on session
   destroy (§5.1 lifecycle table)
6. All 8 ime-procedures from behavior spec (§8.1–§8.5)
7. Mouse event IME interaction (§5.7)
8. MockImeEngine in `testing/` for daemon-side tests (§5.3)
9. Build system: add libitshell3-ime dependency to libitshell3 build.zig

**Out of scope:**

- Korean composition algorithms (already in libitshell3-ime v0.7.0)
- Adaptive coalescing / frame coalescing (Plan 6 — Runtime Policies)
- Pane exit cascade / session destroy cascade (Plan 7 — Cascades). Only the IME
  steps within those cascades (reset/deactivate) are in scope here.
- PreeditStart/PreeditEnd/PreeditUpdate wire message sending (requires protocol
  message dispatch from Plan 3 + direct queue from Plan 4). This plan implements
  the engine-side logic; protocol message emission is stubbed with comments
  noting where wire messages will be sent.
- Client-side preedit rendering (client app, not daemon)
- EVFILT_WRITE management for preedit messages (Plan 6)

## File Structure

| File                                  | Action | Responsibility                                                        |
| ------------------------------------- | ------ | --------------------------------------------------------------------- |
| `src/core/ime_engine.zig`             | Create | ImeEngine vtable, KeyEvent, ImeResult types (dependency inversion)    |
| `src/core/root.zig`                   | Modify | Add `ime_engine` module export                                        |
| `src/core/types.zig`                  | Modify | PaneSlot u4 → u8 per spec                                             |
| `src/core/session.zig`                | Modify | Spec conformance fixes + IME fields (see Task 2)                      |
| `src/input/key_router.zig`            | Create | Phase 0 shortcut check + Phase 1 processKey dispatch                  |
| `src/input/wire_decompose.zig`        | Create | Wire modifier bitmask → KeyEvent decomposition                        |
| `src/input/root.zig`                  | Create | Module root for `input/`                                              |
| `src/server/ime_consumer.zig`         | Create | Phase 2 ImeResult consumption (PTY write, preedit update, key encode) |
| `src/server/ime_lifecycle.zig`        | Create | Per-session engine create/destroy, activate/deactivate                |
| `src/server/ime_procedures.zig`       | Create | All 8 procedures from behavior spec §8.1–§8.5                         |
| `src/server/event_loop.zig`           | Modify | Wire IME lifecycle into session create/destroy; key event dispatch    |
| `src/server/handlers/client_read.zig` | Modify | Replace stub with real key event dispatch through input/ pipeline     |
| `src/testing/mock_ime_engine.zig`     | Create | MockImeEngine for daemon-side IME routing tests                       |
| `src/testing/helpers.zig`             | Modify | Add IME-related test helpers if needed                                |
| `build.zig`                           | Modify | Add libitshell3-ime dependency, add `input/` named sub-module         |

## Tasks

### Task 1: ImeEngine vtable and types in core/

**Files:** `src/core/ime_engine.zig` (create), `src/core/root.zig` (modify)

**Spec:** interface-contract v1.0-r10 `02-types.md` §1-2 (KeyEvent, ImeResult)
and `03-engine-interface.md` §1 (ImeEngine vtable with 8 methods)

**Depends on:** None

**Verification:**

- ImeEngine vtable matches spec: 8 methods with identical signatures
- KeyEvent fields match spec: hid_keycode, modifiers (packed struct), shift,
  action, HID_KEYCODE_MAX, hasCompositionBreakingModifier(),
  isPrintablePosition()
- ImeResult fields match spec: committed_text, preedit_text, forward_key,
  preedit_changed, all optional/defaulted
- core/root.zig exports the new types
- Unit tests verify vtable dispatch through a trivial mock

### Task 2: Session and SessionEntry spec conformance + IME fields

**Files:** `src/core/types.zig` (modify), `src/core/session.zig` (modify), all
files using `PaneSlot` across `src/core/` (modify — cascading type change)

**Spec:** daemon-architecture v1.0-r8 `impl-constraints/state-and-types.md`
(Session/SessionEntry class diagram), `03-integration-boundaries.md` §5.1
(per-session engine state), `02-state-and-types.md` §1.2-§1.3, ADR 00058
(fixed-size inline buffers), Zig naming convention
(`docs/conventions/zig-naming.md`)

**Depends on:** Task 1 (ImeEngine type must exist)

**Verification:**

Type and naming fixes:

- `PaneSlot` changed from `u4` to `u8` per spec — all usages across core/
  updated consistently (including shift arithmetic in `allocPaneSlot`)
- `focused_pane` changed from `PaneSlot` to `?PaneSlot` per spec (nullable)
- `keyboard_layout` renamed to `active_keyboard_layout` per spec
- Default keyboard layout changed from `"us"` to `"qwerty"` per spec
- Length field suffixes: `_length` not `_len` (e.g., `name_length`,
  `active_input_method_length`, `active_keyboard_layout_length`) per Zig naming
  convention
- `SessionEntry` has `latest_client_id: u32` field per spec (default 0)

MAX_SIZE constants added to `types.zig` per ADR 00058:

- `MAX_SESSION_NAME: u8 = 64`
- `MAX_INPUT_METHOD_NAME: u8 = 32`
- `MAX_KEYBOARD_LAYOUT_NAME: u8 = 32`
- `MAX_PREEDIT_BUF: u8 = 64`
- Buffer fields reference these constants (e.g., `name: [MAX_SESSION_NAME]u8`)

Missing spec fields added to Session:

- Session has `creation_timestamp: i64` per spec
- Session has `ime_engine: ImeEngine` field (non-nullable per spec — core/ tests
  use MockImeEngine via dependency injection)
- Session has `current_preedit: ?[]const u8` backed by
  `preedit_buf: [MAX_PREEDIT_BUF]u8`
- Session has `last_preedit_row: ?u16`
- Session.init() accepts an ImeEngine parameter (caller provides mock or real)
- Existing Session tests updated to pass a MockImeEngine

### Task 3: MockImeEngine for daemon tests

**Files:** `src/testing/mock_ime_engine.zig` (create), `src/testing/helpers.zig`
(modify)

**Spec:** daemon-architecture v1.0-r8 `03-integration-boundaries.md` §5.3
(MockImeEngine enables testing all key routing logic without libhangul)

**Depends on:** Task 1 (ImeEngine vtable)

**Verification:**

- MockImeEngine implements the ImeEngine vtable
- Supports configurable responses (preset ImeResult for next processKey call)
- Tracks call history (which methods called, with what arguments)
- Can be wired into Session.ime_engine for routing tests

### Task 4: Wire-to-KeyEvent decomposition

**Files:** `src/input/wire_decompose.zig` (create), `src/input/root.zig`
(create)

**Spec:** daemon-architecture v1.0-r8 `03-integration-boundaries.md` §5.2
Wire-to-KeyEvent Decomposition table (6 wire bits → KeyEvent fields)

**Depends on:** Task 1 (KeyEvent type)

**Verification:**

- Decomposes wire modifier byte into KeyEvent.shift + KeyEvent.modifiers
- Bit 0 → shift, Bit 1 → ctrl, Bit 2 → alt, Bit 3 → super_key
- Bits 4-5 (CapsLock, NumLock) not passed to KeyEvent
- All 6 wire bits tested in isolation and combination

### Task 5: Key router (Phase 0 + Phase 1)

**Files:** `src/input/key_router.zig` (create), `src/input/root.zig` (modify)

**Spec:** daemon-architecture v1.0-r8 `03-integration-boundaries.md` §5.2
(3-phase pipeline overview, Phase 0 shortcut check, Phase 1 processKey)

**Depends on:** Task 1 (ImeEngine, KeyEvent, ImeResult), Task 4 (wire
decomposition)

**Verification:**

- Phase 0: language toggle keys detected and consumed (calls
  setActiveInputMethod, ImeResult consumed — committed_text written to PTY per
  buffer lifetime constraint §5.5, toggle key itself not forwarded)
- Phase 0: daemon shortcuts detected and consumed
- Phase 0: non-shortcut keys passed to Phase 1
- Phase 1: engine.processKey called with decomposed KeyEvent
- ImeResult returned to caller (server/) for Phase 2
- HID keycodes > HID_KEYCODE_MAX bypass IME entirely
- Mouse button events trigger flush before processing (§5.7)
- Mouse scroll/move do NOT trigger flush

### Task 6: Phase 2 ImeResult consumer

**Files:** `src/server/ime_consumer.zig` (create)

**Spec:** daemon-architecture v1.0-r8 `03-integration-boundaries.md` §5.6
(ImeResult to ghostty API mapping) and §5.5 (critical runtime invariant —
consume before next engine call)

**Depends on:** Task 1 (ImeResult type), Task 5 (key router returns ImeResult)

**Verification:**

- committed_text → write to PTY fd
- preedit_text (when preedit_changed) → @memcpy to session.preedit_buf, update
  session.current_preedit
- forward_key → key_encode.encode() + write to PTY fd
- preedit cleared (preedit_text=null, preedit_changed=true) → set
  session.current_preedit = null
- ImeResult consumed BEFORE any subsequent engine call (invariant from §5.5)
- Never uses ghostty_surface_text() for committed text (Korean doubling bug)
- Marks pane dirty after preedit change

### Task 7: Per-session IME lifecycle

**Files:** `src/server/ime_lifecycle.zig` (create), `src/server/event_loop.zig`
(modify)

**Spec:** daemon-architecture v1.0-r8 `03-integration-boundaries.md` §5.1
(lifecycle event mapping table) and behavior §4.3 (eager activate/deactivate on
session focus change)

**Depends on:** Task 1 (ImeEngine), Task 2 (Session IME fields)

**Verification:**

- Engine created on session creation (default: direct mode)
- Engine destroyed (deinit) on session destruction
- deactivate() called when session's attached-client count drops to zero
- activate() called only when count goes from 0→1 (session gains first client)
- deactivate() scope is per-session, not per-client (§4.3)
- Language state preserved across deactivate/activate cycles
- deactivate() return value consumed: if committed text returned, write to PTY;
  if preedit_changed, set session.current_preedit to null and mark dirty (§4.3
  steps 1-3, conditional on ImeResult fields)

### Task 8: IME procedures

**Files:** `src/server/ime_procedures.zig` (create)

**Spec:** daemon-behavior v1.0-r8 `impl-constraints/ime-procedures.md` §8.1–§8.5

**Depends on:** Task 6 (ImeResult consumer), Task 7 (lifecycle)

**Verification:**

- §8.1 Ownership transfer: flush → consume result → clear preedit → send
  PreeditEnd (stub) with old session_id → incrementSessionId → update owner —
  buffer lifetime constraint enforced (consume before next engine call) —
  PreeditState.owner and PreeditState.incrementSessionId() exercised
- §8.2 Client disconnect/detach/eviction: ownership resolved before teardown
- §8.3 Focus change: flush to OLD pane before updating focused_pane
- §8.3 Pane close: reset() NOT flush() — composition discarded; clear
  session.current_preedit (null) and session.preedit.owner (null); PreeditEnd
  (stub) then incrementSessionId()
- §8.3 Alternate screen switch: flush + commit before screen switch; clear
  session.current_preedit and session.preedit.owner
- §8.3 Resize during composition: preedit unchanged, re-overlay at export
- §8.4 Rapid keystroke burst: all keys processed in order; intermediate
  PreeditUpdate messages naturally absent because wire sending is stubbed
- §8.4 Mouse click: flush before mouse event forwarding
- §8.4 InputMethodSwitch: commit_current=true → setActiveInputMethod (atomically
  flushes), consume committed_text, write to PTY, PreeditEnd (stub) +
  InputMethodAck (stub); commit_current=false → reset, clear
  current_preedit/owner, setActiveInputMethod, PreeditEnd (stub) then
  incrementSessionId(), InputMethodAck (stub)
- §8.5 Error recovery: log + best-effort commit + reset to known-good state

### Task 9: Client read handler + event loop wiring

**Files:** `src/server/handlers/client_read.zig` (modify),
`src/server/event_loop.zig` (modify), `build.zig` (modify)

**Spec:** daemon-architecture v1.0-r8 `03-integration-boundaries.md` §5.2
(end-to-end key input data flow) and §5.8 (sequence diagram)

**Depends on:** Tasks 5, 6, 7, 8 (full pipeline)

**Verification:**

- client_read.zig dispatches KeyEvent through input/ → server/ pipeline
- Event loop wires libitshell3-ime HangulImeEngine into session creation
- build.zig adds libitshell3-ime dependency and input/ named sub-module
- End-to-end test: MockImeEngine receives key, returns ImeResult, consumer
  writes to PTY and updates preedit — full pipeline verified
- All existing tests still pass (no regressions)

## Dependency Graph

```
Task 1 (ImeEngine vtable + types)
├── Task 2 (Session IME fields)
│   └── Task 7 (IME lifecycle) ──┐
├── Task 3 (MockImeEngine)       │
├── Task 4 (Wire decomposition)  │
│   └── Task 5 (Key router)      │
│       └── Task 6 (ImeResult consumer)
│           └── Task 8 (IME procedures) ← also needs Task 7
│               └── Task 9 (Wiring + build) ← needs all above
```

**Parallelization:** Tasks 2, 3, 4 can run in parallel after Task 1.

## Summary

| Task | Files                                                     | Spec Section                         |
| ---- | --------------------------------------------------------- | ------------------------------------ |
| 1    | `core/ime_engine.zig`, `core/root.zig`                    | IME contract §1-2, §3.5              |
| 2    | `core/types.zig`, `core/session.zig`                      | arch §5.1, state-and-types §1.2-§1.3 |
| 3    | `testing/mock_ime_engine.zig`, `testing/helpers.zig`      | arch §5.3                            |
| 4    | `input/wire_decompose.zig`, `input/root.zig`              | arch §5.2 Wire-to-KeyEvent table     |
| 5    | `input/key_router.zig`, `input/root.zig`                  | arch §5.2 pipeline overview          |
| 6    | `server/ime_consumer.zig`                                 | arch §5.6, §5.5                      |
| 7    | `server/ime_lifecycle.zig`, `server/event_loop.zig`       | arch §5.1, behavior §4.3             |
| 8    | `server/ime_procedures.zig`                               | behavior §8.1–§8.5                   |
| 9    | `handlers/client_read.zig`, `event_loop.zig`, `build.zig` | arch §5.2, §5.8                      |
