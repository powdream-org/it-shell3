# Frame Delivery & Runtime Policies Implementation Plan

**Goal:** Wire the frame export pipeline end-to-end and implement all runtime
policies governing frame delivery, adaptive coalescing, health escalation, flow
control, resize orchestration, and EVFILT_WRITE delivery management.

**Architecture:** The plan builds atop Plan 4's ring buffer infrastructure and
Plan 8's input pipeline. It connects the ghostty export pipeline (bulkExport +
overlayPreedit) to the ring buffer via a new frame builder module, adds
coalescing timer and EVFILT_WRITE chain handlers, implements per-client health
state tracking with graduated degradation, and wires WindowResize through the
resize debounce and multi-client resize policy system. The I-frame scheduling
timer resets on any I-frame production (ADR 00057).

**Tech Stack:** Zig 0.15+, vendored libghostty (v1.3.1-patch), kqueue/epoll
event loop, libitshell3-protocol (FrameUpdate wire format, CellData encoding).

**Spec references:**

- daemon-behavior v1.0-r9 — `03-policies-and-procedures.md` (Sections 2-6)
- daemon-behavior v1.0-r9 — `02-event-handling.md` (Section 1, frame delivery
  data flow)
- daemon-architecture v1.0-r9 — `03-integration-boundaries.md` (Section 4.6
  frame export pipeline, Section 4.3 CellData/FlatCell)
- daemon-architecture v1.0-r9 — `02-state-and-types.md` (Section 4 ring buffer
  architecture, Section 4.9 I-frame scheduling)
- server-client-protocols v1.0-r13 — `04-input-and-renderstate.md` (Section 3
  FrameUpdate wire format, Section 3.2 JSON metadata blob)
- server-client-protocols v1.0-r13 — `06-flow-control-and-auxiliary.md`
  (Sections 1-2: ClientDisplayInfo, PausePane, ContinuePane, FlowControlConfig,
  OutputQueueStatus)
- server-client-protocols v1.0-r13 — `03-session-pane-management.md` (Section 5
  WindowResize, Section 4.6 ClientHealthChanged)
- ADR 00055 — Ring cursor lag formula (pre-computed byte thresholds)
- ADR 00056 — FrameEntry is prose; introduce `server/frame_builder.zig`
- ADR 00057 — I-frame timer resets on any I-frame production

---

## Scope

**In scope:**

1. Frame builder: FlatCell-to-CellData conversion and dirty bitmap to DirtyRow
   assembly (ADR 00056)
2. JSON metadata blob serialization for FrameUpdate (cursor, dimensions, colors,
   mouse, terminal modes)
3. Coalescing timer chain handler with 4-tier model and tier transition
   hysteresis
4. Per-(client, pane) coalescing state tracking
5. EVFILT_WRITE chain handler for two-channel delivery (direct queue then ring)
6. Ring cursor lag thresholds: pre-computed byte thresholds at ring init (ADR
   00055)
7. Smooth degradation based on ring cursor lag (50%/75%/90% thresholds)
8. Health escalation state machine (healthy/stale, PausePane timeline,
   ClientHealthChanged notification)
9. Flow control handlers: PausePane advisory tracking, ContinuePane with cursor
   advance, FlowControlConfig with transport-aware defaults
10. WindowResize handler with resize debounce (250ms per pane)
11. Multi-client resize policy (latest client tracking, stale exclusion)
12. Stale re-inclusion hysteresis (5s timer)
13. Resize orchestration: effective size computation, ioctl TIOCSWINSZ,
    WindowResizeAck, LayoutChanged, I-frame generation
14. I-frame scheduling timer with reset on any I-frame (ADR 00057)
15. Idle suppression during resize (500ms post-debounce settling)
16. Session attach initial I-frame delivery (resolve TODO in
    session_handler.zig)
17. Wire ghostty key_encode for bypassed keys (resolve TODO in
    input_dispatcher.zig)
18. AmbiguousWidthConfig pass-through to ghostty Terminal (resolve TODO in
    ime_dispatcher.zig)
19. Focus reporting mode check before writing focus escape (resolve TODO in
    input_dispatcher.zig)
20. Pane metadata extraction from ghostty Terminal after VT stream processing
    (resolve TODO in pty_read.zig)
21. Session dimensions wiring for pane handler (resolve TODOs for hardcoded
    80x24)

**Out of scope:**

- Pane exit cascade and session destroy cascade (Plan 10)
- Graceful shutdown sequence (Plan 10)
- Silence detection timer (Plan 17+)
- Opt-in notification subscriptions (Plan 17+)
- Mouse event handlers (Plan 17+)
- Clipboard (Plan 17+)
- OutputQueueStatus periodic notifications (lower priority, can be added later
  without structural changes)

---

## File Structure

| File                                               | Action | Responsibility                                                           |
| -------------------------------------------------- | ------ | ------------------------------------------------------------------------ |
| `src/server/delivery/frame_builder.zig`            | Create | FlatCell-to-CellData conversion, dirty bitmap-to-DirtyRow assembly       |
| `src/server/delivery/metadata_serializer.zig`      | Create | JSON metadata blob construction for FrameUpdate                          |
| `src/server/delivery/coalescing_state.zig`         | Create | Per-(client, pane) coalescing tier state and transition logic            |
| `src/server/delivery/ring_buffer.zig`              | Modify | Add pre-computed lag thresholds (ADR 00055)                              |
| `src/server/delivery/frame_serializer.zig`         | Modify | Accept optional JSON metadata blob alongside DirtyRows                   |
| `src/server/handlers/coalescing_timer_handler.zig` | Create | Coalescing timer chain handler: export, serialize, write to ring         |
| `src/server/handlers/write_handler.zig`            | Create | EVFILT_WRITE chain handler: drain direct queue then ring per client      |
| `src/server/handlers/resize_handler.zig`           | Create | WindowResize handler, debounce, multi-client resize policy orchestration |
| `src/server/handlers/flow_control_dispatcher.zig`  | Modify | Wire PausePane, ContinuePane, FlowControlConfig handlers                 |
| `src/server/handlers/session_pane_dispatcher.zig`  | Modify | Wire WindowResize dispatch (resolve TODO)                                |
| `src/server/handlers/timer_handler.zig`            | Modify | Add I-frame timer, health escalation timer, resize debounce timer IDs    |
| `src/server/handlers/session_handler.zig`          | Modify | Wire initial I-frame on session attach (resolve TODO)                    |
| `src/server/handlers/pane_handler.zig`             | Modify | Wire actual session dimensions instead of hardcoded 80x24                |
| `src/server/handlers/input_dispatcher.zig`         | Modify | Wire ghostty key_encode for bypassed keys, focus mode check              |
| `src/server/handlers/ime_dispatcher.zig`           | Modify | Wire AmbiguousWidthConfig pass-through to Terminal                       |
| `src/server/handlers/pty_read.zig`                 | Modify | Wire metadata extraction from ghostty Terminal                           |
| `src/server/handlers/notification_builder.zig`     | Modify | Add ClientHealthChanged notification builder                             |
| `src/server/connection/client_state.zig`           | Modify | Add health state, flow control config, coalescing state fields           |
| `src/server/state/session_entry.zig`               | Modify | Add effective dimensions, latest_client tracking enhancements            |
| `src/server/state/pane.zig`                        | Modify | Add last_i_frame_time, resize debounce deadline                          |

---

## Tasks

### Task 1: Frame Builder (FlatCell to CellData + DirtyRow Assembly)

**Files:** `src/server/delivery/frame_builder.zig` (create)

**Spec:** daemon-architecture §4.3 (CellData = FlatCell terminology binding,
field order divergence), §4.6 (frame export pipeline steps S3-S4); ADR 00056
(frame_builder.zig location and responsibility)

**Depends on:** None (standalone module)

**Verification:**

- FlatCell array with known field values converts to CellData array with correct
  protocol wire field order
- Dirty bitmap (256-bit) correctly maps to DirtyRow array with row indices
  matching set bits
- Empty dirty bitmap produces empty DirtyRow array
- Full dirty bitmap (I-frame) produces DirtyRow for every row
- Wide characters (wide=1 + spacer_tail=2) preserved through conversion
- Per-row side tables (GraphemeTable, UnderlineColorTable) are assembled from
  export result data

### Task 2: JSON Metadata Blob Serializer

**Files:** `src/server/delivery/metadata_serializer.zig` (create)

**Spec:** protocol 04 §3.2 (JSON metadata blob structure, field definitions,
I-frame required vs P-frame optional semantics); protocol 04 §3.1 (section_flags
bit 7 for JSON metadata presence)

**Depends on:** None (standalone module)

**Verification:**

- I-frame metadata includes all REQUIRED fields (cursor, dimensions, full
  256-entry palette, fg, bg, mouse, terminal_modes)
- P-frame metadata includes only changed fields; absent fields are omitted (not
  null)
- JSON output is valid UTF-8 and length-prefixed (4-byte u32 LE + JSON bytes)
- Cursor fields (x, y, visible, style, blinking, password_input) serialize
  correctly
- Palette serialization produces 256 entries with [r,g,b] triples
- palette_changes delta format serializes correctly for P-frames

### Task 3: Ring Buffer Lag Thresholds

**Files:** `src/server/delivery/ring_buffer.zig` (modify)

**Spec:** daemon-behavior §4.4 (smooth degradation thresholds 50%/75%/90%); ADR
00055 (pre-computed byte thresholds, lag formula, strict greater-than semantics)

**Depends on:** None

**Verification:**

- Thresholds are computed at init time from capacity using integer arithmetic
- `threshold_50 = capacity >> 1`
- `threshold_75 = (capacity >> 1) + (capacity >> 2)`
- `threshold_90 = capacity - capacity / 10`
- Lag check uses strict greater-than (lag at exactly 50% does not trigger)
- lagPercent and lagBytes functions return correct values for various cursor
  positions

### Task 4: Frame Serializer Enhancement (JSON Metadata Support)

**Files:** `src/server/delivery/frame_serializer.zig` (modify)

**Spec:** protocol 04 §3.1 (section_flags bit 7 for JSONMetadata); protocol 04
§3.2 (JSON blob follows binary DirtyRows/CellData section)

**Depends on:** Task 2 (metadata serializer produces the JSON blob)

**Verification:**

- When JSON metadata is provided, section_flags bit 7 is set
- JSON blob is appended after binary DirtyRows section with 4-byte length prefix
- When no JSON metadata, bit 7 is clear and no JSON section in output
- Total serialized size includes protocol header + frame header + DirtyRows +
  JSON metadata

### Task 5: Per-(Client, Pane) Coalescing State

**Files:** `src/server/delivery/coalescing_state.zig` (create),
`src/server/connection/client_state.zig` (modify)

**Spec:** daemon-behavior §5.1 (4-tier model + Idle), §5.2 (tier transitions
with hysteresis), §5.3 (preedit immediate rule), §5.5 (WAN coalescing
adjustments), §5.6 (power-aware throttling), §5.7 (idle suppression during
resize), §5.8 (per-(client, pane) cadence independence)

**Depends on:** Task 3 (lag thresholds for degradation integration)

**Verification:**

- Each (client, pane) pair has independent coalescing tier
- Tier 0 (Preedit) triggers on preedit state change regardless of current tier
- Interactive-to-Active downgrade requires sustained output >100ms
- Active-to-Bulk downgrade requires sustained high throughput >500ms
- Any-to-Idle after no output >100ms
- Upgrade (faster) is immediate on trigger event
- WAN adjustments: SSH transport raises Tier 2 to 33ms, Tier 3 to 100ms
- WAN adjustments: bandwidth_hint below 1 Mbps forces Tier 3 for all non-preedit
  output
- WAN adjustments: estimated_rtt_ms above 100ms increases Idle threshold to
  200ms
- Power-aware: battery caps at Tier 2, low_battery caps at Tier 3
- Preedit is never throttled regardless of power, transport, or bandwidth_hint
- One pane's tier does not affect another pane's delivery for same client

### Task 6: Client Health State and Flow Control Fields

**Files:** `src/server/connection/client_state.zig` (modify),
`src/server/state/session_entry.zig` (modify)

**Spec:** daemon-behavior §3.1-3.3 (health states, stale triggers), §3.5
(recovery), §4.3 (FlowControlConfig parameters), §2.2 (latest client tracking)

**Depends on:** None

**Verification:**

- ClientState has health_state (healthy/stale), paused flag, flow control config
  fields
- Health state transitions are tracked with timestamps
- Stale timeout resets on application-level messages (KeyEvent, WindowResize,
  ContinuePane, ClientDisplayInfo, request messages)
- HeartbeatAck does NOT reset stale timeout
- FlowControlConfig defaults differ by transport type (local vs SSH)
- SessionEntry latest_client_id updates on KeyEvent and WindowResize
- SessionEntry tracks effective dimensions (cols, rows) for the session

### Task 7: Health Escalation Timer and State Machine

**Files:** `src/server/handlers/timer_handler.zig` (modify),
`src/server/handlers/notification_builder.zig` (modify),
`src/server/connection/client_state.zig` (modify)

**Spec:** daemon-behavior §3.2 (PausePane escalation timeline: T=0 healthy, T=5s
resize excluded, T=60s/120s stale, T=300s evicted), §3.3 (ring cursor stagnation
trigger), §3.4 (preedit commit on eviction), §9.1 (ClientHealthChanged is
always-sent notification)

**Depends on:** Task 6 (health state fields)

**Verification:**

- At T=5s after PausePane, client is excluded from resize calculation
- At T=60s (local) or T=120s (SSH), ClientHealthChanged sent to peer clients
- At T=300s, Disconnect(reason: stale_client) sent and connection torn down
- Preedit commit occurs before eviction if client owns active preedit
- Recovery from stale advances ring cursor to latest I-frame
- ClientHealthChanged carries correct health/previous_health/reason fields
- Ring cursor stagnation (>90% for stale_timeout_ms) triggers stale
  independently
- On stale recovery, LayoutChanged enqueued to direct queue if layout changed
  during stale period
- On stale recovery, PreeditSync enqueued to direct queue if preedit is active
- Context messages (LayoutChanged, PreeditSync) arrive before the I-frame
  (guaranteed by direct queue priority over ring buffer)
- ContinuePane does NOT send context messages (stale recovery only)

### Task 8: Flow Control Handlers (PausePane, ContinuePane, FlowControlConfig)

**Files:** `src/server/handlers/flow_control_dispatcher.zig` (modify)

**Spec:** daemon-behavior §4.1 (PausePane advisory), §4.2 (ContinuePane recovery
ordering), §4.3 (FlowControlConfig parameters), §4.4 (smooth degradation);
protocol 06 §2.4-2.7 (PausePane/ContinuePane/FlowControlConfig wire formats)

**Depends on:** Task 6 (health/flow state fields), Task 5 (coalescing state for
tier restoration)

**Verification:**

- PausePane starts health escalation timeline, does NOT stop ring writes
- ContinuePane advances ring cursor to latest I-frame, restores coalescing tier
- FlowControlConfig updates per-client flow parameters, sends
  FlowControlConfigAck with effective values
- Smooth degradation: lag >50% auto-downgrades to Bulk, lag >75% forces Bulk,
  lag >90% next ContinuePane seeks to I-frame
- Transport-aware defaults applied correctly (local vs SSH)

### Task 9: Coalescing Timer Chain Handler

**Files:** `src/server/handlers/coalescing_timer_handler.zig` (create),
`src/server/handlers/timer_handler.zig` (modify)

**Spec:** daemon-architecture §4.6 (frame export pipeline: vtStream -> update ->
bulkExport -> overlayPreedit -> serialize -> ring); daemon-behavior §5.1-5.4
(coalescing tier intervals, preedit immediate rule, immediate-first-batch-rest)

**Depends on:** Task 1 (frame builder), Task 2 (metadata serializer), Task 4
(enhanced frame serializer), Task 5 (coalescing state)

**Verification:**

- Timer fires at the minimum coalescing interval across all active (client,
  pane) pairs
- For each dirty pane: RenderState.update + bulkExport + overlayPreedit + frame
  builder + serialize to ring
- Preedit state changes trigger immediate frame (Tier 0, 0ms)
- Immediate-first-batch-rest: preedit frame not delayed by PTY output batching
- Frame suppression for undersized panes (cols < 2 or rows < 1)
- Dirty mask cleared after frame export per pane
- frame_sequence incremented per write

### Task 10: I-Frame Scheduling Timer

**Files:** `src/server/state/pane.zig` (modify),
`src/server/handlers/coalescing_timer_handler.zig` (modify)

**Spec:** daemon-architecture §4.9 (I-frame scheduling: default 1s, configurable
0.5-5s, no-op when unchanged); ADR 00057 (timer resets on any I-frame
production)

**Depends on:** Task 9 (coalescing timer handler calls frame export)

**Verification:**

- Default keyframe interval is 1 second
- Timer resets on ANY I-frame production (attach, recovery, resize, timer)
- No-op when pane has no changes since last I-frame
- I-frame from non-timer source (e.g., resize) pushes next timer-driven I-frame
  forward by full interval
- Ring always contains at least one complete I-frame per pane

### Task 11: EVFILT_WRITE Chain Handler

**Files:** `src/server/handlers/write_handler.zig` (create)

**Spec:** daemon-architecture §4.4 (two-channel write priority), §4.7
(write-ready and backpressure); daemon-behavior §4.5 (socket write priority:
direct queue first, ring second)

**Depends on:** Task 3 (ring buffer with lag thresholds)

**Verification:**

- Direct queue drained completely before any ring buffer data
- Partial writes handled: cursor advances by bytes written, EVFILT_WRITE stays
  armed
- would_block: EVFILT_WRITE stays armed, no cursor advance
- peer_closed: triggers client disconnect
- EVFILT_WRITE disabled when client is fully caught up (no pending data)
- EVFILT_WRITE re-enabled when new frame data is written to ring
- Ring cursor overwrite detected: auto-seek to latest I-frame before delivery

### Task 12: WindowResize Handler with Debounce

**Files:** `src/server/handlers/resize_handler.zig` (create),
`src/server/handlers/session_pane_dispatcher.zig` (modify),
`src/server/state/pane.zig` (modify)

**Spec:** daemon-behavior §2 (multi-client resize policy), §2.4 (250ms per-pane
debounce), §2.5 (5s stale re-inclusion hysteresis), §2.6 (resize orchestration
ordering); daemon-architecture §1.4 (first-resize-no-debounce exception);
protocol 03 §5.1-5.3 (WindowResize/WindowResizeAck wire format)

**Depends on:** Task 6 (latest_client tracking, effective dimensions), Task 10
(I-frame scheduling for post-resize I-frame)

**Verification:**

- WindowResize parsed and client display_info updated
- Resize debounced at 250ms per pane (rapid WindowResize events coalesced)
- Latest policy: effective size = most recently active client's dimensions
- Stale clients excluded from resize computation
- Resize orchestration order: effective size -> ioctl(TIOCSWINSZ) ->
  WindowResizeAck -> LayoutChanged -> I-frame
- WindowResizeAck sent only to requesting client
- LayoutChanged sent to ALL attached clients
- I-frame(s) written for affected panes
- Client detach triggers resize recomputation
- Latest client updates on KeyEvent and WindowResize
- Stale re-inclusion: 5s hysteresis before recovered client's dimensions
  included
- First resize after session creation or client attach fires immediately (no
  debounce)
- Per-pane state tracks whether first resize has occurred since creation/attach

### Task 13: Idle Suppression During Resize

**Files:** `src/server/delivery/coalescing_state.zig` (modify),
`src/server/handlers/resize_handler.zig` (modify)

**Spec:** daemon-behavior §5.7 (idle suppression during resize + 500ms settling)

**Depends on:** Task 12 (resize handler sets the resize window), Task 5
(coalescing state has idle transition logic)

**Verification:**

- During active resize drag (within 250ms debounce window), Idle transition
  suppressed
- For 500ms after debounce fires, Idle transition still suppressed
- After 500ms settling, normal Idle transition resumes
- Pane coalescing tier does not drop to Idle between rapid resize events

### Task 14: Session Attach Initial I-Frame and Dimension Wiring

**Files:** `src/server/handlers/session_handler.zig` (modify),
`src/server/handlers/pane_handler.zig` (modify)

**Spec:** daemon-behavior §12 (READY -> OPERATING: initialize ring cursors, send
I-frame); daemon-architecture §4.6 (frame export pipeline)

**Depends on:** Task 9 (coalescing timer handler for frame export), Task 12
(effective dimensions)

**Verification:**

- On AttachSession success, client ring cursors initialized for all panes in
  session
- Initial I-frame sent for all panes in the newly attached session
- LayoutChanged uses actual session effective dimensions, not hardcoded 80x24
- buildLayoutPayload uses actual session dimensions
- SplitPane uses actual session dimensions for leaf dimension computation

### Task 15: Input Pipeline TODO Resolution

**Files:** `src/server/handlers/input_dispatcher.zig` (modify),
`src/server/handlers/ime_dispatcher.zig` (modify),
`src/server/handlers/pty_read.zig` (modify)

**Spec:** daemon-architecture §4.2 (key_encode API), §4.5 (helper functions);
daemon-behavior §2.9 (AmbiguousWidthConfig pass-through); protocol 04 §2.7
(FocusEvent focus_reporting check)

**Depends on:** None (independent TODO cleanup)

**Verification:**

- Bypassed keys (ImeResult.bypassed) encoded via ghostty key_encode and written
  to PTY
- FocusEvent checks terminal focus_reporting mode before writing escape sequence
- AmbiguousWidthConfig applies ambiguous_width value to ghostty Terminal
  instance(s) per scope field
- PTY read handler extracts title/cwd from ghostty Terminal after VT stream
  processing and broadcasts PaneMetadataChanged on change

---

## Dependency Graph

```
Task 1 (Frame Builder) ─────────────────────────────────────────────┐
Task 2 (Metadata Serializer) ───────────────┐                      │
Task 3 (Ring Lag Thresholds) ─────────┐     │                      │
                                      │     │                      │
                                      v     v                      │
                               Task 4 (Frame Serializer Enhancement)│
                                      │                             │
Task 5 (Coalescing State) ◄───────Task 3                           │
Task 6 (Health/Flow Fields) ──────────────────────┐                │
                                      │           │                │
                                      v           v                │
                               Task 7 (Health Escalation)          │
                               Task 8 (Flow Control Handlers)      │
                                      │                            │
                                      v                            v
                               Task 9 (Coalescing Timer Handler) ◄─┘
                                      │
                                      v
                               Task 10 (I-Frame Timer)
                                      │
Task 11 (EVFILT_WRITE Handler) ◄──Task 3
                                      │
Task 12 (WindowResize) ◄─────────Task 6, Task 10
                                      │
                                      v
                               Task 13 (Idle Suppression)
                                      │
Task 14 (Attach I-Frame + Dims) ◄─Task 9, Task 12
Task 15 (Input TODOs) ─── (independent)
```

Parallelizable groups:

- Group A: Tasks 1, 2, 3 (standalone, no dependencies)
- Group B: Tasks 5, 6, 15 (parallel after Group A or independent)
- Group C: Tasks 4, 7, 8, 11 (depend on Group A/B outputs)
- Group D: Tasks 9, 10, 12, 13, 14 (depend on Group C)

---

## Summary

| Task | Files                                                        | Spec Section                                     |
| ---- | ------------------------------------------------------------ | ------------------------------------------------ |
| 1    | `delivery/frame_builder.zig`                                 | arch §4.3, §4.6; ADR 00056                       |
| 2    | `delivery/metadata_serializer.zig`                           | protocol 04 §3.2                                 |
| 3    | `delivery/ring_buffer.zig`                                   | behavior §4.4; ADR 00055                         |
| 4    | `delivery/frame_serializer.zig`                              | protocol 04 §3.1 (section_flags bit 7)           |
| 5    | `delivery/coalescing_state.zig`, `client_state.zig`          | behavior §5.1-5.8                                |
| 6    | `client_state.zig`, `session_entry.zig`                      | behavior §3.1-3.3, §4.3, §2.2                    |
| 7    | `timer_handler.zig`, `notification_builder.zig`              | behavior §3.2, §3.3, §3.4                        |
| 8    | `flow_control_dispatcher.zig`                                | behavior §4.1-4.4; protocol 06 §2.4-2.7          |
| 9    | `coalescing_timer_handler.zig`, `timer_handler.zig`          | arch §4.6; behavior §5.1-5.4                     |
| 10   | `pane.zig`, `coalescing_timer_handler.zig`                   | arch §4.9; ADR 00057                             |
| 11   | `write_handler.zig`                                          | arch §4.4, §4.7; behavior §4.5                   |
| 12   | `resize_handler.zig`, `session_pane_dispatcher.zig`          | behavior §2; protocol 03 §5                      |
| 13   | `coalescing_state.zig`, `resize_handler.zig`                 | behavior §5.7                                    |
| 14   | `session_handler.zig`, `pane_handler.zig`                    | behavior §12; arch §4.6                          |
| 15   | `input_dispatcher.zig`, `ime_dispatcher.zig`, `pty_read.zig` | arch §4.2, §4.5; behavior §2.9; protocol 04 §2.7 |
