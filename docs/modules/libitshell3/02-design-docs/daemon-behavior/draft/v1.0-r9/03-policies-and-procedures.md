# Runtime Policies and Procedures

- **Date**: 2026-03-24
- **Scope**: Connection limits, multi-client resize, health escalation, flow
  control, adaptive coalescing, input processing priority, preedit ownership and
  lifecycle, notification defaults, heartbeat policy, silence detection timer,
  client state transitions, handshake timeouts, negotiation algorithms, field
  overflow policy

---

## 1. Connection Limits

**Trigger**: New client connection attempt (accept on listen_fd).

**Preconditions**: Daemon is running and accepting connections.

**Policy values**:

| Parameter              | Value | Description                                         |
| ---------------------- | ----- | --------------------------------------------------- |
| `MAX_CLIENTS`          | 64    | Compile-time capacity (fixed-size array in .bss)    |
| RLIMIT_NOFILE (target) | 8192  | Daemon SHOULD raise soft limit to hard limit or cap |

**Invariants**:

- The daemon enforces a compile-time connection limit of `MAX_CLIENTS = 64`.
  This is the maximum number of simultaneous client connections.
- `MAX_SESSIONS` (64) and `MAX_CLIENTS` (64) constrain the deployment ceiling
  independently of fd availability.
- When `MAX_CLIENTS` is reached, the daemon MUST accept the connection, send
  `ERR_RESOURCE_EXHAUSTED` (0x00000600), then close the connection.
- The daemon MAY also reject `CreateSessionRequest` with
  `ERR_RESOURCE_EXHAUSTED` when `MAX_SESSIONS` is reached.

**Resource budget**: Each connection consumes one fd; each pane consumes one fd
(PTY master). A typical deployment (50 sessions, 5 panes each) requires
approximately 300 file descriptors.

---

## 2. Multi-Client Resize Policy

**Trigger**: WindowResize from any attached client, client detach/attach, stale
exclusion, or stale re-inclusion.

**Preconditions**: At least one client attached to the session.

### 2.1 Resize Policies

| Policy     | Algorithm                                                    | Default |
| ---------- | ------------------------------------------------------------ | ------- |
| `latest`   | PTY dimensions = most recently active client's reported size | **Yes** |
| `smallest` | PTY dimensions = min(cols) x min(rows) across eligible       | Opt-in  |

The active policy is server configuration, reported to clients in
`AttachSessionResponse`.

### 2.2 Latest Client Tracking

Under `latest` policy, the daemon tracks the most recently active client per
session via `latest_client_id`. Updated on:

- `KeyEvent`
- `WindowResize`

`HeartbeatAck` does NOT update `latest_client_id`.

When the latest client detaches or becomes stale, the daemon re-scans remaining
attached clients and selects the first healthy client with the largest terminal
dimensions.

### 2.3 Viewport Clipping

Clients with smaller dimensions than the effective size MUST clip to their own
viewport (top-left origin). Per-client viewports (scroll to see clipped areas)
are deferred to v2.

### 2.4 Resize Debouncing

**Policy values**:

| Parameter       | Value | Description                                  |
| --------------- | ----- | -------------------------------------------- |
| Debounce window | 250ms | Per-pane debounce to prevent SIGWINCH storms |

### 2.5 Stale Re-Inclusion Hysteresis

**Policy values**:

| Parameter         | Value | Description                                      |
| ----------------- | ----- | ------------------------------------------------ |
| Hysteresis period | 5s    | Wait before including recovered client in resize |

**Ordering constraints**:

| # | Constraint                                                          | Verification                                                                            |
| - | ------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 1 | Client recovery MUST precede hysteresis timer start                 | No hysteresis timer exists for a non-recovered client                                   |
| 2 | Hysteresis expiry MUST precede dimension inclusion in resize calc   | No resize triggered by recovering client's dimensions within 5s of recovery             |
| 3 | Re-exclusion within hysteresis window MUST cancel pending inclusion | If client becomes stale again within 5s, no resize occurs from that client's dimensions |

### 2.6 Resize Orchestration

**Ordering constraints**:

| # | Constraint                                                     | Verification                                        |
| - | -------------------------------------------------------------- | --------------------------------------------------- |
| 1 | Effective size computation MUST precede ioctl(TIOCSWINSZ)      | PTY dimensions match the computed effective size    |
| 2 | ioctl(TIOCSWINSZ) MUST precede WindowResizeAck                 | Ack confirms PTY was actually resized               |
| 3 | WindowResizeAck to requester MUST precede LayoutChanged to all | Response-before-notification invariant              |
| 4 | LayoutChanged MUST precede I-frame writes to ring buffer       | Clients receive layout context before frame content |

**Observable effects** (wire messages, in order):

1. WindowResizeAck to requesting client [if triggered by WindowResize]
2. LayoutChanged to ALL attached clients with updated pane dimensions
3. I-frame(s) for affected panes via ring buffer

### 2.7 Client Detach Resize

When a client detaches, the daemon recomputes effective size using remaining
clients. If the effective size changes:

1. LayoutChanged to all remaining clients
2. I-frame(s) for affected panes

### 2.8 KeyEvent pane_id Routing

When `pane_id` is omitted or 0, the daemon routes to the session's focused pane.
When present and non-zero, the daemon validates existence and routes directly.

**Invariant**: During IME composition, clients SHOULD specify `pane_id` to
prevent focus-change races.

### 2.9 AmbiguousWidthConfig Pass-Through

When the daemon receives `AmbiguousWidthConfig` (0x0406), it passes the
`ambiguous_width` value to the Terminal instance(s) determined by the `scope`
field (`"per_pane"`, `"per_session"`, or `"global"`).

**Invariant**: Server-side Terminal state MUST match client-side cell width
computation for correct cell grid rendering.

### 2.10 Pane Resize Procedure (ResizePaneRequest)

**Trigger**: Client sends `ResizePaneRequest` with `orientation` (u8: 0 =
horizontal, 1 = vertical) and `delta_ratio` (i32, signed fixed-point x10^4).

**Procedure**:

1. Receive `ResizePaneRequest` with `orientation` + `delta_ratio`.
2. Find nearest ancestor split node matching `orientation`.
3. Compute `new_ratio = old_ratio + delta_ratio` (integer arithmetic).
4. Clamp to `[MIN_RATIO, 10000 - MIN_RATIO]` where `MIN_RATIO = 500` (5%).
5. Store `new_ratio` in `SplitNodeData`.
6. Recompute affected pane leaf rectangles with integer arithmetic
   (`width * ratio / 10000`).
7. Issue `TIOCSWINSZ` to affected PTYs (debounced per Section 2.4 policy).

**Invariant**: All ratio arithmetic uses integer operations. No floating-point
is involved at any step.

---

## 3. Health Escalation

**Trigger**: PausePane received, or ring cursor stagnation detected.

**Preconditions**: Client is in OPERATING state and attached to a session.

### 3.1 Client Health States

| State     | Resize participation | Frame delivery              |
| --------- | -------------------- | --------------------------- |
| `healthy` | Yes                  | Full (per coalescing tier)  |
| `stale`   | No (excluded)        | None (ring cursor stagnant) |

`paused` (PausePane active) is an orthogonal flow-control state, not a health
state. A paused client remains `healthy` until the stale timeout fires.

### 3.2 PausePane Health Escalation Timeline

| Phase           | Time offset | Transport | Action                                                      |
| --------------- | ----------- | --------- | ----------------------------------------------------------- |
| Healthy         | T=0s        | Any       | PausePane received. Still participates in resize.           |
| Resize excluded | T=5s        | Any       | Daemon recalculates effective size without this client.     |
| Stale (local)   | T=60s       | Unix      | Daemon sends ClientHealthChanged (0x0185) to peer clients.  |
| Stale (SSH)     | T=120s      | SSH       | Daemon sends ClientHealthChanged (0x0185) to peer clients.  |
| Evicted         | T=300s      | Any       | Daemon sends Disconnect (reason: stale_client), tears down. |

### 3.3 Stale Triggers

The stale timeout clock resets ONLY on messages proving application-level
processing:

- ContinuePane
- KeyEvent
- WindowResize
- ClientDisplayInfo
- Any request message (CreateSession, SplitPane, etc.)

**Invariant**: HeartbeatAck MUST NOT reset the stale timeout. On iOS, the OS can
suspend the application while keeping TCP sockets alive — the TCP stack responds
to heartbeats even though the application event loop is frozen.

**Ring cursor stagnation trigger**: If a client's ring cursor lag exceeds 90% of
ring capacity for `stale_timeout_ms` AND the client has not sent any
application-level message during that period, the client transitions to `stale`.

### 3.4 Preedit Commit on Eviction

**Ordering constraints**:

| # | Constraint                                                    | Verification                                               |
| - | ------------------------------------------------------------- | ---------------------------------------------------------- |
| 1 | Preedit commit to PTY MUST precede PreeditEnd to peers        | PreeditEnd arrives after committed text is written to PTY  |
| 2 | PreeditEnd to peers MUST precede Disconnect to evicted client | Peers see composition end before the eviction notification |

**Observable effects** (wire messages, in order):

Common prefix (if evicted client owns active preedit):

1. PreeditEnd(reason="client_evicted") to all remaining peer clients

Then:

2. Disconnect(reason=stale_client) to the evicted client

### 3.5 Recovery from Stale

All recovery scenarios advance the client's ring cursor to the latest I-frame:

| Recovery trigger | Additional messages                                                                  |
| ---------------- | ------------------------------------------------------------------------------------ |
| ContinuePane     | None                                                                                 |
| Stale recovery   | LayoutChanged (if layout changed) + PreeditSync (if preedit active) via direct queue |
| Ring overwrite   | None                                                                                 |

**Invariant**: Per socket write priority, context messages (LayoutChanged,
PreeditSync) MUST arrive BEFORE the I-frame from the ring buffer.

**Policy values**:

| Parameter        | Value | Description                                                       |
| ---------------- | ----- | ----------------------------------------------------------------- |
| Eviction timeout | 300s  | MAY reset on HeartbeatAck as safety net against false disconnects |

---

## 4. Flow Control

### 4.1 PausePane (Advisory Signal)

PausePane is client-to-server advisory. The ring buffer writes
**unconditionally** — PausePane does NOT stop writes. PausePane triggers the
health escalation timeline (Section 3.2).

### 4.2 ContinuePane (Recovery)

**Ordering constraints**:

| # | Constraint                                                     | Verification                                                   |
| - | -------------------------------------------------------------- | -------------------------------------------------------------- |
| 1 | Ring cursor advance to I-frame MUST precede resume of delivery | Client receives I-frame as first frame after ContinuePane      |
| 2 | Coalescing tier restoration MUST follow cursor advance         | Client is not stuck at degraded tier after successful recovery |

### 4.3 FlowControlConfig

| Parameter             | Type | Default (local) | Default (SSH) | Description                                    |
| --------------------- | ---- | --------------- | ------------- | ---------------------------------------------- |
| `max_queue_age_ms`    | u32  | 5000            | 10000         | Max ring cursor lag before PausePane advisory  |
| `auto_continue`       | bool | true            | true          | Auto-send ContinuePane after PausePane timeout |
| `stale_timeout_ms`    | u32  | 60000           | 120000        | Time until stale transition                    |
| `eviction_timeout_ms` | u32  | 300000          | 300000        | Time until eviction after stale                |

Values of 0 disable the corresponding timeout (except `eviction_timeout_ms`,
which has a server-enforced minimum).

### 4.4 Smooth Degradation Before PausePane

| Ring cursor lag | Action                                              |
| --------------- | --------------------------------------------------- |
| > 50%           | Auto-downgrade coalescing tier (Active → Bulk)      |
| > 75%           | Force Bulk tier regardless of throughput            |
| > 90%           | Next ContinuePane advances cursor to latest I-frame |

**Invariant**: PausePane is a last resort, not a routine flow control mechanism.

### 4.5 Socket Write Priority

Two queues per client:

1. **Direct message queue** (higher priority): Control messages (LayoutChanged,
   PreeditSync, PreeditUpdate, PreeditEnd, session management responses).
   Preedit protocol messages (0x0400-0x0405) use this queue.
2. **Ring buffer** (lower priority): Frame data (I-frames, P-frames). All
   frames, including those with preedit cell data, go through the shared ring.

**Invariant**: On each writable event, the daemon MUST drain the direct queue
first, then write ring buffer data. This ensures context messages arrive before
frames that reference them.

---

## 5. Adaptive Coalescing

### 5.1 Four-Tier Model

Coalescing state is tracked per (client, pane) pair.

| Tier | Name        | Min interval     | Trigger                                        |
| ---- | ----------- | ---------------- | ---------------------------------------------- |
| 0    | Preedit     | 0 ms (immediate) | Preedit state change (Start, Update, End)      |
| 1    | Interactive | 0 ms (immediate) | Keystroke echo, cursor movement                |
| 2    | Active      | 16 ms (~60 fps)  | Sustained PTY output (e.g., cat, build output) |
| 3    | Bulk        | 33 ms (~30 fps)  | High-throughput PTY output sustained >500ms    |
| --   | Idle        | No frames        | No PTY output for >100ms                       |

### 5.2 Tier Transitions

- **Upgrade** (higher → lower tier / faster): Immediate on trigger event.
- **Downgrade** (lower → higher tier / slower): Requires sustained condition:
  - Interactive → Active: sustained output >100ms
  - Active → Bulk: sustained high throughput >500ms
  - Any → Idle: no output >100ms

### 5.3 Preedit Immediate Rule

**Invariant**: Preedit state changes MUST trigger immediate frame delivery (Tier
0), regardless of the current coalescing tier.

**Ordering constraints**:

| # | Constraint                                                        | Verification                                     |
| - | ----------------------------------------------------------------- | ------------------------------------------------ |
| 1 | processKey() MUST precede RenderState.update() + bulkExport()     | Preedit change is captured in the exported frame |
| 2 | overlayPreedit() MUST follow bulkExport()                         | Preedit cells are injected post-export           |
| 3 | Preedit frame write to ring MUST precede any coalesced PTY frames | Preedit latency is never delayed by batching     |

**Invariant**: Preedit latency MUST stay under 33ms over local Unix socket.

### 5.4 "Immediate First, Batch Rest" Rule

When a KeyEvent produces both preedit AND committed text in the same ImeResult:

1. Committed text written to PTY (may trigger PTY output).
2. Preedit change triggers immediate frame.
3. Subsequent PTY output follows normal coalescing.

**Invariant**: The preedit frame MUST NOT be delayed by batching with PTY
output.

### 5.5 WAN Coalescing Adjustments

| ClientDisplayInfo field | Effect                                                 |
| ----------------------- | ------------------------------------------------------ |
| `transport_type: "ssh"` | Tier 2 interval raised to 33ms; Tier 3 raised to 100ms |
| `bandwidth_hint`        | Below 1 Mbps: force Tier 3 for all non-preedit output  |
| `estimated_rtt_ms`      | Above 100ms: increase Idle threshold to 200ms          |

**Invariant**: Preedit is NEVER throttled, regardless of transport type or
bandwidth.

### 5.6 Power-Aware Throttling

| Power state   | Coalescing cap            | Preedit   |
| ------------- | ------------------------- | --------- |
| `ac`          | No cap (full tier model)  | Immediate |
| `battery`     | Max Tier 2 (16ms / 60fps) | Immediate |
| `low_battery` | Max Tier 3 (33ms / 30fps) | Immediate |

### 5.7 Idle Suppression During Resize

During an active resize drag (WindowResize events within the 250ms debounce
window) and for 500ms after the debounce fires, the daemon suppresses the Idle
timeout.

**Invariant**: The daemon MUST NOT transition a pane's coalescing tier to Idle
during the resize + 500ms settling period.

### 5.8 Per-(Client, Pane) Cadence

**Invariant**: One pane's coalescing tier MUST NOT affect another pane's
delivery timing within the same client. One client's coalescing tier MUST NOT
affect another client's delivery for the same pane.

All clients receive FrameUpdate for all panes in the attached session from the
shared per-pane ring buffer. Each client reads at its own cursor position via
per-(client, pane) coalescing tiers.

---

## 6. Input Processing Priority

**Trigger**: Event loop dequeues multiple pending client messages in one
iteration.

**Preconditions**: Multiple messages available from kevent64 return.

When multiple client messages are pending, the server processes them in priority
order. Higher-priority messages are dispatched first, ensuring user-visible
feedback is never starved by bulk transfers.

| Priority | Message type(s)          | Rationale                                         |
| -------- | ------------------------ | ------------------------------------------------- |
| 1        | KeyEvent, TextInput      | Affects what the user sees immediately (key echo) |
| 2        | MouseButton, MouseScroll | User interaction requiring prompt visual feedback |
| 3        | MouseMove                | Bulk; can be coalesced across pending messages    |
| 4        | PasteData                | Bulk transfer; latency-tolerant                   |
| 5        | FocusEvent               | Advisory; no immediate visual consequence         |

**Invariant**: KeyEvent and TextInput messages MUST be dispatched before all
lower-priority message types within the same event loop iteration.

---

## 7. Preedit Ownership

### 7.1 Single-Owner Model

The daemon maintains preedit ownership at the session level. At most one pane in
a session can have active preedit at any time (preedit exclusivity invariant).
The pane with active preedit is always `Session.focused_pane`.

**Invariant**: There MUST NOT exist a state where preedit is active on a
non-focused pane. Proof: focus change always commits preedit (Section 8.1), and
new composition can only start on the focused pane (keys are routed to focused
pane).

### 7.2 Ownership Rules (Last-Writer-Wins)

**Ownership transition** (Client A owns preedit, Client B sends composing
KeyEvent):

**Ordering constraints**:

| # | Constraint                                                       | Verification                                                      |
| - | ---------------------------------------------------------------- | ----------------------------------------------------------------- |
| 1 | engine.flush() for Client A MUST precede Client B's processKey() | Client A's text is committed before Client B's composition starts |
| 2 | PreeditEnd (A's session) MUST precede PreeditStart (B's session) | All clients see composition end before new composition start      |
| 3 | preedit.session_id increment MUST occur between End and Start    | PreeditStart carries a new session_id                             |

**Observable effects** (wire messages to all attached clients, in order):

1. PreeditEnd(reason="replaced_by_other_client", preedit_session_id=N)
2. PreeditStart(owner=client_B, preedit_session_id=N+1)

### 7.3 Owner Disconnect

When the preedit owner disconnects:

1. Daemon commits current preedit text to PTY.
2. PreeditEnd(reason="client_disconnected") to remaining clients.

### 7.4 Non-Composing Input from Non-Owner

Regular (non-composing) KeyEvents from any client are always processed normally.
If a non-owner sends a regular key, the owner's preedit is committed first.

### 7.5 Inactivity Timeout

**Policy values**:

| Parameter          | Value | Description                                    |
| ------------------ | ----- | ---------------------------------------------- |
| Inactivity timeout | 30s   | No input from preedit owner → commit and clear |

---

## 8. Preedit Lifecycle on State Changes

This section defines daemon behavior when external events interrupt active
preedit composition. General principle: preedit is always resolved (committed or
cancelled) before processing the interrupting action.

### 8.1 Focus Change (Intra-Session)

**Trigger**: Focused pane changes within a session during active composition.

**Ordering constraints**:

| # | Constraint                                                      | Verification                                     |
| - | --------------------------------------------------------------- | ------------------------------------------------ |
| 1 | Preedit commit to old pane PTY MUST precede focused_pane update | Committed text goes to the correct (old) PTY     |
| 2 | PreeditEnd MUST precede LayoutChanged                           | Clients see composition end before layout change |

**Observable effects**:

1. PreeditEnd(reason="focus_changed")
2. NavigatePaneResponse — to requester
3. LayoutChanged(new_focus=...)

### 8.2 Alternate Screen Switch

**Trigger**: Application switches from primary to alternate screen while
composition is active.

**Ordering constraints**:

| # | Constraint                                                     | Verification                                          |
| - | -------------------------------------------------------------- | ----------------------------------------------------- |
| 1 | Preedit commit to PTY MUST precede screen switch processing    | Text preserved before screen transition               |
| 2 | PreeditEnd MUST precede FrameUpdate(I-frame, screen=alternate) | Composition end visible before alternate screen frame |

**Observable effects**:

1. PreeditEnd(reason="committed")
2. FrameUpdate(frame_type=1, screen=alternate)

### 8.3 Pane Close (Non-Last Pane)

**Trigger**: User closes a non-last pane while composition is active on that
pane.

The daemon cancels the composition via engine.reset() — does NOT commit to PTY
(the PTY is being closed).

**Ordering constraints**:

| # | Constraint                            | Verification                                       |
| - | ------------------------------------- | -------------------------------------------------- |
| 1 | PreeditEnd MUST precede LayoutChanged | Clients see composition end before pane disappears |

**Observable effects**:

1. PreeditEnd(reason="pane_closed")
2. LayoutChanged(new_focus=...)

### 8.4 Pane Close (Last Pane — Session Destroy)

**Trigger**: Last pane in session closes.

The daemon uses engine.deactivate() (which flushes composition) then
engine.deinit(). This is the session-close contract.

**Ordering constraints**:

| # | Constraint                                       | Verification                                         |
| - | ------------------------------------------------ | ---------------------------------------------------- |
| 1 | engine.deactivate() flush MUST precede PTY close | Committed text is written while PTY fd is still open |
| 2 | PreeditEnd MUST precede SessionListChanged       | Composition end visible before session destruction   |

**Observable effects** (if composition was active):

1. PreeditEnd(reason="session_destroyed")
2. SessionListChanged(event="destroyed", session_id=N)

### 8.5 Owner Disconnect

**Trigger**: Composing client's connection drops.

**Ordering constraints**:

| # | Constraint                                             | Verification                                   |
| - | ------------------------------------------------------ | ---------------------------------------------- |
| 1 | Preedit commit to PTY MUST precede PreeditEnd to peers | Text preserved before ownership cleared        |
| 2 | PreeditEnd MUST precede connection teardown completion | Peers notified before client state deallocated |

**Observable effects**:

1. PreeditEnd(reason="client_disconnected") to remaining clients

### 8.6 Input Method Switch During Active Preedit

**Trigger**: Client sends InputMethodSwitch (0x0404) while composition is
active.

**Case: commit_current=true**:

**Ordering constraints**:

| # | Constraint                                                      | Verification                                                        |
| - | --------------------------------------------------------------- | ------------------------------------------------------------------- |
| 1 | Committed text extracted BEFORE any further engine calls        | Buffer lifetime invariant — engine buffers invalidated on next call |
| 2 | PreeditEnd MUST precede InputMethodAck                          | Composition end visible before method switch confirmation           |
| 3 | Owner clear and session_id increment MUST occur with PreeditEnd | No stale ownership after switch                                     |

**Observable effects**:

1. PreeditEnd(reason="committed")
2. InputMethodAck(active_input_method=new_method)

**Case: commit_current=false**:

**Ordering constraints**:

| # | Constraint                                         | Verification                                              |
| - | -------------------------------------------------- | --------------------------------------------------------- |
| 1 | engine.reset() MUST precede setActiveInputMethod() | Old composition discarded before engine switch            |
| 2 | PreeditEnd MUST precede InputMethodAck             | Composition end visible before method switch confirmation |

**Observable effects**:

1. PreeditEnd(reason="cancelled")
2. InputMethodAck(active_input_method=new_method)

### 8.7 Concurrent Preedit and Resize

**Trigger**: Terminal resize while composition is active.

No PreeditEnd or PreeditUpdate is sent. The composition continues uninterrupted.
Preedit is re-overlaid at export time using the updated cursor position.

**Observable effects**:

1. FrameUpdate(frame_type=1) — preedit cells at updated position

### 8.8 Mouse Click During Composition

**Trigger**: MouseButton event received while composition is active and mouse
reporting is enabled in the terminal.

**Ordering constraints**:

| # | Constraint                                                              | Verification                       |
| - | ----------------------------------------------------------------------- | ---------------------------------- |
| 1 | Preedit commit to PTY MUST precede mouse event forwarding               | Text preserved before mouse action |
| 2 | Owner clear and preedit_session_id increment MUST occur with PreeditEnd | No stale ownership after commit    |

**Observable effects**:

1. PreeditEnd(reason="committed")

**Invariant**: Only MouseButton triggers preedit commit. MouseScroll and
MouseMove do NOT.

### 8.9 Rapid Keystroke Bursts

**Trigger**: Multiple pending KeyEvents processed in same event loop iteration.

**Ordering constraints**:

| # | Constraint                                                         | Verification                                                   |
| - | ------------------------------------------------------------------ | -------------------------------------------------------------- |
| 1 | All KeyEvents MUST be processed through IME in arrival order       | Composition state is consistent with keystroke sequence        |
| 2 | Intermediate preedit states MUST be coalesced within same frame    | Client receives one PreeditUpdate per frame, not per keystroke |
| 3 | Final preedit text injected via overlayPreedit() into single frame | One frame per burst, not one per keystroke                     |

**Observable effects**:

1. Single FrameUpdate with final preedit state
2. Single PreeditUpdate (final state only)

### 8.10 reset() vs flush() Summary

| Scenario                                   | Method                                   |
| ------------------------------------------ | ---------------------------------------- |
| Pane close (non-last pane)                 | engine.reset() (discard)                 |
| Pane close (last pane — session destroy)   | engine.deactivate() then engine.deinit() |
| Focus change                               | engine.flush() (commit)                  |
| Alt screen switch                          | engine.flush() (commit)                  |
| Owner disconnect                           | engine.flush() (commit)                  |
| Client eviction                            | engine.flush() (commit)                  |
| Replaced by other client                   | engine.flush() (commit)                  |
| Input method switch (commit_current=true)  | engine.flush() (commit)                  |
| Input method switch (commit_current=false) | engine.reset() (discard)                 |
| 30s inactivity timeout                     | engine.flush() (commit)                  |
| Mouse click during composition             | engine.flush() (commit)                  |
| Error recovery                             | engine.reset() (discard)                 |

**Invariant**: Only three scenarios use reset() (discard): non-last pane close,
input method switch with commit_current=false, and error recovery. All other
preedit-ending scenarios use flush() (commit) to preserve the user's work.

### 8.11 Error Recovery

**Trigger**: Invalid composition state detected (should not occur with correctly
implemented Korean algorithms).

**Observable effects**:

1. PreeditEnd(reason="cancelled") to all clients

The daemon returns to a known-good state without crashing: best-effort commit of
existing preedit text, then engine.reset() to force clean state.

---

## 9. Notification Defaults

### 9.1 Always-Sent Notifications

After `AttachSession`, the client automatically receives these notifications
without explicit subscription:

| Notification        | Description                                       |
| ------------------- | ------------------------------------------------- |
| LayoutChanged       | Pane tree structure changes                       |
| SessionListChanged  | Session created/destroyed/renamed                 |
| PaneMetadataChanged | Pane field updates (title, cwd, is_running, etc.) |
| ClientAttached      | Another client attached to session                |
| ClientDetached      | Another client detached from session              |
| ClientHealthChanged | Client health state changed                       |

**Invariant**: These structural notifications MUST NOT be unsubscribable.

`PaneMetadataChanged` is a field-update notification: carries only changed
fields. On process exit, `is_running: false` and `exit_status` are always
present.

### 9.2 Opt-In Notifications

All of: PaneTitleChanged, ProcessExited, Bell, RendererHealth, PaneCwdChanged,
ActivityDetected, SilenceDetected — require explicit subscription via
`Subscribe` (0x0810).

`ProcessExited` is complementary to `PaneMetadataChanged`, not redundant.
`PaneMetadataChanged` keeps field state in sync; `ProcessExited` enables
event-driven reactions.

### 9.3 Subscription Scope

Subscriptions are per-connection. Each connection manages its own subscriptions
independently. Subscriptions can be per-pane (`pane_id` specified) or global
(`pane_id = 0` for all panes).

---

## 10. Heartbeat Policy

### 10.1 Parameters

| Parameter          | Default | Description                                                             |
| ------------------ | ------- | ----------------------------------------------------------------------- |
| Heartbeat interval | 30s     | How often to send Heartbeat if no other messages sent                   |
| Connection timeout | 90s     | No message of any kind received within this period → connection is dead |

### 10.2 Behavior

Either side MAY send `Heartbeat` (0x0003) if no other messages have been sent
within the heartbeat interval. The receiver responds with `HeartbeatAck`
(0x0004).

If no message of any kind is received within 90 seconds (3 missed heartbeat
intervals), the daemon sends `Disconnect(reason: timeout)`.

### 10.3 Transport-Specific Behavior

- **Unix domain sockets (local)**: Heartbeat is optional. OS detects dead
  sockets via SO_KEEPALIVE or write errors.
- **SSH tunnels**: Heartbeats complement SSH's ServerAliveInterval. Recommended
  to detect tunnel failures.

### 10.4 Orthogonality with Health States

| Combination                       | Meaning                                                      |
| --------------------------------- | ------------------------------------------------------------ |
| Heartbeat-healthy + output-stale  | `stale` (app frozen, TCP alive — iOS backgrounding scenario) |
| Heartbeat-missed + output-healthy | Connection problem (will disconnect at 90s)                  |

**Invariant**: HeartbeatAck MUST NOT reset the stale timeout. These are
independent systems: heartbeat is connection liveness (90s → Disconnect); health
states are application responsiveness (triggered by ring cursor lag and
PausePane duration).

---

## 11. Silence Detection Timer

### 11.1 Overview

Per-pane silence detection timer: fires when a pane produces no PTY output for a
client-specified duration. Clients subscribe via `Subscribe` (0x0810) with
`SilenceDetected` and a `silence_threshold_ms` parameter.

### 11.2 Timer Lifecycle

| Phase  | Condition                                  | Action                                  |
| ------ | ------------------------------------------ | --------------------------------------- |
| Arm    | PTY read + ≥1 subscriber + timer not armed | Set deadline = now + min_threshold      |
| Reset  | Each subsequent PTY read                   | Update deadline = now + min_threshold   |
| Fire   | Minimum threshold reached                  | Send SilenceDetected to ALL subscribers |
| Re-arm | Next PTY read after firing                 | Arm per above                           |
| Disarm | Last subscriber removed (count → 0)        | Set deadline = null                     |

### 11.3 Timer Reset Point

**Invariant**: The timer MUST reset in the PTY read handler, after read(pty_fd),
before terminal.vtStream(). The silence timer measures PTY output activity, not
rendering activity. Control sequences that produce no visible changes still
reset the timer.

### 11.4 Minimum-Threshold-Wins Semantics

When multiple clients subscribe with different thresholds, the pane-level timer
uses the minimum. On fire, SilenceDetected is sent to ALL subscribers — no
per-client selective firing.

### 11.5 Cleanup Triggers

| # | Trigger              | Action                                             |
| - | -------------------- | -------------------------------------------------- |
| 1 | Explicit Unsubscribe | Remove subscription, recalculate min threshold     |
| 2 | Client disconnect    | Remove all subscriptions for client                |
| 3 | Connection timeout   | Remove all subscriptions for client                |
| 4 | Session detach       | Remove subscriptions for panes in detached session |
| 5 | Client eviction      | Remove all subscriptions for client                |
| 6 | Pane destruction     | Cancel all subscriptions for the destroyed pane    |

**Invariant**: When subscriber count reaches 0, the per-pane timer MUST
auto-disarm. When global total_silence_subscribers reaches 0, the mechanism MUST
be disabled.

### 11.6 Flow Control Interaction

**Invariant**: The silence timer MUST operate independently of the flow control
system. A pane with active silence subscriptions continues tracking PTY output
activity regardless of whether clients are paused, stale, or in degraded
coalescing tiers.

---

## 12. Client State Transitions

**State machine**: HANDSHAKING → READY → OPERATING → DISCONNECTING → [closed]

| From          | Event                                | To            | Action                                                                   |
| ------------- | ------------------------------------ | ------------- | ------------------------------------------------------------------------ |
| HANDSHAKING   | Valid ClientHello                    | READY         | Send ServerHello with capabilities, protocol version                     |
| HANDSHAKING   | Invalid ClientHello / timeout        | [closed]      | Send error, close connection                                             |
| READY         | AttachSessionRequest                 | OPERATING     | Set attached_session, initialize ring cursors, send I-frame              |
| READY         | Client disconnect                    | [closed]      | Clean up ClientState                                                     |
| OPERATING     | DetachSessionRequest                 | READY         | Clear attached_session, clear ring cursors, remove silence subscriptions |
| OPERATING     | AttachSessionRequest (any)           | OPERATING     | Error response: `ERR_SESSION_ALREADY_ATTACHED`. No state change          |
| OPERATING     | KeyEvent / MouseEvent                | OPERATING     | Route to attached session's focused pane                                 |
| OPERATING     | WindowResize                         | OPERATING     | Update display_info, recalculate pane dimensions                         |
| OPERATING     | DestroySessionRequest (own session)  | READY         | Session destroyed, client detached                                       |
| OPERATING     | Client disconnect                    | [closed]      | Clean up ClientState                                                     |
| OPERATING     | Disconnect (reason: server_shutdown) | DISCONNECTING | Begin drain sequence                                                     |
| DISCONNECTING | All pending messages sent            | [closed]      | conn.close(), free ClientState                                           |
| DISCONNECTING | Drain timeout expires                | [closed]      | conn.close(), free ClientState                                           |

**Invariant**: Unexpected disconnects (conn.recv() returns peer_closed) go
directly to [closed] without passing through DISCONNECTING. The DISCONNECTING
state exists only for graceful drain of pending outbound messages.

**Key transition**: OPERATING → READY (detach without disconnect) enables
session switching without reconnecting. To switch sessions, the client MUST
explicitly send `DetachSessionRequest` first, then `AttachSessionRequest`.

---

## 13. Handshake Timeouts

| Stage                                             | Duration | Action on timeout                               |
| ------------------------------------------------- | -------- | ----------------------------------------------- |
| Transport connection (accept to first byte)       | 5s       | Close socket                                    |
| ClientHello → ServerHello                         | 5s       | Send Error(ERR_INVALID_STATE), close connection |
| READY → AttachSessionRequest/CreateSessionRequest | 60s      | Send Disconnect(TIMEOUT), close connection      |
| Heartbeat response                                | 90s      | Send Disconnect(TIMEOUT), close connection      |

This is the single authoritative timeout table. The protocol spec defers
concrete values to daemon design docs.

**Invariant**: Each timeout MUST be enforced via per-client EVFILT_TIMER. The
timer is cancelled when the expected message arrives.

---

## 14. Negotiation Algorithms

### 14.1 Protocol Version Selection

```
negotiated_version = min(server_max_version, client.protocol_version_max)

if negotiated_version < client.protocol_version_min → ERR_VERSION_MISMATCH
if negotiated_version < server_min_version → ERR_VERSION_MISMATCH
```

In v1, both min and max are 1.

### 14.2 General Capability Intersection

```
negotiated_caps = intersection(client.capabilities, server.capabilities)
```

Each capability independently negotiated. Unknown capability names are ignored
(forward compatibility).

### 14.3 Render Capability Intersection

```
negotiated_render_caps = intersection(client.render_capabilities,
                                       server.render_capabilities)
```

**Invariant**: At least one rendering mode MUST be supported. If neither
`cell_data` nor `vt_fallback` is in the intersection, the server MUST send
`Error(ERR_CAPABILITY_REQUIRED, detail="No common rendering mode")` and
disconnect.

---

## 15. Field Overflow Policy

All session string fields use fixed-size inline buffers. Overflow handling
depends on the field origin.

### 15.1 Client-Originated Fields

Fields set by client requests (e.g., `CreateSessionRequest`,
`RenameSessionRequest`):

| Field          | Max bytes | On overflow                      |
| -------------- | --------- | -------------------------------- |
| `session_name` | 64        | REJECT with `ERR_FIELD_TOO_LONG` |

The daemon MUST reject the entire request with `ERR_FIELD_TOO_LONG` if the field
value exceeds the maximum byte length. No partial processing occurs.

### 15.2 OSC-Originated Fields

Fields set by terminal escape sequences (OSC 0/2 for title, OSC 7 for cwd):

| Field        | Max bytes | On overflow                |
| ------------ | --------- | -------------------------- |
| `pane_title` | 256       | TRUNCATE at UTF-8 boundary |
| `pane_cwd`   | 4096      | TRUNCATE at UTF-8 boundary |

The daemon MUST truncate to the largest valid UTF-8 prefix that fits within the
buffer. The daemon cannot reject shell output — truncation is the only option.

### 15.3 Daemon-Internal Constants

Fields with predetermined values from a fixed registry (e.g., `input_method`,
`keyboard_layout`, `preedit_buf`):

| Field             | Max bytes | Overflow possible |
| ----------------- | --------- | ----------------- |
| `input_method`    | 32        | No                |
| `keyboard_layout` | 32        | No                |
| `preedit_buf`     | 64        | No                |

These fields are populated from a compile-time registry of known identifiers.
Runtime overflow cannot occur because all valid values are predetermined and
verified to fit within the buffer at compile time.
