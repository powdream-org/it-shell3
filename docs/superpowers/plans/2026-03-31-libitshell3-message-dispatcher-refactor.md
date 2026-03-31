# Message Dispatcher Refactor Implementation Plan

**Goal:** Refactor the monolithic `message_dispatcher.zig` into a two-level
category-based dispatch architecture matching protocol message type ranges, with
no behavioral change.

**Architecture:** The top-level dispatcher becomes a thin router that shifts
`msg_type >> 8` to select one of six category dispatchers. Each category
dispatcher owns JSON parsing and handler invocation for its message range. The
0x01xx category uses a second-level split via `(raw & 0xC0) >> 6` to separate
session, pane, and notification sub-categories. Four stub dispatchers (input,
render, IME, flow control) provide pre-wired entry points for Plans 8 and 9.

**Tech Stack:** Zig (build.zig modules: itshell3\_server, itshell3\_protocol,
itshell3\_core)

**Spec references:**

- protocol 01-protocol-overview §4 — Message Type ID Allocation (range
  definitions)
- ADR 00064 — Category-Based Message Dispatcher (structural decision)
- daemon-architecture v1.0-r8 01-module-structure — server/ component
  responsibilities
- daemon-behavior v1.0-r8 02-event-handling — response-before-notification
  ordering

---

## Scope

**In scope:**

1. Define `CategoryDispatchParams` struct in `message_dispatcher.zig`
2. Refactor top-level `dispatch()` to a page-level switch (`msg_type >> 8`)
3. Extract lifecycle message handling into `lifecycle_dispatcher.zig` (0x00xx)
4. Extract session/pane dispatch into `session_pane_dispatcher.zig` (0x01xx)
   with second-level split
5. Create stub dispatchers for input (0x02xx), render (0x03xx), IME (0x04xx),
   flow control (0x05xx)
6. Ensure all existing tests pass without modification

**Out of scope:**

- Adding new message type handlers (Plans 8, 9 will fill in stubs)
- Changing handler logic in `session_handler.zig` or `pane_handler.zig` (they
  remain as-is)
- Changing `notification_builder.zig` or `protocol_envelope.zig`
- Modifying the protocol library or message type definitions

## File Structure

| File                                              | Action | Responsibility                                                 |
| ------------------------------------------------- | ------ | -------------------------------------------------------------- |
| `src/server/handlers/message_dispatcher.zig`      | Modify | Slim down to CategoryDispatchParams + page-level switch router |
| `src/server/handlers/lifecycle_dispatcher.zig`    | Create | Handshake, heartbeat, disconnect, error handling (from 0x00xx) |
| `src/server/handlers/session_pane_dispatcher.zig` | Create | Second-level split: session, pane, notification (0x01xx)       |
| `src/server/handlers/input_dispatcher.zig`        | Create | Stub dispatcher for 0x02xx (Plan 8)                            |
| `src/server/handlers/render_dispatcher.zig`       | Create | Stub dispatcher for 0x03xx (Plan 9)                            |
| `src/server/handlers/ime_dispatcher.zig`          | Create | Stub dispatcher for 0x04xx (Plan 8)                            |
| `src/server/handlers/flow_control_dispatcher.zig` | Create | Stub dispatcher for 0x05xx (Plan 9)                            |

## Tasks

### Task 1: Define CategoryDispatchParams and refactor top-level dispatch

**Files:** `src/server/handlers/message_dispatcher.zig` (modify)

**Spec:** ADR 00064 — CategoryDispatchParams struct definition and page-level
switch. Protocol 01-protocol-overview §4 — message type range boundaries.

**Depends on:** None

**Verification:**

- `message_dispatcher.zig` contains a `CategoryDispatchParams` struct and a
  top-level `dispatch()` that switches on `msg_type >> 8` with six arms (0x00
  through 0x05) plus an `else` catch-all
- `DispatcherContext` struct is preserved with all existing fields
- Helper functions (`makeSessionHandlerContext`, `makePaneHandlerContext`,
  `parseDirection`) are removed from this file (they move to category
  dispatchers in subsequent tasks)
- The `READY_IDLE_TIMEOUT_MS` constant remains in this file
- File compiles (category dispatcher imports may be stubs at this point)

### Task 2: Create lifecycle dispatcher

**Files:** `src/server/handlers/lifecycle_dispatcher.zig` (create),
`src/server/handlers/message_dispatcher.zig` (modify — remove lifecycle
functions)

**Spec:** Protocol 01-protocol-overview §4 — Handshake & Lifecycle range
(0x0001-0x00FF). daemon-behavior 02-event-handling — handshake state machine,
heartbeat processing.

**Depends on:** Task 1

**Verification:**

- `lifecycle_dispatcher.zig` exports a `dispatch` function accepting
  `CategoryDispatchParams`
- Handles `client_hello`, `heartbeat`, `heartbeat_ack`, `disconnect`, and
  `error` message types
- All lifecycle-related private functions (`handleClientHello`,
  `cancelHandshakeTimer`, `handleHeartbeat`, `handleHeartbeatAck`,
  `handleDisconnect`) are moved from `message_dispatcher.zig` into this file
- `message_dispatcher.zig` no longer contains any lifecycle handling logic
- Existing lifecycle tests pass (handshake, heartbeat, disconnect flows)

### Task 3: Create session/pane dispatcher with second-level split

**Files:** `src/server/handlers/session_pane_dispatcher.zig` (create),
`src/server/handlers/message_dispatcher.zig` (modify — remove session/pane arms)

**Spec:** ADR 00064 — second-level split via `(raw & 0xC0) >> 6` for session
(0x0100-0x013F), pane (0x0140-0x017F), notification (0x0180-0x019F). Protocol
01-protocol-overview §4 — Session & Pane Management range (0x0100-0x01FF).

**Depends on:** Task 1

**Verification:**

- `session_pane_dispatcher.zig` exports a `dispatch` function accepting
  `CategoryDispatchParams`
- Contains a second-level switch on `(@intFromEnum(msg_type) & 0xC0) >> 6` with
  arms for session (0), pane (1), and notification (2)
- Session arm dispatches all seven session request types (CreateSession through
  AttachOrCreate) with JSON parsing
- Pane arm dispatches all ten pane request types (CreatePane through LayoutGet)
  with JSON parsing
- Notification arm is a no-op (server-to-client only; daemon does not receive
  notifications)
- `makeSessionHandlerContext`, `makePaneHandlerContext`, and `parseDirection`
  helper functions reside in this file
- `message_dispatcher.zig` no longer contains any session/pane handling logic
- All existing session and pane handler tests pass

### Task 4: Create stub dispatchers for future plans

**Files:** `src/server/handlers/input_dispatcher.zig` (create),
`src/server/handlers/render_dispatcher.zig` (create),
`src/server/handlers/ime_dispatcher.zig` (create),
`src/server/handlers/flow_control_dispatcher.zig` (create)

**Spec:** Protocol 01-protocol-overview §4 — Input Forwarding (0x0200-0x02FF),
Render State (0x0300-0x03FF), CJK & IME (0x0400-0x04FF), Flow Control
(0x0500-0x05FF).

**Depends on:** Task 1

**Verification:**

- Each stub file exports a `dispatch` function accepting
  `CategoryDispatchParams`
- Each stub function is a no-op (silently ignores all message types in its
  range)
- All four files compile and are importable from `message_dispatcher.zig`
- Dispatching a message type from any of these ranges does not crash (existing
  test for unknown message types still passes)

### Task 5: Verify full integration and test suite

**Files:** No new files — verification only

**Spec:** ADR 00064 — "Pure structural refactor. No behavioral change — all
existing tests continue to pass without modification."

**Depends on:** Tasks 2, 3, 4

**Verification:**

- `zig build test --summary all` passes with zero failures from project root
  (subshell into `modules/libitshell3`)
- `message_dispatcher.zig` is under 80 lines (down from ~420)
- No handler logic remains in `message_dispatcher.zig` — only the
  `CategoryDispatchParams` struct, `DispatcherContext` struct,
  `READY_IDLE_TIMEOUT_MS` constant, page-level switch, and test infrastructure
- Each category dispatcher is self-contained: no cross-imports between category
  dispatchers

## Dependency Graph

```
Task 1 (CategoryDispatchParams + router)
├── Task 2 (lifecycle dispatcher)
├── Task 3 (session/pane dispatcher)
└── Task 4 (stub dispatchers)
         └── all three ──→ Task 5 (integration verification)
```

Tasks 2, 3, and 4 are independent of each other and can proceed in parallel
after Task 1 completes.

## Summary

| Task | Files                                                                                                | Spec Section                                   |
| ---- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| 1    | `message_dispatcher.zig`                                                                             | ADR 00064, protocol §4                         |
| 2    | `lifecycle_dispatcher.zig`, `message_dispatcher.zig`                                                 | Protocol §4 (0x00xx), daemon-behavior §2       |
| 3    | `session_pane_dispatcher.zig`, `message_dispatcher.zig`                                              | ADR 00064 (second-level), protocol §4 (0x01xx) |
| 4    | `input_dispatcher.zig`, `render_dispatcher.zig`, `ime_dispatcher.zig`, `flow_control_dispatcher.zig` | Protocol §4 (0x02xx-0x05xx)                    |
| 5    | (verification only)                                                                                  | ADR 00064 (no behavioral change)               |
