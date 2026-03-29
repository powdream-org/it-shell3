# Session & Pane Operations Implementation Plan

**Goal:** Implement session CRUD, pane CRUD, session attachment tracking, pane
metadata extraction, and always-sent notifications on top of the Plan 6 message
dispatch infrastructure.

**Architecture:** Message handlers for 20+ request/response pairs routed through
the existing `message_dispatcher.zig`. Each handler validates state, mutates
`SessionManager`/`SessionEntry`/`Session` structs, sends a response to the
requester via the direct queue, then broadcasts notifications to peers. All
operations are single-event-loop-iteration atomic per the daemon-behavior
invariant.

**Tech Stack:** Zig, libitshell3 (core/ + server/), libitshell3-protocol
(message types, header serialization), POSIX (forkpty, ioctl TIOCSWINSZ).

**Spec references:**

- `daemon-architecture/draft/v1.0-r8/01-module-structure.md` (module
  decomposition, SessionEntry, pane struct placement)
- `daemon-architecture/draft/v1.0-r8/02-state-and-types.md` (state tree, pane
  metadata tracking, PTY lifecycle, layout enforcement)
- `daemon-architecture/draft/v1.0-r8/impl-constraints/state-and-types.md` (type
  definitions reference)
- `daemon-behavior/draft/v1.0-r8/01-daemon-lifecycle.md` (startup default
  session)
- `daemon-behavior/draft/v1.0-r8/02-event-handling.md` (response-before-
  notification, session rename, client connect/disconnect, preedit lifecycle on
  state changes)
- `daemon-behavior/draft/v1.0-r8/03-policies-and-procedures.md` (connection
  limits, multi-client resize, notification defaults, client state transitions)
- `server-client-protocols/draft/v1.0-r12/01-protocol-overview.md` (binary
  framing, message type ranges)
- `server-client-protocols/draft/v1.0-r12/03-session-pane-management.md` (all
  session/pane message definitions, layout tree wire format, notifications)

---

## Scope

**In scope:**

1. Protocol header wrapping for all outbound messages (fix Plan 6 TODO: raw JSON
   without 16-byte header)
2. Pane metadata detection via ghostty vtStream() processing (title/cwd change
   detection, PaneMetadataChanged broadcast)
3. Real `creation_timestamp` on session creation (fix Plan 5.5 TODO)
4. Pane fields: `foreground_process`, `foreground_pid` (fix Plan 5.5 TODO;
   stubbed, not populated until process monitoring is implemented)
5. Session messages: CreateSessionRequest/Response,
   ListSessionsRequest/Response, AttachSessionRequest/Response,
   DetachSessionRequest/Response, DestroySessionRequest/Response,
   RenameSessionRequest/Response, AttachOrCreateRequest/Response
6. Pane messages: CreatePaneRequest/Response, SplitPaneRequest/Response,
   ClosePaneRequest/Response, FocusPaneRequest/Response,
   NavigatePaneRequest/Response, ResizePaneRequest/Response,
   EqualizeSplitsRequest/Response, ZoomPaneRequest/Response,
   SwapPanesRequest/Response, LayoutGetRequest/Response
7. Always-sent notifications: LayoutChanged, SessionListChanged,
   PaneMetadataChanged, ClientAttached, ClientDetached
8. Session attachment tracking (attached_session_id + attached_session pointer)
9. Layout tree JSON serialization (recursive split tree to wire format)
10. PaneId-to-PaneSlot wire lookup in SessionEntry

**Out of scope:**

- Preedit interaction with focus/close/destroy operations — Plan 8 (requires
  PreeditEnd wire messages not yet implemented)
- ClientHealthChanged notification — Plan 9 (requires health escalation)
- Opt-in notifications (ProcessExited, Bell, etc.) — Plan 17+
- Silence detection fields (silence_subscriptions, silence_deadline) — Plan 17+
- PTY fork for new panes (forkpty + Terminal.init) — requires OS vtable
  extension, included as a task but shell spawning is stub-ready
- Ring cursor initialization on attach — Plan 9 (frame delivery pipeline)
- Multi-client resize calculation — Plan 9 (resize policy engine)
- WindowResize handling — Plan 9 (resize debounce + TIOCSWINSZ)

## File Structure

| File                                       | Action             | Responsibility                                                                                                                               |
| ------------------------------------------ | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `server/handlers/message_dispatcher.zig`   | Modify             | Route session/pane message types to new handler modules; fix protocol header wrapping TODO                                                   |
| `server/handlers/session_handler.zig`      | New                | Handle 7 session request types (Create, List, Attach, Detach, Destroy, Rename, AttachOrCreate)                                               |
| `server/handlers/pane_handler.zig`         | New                | Handle 10 pane request types (Create, Split, Close, Focus, Navigate, Resize, Equalize, Zoom, Swap, LayoutGet)                                |
| `server/handlers/notification_builder.zig` | New                | Build JSON payloads for 5 always-sent notifications (LayoutChanged, SessionListChanged, PaneMetadataChanged, ClientAttached, ClientDetached) |
| `server/handlers/protocol_envelope.zig`    | New                | Wrap JSON payloads with 16-byte protocol header; used by all outbound message paths                                                          |
| `server/connection/connection_state.zig`   | Modify             | Remove TODO(Plan 7) for OPERATING→OPERATING transition (invalid per ADR 00020)                                                               |
| `server/state/session_manager.zig`         | Modify             | Add `findSessionByName`, `getSessionList`, rename helpers                                                                                    |
| `server/state/session_entry.zig`           | Modify             | Add `findPaneByPaneId` (wire ID to slot lookup), `attachedClientCount` tracking, zoom state                                                  |
| `server/state/pane.zig`                    | Modify             | Add `foreground_process`, `foreground_pid` fields; assign vt_stream during creation; make terminal/render_state non-optional                 |
| `server/handlers/pty_read_handler.zig`     | Modify             | Add metadata change detection hook after vtStream processing (title/cwd changes → PaneMetadataChanged)                                       |
| `core/session.zig`                         | Modify             | Accept `creation_timestamp` parameter in `init()`, add `setName()`                                                                           |
| `core/split_tree.zig`                      | Modify             | Add `equalizeRatios()`, `swapLeaves()`, `computeLeafDimensions()`                                                                            |
| `server/connection/broadcast.zig`          | Modify (if needed) | Ensure `broadcastToAllConnected` exists (READY + OPERATING, for SessionListChanged)                                                          |
| `server/root.zig`                          | Modify             | Export new handler modules                                                                                                                   |
| `server/handlers/timer_handler.zig`        | Modify             | Fix protocol header wrapping for heartbeat messages                                                                                          |

## Tasks

### Task 1: Protocol Envelope — Header Wrapping for Outbound Messages

**Files:** `server/handlers/protocol_envelope.zig` (new),
`server/handlers/message_dispatcher.zig`, `server/handlers/timer_handler.zig`

**Spec:** protocol 01-protocol-overview (16-byte header: magic 0x4954 + version

- flags + msg_type + reserved + payload_len + sequence)

**Depends on:** None (prerequisite for all subsequent tasks)

**Verification:**

- All outbound messages (ServerHello, HeartbeatAck, Heartbeat) are prefixed with
  the 16-byte protocol header
- Header fields (magic, version, flags, msg_type, payload_length, sequence) are
  correctly populated
- Existing handshake and heartbeat tests continue to pass
- The envelope function is reusable by all handler modules

### Task 2: ADR 00020 Compliance — Remove Invalid OPERATING→OPERATING Transition

**Files:** `server/connection/connection_state.zig`

**Spec:** ADR 00020 (session attachment model: client must DetachSessionRequest
before AttachSessionRequest; OPERATING→OPERATING is NOT valid)

**Depends on:** None

**Verification:**

- The `TODO(Plan 7)` for OPERATING→OPERATING transition is removed
- `transitionTo(.operating)` from `.operating` remains rejected (returns error)
- All existing transition tests continue to pass
- No code path enables session switching without going through READY first

### Task 3: Session Creation Timestamp and Name Mutation

**Files:** `core/session.zig`, `server/state/session_manager.zig`

**Spec:** daemon-architecture 02-state-and-types (Session.creation_timestamp),
protocol 03-session-pane-management (ListSessionsResponse includes created_at)

**Depends on:** None

**Verification:**

- `Session.init()` accepts a `creation_timestamp` parameter (no longer hardcoded
  to 0)
- `Session.setName()` updates inline buffer and name_length
- `SessionManager.createSession()` accepts and forwards a timestamp
- `SessionManager.findSessionByName()` returns the matching entry or null

### Task 4: Pane Struct Field Additions and Type Corrections

**Files:** `server/state/pane.zig`, `core/types.zig`

**Spec:** daemon-architecture impl-constraints/state-and-types.md (Pane:
foreground_process, foreground_pid, terminal, render_state)

**Depends on:** None

**Verification:**

- `Pane` has `foreground_process` (inline buffer + length) and `foreground_pid`
  fields
- Fields initialize to empty/zero defaults
- Setter methods follow existing pattern (setTitle, setCwd)
- `terminal` and `render_state` fields are non-optional (`*` not `?*`) per spec
- Import aliases (`terminal_mod`, `render_state_mod`) are replaced with direct
  `ghostty.terminal` / `ghostty.render_state` namespace references
- `vt_stream` field uses `ghostty.terminal.ReadonlyStream` namespace (not alias)

### Task 5: SessionEntry Enhancements — Wire ID Lookup, Zoom State, Attachment Counting

**Files:** `server/state/session_entry.zig`

**Spec:** daemon-architecture 01-module-structure (PaneId wire lookup is cold
path, linear scan of pane_slots), protocol 03-session-pane-management (zoom
state in ZoomPaneResponse and LayoutChanged)

**Depends on:** Task 4

**Verification:**

- `findPaneSlotByPaneId(pane_id: PaneId)` returns `?PaneSlot` via linear scan
- Zoom state tracked (zoomed_pane: ?PaneSlot)
- `toggleZoom()` sets/clears zoom state
- When zoomed, layout queries report the zoomed pane filling the full area

### Task 6: Split Tree Operations — Equalize, Swap, Leaf Dimensions

**Files:** `core/split_tree.zig`

**Spec:** protocol 03-session-pane-management (EqualizeSplitsRequest sets all
ratios to 0.5, SwapPanesRequest swaps two leaves,
LayoutChanged/LayoutGetResponse carries per-leaf cols/rows/x_off/y_off)

**Depends on:** None

**Verification:**

- `equalizeRatios()` sets all split node ratios to 0.5
- `swapLeaves()` exchanges two PaneSlot values in the tree
- `computeLeafDimensions()` returns per-leaf (cols, rows, x_offset, y_offset)
  given total_cols and total_rows
- All operations preserve tree structural invariants

### Task 7: Notification Builders

**Files:** `server/handlers/notification_builder.zig` (new)

**Spec:** protocol 03-session-pane-management (LayoutChanged 0x0180,
PaneMetadataChanged 0x0181, SessionListChanged 0x0182, ClientAttached 0x0183,
ClientDetached 0x0184)

**Depends on:** Task 1 (protocol envelope), Task 6 (leaf dimensions for
LayoutChanged)

**Verification:**

- Each builder produces a JSON payload wrapped in a protocol header
- LayoutChanged includes recursive layout tree with per-leaf fields (pane_id,
  cols, rows, x_off, y_off, preedit_active, active_input_method,
  active_keyboard_layout), active_pane_id, zoomed_pane_present, zoomed_pane_id
- SessionListChanged includes event type (created/destroyed/renamed),
  session_id, name
- PaneMetadataChanged includes only changed fields
- ClientAttached/ClientDetached include session_id, client_id, client_name,
  attached_clients count
- All builders use fixed-size scratch buffers (no heap allocation)

### Task 8: Pane Metadata Detection via vtStream Processing

**Files:** `server/state/pane.zig`, `server/handlers/pty_read_handler.zig`

**Spec:** daemon-architecture 01-module-structure (Section 1.6 — metadata
changes detected during terminal.vtStream() processing),
implementation-learnings G3 (vtStream returns ephemeral parser state held for
pane lifetime)

**Depends on:** Task 4 (pane fields), Task 7 (notification builders)

**Verification:**

- ghostty vtStream() lifecycle is correctly managed: stream obtained during pane
  creation, held for pane lifetime, released during pane destruction
- vt_stream field is assigned during pane creation and cleared during pane
  destruction
- After vtStream processing in the pty_read handler, title/cwd changes are
  detected by comparing previous and current values
- On title or cwd change: Pane fields are updated, PaneMetadataChanged
  notification is broadcast to session-scoped peers
- Import aliases (`terminal_mod`) cleaned up to use `ghostty.terminal` namespace
  directly

### Task 9: Session Handlers — Create, List, Rename

**Files:** `server/handlers/session_handler.zig` (new),
`server/handlers/message_dispatcher.zig`

**Spec:** protocol 03-session-pane-management (0x0100-0x010B), daemon-behavior
02-event-handling (session rename broadcast, response-before-notification)

**Depends on:** Task 1, Task 3, Task 7

**Verification:**

- CreateSessionRequest: allocates session via SessionManager, allocates initial
  pane slot, sends CreateSessionResponse to requester, broadcasts
  SessionListChanged(event="created") to all connected clients
- ListSessionsRequest: iterates SessionManager slots, sends ListSessionsResponse
  with session_id, name, created_at, pane_count, attached_clients for each
  session
- RenameSessionRequest: validates duplicate name, updates session name, sends
  RenameSessionResponse then SessionListChanged(event="renamed")
- Error cases: MaxSessionsReached, session not found, duplicate name
- Response-before-notification ordering is maintained

### Task 10: Session Handlers — Attach, Detach, Destroy, AttachOrCreate

**Files:** `server/handlers/session_handler.zig`,
`server/connection/connection_state.zig`

**Spec:** protocol 03-session-pane-management (0x0104-0x010D), daemon-behavior
02-event-handling (session destroy cascade wire ordering), daemon-behavior
03-policies-and-procedures (client state transitions), daemon-behavior
02-event-handling (Section 4.2 DestroySessionRequest 5 wire messages), ADR 00020
(session attachment model)

**Depends on:** Task 5, Task 7, Task 9

**Verification:**

- AttachSessionRequest: transitions client to OPERATING, sets
  attached_session_id and attached_session pointer, sends AttachSessionResponse
  (with active_pane_id, input method, resize policy), sends LayoutChanged, sends
  ClientAttached to other attached clients
- AttachSessionRequest while OPERATING: returns ERR_SESSION_ALREADY_ATTACHED per
  ADR 00020 — client must DetachSessionRequest first
- DetachSessionRequest: clears attachment, transitions to READY, sends
  DetachSessionResponse, sends ClientDetached to remaining peers
- DestroySessionRequest (5 wire messages per daemon-behavior Section 4.2):
  1. PreeditEnd to affected clients (out of scope Plan 8 — note as TODO)
  2. DestroySessionResponse to requester
  3. SessionListChanged(event="destroyed") broadcast
  4. DetachSessionResponse to each other attached client
  5. ClientDetached(client_id=C) to requester, for each detached peer client
- AttachOrCreate: finds session by name or creates new, then follows attach
  flow; response includes action_taken field
- detach_others: force-detaches other clients before attaching

### Task 11: Pane Handlers — Create, Split, Close

**Files:** `server/handlers/pane_handler.zig` (new),
`server/handlers/message_dispatcher.zig`

**Spec:** protocol 03-session-pane-management (0x0140-0x0145, Section 2.1-2.4),
daemon-architecture 02-state-and-types (layout enforcement, pane limit),
daemon-behavior 02-event-handling (pane exit cascade wire messages)

**Depends on:** Task 5, Task 7

**Verification:**

- CreatePaneRequest: allocates a standalone pane in the session without
  splitting, sends CreatePaneResponse(new_pane_id), broadcasts LayoutChanged;
  validates pane limit (PANE_LIMIT_EXCEEDED); initializes Terminal and
  RenderState for the new pane (non-optional per spec)
- SplitPaneRequest: validates pane limit (PANE_LIMIT_EXCEEDED) and minimum pane
  size (TOO_SMALL, status 3), allocates new pane slot, calls
  split_tree.splitLeaf with direction/ratio, sends
  SplitPaneResponse(new_pane_id), broadcasts LayoutChanged; unzooms if zoomed;
  initializes Terminal and RenderState for the new pane (non-optional per spec)
- ClosePaneRequest: calls split_tree.removeLeaf, frees pane slot, sends
  ClosePaneResponse (with side_effect and new_focus_pane_id), broadcasts
  LayoutChanged; when last pane, triggers session auto-destroy path
  (SessionListChanged + DetachSessionResponse to attached clients)
- Direction mapping: protocol direction integers (0-3) map to split tree
  orientation + left/right child placement
- Focus transfers to sibling on close per spec

### Task 12: Pane Handlers — Focus, Navigate

**Files:** `server/handlers/pane_handler.zig`

**Spec:** protocol 03-session-pane-management (0x0146-0x0149),
daemon-architecture 02-state-and-types (pane navigation algorithm)

**Depends on:** Task 5, Task 7

**Verification:**

- FocusPaneRequest: validates pane exists in session, updates
  session.focused_pane, sends FocusPaneResponse(previous_pane_id), broadcasts
  LayoutChanged
- NavigatePaneRequest: calls core/navigation.findPaneInDirection, updates
  focused_pane, sends NavigatePaneResponse(focused_pane_id), broadcasts
  LayoutChanged
- When focus does not change (single pane or same pane), response is sent but no
  LayoutChanged is broadcast

### Task 13: Pane Handlers — Resize, Equalize, Zoom, Swap, LayoutGet

**Files:** `server/handlers/pane_handler.zig`

**Spec:** protocol 03-session-pane-management (0x014A-0x0153)

**Depends on:** Task 5, Task 6, Task 7

**Verification:**

- ResizePaneRequest: finds the split node adjacent to the target pane in the
  requested direction, adjusts ratio by delta, sends ResizePaneResponse,
  broadcasts LayoutChanged
- EqualizeSplitsRequest: calls split_tree.equalizeRatios, sends
  EqualizeSplitsResponse, broadcasts LayoutChanged
- ZoomPaneRequest: toggles zoom via SessionEntry.toggleZoom, sends
  ZoomPaneResponse(zoomed), broadcasts LayoutChanged
- SwapPanesRequest: calls split_tree.swapLeaves, sends SwapPanesResponse,
  broadcasts LayoutChanged
- LayoutGetRequest: builds LayoutChanged-format payload, sends as
  LayoutGetResponse with RESPONSE flag

### Task 14: Message Dispatcher Integration

**Files:** `server/handlers/message_dispatcher.zig`, `server/root.zig`

**Spec:** protocol 01-protocol-overview (message type ranges 0x0100-0x01FF)

**Depends on:** Tasks 9-13

**Verification:**

- All session message types (0x0100-0x010D) dispatch to session_handler
- All pane message types (0x0140-0x0153) dispatch to pane_handler
- DispatcherContext includes SessionManager reference
- Unknown message types within the range are handled gracefully
- The `else` stub arm in dispatch() now routes to concrete handlers

### Task 15: Broadcast Enhancements

**Files:** `server/connection/broadcast.zig`

**Spec:** daemon-behavior 02-event-handling (SessionListChanged broadcast to ALL
connected clients), protocol 03-session-pane-management (ClientAttached/Detached
delivery scope)

**Depends on:** Task 7

**Verification:**

- SessionListChanged is delivered to all READY and OPERATING clients (not just
  session-scoped), using broadcastToActive
- ClientAttached/ClientDetached are delivered to session-scoped peers only
  (excluding the triggering client)
- LayoutChanged is delivered to session-scoped peers only

---

## Dependency Graph

```
Task 1 (protocol envelope)
Task 2 (ADR 00020 compliance — remove invalid transition)
Task 3 (session timestamp + name)
Task 4 (pane fields + type corrections)
Task 6 (split tree ops)
    |
    v
Task 5 (SessionEntry enhancements) -- depends on Task 4
    |
    v
Task 7 (notification builders) -- depends on Task 1, Task 6
    |
    v
Task 8 (metadata detection via vtStream) -- depends on Task 4, Task 7
Task 9 (session: create/list/rename) -- depends on Task 1, Task 3, Task 7
    |
    v
Task 10 (session: attach/detach/destroy/attachOrCreate) -- depends on Task 5, Task 7, Task 9
    |
    v
Task 11 (pane: create/split/close) -- depends on Task 5, Task 7
Task 12 (pane: focus/navigate) -- depends on Task 5, Task 7
Task 13 (pane: resize/equalize/zoom/swap/layoutget) -- depends on Task 5, Task 6, Task 7
    |
    v
Task 14 (dispatcher integration) -- depends on Tasks 9-13
    |
    v
Task 15 (broadcast enhancements) -- depends on Task 7
```

**Parallelizable groups:**

- Tasks 1, 2, 3, 4, 6 are all independent
- Task 5 after Task 4
- Task 7 after Tasks 1 + 6
- Tasks 8, 9, 11, 12, 13 after Task 7 (can run in parallel)
- Task 10 after Task 9
- Task 14 after all handlers
- Task 15 after Task 7

---

## Summary

| Task | Files                                                                        | Spec Section                                                                  |
| ---- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| 1    | `protocol_envelope.zig` (new), `message_dispatcher.zig`, `timer_handler.zig` | protocol 01 (16-byte header)                                                  |
| 2    | `connection_state.zig`                                                       | ADR 00020 (remove invalid OPERATING→OPERATING transition)                     |
| 3    | `session.zig`, `session_manager.zig`                                         | daemon-arch 02 (creation_timestamp), protocol 03 (ListSessions)               |
| 4    | `pane.zig`, `types.zig`                                                      | daemon-arch impl-constraints/state-and-types (fields + non-optional types)    |
| 5    | `session_entry.zig`                                                          | daemon-arch 01 (PaneId wire lookup), protocol 03 (zoom state)                 |
| 6    | `split_tree.zig`                                                             | protocol 03 (equalize, swap, layout dimensions)                               |
| 7    | `notification_builder.zig` (new)                                             | protocol 03 (0x0180-0x0184 notifications)                                     |
| 8    | `pane.zig`, `pty_read_handler.zig`                                           | daemon-arch 01 (Section 1.6 metadata detection), impl-learnings G3 (vtStream) |
| 9    | `session_handler.zig` (new), `message_dispatcher.zig`                        | protocol 03 (0x0100-0x010B)                                                   |
| 10   | `session_handler.zig`, `connection_state.zig`                                | protocol 03 (0x0104-0x010D), daemon-behavior 02/03, ADR 00020                 |
| 11   | `pane_handler.zig` (new), `message_dispatcher.zig`                           | protocol 03 (0x0140-0x0145), daemon-arch 02                                   |
| 12   | `pane_handler.zig`                                                           | protocol 03 (0x0146-0x0149), daemon-arch 02                                   |
| 13   | `pane_handler.zig`                                                           | protocol 03 (0x014A-0x0153)                                                   |
| 14   | `message_dispatcher.zig`, `root.zig`                                         | protocol 01 (message type ranges)                                             |
| 15   | `broadcast.zig`                                                              | daemon-behavior 02 (notification delivery scope)                              |
