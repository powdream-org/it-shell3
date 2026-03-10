# Daemon Runtime Policies

**Version**: v0.3
**Status**: Draft
**Scope**: Connection limits, multi-client resize, health escalation, flow control, adaptive coalescing, preedit ownership and lifecycle, session persistence, notification defaults, heartbeat policy
**Source topics**: P3, P4, P7, P8, P10, P11, P12, P13, P17+I7, P18, P19
**Cross-references**: doc 01 (Module Decomposition, Event Loop), doc 02 (IME Integration), doc 03 (Client Connections, Ring Buffer Delivery)

---

## 1. Connection Limits (P3)

The daemon imposes no protocol-level limit on simultaneous connections. Implementation-level limits apply:

- **Minimum**: The daemon MUST support at least 256 concurrent connections.
- **Rejection**: When resource limits are reached, the daemon rejects new connections or requests with `ERR_RESOURCE_EXHAUSTED` (0x00000600). The daemon MAY reject new connections during handshake if file descriptor limits are reached, or reject `CreateSessionRequest` if session capacity limits are reached. In both cases, the error code is `ERR_RESOURCE_EXHAUSTED`.
- **File descriptor budget**: Each connection consumes one fd; each pane consumes one fd (PTY master). A typical multi-tab deployment (50 sessions, 5 panes each) requires approximately 300 file descriptors.
- **RLIMIT_NOFILE**: The daemon SHOULD raise `RLIMIT_NOFILE` at startup to the hard limit or a reasonable cap (e.g., 8192). The macOS default soft limit (256) is insufficient.

The limit is an implementation guard, not a protocol constant. Future versions may raise it without protocol changes.

---

## 2. Multi-Client Resize Policy (P4)

When multiple clients attach to the same session, the daemon determines the effective terminal size for the session's pane tree.

### 2.1 Resize Policies

| Policy | Algorithm | Default |
|--------|-----------|---------|
| `latest` | PTY dimensions = most recently active client's reported size | **Yes** (matches tmux 3.1+ default) |
| `smallest` | PTY dimensions = `min(cols)` x `min(rows)` across all eligible clients | Opt-in |

The active policy is server configuration, reported to clients in `AttachSessionResponse`.

### 2.2 Latest Client Tracking

Under the `latest` policy, the daemon tracks the most recently active client per session via `latest_client_id`. This field is updated when the client sends:

- `KeyEvent`
- `WindowResize`

`HeartbeatAck` does NOT update `latest_client_id`. When the latest client detaches or becomes stale (Section 3), the daemon falls back to the next most-recently-active healthy client.

### 2.3 Viewport Clipping

Clients with smaller dimensions than the effective size MUST clip to their own viewport (top-left origin), matching tmux `latest` policy behavior. Per-client viewports (scroll to see clipped areas) are deferred to v2.

### 2.4 Resize Debouncing

Resize is debounced at 250ms per pane to prevent SIGWINCH storms during rapid resize drags.

### 2.5 Stale Re-Inclusion Hysteresis

When a stale client recovers (sends ContinuePane or any application-level message), the daemon does NOT immediately include the recovering client's dimensions in the resize calculation. Instead, a 5-second hysteresis period applies:

1. Client recovers from stale state.
2. Daemon waits 5 seconds before including the client's dimensions.
3. If the client becomes stale again within the 5-second window, the inclusion is cancelled.

This prevents resize oscillation when a client is intermittently responsive (e.g., iOS app cycling between foreground and background).

---

## 3. Health Escalation (P7)

### 3.1 Client Health States

The daemon maintains two health states per client, orthogonal to connection lifecycle:

| State | Definition | Resize participation | Frame delivery |
|-------|-----------|---------------------|----------------|
| `healthy` | Normal operation | Yes | Full (per coalescing tier) |
| `stale` | Paused too long or output queue stagnant | No (excluded from resize) | None (ring cursor stagnant) |

`paused` (PausePane active) is an orthogonal flow-control state, not a health state. A paused client remains `healthy` until the stale timeout fires.

### 3.2 PausePane Health Escalation Timeline

```
T=0s:    PausePane received. Client still healthy. Still participates in resize.
T=5s:    Resize exclusion. Daemon recalculates effective size without this client.
T=60s:   Stale transition (local Unix socket transport).
         Daemon sends ClientHealthChanged (0x0185) to peer clients.
T=120s:  Stale transition (SSH tunnel transport).
T=300s:  Eviction. Daemon sends Disconnect("stale_client") and tears down connection.
```

All timeouts are configurable via FlowControlConfig (Section 4.3). The 5s grace period and the stale timeout serve different purposes:

- **5s grace**: "Should this client affect PTY dimensions right now?" (resize concern)
- **60s/120s stale**: "Is this client meaningfully participating in the session?" (health concern, triggers peer notification)

### 3.3 Stale Triggers

The stale timeout clock resets ONLY when the client sends a message that proves application-level processing:

- ContinuePane
- KeyEvent
- WindowResize
- ClientDisplayInfo
- Any request message (CreateSession, SplitPane, etc.)

**HeartbeatAck does NOT reset the stale timeout.** On iOS, the OS can suspend the application while keeping TCP sockets alive. The TCP stack continues to respond to heartbeats even though the application event loop is frozen. If HeartbeatAck reset the stale timeout, a backgrounded iPad client would never be marked stale, and its stale dimensions would permanently constrain healthy clients.

**Ring cursor stagnation as stale trigger**: In addition to PausePane duration, the daemon uses ring cursor stagnation:

```
If client's ring cursor lag > 90% of ring capacity for stale_timeout_ms (60s/120s)
   AND client has not sent any application-level message during that period:
   -> transition to `stale`
```

This catches the "TCP alive but app frozen" scenario without wire format changes.

The eviction timeout (300s) MAY reset on HeartbeatAck as a safety net against false disconnects (the connection is alive, just slow).

### 3.4 Preedit Commit on Eviction (P13)

When the daemon evicts a stale client at T=300s:

1. If the evicted client owns an active preedit composition, the daemon commits (flushes) the preedit text to PTY.
2. The daemon sends `PreeditEnd` with `reason: "client_evicted"` to all remaining peer clients.
3. The daemon sends `Disconnect("stale_client")` to the evicted client and tears down the connection.

This prevents orphaned composition state. The commit happens before the connection teardown.

### 3.5 Recovery from Stale

All recovery scenarios collapse into a single operation: advance the client's ring cursor to the latest I-frame. The only variation is what additional messages accompany recovery:

| Recovery trigger | Procedure |
|-----------------|-----------|
| ContinuePane (after PausePane) | Advance cursor to latest I-frame. No additional messages. |
| Stale recovery | Advance cursor to latest I-frame + enqueue LayoutChanged (if layout changed during stale period) and PreeditSync (if preedit active on any pane) into the direct message queue. Per socket write priority (Section 4.1), these context messages arrive BEFORE the I-frame from the ring. |
| Ring overwrite (cursor falls behind ring tail) | Advance cursor to latest I-frame. No additional messages. |

---

## 4. Flow Control (P8)

### 4.1 PausePane (Advisory Signal)

PausePane is a client-to-server advisory signal indicating the client cannot keep up with frame delivery. The daemon's ring buffer writes **unconditionally** — PausePane does NOT stop the daemon from writing frames to the ring. PausePane triggers the health escalation timeline (Section 3.2) and informs the daemon that the client's ring cursor is expected to stagnate.

### 4.2 ContinuePane (Recovery)

When a client sends ContinuePane (or `auto_continue` triggers after the configured timeout):

1. The daemon advances the client's ring cursor to the latest I-frame.
2. Incremental updates resume from that point.
3. The client's coalescing tier is restored based on current throughput.

The I-frame IS the full state resync — same data, same wire format, no special codepath.

### 4.3 FlowControlConfig

Clients configure flow control behavior via `FlowControlConfig` (0x0502). The daemon acknowledges with `FlowControlConfigAck` (0x0503).

| Parameter | Type | Default (local) | Default (SSH) | Description |
|-----------|------|-----------------|---------------|-------------|
| `max_queue_age_ms` | u32 | 5000 | 10000 | Max ring cursor lag before PausePane advisory |
| `auto_continue` | bool | true | true | Auto-send ContinuePane after PausePane timeout |
| `stale_timeout_ms` | u32 | 60000 | 120000 | Time until stale transition |
| `eviction_timeout_ms` | u32 | 300000 | 300000 | Time until eviction after stale |

The daemon selects transport-aware defaults based on the connection type. Clients may override any parameter. Values of 0 disable the corresponding timeout (except `eviction_timeout_ms`, which has a server-enforced minimum).

### 4.4 Smooth Degradation Before PausePane

Before resorting to PausePane, the daemon applies smooth degradation based on ring cursor lag:

1. **Ring cursor lag > 50%** of ring capacity: Auto-downgrade coalescing tier (Active -> Bulk) for this client. Skip more P-frames.
2. **Ring cursor lag > 75%**: Force Bulk tier regardless of throughput.
3. **Ring cursor lag > 90%**: Client's next ContinuePane (or auto_continue) advances cursor to latest I-frame.
4. **Client sends ContinuePane**: Advance cursor. Resume incremental updates. Restore original tier.

This graduated approach keeps the client receiving updates for as long as possible. PausePane is a last resort, not a routine flow control mechanism.

### 4.5 Socket Write Priority

The daemon maintains two queues per client:

1. **Direct message queue**: Control messages (LayoutChanged, PreeditSync, PreeditEnd, session management responses). Higher priority.
2. **Ring buffer**: Frame data (I-frames, P-frames). Lower priority.

On each writable event, the daemon drains the direct queue first, then writes ring buffer data. This ensures context messages (e.g., LayoutChanged after stale recovery) arrive before the I-frame that references them.

---

## 5. Adaptive Coalescing (P10)

### 5.1 Four-Tier Model

The daemon uses a 4-tier adaptive coalescing model (plus an Idle quiescent state) to balance latency and throughput. Coalescing state is tracked per (client, pane) pair.

| Tier | Name | Min interval | Trigger |
|------|------|-------------|---------|
| 0 | Preedit | 0 ms (immediate) | Preedit state change (PreeditStart, PreeditUpdate, PreeditEnd) |
| 1 | Interactive | 0 ms (immediate) | Keystroke echo, cursor movement |
| 2 | Active | 16 ms (~60 fps) | Sustained PTY output (e.g., `cat large_file`, build output) |
| 3 | Bulk | 33 ms (~30 fps) | High-throughput PTY output sustained >500ms |
| -- | Idle | No frames | No PTY output for >100ms |

### 5.2 Tier Transitions

Tier transitions use hysteresis to prevent oscillation:

- **Upgrade** (higher tier -> lower tier / faster): Immediate on trigger event.
- **Downgrade** (lower tier -> higher tier / slower): Requires sustained condition for a threshold period.
  - Interactive -> Active: sustained output >100ms
  - Active -> Bulk: sustained high throughput >500ms
  - Any -> Idle: no output >100ms

### 5.3 Preedit Immediate Rule

Preedit state changes ALWAYS trigger immediate frame delivery (Tier 0), regardless of the current coalescing tier. When a KeyEvent triggers a preedit change:

1. The daemon calls the IME engine's `processKey()`.
2. If preedit changed, the daemon applies preedit via `overlayPreedit()` post-`bulkExport()` to inject preedit cells into the exported frame data.
3. The daemon immediately triggers `RenderState.update()` + `bulkExport()` outside the normal coalescing window.
4. The resulting frame is written to the ring buffer and flushed to all clients without delay.

This ensures preedit latency stays under 33ms over local Unix socket, which is critical for responsive Korean/CJK composition.

### 5.4 "Immediate First, Batch Rest" Rule

When a KeyEvent produces both preedit AND committed text in the same ImeResult:

1. The committed text is written to PTY (which may trigger PTY output).
2. The preedit change triggers an immediate frame.
3. Subsequent PTY output (from the committed text echo) follows normal coalescing.

The preedit frame is never delayed by batching with PTY output.

### 5.5 WAN Coalescing Adjustments

For SSH tunnel connections, the daemon adjusts coalescing based on the client's `ClientDisplayInfo` (0x0505) message:

| Field | Effect on coalescing |
|-------|---------------------|
| `transport_type: "ssh"` | Tier 2 minimum interval raised to 33ms; Tier 3 raised to 100ms |
| `bandwidth_hint` | Below 1 Mbps: force Tier 3 for all non-preedit output |
| `estimated_rtt_ms` | Above 100ms: increase Idle threshold to 200ms |

**Preedit is NEVER throttled**, regardless of transport type or bandwidth. Korean composition latency is non-negotiable.

### 5.6 Power-Aware Throttling

The client reports power state via `ClientDisplayInfo`:

| Power state | Coalescing cap | Preedit |
|-------------|---------------|---------|
| `ac` | No cap (full tier model) | Immediate |
| `battery` | Max Tier 2 (16ms / 60fps) | Immediate |
| `low_battery` | Max Tier 3 (33ms / 30fps) | Immediate |

Preedit is always immediate regardless of power state.

### 5.7 Idle Suppression During Resize

During an active resize drag (daemon receiving WindowResize events within the 250ms debounce window), the daemon suppresses the Idle timeout. This prevents the coalescing state from dropping to Idle between resize events, which would cause unnecessary I-frame generation on each resize step.

### 5.8 Per-(Client, Pane) Cadence

Coalescing state is tracked independently for each (client, pane) pair. One pane at Bulk tier does not affect another pane at Interactive tier, even within the same client connection. One client at Bulk tier does not affect another client's coalescing for the same pane.

---

## 6. Preedit Ownership (P11)

### 6.1 Single-Owner Model

The daemon maintains preedit ownership state per pane. At most one pane in a session can have active preedit at any time (preedit exclusivity invariant). The ownership tracking struct:

```
PanePreeditState {
    owner: ?u32,              // client_id of the composing client, null = no active composition
    preedit_session_id: u32,  // monotonic counter for composition sessions
    preedit_text: []u8,       // current preedit string (UTF-8)
    // input_method is stored at session level, not per-pane
}
```

The struct is pure ownership tracking for multi-client coordination. Cursor position and display width are determined by `overlayPreedit()` at export time (see internal architecture doc §4.4). Composition state is managed by the IME engine, not tracked in protocol structs.

### 6.2 Ownership Rules (Last-Writer-Wins)

1. **First composer**: When Client A sends a KeyEvent that triggers composition on a pane with no active preedit, Client A becomes the preedit owner.

2. **Concurrent attempt**: When Client B sends a composing KeyEvent on the same pane while Client A owns the preedit:
   - Daemon commits Client A's current preedit text to PTY.
   - Daemon sends `PreeditEnd` to all clients with `reason: "replaced_by_other_client"`.
   - Daemon starts a new composition session owned by Client B.
   - Daemon sends `PreeditStart` to all clients with Client B as owner.

3. **Owner disconnect**: When the preedit owner disconnects:
   - Daemon commits current preedit text to PTY (if any).
   - Daemon sends `PreeditEnd` with `reason: "client_disconnected"`.

4. **Non-composing input from non-owner**: Regular (non-composing) KeyEvents from any client are always processed normally, regardless of preedit ownership. If a non-owner sends a regular key, the owner's preedit is committed first.

### 6.3 Inactivity Timeout

If the daemon receives no input from the preedit owner for 30 seconds, it commits the current preedit text to PTY and sends `PreeditEnd`. This handles cases where the client is frozen but the socket is still open.

---

## 7. Preedit Lifecycle on State Changes (P12)

This section defines daemon behavior when external events interrupt an active preedit composition. The general principle: preedit is always resolved (committed or cancelled) before processing the interrupting action.

### 7.1 Focus Change (Intra-Session)

When the focused pane changes within a session during active composition, the daemon flushes the active preedit to the outgoing pane's PTY and clears the preedit overlay, sending `PreeditEnd` with `reason: "focus_changed"` to all clients. See doc 02 Section 4.4 for the full procedure and pseudocode.

### 7.2 Alternate Screen Switch

When an application switches from primary to alternate screen (e.g., `vim` launches) while composition is active:

1. Daemon commits current preedit text to PTY.
2. Daemon sends `PreeditEnd` with `reason: "committed"`.
3. Daemon processes the screen switch.
4. Daemon sends FrameUpdate with `frame_type=1` (I-frame), `screen=alternate`.

Alternate screen applications have their own input handling. Carrying preedit state into the alternate screen would be confusing.

### 7.3 Pane Close

When the user closes a pane while composition is active:

1. Daemon cancels the active composition via `engine.reset()` — does NOT commit to PTY (the PTY is being closed).
2. Daemon sends `PreeditEnd` with `reason: "pane_closed"` to all clients.
3. Daemon proceeds with the pane close sequence.

**This is the ONLY scenario where `engine.reset()` (discard) is used instead of `engine.flush()` (commit).** All other preedit-ending scenarios use flush/commit to preserve the user's work.

### 7.4 Owner Disconnect

When the composing client's connection drops (network failure, crash, session detach):

1. Daemon detects disconnect (socket read returns 0 or error).
2. Daemon commits current preedit text to PTY (best-effort: preserve the user's work).
3. Daemon sends `PreeditEnd` with `reason: "client_disconnected"` to remaining clients.
4. Daemon clears preedit ownership.

Session detach reuses the `"client_disconnected"` reason because from remaining clients' perspective, the effect is identical.

### 7.5 Input Method Switch During Active Preedit

When a client sends `InputMethodSwitch` (0x0404) while composition is active:

- If `commit_current=true`: Daemon commits preedit to PTY, sends `PreeditEnd` with `reason: "committed"`.
- If `commit_current=false`: Daemon cancels preedit via `engine.reset()`, sends `PreeditEnd` with `reason: "cancelled"`.

Then the daemon switches the session's input method and sends `InputMethodAck` to all attached clients.

### 7.6 Concurrent Preedit and Resize

When the terminal is resized while composition is active:

1. Daemon processes the resize through the ghostty Terminal.
2. The ghostty surface handles preedit cursor repositioning internally.
3. Daemon sends FrameUpdate with `frame_type=1` (I-frame) — preedit cells are included at the updated position.

No separate PreeditUpdate with cursor coordinates is needed. The preedit text is not affected by resize — only its display position changes.

### 7.7 Summary: reset() vs flush()

| Scenario | Method | Rationale |
|----------|--------|-----------|
| Pane close | `engine.reset()` (discard) | PTY is closing; committing text is pointless |
| Focus change | `engine.flush()` (commit) | Preserve user's work |
| Alt screen switch | `engine.flush()` (commit) | Preserve user's work |
| Owner disconnect | `engine.flush()` (commit) | Best-effort preservation |
| Client eviction | `engine.flush()` (commit) | Prevent orphaned state |
| Replaced by other client | `engine.flush()` (commit) | Preserve first client's work |
| Input method switch (commit_current=true) | `engine.flush()` (commit) | Explicit user request |
| Input method switch (commit_current=false) | `engine.reset()` (discard) | Explicit user request |
| 30s inactivity timeout | `engine.flush()` (commit) | Preserve user's work |

---

## 8. Session Persistence (P17 + I7)

### 8.1 Snapshot Model

The daemon uses periodic snapshots to disk (JSON format, 8-second auto-save interval, following cmux's model). Snapshots are triggered automatically and can be triggered explicitly by clients via `SnapshotRequest` (0x0700).

### 8.2 IME State in Snapshots

The session snapshot persists IME state at the session level:

```json
{
    "session_id": 1,
    "name": "my-session",
    "ime": {
        "input_method": "korean_2set",
        "keyboard_layout": "qwerty"
    },
    "panes": [...]
}
```

Two fields at session level:
- `input_method`: canonical protocol string (e.g., `"korean_2set"`, `"direct"`). The canonical registry is in IME Interface Contract, Section 3.7.
- `keyboard_layout`: physical keyboard layout (e.g., `"qwerty"`). Orthogonal to `input_method`.

Panes carry no IME state. They do not have per-pane `input_method` or `keyboard_layout` fields.

### 8.3 What is NOT Persisted

- **Preedit text** (in-progress composition). On restore, all sessions start with empty composition. Nobody expects to resume mid-syllable after a daemon restart.
- **Engine-internal state** (e.g., libhangul's jamo stack). Reconstructing this is not feasible and not useful.

### 8.4 Preedit Flush Before Save

Before writing a snapshot, the daemon MUST flush any active preedit composition on all sessions. This ensures the committed text is captured in the terminal state that gets snapshot. The flush sequence:

1. For each session with active preedit: call `engine.flush()` to commit preedit to PTY.
2. Send `PreeditEnd` to all clients.
3. Allow the committed text to propagate through the terminal (PTY echo -> VT parse -> Terminal state).
4. Proceed with snapshot.

### 8.5 Engine Reconstruction on Restore

When restoring a session from snapshot:

1. Create one `ImeEngine` instance per session with the saved `input_method` string (e.g., `HangulImeEngine.init(allocator, "korean_2set")`).
2. The engine constructor decomposes the canonical string into engine-internal types (language dispatch + engine-native keyboard ID). No code outside the engine constructor performs this decomposition.
3. Composition state is `null` — the engine starts with no active composition.
4. All panes in the restored session share this engine instance.

### 8.6 Restore Sequence (IME-Relevant Steps)

When the daemon processes a `RestoreSessionRequest`:

1. Read snapshot file, validate format.
2. Create session with saved name and fresh server-assigned `session_id`.
3. Walk the saved layout tree, create panes with fresh `pane_id`s, spawn shells.
4. **Re-initialize the per-session IME engine** from saved `input_method` string.
5. Restore scrollback if requested.
6. Send `RestoreSessionResponse`, `LayoutChanged`, and I-frame for each pane.

---

## 9. Notification Defaults (P18)

### 9.1 Always-Sent Notifications

After `AttachSession`, the client automatically receives these notifications without explicit subscription:

| Notification | Source |
|-------------|--------|
| LayoutChanged | doc 03 (session/pane management) |
| SessionListChanged | doc 03 |
| PaneMetadataChanged | doc 03 |
| ClientAttached | doc 03 |
| ClientDetached | doc 03 |
| ClientHealthChanged | doc 03 |

These are structural notifications that every client needs for correct operation. They cannot be unsubscribed.

### 9.2 Opt-In Notifications

All notifications defined in the protocol's notification section (PaneTitleChanged, ProcessExited, Bell, RendererHealth, PaneCwdChanged, ActivityDetected, SilenceDetected) require explicit subscription via `Subscribe` (0x0810). The daemon does not send these until the client subscribes.

### 9.3 Subscription Scope

Subscriptions are per-connection. If a client has multiple connections (one per session/tab), each connection manages its own subscriptions independently. Subscriptions can be per-pane (`pane_id` specified) or global (`pane_id = 0` for all panes).

---

## 10. Heartbeat Policy (P19)

### 10.1 Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Heartbeat interval | 30 seconds | How often to send Heartbeat if no other messages sent |
| Connection timeout | 90 seconds | If no message of any kind received within this period, connection is dead |

### 10.2 Behavior

Either side MAY send `Heartbeat` (0x0003) if no other messages have been sent within the heartbeat interval. The receiver responds with `HeartbeatAck` (0x0004). In the typical case, the server initiates heartbeats; a client MAY also send heartbeats to detect server unresponsiveness.

If no message (of any kind) is received within 90 seconds (3 missed heartbeat intervals), the daemon considers the connection dead and sends `Disconnect(TIMEOUT)`.

### 10.3 Transport-Specific Behavior

- **Unix domain sockets (local)**: Heartbeat is optional. The OS detects dead sockets via `SO_KEEPALIVE` or write errors (`EPIPE`/`SIGPIPE`) much faster.
- **SSH tunnels**: Heartbeats are complementary to SSH's own `ServerAliveInterval` keepalive. Recommended to detect tunnel failures that the OS may not report immediately.

### 10.4 Orthogonality with Health States

Heartbeat is a **connection liveness** mechanism (90s timeout -> Disconnect). Health states (Section 3) are an **application responsiveness** mechanism (triggered by ring cursor lag and PausePane duration). These are independent systems:

| Combination | Meaning |
|-------------|---------|
| Heartbeat-healthy + output-stale | `stale` (app frozen, TCP alive — the iOS backgrounding scenario) |
| Heartbeat-missed + output-healthy | Connection problem (will resolve or disconnect at 90s) |

`HeartbeatAck` does NOT reset the stale timeout (Section 3.3). The `echo_nonce` extension (application-level heartbeat verification) is deferred to v2 as a `HEARTBEAT_NONCE` capability.

---

## 11. Design Decisions Log

| Decision | Status | Rationale |
|----------|--------|-----------|
| HeartbeatAck does not reset stale timeout | **Decided** | iOS backgrounding keeps TCP alive while app is frozen. HeartbeatAck from frozen app would mask stale state. |
| Preedit never throttled | **Decided** | Korean composition latency under 33ms is non-negotiable. Preedit Tier 0 is exempt from all WAN, power, and degradation adjustments. |
| Single preedit owner per session | **Decided** | Per-session IME engine makes simultaneous compositions physically impossible. Preedit exclusivity invariant is the normative statement. |
| Pane close uses reset(), all others use flush() | **Decided** | Committing text to a closing PTY is pointless. All other scenarios preserve the user's work. |
| 5s hysteresis for stale re-inclusion | **Decided** | Prevents resize oscillation from intermittently responsive clients (iOS foreground/background cycling). |
| Snapshot flushes preedit before save | **Decided** | Ensures committed text is captured in the terminal state. Composition state is not persisted. |
| Coalescing per (client, pane) pair | **Decided** | One pane's throughput pattern should not affect another pane's latency. One client's degradation should not affect other clients. |
| Smooth degradation before PausePane | **Decided** | Graduated tier downgrade (50% -> 75% -> 90%) keeps clients receiving updates as long as possible. PausePane is last resort. |
