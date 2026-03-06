# 06 - Flow Control and Auxiliary Protocols

**Version**: v0.7
**Status**: Draft
**Date**: 2026-03-05
**Author**: systems-engineer (AI-assisted)

## Overview

This document specifies flow control (backpressure), adaptive frame coalescing, clipboard, persistence, notification, subscription, heartbeat, and extension negotiation protocols for libitshell3. These are auxiliary protocols that complement the core session/pane management (doc 03), input forwarding (doc 04), and render state streaming (doc 04).

All messages use the binary framing defined in document 01 (16-byte header: magic(2) + version(1) + flags(1) + msg_type(2) + reserved(2) + payload_len(4) + sequence(4), little-endian byte order).

### Conventions

Same as doc 03:
- Little-endian byte order for all multi-byte integers in the binary header.
- Control messages (this document) use JSON payloads unless otherwise noted.
- **Optional fields**: When a JSON field has no value, the field MUST be omitted from the JSON object. Senders MUST NOT include fields with `null` values. Receivers MUST tolerate both missing keys and `null` values as "absent" (defensive parsing for forward/backward compatibility).
- IDs are u32, server-assigned, monotonically increasing (see doc 03 ID Types).
- Boolean fields use JSON `true`/`false`.
- `payload_len` in the header is the payload size only (NOT including the 16-byte header).

---

## Message Type Range Assignments

| Range | Category | Document |
|-------|----------|----------|
| `0x0001` - `0x00FF` | Handshake, capability negotiation | Doc 02 |
| `0x0100` - `0x01FF` | Session and pane management | Doc 03 |
| `0x0200` - `0x02FF` | Input forwarding | Doc 04 |
| `0x0300` - `0x03FF` | Render state / frame updates | Doc 04 |
| `0x0400` - `0x04FF` | CJK preedit / IME protocol | Doc 05 |
| `0x0500` - `0x05FF` | Flow control and backpressure | **This doc** |
| `0x0600` - `0x06FF` | Clipboard | **This doc** |
| `0x0700` - `0x07FF` | Persistence (snapshot/restore) | **This doc** |
| `0x0800` - `0x08FF` | Notifications and subscriptions | **This doc** |
| `0x0900` - `0x09FF` | Reserved for future connection health extensions | Doc 01 / Doc 02 (see Section 7) |
| `0x0A00` - `0x0AFF` | Extension negotiation | **This doc** |
| `0x0B00` - `0x0FFF` | Reserved for future use | -- |
| `0xF000` - `0xFFFE` | Vendor/custom extensions | **This doc** |
| `0xFFFF` | Reserved (never used) | -- |

---

## 1. Adaptive Frame Coalescing

### Background

libitshell3 does not use a fixed frame rate. Instead, the server employs a **4-tier adaptive coalescing model** with an additional Idle state, informed by iTerm2's adaptive cadence and ghostty's event-driven rendering. The coalescing tier is determined per-(client, pane) pair based on PTY throughput, keystroke recency, and preedit state.

> **Terminology note**: The model has 4 active coalescing tiers (Preedit, Interactive, Active, Bulk) plus an Idle state. Idle produces no frames and is not an active coalescing tier -- it is the quiescent state entered when there is no PTY output and no user interaction. The tier table in Section 1.1 lists all 5 states for completeness.

### 1.1 Coalescing Tiers

| Tier | Condition | Frame interval | Rationale |
|------|-----------|----------------|-----------|
| **Preedit** | Active IME composition + keystroke | Immediate (0 ms) | CJK preedit must render instantly for usable composition. MUST requirement: <33 ms end-to-end over Unix socket. |
| **Interactive** | PTY output <1 KB/s + keystroke within 200 ms | Immediate (0 ms) | Keystroke echo and shell prompts must feel instantaneous. Matches ghostty's "immediate first frame" behavior. |
| **Active** | PTY output 1-100 KB/s | 16 ms (display Hz) | Sustained output (e.g., scrolling code, logs). Matches display refresh rate. |
| **Bulk** | PTY output >100 KB/s sustained 500 ms | 33 ms (~30 fps) | Heavy throughput (e.g., `cat /dev/urandom`, large builds). Reduces CPU/bandwidth without visible quality loss. |
| **Idle** | No PTY output for 500 ms | No frames sent | Nothing to send. Server emits no FrameUpdate until new output arrives. |

### 1.2 Transition Thresholds with Hysteresis

Tier transitions use hysteresis to prevent oscillation:

| Transition | Trigger | Hysteresis |
|-----------|---------|------------|
| Idle -> Interactive | KeyEvent received + PTY output within 5 ms | None |
| Idle -> Active | PTY output arrives without recent keystroke | None |
| Active -> Bulk | >100 KB/s sustained for 500 ms | Drop back to Active at <50 KB/s for 1 s |
| Active -> Idle | No PTY output for 500 ms | None |
| Any -> Preedit | Preedit state changed (composition started/updated) | 200 ms timeout back to previous tier after composition ends |

The Active->Bulk hysteresis prevents rapid tier flapping during bursty output (e.g., compiler output interspersed with linking pauses).

### 1.3 "Immediate First, Batch Rest"

When a pane transitions from Idle to any active tier, the **first frame is sent immediately** without coalescing delay. Subsequent frames follow the tier's coalescing interval. This ensures that the first character of output after a prompt never has artificial latency, matching ghostty's observed behavior (removed 10 ms coalescing timer because immediate first frame was strictly better).

### 1.4 Per-(Client, Pane) Cadence

The server maintains coalescing state independently for each (client, pane) pair:

- **Per-client coalescing timers**: Each client receives FrameUpdates at its own rate. A fast desktop client on AC power gets Active-tier frames at 16 ms while a battery-constrained iPad client simultaneously receives the same pane's updates at 50 ms.
- **Independent tier state**: Pane 1 can be at Preedit tier (user composing CJK) while pane 2 is at Bulk tier (running `make -j16`), and both are tracked independently for each attached client.

> **Normative**: The server maintains a single dirty bitmap per pane. Frame data (I-frames and P-frames) is serialized once per pane per frame interval. All clients viewing the same pane receive identical frame data from the shared ring buffer (Section 2). Clients at different coalescing tiers receive different subsets of frames from the same sequence, but each frame's content is identical regardless of which client receives it.

### 1.5 Client Power Hints and Display Info

Clients communicate their display capabilities, power state, and transport information via the `ClientDisplayInfo` message, allowing the server to optimize frame delivery.

#### ClientDisplayInfo (0x0505)

Sent by the client during handshake (after capability negotiation) and whenever display, power, or transport state changes. This is a runtime message, not handshake-only — the client may send it at any time.

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0505` | ClientDisplayInfo | C -> S | Client reports display, power, and transport state |
| `0x0506` | ClientDisplayInfoAck | S -> C | Server acknowledges display info |

**ClientDisplayInfo payload** (JSON):

```json
{
  "display_refresh_hz": 60,
  "power_state": "ac",
  "preferred_max_fps": 0,
  "transport_type": "local",
  "estimated_rtt_ms": 0,
  "bandwidth_hint": "local"
}
```

| Field | Type | Values | Description |
|-------|------|--------|-------------|
| `display_refresh_hz` | number | 60, 120, etc. | Display refresh rate |
| `power_state` | string | `"ac"`, `"battery"`, `"low_battery"` | Client power state |
| `preferred_max_fps` | number | 0 = no preference | Client's preferred fps cap (0 = use server default) |
| `transport_type` | string | `"local"`, `"ssh_tunnel"`, `"unknown"` | How the client connects to the daemon |
| `estimated_rtt_ms` | u16 | 0 = unknown/local | Client's measured or estimated round-trip time to the daemon. The client is the only entity that knows the true end-to-end latency (see Design Note below). |
| `bandwidth_hint` | string | `"local"`, `"lan"`, `"wan"`, `"cellular"` | Network bandwidth class |

> **Design Note — why the client self-reports RTT**: With SSH tunneling, the daemon only sees a Unix socket connection to sshd. Heartbeat RTT only measures the local socket hop (~0ms), not the true end-to-end latency. The client is the only entity that knows the actual transport latency. Neither tmux nor zellij measures server-side RTT. See Issue 2 and Issue 4 resolutions for full rationale.

**ClientDisplayInfoAck payload** (JSON):

```json
{
  "status": 0,
  "effective_max_fps": 60
}
```

**Power-aware throttling**:

| Power state | Active tier cap | Bulk tier cap | Preedit |
|-------------|-----------------|---------------|---------|
| `ac` | display_refresh_hz (default 60 fps) | 30 fps | Always immediate |
| `battery` | 20 fps | 10 fps | Always immediate |
| `low_battery` | 10 fps | 5 fps | Always immediate |

> **Preedit is always immediate regardless of power state.** A preedit-only frame is ~110 bytes, which is negligible for both bandwidth and power. Throttling preedit would make CJK input unusable.

The `display_refresh_hz` field allows the server to set the Active tier ceiling to match the client's display. On a 120 Hz ProMotion Mac, Active tier uses 8 ms intervals; on a 60 Hz display, 16 ms.

### 1.6 WAN Coalescing Tier Adjustments

When the server receives `ClientDisplayInfo` with `transport_type: "ssh_tunnel"`, it adjusts coalescing intervals for that client to account for network conditions:

| Tier | Local | SSH Tunnel (WAN) |
|------|-------|------------------|
| Preedit | Immediate (0ms) | Immediate (0ms) — never throttled |
| Interactive | Immediate (0ms) | Immediate (0ms) |
| Active | 16ms (60fps) | 33ms (30fps) |
| Bulk | 33ms (30fps) | 66ms (15fps) |

The server selects WAN intervals based on `transport_type` and `bandwidth_hint`:
- `"local"` transport: standard tier intervals.
- `"ssh_tunnel"` + `"lan"`: standard intervals (LAN has negligible latency).
- `"ssh_tunnel"` + `"wan"`: WAN intervals as shown above.
- `"ssh_tunnel"` + `"cellular"`: WAN intervals, further reduced by power state if `"battery"` or `"low_battery"`.

> **Preedit latency scoping**: Preedit FrameUpdates MUST be flushed immediately with no server-side coalescing delay. Over Unix domain socket, the server MUST deliver the FrameUpdate to the transport layer within 33ms of receiving the triggering KeyEvent. Over SSH tunnel or other network transport, the server adds no additional delay; end-to-end latency is dominated by network RTT. For remote clients over SSH with 50-100ms RTT, user-perceived preedit latency will be approximately equal to the round-trip time. Client-side composition prediction is a potential mitigation deferred to a future version.

### 1.7 Idle Coalescing Suppression During Resize

During the 250ms resize debounce window (doc 03 Section 5.4) and for 500ms after the debounce fires (`ioctl(TIOCSWINSZ)`), the server MUST NOT transition the pane's coalescing tier to Idle, even if no new PTY output arrives.

**Rationale**: The PTY application is processing SIGWINCH and may briefly pause output; this is not true idleness. Transitioning to Idle would suppress frame delivery, causing the client to miss the post-resize FrameUpdate.

After the 500ms grace expires, normal coalescing tier transitions resume.

---

## 2. Flow Control and Backpressure

### Background

When a pane produces output faster than a client can consume it, the server must manage delivery. libitshell3 uses a **shared per-pane ring buffer** model with per-client read cursors, replacing the per-client output buffer model from v0.6. The ring buffer is combined with an I/P-frame model (doc 04) to provide O(1) frame serialization and automatic state recovery.

### Architecture

```
Server writes once per frame interval:                Per-client read cursors:
                                                       Client A (Interactive) ─┐
  PTY output → terminal emulator → frame serializer    Client B (Bulk) ──────┐ │
       │                                    │          Client C (paused) ───┐ │ │
       │                                    ▼                              ▼ ▼ ▼
       │                              ┌─────────────────────────────────────────┐
       └──────────────────────────────│  Shared Ring Buffer (2 MB per pane)     │
                                      │  [I₀][P₁][P₂][P₃][I₁][P₄][P₅]...     │
                                      └─────────────────────────────────────────┘
                                              │           │
                                     write ◄──┘           └──► writev() to sockets
                                     (once)                    (zero-copy from ring)
```

**Key properties**:
- Frame data is serialized **once** per pane per frame interval and written to the ring.
- Per-client state is a **read cursor** (12 bytes: ring offset + partial write offset).
- Socket writes use `writev()` directly from ring memory — zero-copy.
- When a cursor falls behind the ring write head, the server advances it to the latest I-frame.

### Message Types

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0500` | PausePane | S -> C | Server signals client is falling behind |
| `0x0501` | ContinuePane | C -> S | Client signals readiness to resume |
| `0x0502` | FlowControlConfig | C -> S | Client configures flow control parameters |
| `0x0503` | FlowControlConfigAck | S -> C | Server acknowledges configuration |
| `0x0504` | OutputQueueStatus | S -> C | Server reports delivery pressure |

### 2.1 Shared Ring Buffer Model

The server maintains a shared ring buffer per pane. All frame data (I-frames and P-frames) is written once to the ring. Per-client read cursors track each client's delivery position.

**Ring parameters**:

| Parameter | Default | Configurable | Description |
|-----------|---------|-------------|-------------|
| Ring size | 2 MB per pane | Server config (not protocol-negotiated) | Total ring buffer capacity |
| Keyframe interval | 1 second | Server config (0.5-5 seconds) | How often the server writes an I-frame |

**Sizing analysis** (120x40 CJK worst case, 1s keyframe interval, 60fps Active tier):

| Component | Size |
|-----------|------|
| 1 I-frame | ~116 KB |
| 60 P-frames (typical) | ~10-30 KB each = ~600KB-1.8MB |
| Minimum ring (2 I-frames) | ~232 KB |
| Typical interactive ring usage | ~1.3 MB |
| Worst case (sustained full-screen rewrite) | ~7 MB |

2 MB covers typical interactive use with headroom. For heavy output (sustained full-screen rewrite), the ring wraps and slow clients skip to the latest I-frame — correct behavior.

> **Normative**: The ring MUST always contain at least one complete I-frame for each pane. When the ring write head is about to overwrite the only remaining I-frame in the ring, the server MUST first write a new I-frame before the overwrite proceeds. This ensures that any client seeking to the latest I-frame (recovery, attach, ContinuePane) always finds one.

**Implementation model**:
- Variable-length byte-level ring (not fixed-slot) — frames vary from ~100 bytes to ~116KB.
- Ring overwrites unconditionally. No drain coordination (unlike tmux's control mode which drains when the slowest client catches up). No "convoy effect" from slow clients.
- Socket write path: `writev()` directly from ring memory — zero-copy.
- EAGAIN handling: cursor stays at current position, re-arm epoll/kqueue. No special recovery.
- Concurrency: `pane_mutex` -> `ring_lock` ordering. Socket writers do not need `pane_mutex` — they read from the ring only. This decouples the socket write path from the pane mutex.

**Memory comparison** (100 clients, 4 panes):

| Metric | Per-client buffers (v0.6) | Shared ring (v0.7) |
|--------|--------------------------|---------------------|
| Total memory | 200 MB (100 x 4 x 512KB) | 8 MB (4 x 2MB) + cursors |
| memcpy per frame | 100 copies | 1 ring write |
| Per-client state | 512KB buffer | 12 bytes (cursor + partial offset) |

### 2.2 Preedit Bypass Buffer

Preedit-only frames (`frame_type=0` with preedit state change) are delivered directly to each client via a per-client **latest-wins priority buffer**. They are NOT written to the shared ring buffer.

**Rationale**: A behind client's ring cursor creates position-dependent latency for preedit-only frames. A Bulk-tier client with unread frames queued ahead in the ring must process those frames before reaching a preedit frame, violating the <33ms preedit latency target. Delivering preedit-only frames outside the ring eliminates this latency source entirely.

**Per-client preedit bypass buffer**:
- Holds at most 1 preedit-bypass frame (~128 bytes).
- Latest-wins: any new preedit frame unconditionally replaces whatever is in the buffer.
- Drained with highest priority on socket-writable events (before direct message queue and ring data).

**Bypass condition**: `frame_type=0 AND preedit JSON present AND (preedit.active changed OR preedit.text changed)`. Cursor-only metadata updates without preedit changes go into the ring as normal `frame_type=0` entries — they are not latency-critical.

**O(N) cost is negligible**: At ~110 bytes per frame at typing speed (~15/s), preedit bypass costs 110 * 15 * N = 1650N bytes/s. Even with 100 clients: ~165KB/s.

**Socket write priority order**:
1. **Preedit-bypass buffer** (~110 bytes, highest priority)
2. **Direct message queue** (LayoutChanged, PreeditSync, ClientHealthChanged, etc.)
3. **Ring buffer frames** (via `writev()` zero-copy from ring memory)

### 2.3 Ring Contents

The shared ring buffer contains:
- **I-frames** (`frame_type=2`, `frame_type=3`): All rows, self-contained keyframes.
- **P-frames with dirty rows** (`frame_type=1`): Cumulative dirty rows since last I-frame.
- **Metadata-only frames without preedit changes** (`frame_type=0`, cursor-only moves, mode changes): Non-latency-critical metadata updates.

The ring does NOT contain preedit-only frames (those go through the per-client bypass buffer per Section 2.2).

The per-pane `frame_sequence` counter is incremented for every frame written to the ring buffer. Preedit-only frames delivered via the bypass buffer do NOT increment `frame_sequence`.

### 2.4 PausePane (0x0500)

In the ring buffer model, PausePane is an **advisory signal** for the health escalation state machine, not a flow-control stop mechanism. The ring writes unconditionally for all clients regardless of pause state.

PausePane is sent by the server when a client's ring cursor falls behind the ring write head by >90% of ring capacity.

**What PausePane does**:
- Triggers the health escalation timeline (Section 2.8).
- Excludes the client from resize calculation after 5s (doc 03 Section 5.5).

**What PausePane does NOT do**:
- Does NOT stop frame production for the pane (ring writes unconditionally).
- Does NOT allocate or manage a per-client output buffer.

**Preedit delivery during PausePane**: Preedit-only frames are always delivered via the per-client bypass buffer (Section 2.2), independent of ring cursor state. No special PausePane exception needed — the bypass path applies to all clients at all times.

> **Preedit-only FrameUpdate format**: When delivering a preedit bypass frame, the server sends a FrameUpdate with `frame_type=0` (P-frame, metadata-only): no DirtyRows section, JSON preedit metadata only. This is approximately 100-110 bytes. The client uses this to update the preedit overlay without receiving or processing the full terminal grid state.
>
> **Edge case — preedit commit while paused**: If a preedit composition is committed (PreeditEnd) while the pane is paused, the client sees PreeditEnd and can remove the preedit overlay, but the committed text in the terminal grid is not visible until the client catches up via ring cursor advance. This is acceptable because: (1) the commit is a single-character insertion, not a visual layout change; (2) the client will receive an I-frame reflecting the committed state when it catches up.

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "ring_lag_percent": 92,
  "ring_lag_bytes": 1884160
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Pane for which the client is falling behind |
| `ring_lag_percent` | number | Client cursor's lag as percentage of ring capacity |
| `ring_lag_bytes` | number | Absolute byte lag between client cursor and write head |

### 2.5 ContinuePane (0x0501)

Sent by the client when it has finished processing queued frames and is ready to resume normal delivery. In the ring model, the server advances the client's cursor to the latest I-frame in the ring.

**Payload** (JSON):

```json
{
  "pane_id": 1
}
```

The server advances the client's ring cursor to the latest I-frame. The client receives the I-frame (a complete self-contained terminal state) and resumes normal incremental delivery from that point. No `last_processed_seq` field is needed — the ring cursor position already tracks the client's state.

### 2.6 FlowControlConfig (0x0502)

Client configures per-connection flow control parameters. Sent once during the handshake phase, and may be sent again at any time to adjust.

**Payload** (JSON):

```json
{
  "max_queue_age_ms": 5000,
  "auto_continue": true,
  "resize_exclusion_timeout_ms": 5000,
  "stale_timeout_ms": 60000,
  "eviction_timeout_ms": 300000
}
```

| Field | Type | Default (local) | Default (SSH) | Description |
|-------|------|-----------------|---------------|-------------|
| `max_queue_age_ms` | number | 5000 | 5000 | Time-based staleness trigger (orthogonal to ring lag) |
| `auto_continue` | boolean | true | true | Server auto-continues after PausePane when client catches up |
| `resize_exclusion_timeout_ms` | number | 5000 | 5000 | Grace period before resize exclusion after PausePane |
| `stale_timeout_ms` | number | 60000 | 120000 | PausePane duration before `stale` health transition |
| `eviction_timeout_ms` | number | 300000 | 300000 | Total duration before forced disconnect |

The server selects transport-aware defaults based on `ClientDisplayInfo.transport_type`. The client can override via this message.

### 2.7 FlowControlConfigAck (0x0503)

**Payload** (JSON):

```json
{
  "status": 0,
  "effective_max_age_ms": 5000,
  "effective_resize_exclusion_ms": 5000,
  "effective_stale_ms": 60000,
  "effective_eviction_ms": 300000
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = accepted, 1 = adjusted (server clamped values) |

### 2.8 Client Health Model and Escalation Timeline

The protocol defines two health states orthogonal to connection lifecycle:

| State | Definition | Resize participation | Frame delivery |
|-------|-----------|---------------------|----------------|
| `healthy` | Normal operation | Yes | Full (per coalescing tier) via ring |
| `stale` | Paused too long or ring cursor stagnant | No (excluded after 5s grace) | None from ring (preedit bypass only) |

**`paused`** (PausePane active) is an orthogonal flow-control state, not a health state. A paused client remains `healthy` until the stale timeout fires.

**Smooth degradation** (auto-tier-downgrade at 50% ring lag, force Bulk at 75%, queue compaction) is **server-internal** implementation behavior, NOT a protocol-visible state. It is documented as implementation guidance below and reported via RendererHealth (0x0803) for debugging. It does not trigger ClientHealthChanged and does not affect resize.

**PausePane escalation timeline**:

```
T=0s:    PausePane sent. Client is still `healthy`. Still participates in resize.

T=5s:    Resize exclusion. Server recalculates effective size without this client.
         No protocol message. Server-internal decision.
         Handles the common case of brief iOS backgrounding without waiting
         for the full stale timeout.

T=60s:   `stale` health state transition (local transport).
(local)  Server sends ClientHealthChanged (0x0185) to all peer clients.

T=120s:  `stale` health state transition (SSH tunnel transport).
(SSH)    Same behavior as T=60s. Longer timeout accounts for higher latency
         and more variable behavior over SSH tunnels.

T=300s:  Eviction. Server sends Disconnect("stale_client") and tears down
         the connection. Transport-independent.
```

All timeouts are configurable via FlowControlConfig (Section 2.6).

**The 5s grace period and the stale timeout serve different purposes:**
- 5s grace: "Should this client affect PTY dimensions right now?" (resize concern)
- 60s/120s stale: "Is this client meaningfully participating in the session?" (health concern, triggers peer notification)

### 2.9 Stale Triggers

The stale timeout clock resets ONLY when the client sends a message that proves application-level processing:

- ContinuePane
- KeyEvent
- WindowResize
- ClientDisplayInfo
- Any request message (CreateSession, SplitPane, etc.)

**HeartbeatAck does NOT reset the stale timeout.**

**Rationale**: On iOS, the OS can suspend the application while keeping TCP sockets alive. The TCP stack continues to respond to heartbeats (ACKs) even though the application event loop is frozen. If HeartbeatAck reset the stale timeout, a backgrounded iPad client would never be marked stale, and its stale dimensions would permanently constrain healthy clients.

**Ring cursor stagnation as stale trigger**: In addition to PausePane duration, the server uses ring cursor stagnation:

```
If client's ring cursor lag > 90% of ring capacity for stale_timeout_ms (60s/120s)
   AND client has not sent any application-level message during that period:
   -> transition to `stale`
```

This catches the "TCP alive but app frozen" scenario without wire format changes.

The eviction timeout (300s) MAY reset on HeartbeatAck as a safety net against false disconnects (the connection is alive, just slow).

### 2.10 Recovery Codepath

Three distinct recovery procedures collapse into a single operation: **advance client ring cursor to latest I-frame**.

| Recovery trigger | v0.6 procedure | v0.7 procedure |
|-----------------|----------------|----------------|
| ContinuePane (after PausePane) | Discard buffered frames, send dirty=full snapshot | Advance cursor to latest I-frame |
| Ring overwrite (cursor falls behind ring tail) | N/A (new in v0.7) | Advance cursor to latest I-frame |
| Stale recovery | LayoutChanged + dirty=full FrameUpdate + PreeditSync | Advance cursor to latest I-frame |

The I-frame IS the full FrameUpdate — same data, same wire format, same client processing. The only variation is what additional messages accompany recovery:

- **ContinuePane**: Advance cursor. No additional messages needed.
- **Stale recovery**: Advance cursor + enqueue LayoutChanged (if layout changed during stale period) and PreeditSync (if preedit active on any pane) into the direct message queue. Per socket write priority (Section 2.2), these context messages arrive BEFORE the I-frame from the ring.

**Preedit commit on eviction**: When the server evicts a stale client at T=300s, any active preedit composition owned by that client MUST be committed (flushed to the terminal grid) before the client connection is torn down. This prevents orphaned composition state. The server sends PreeditEnd with `reason: "client_evicted"` to remaining peer clients before the Disconnect.

### 2.11 Smooth Degradation Before PausePane (Implementation Guidance)

Before resorting to PausePane, the server applies smooth degradation based on ring cursor lag:

```
1. Ring cursor lag above 50% of ring capacity:
   -> Auto-downgrade tier (Active -> Bulk) for this client.
   -> Skip more P-frames (deliver fewer frames from the ring).

2. Ring cursor lag above 75% of ring capacity:
   -> Force Bulk tier regardless of throughput.

3. Ring cursor lag above 90% of ring capacity:
   -> Send PausePane to the client.
   -> Client cursor will naturally advance to latest I-frame on ContinuePane.
   -> Continue delivering preedit-only frames via bypass buffer.

4. Client sends ContinuePane (or auto_continue triggers):
   -> Advance cursor to latest I-frame.
   -> Resume incremental updates from that point.
   -> Restore original tier based on current throughput.
```

This graduated approach keeps the client receiving updates for as long as possible. PausePane is a last resort, not a routine flow control mechanism.

**Key insight**: Unlike tmux (which buffers raw bytes), libitshell3 buffers structured frames in a ring. The I/P-frame model means the server can always recover any client by advancing its cursor to the latest I-frame — no special resync codepath needed.

### 2.12 OutputQueueStatus (0x0504)

Periodic notification (configurable interval) reporting delivery pressure for the client's subscribed panes. Allows the client to proactively adjust rendering behavior.

> **Normative**: OutputQueueStatus reports **per-client** delivery state for the receiving client's connection, not aggregate server state. Each client sees only its own ring cursor lag metrics. In a multi-client scenario, Client A's OutputQueueStatus reflects Client A's ring cursor position, which may differ from Client B's for the same pane (due to different consumption rates, coalescing tiers, or flow control states).

**Payload** (JSON):

```json
{
  "panes": [
    {
      "pane_id": 1,
      "ring_lag_bytes": 204800,
      "ring_lag_percent": 10,
      "paused": false
    }
  ]
}
```

---

## 3. Clipboard

### Background

Clipboard integration bridges the terminal application (OSC 52) and the host OS clipboard (macOS pasteboard, Linux X11/Wayland). The server intercepts OSC 52 sequences from PTY output and translates them into structured clipboard messages.

### Message Types

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0600` | ClipboardWrite | S -> C | Server requests client write to OS clipboard |
| `0x0601` | ClipboardRead | C -> S | Client requests clipboard contents for a pane |
| `0x0602` | ClipboardReadResponse | S -> C | Server returns clipboard contents |
| `0x0603` | ClipboardChanged | S -> C | Clipboard content changed notification |
| `0x0604` | ClipboardWriteFromClient | C -> S | Client pushes clipboard content to server |

### 3.1 ClipboardWrite (0x0600)

Sent by the server when a shell application writes to the clipboard via OSC 52. The client should write the data to the host OS clipboard.

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "clipboard_type": "system",
  "data": "copied text here",
  "encoding": "utf8"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Source pane |
| `clipboard_type` | string | `"system"` (clipboard) or `"selection"` (primary/X11) |
| `data` | string | Clipboard content |
| `encoding` | string | `"utf8"` or `"base64"` (for binary data) |

**OSC 52 integration**: When the server's terminal emulator processes `ESC ] 52 ; c ; <base64-data> ST`, it:
1. Decodes the base64 data.
2. Sends a ClipboardWrite to all attached clients with the decoded data.
3. The `clipboard_type` maps from the OSC 52 selection parameter: `c` = system, `p`/`s` = selection.

**Security**: The server may be configured to prompt before clipboard writes (matching iTerm2's security model). If prompting is enabled, the ClipboardWrite message includes a confirmation token and the client must display a user prompt before writing to the OS clipboard. This is controlled via capabilities negotiation.

### 3.2 ClipboardRead (0x0601)

Sent by the client when a shell application requests clipboard contents via OSC 52 query (`ESC ] 52 ; c ; ? ST`) and the server's terminal emulator forwards the request.

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "clipboard_type": "system"
}
```

### 3.3 ClipboardReadResponse (0x0602)

Server responds with the current clipboard contents.

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "clipboard_type": "system",
  "status": 0,
  "data": "clipboard contents"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = success, 1 = denied, 2 = unavailable |

### 3.4 ClipboardChanged (0x0603)

Optional notification sent by the server when its internal clipboard buffer changes (e.g., copy from scrollback selection). Clients subscribed to clipboard events receive this.

**Payload** (JSON):

```json
{
  "clipboard_type": "system",
  "data": "new clipboard contents"
}
```

### 3.5 ClipboardWriteFromClient (0x0604)

Bidirectional clipboard sync: client pushes its OS clipboard content to the server, e.g., for paste operations or to sync across multiple clients.

**Payload** (JSON):

```json
{
  "clipboard_type": "system",
  "data": "pasted text"
}
```

---

## 4. Persistence (Snapshot/Restore)

### Background

libitshell3 uses a hybrid persistence model: the daemon holds live state in memory, and periodically snapshots to disk (JSON format, 8-second auto-save interval, following cmux's proven model). Snapshot/restore messages allow clients to trigger snapshots explicitly and to restore sessions after daemon restart.

### Message Types

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0700` | SnapshotRequest | C -> S | Client requests a session snapshot |
| `0x0701` | SnapshotResponse | S -> C | Snapshot result |
| `0x0702` | RestoreSessionRequest | C -> S | Client requests session restore from snapshot |
| `0x0703` | RestoreSessionResponse | S -> C | Restore result |
| `0x0704` | SnapshotListRequest | C -> S | List available snapshots |
| `0x0705` | SnapshotListResponse | S -> C | Available snapshots |
| `0x0706` | SnapshotAutoSaveConfig | C -> S | Configure auto-save |
| `0x0707` | SnapshotAutoSaveConfigAck | S -> C | Auto-save configuration result |

### 4.1 SnapshotRequest (0x0700)

Triggers an immediate snapshot of the specified session to disk.

**Payload** (JSON):

```json
{
  "session_id": 0,
  "include_scrollback": true,
  "max_scrollback_lines": 4000
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | u32 | 0 = all sessions |
| `include_scrollback` | boolean | Whether to include scrollback buffer |
| `max_scrollback_lines` | number | 0 = use default, max 4000 |

### 4.2 SnapshotResponse (0x0701)

**Payload** (JSON):

```json
{
  "status": 0,
  "path": "/var/lib/itshell3/snapshots/session-1.json",
  "snapshot_size": 12345,
  "timestamp": 1709568000,
  "error": ""
}
```

### 4.3 RestoreSessionRequest (0x0702)

Requests the server to restore a session from a previously saved snapshot. The server creates new PTYs, spawns shells, and applies the saved layout. Scrollback is replayed if available.

**Payload** (JSON):

```json
{
  "path": "",
  "snapshot_session_name": "",
  "restore_scrollback": true
}
```

| Field | Type | Description |
|-------|------|-------------|
| `path` | string | Snapshot file path (empty = restore from most recent) |
| `snapshot_session_name` | string | Session name from snapshot (empty = restore all) |
| `restore_scrollback` | boolean | Whether to restore scrollback buffer |

### 4.4 RestoreSessionResponse (0x0703)

On success, the server follows with CreateSessionResponse-like data and LayoutChanged notifications.

**Payload** (JSON):

```json
{
  "status": 0,
  "session_id": 5,
  "pane_count": 3,
  "error": ""
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = success, 1 = snapshot not found, 2 = corrupt, 3 = I/O error |
| `session_id` | u32 | Newly assigned by server |
| `pane_count` | number | Number of restored panes |

**Restore sequence**:
1. Client sends RestoreSessionRequest.
2. Server reads snapshot file, validates format.
3. Server creates the session with the saved name and a fresh server-assigned session_id.
4. Server walks the saved layout tree, creating panes (with fresh pane_ids) and spawning shells.
5. Server re-initializes the IME engine for the restored session (see below).
6. If `restore_scrollback=true`, server writes saved scrollback to a temp file and sets `ITSHELL3_RESTORE_SCROLLBACK_FILE` in the shell environment (following cmux's pattern).
7. Server sends RestoreSessionResponse.
8. Server sends LayoutChanged for the restored session.
9. Server sends FrameUpdate (I-frame) for each pane.

**IME engine initialization**: When restoring a session, the server MUST re-initialize the per-session IME engine:

1. Create one `ImeEngine` instance per session with the saved `input_method` string from the session snapshot (e.g., `"korean_2set"`).
2. The engine constructor decomposes the canonical string into engine-internal types (language dispatch + engine-native keyboard ID). No code outside the engine constructor performs this decomposition.
3. Composition state is NOT restored — any mid-composition state was flushed on the previous detach/shutdown. The engine starts with no active composition (composition state is `null`).

The session snapshot persists at session level: `input_method` (canonical string, e.g., `"direct"`, `"korean_2set"`) and `keyboard_layout` (e.g., `"qwerty"`). No per-pane IME fields are stored. See IME Interface Contract, Section 3.7 for the canonical registry of valid `input_method` strings.

### 4.5 SnapshotListRequest (0x0704)

No payload. JSON body is `{}`.

### 4.6 SnapshotListResponse (0x0705)

**Payload** (JSON):

```json
{
  "status": 0,
  "snapshots": [
    {
      "path": "/var/lib/itshell3/snapshots/session-1.json",
      "name": "my-session",
      "timestamp": 1709568000,
      "file_size": 12345,
      "has_scrollback": true
    }
  ]
}
```

### 4.7 SnapshotAutoSaveConfig (0x0706)

**Payload** (JSON):

```json
{
  "interval_ms": 8000,
  "include_scrollback": true,
  "max_scrollback_lines": 4000
}
```

| Field | Type | Description |
|-------|------|-------------|
| `interval_ms` | number | 0 = disable auto-save |
| `include_scrollback` | boolean | Whether to include scrollback in auto-saves |
| `max_scrollback_lines` | number | Maximum scrollback lines per pane |

### 4.8 SnapshotAutoSaveConfigAck (0x0707)

**Payload** (JSON):

```json
{
  "status": 0,
  "effective_interval_ms": 8000
}
```

**Default auto-save**: 8000 ms (8 seconds), matching cmux. Minimum: 1000 ms. Scrollback included by default with a 4000-line limit per pane.

---

## 5. Notifications

Server-initiated notifications for events that clients may want to track. Unlike the notifications in doc 03 (which are always sent), these are opt-in via the subscription system (Section 6).

### Message Types

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0800` | PaneTitleChanged | S -> C | Pane title changed (OSC 0/2) |
| `0x0801` | ProcessExited | S -> C | Foreground process exited |
| `0x0802` | Bell | S -> C | Bell character received (BEL / \a) |
| `0x0803` | RendererHealth | S -> C | Server-side rendering health report |
| `0x0804` | PaneCwdChanged | S -> C | Pane working directory changed |
| `0x0805` | ActivityDetected | S -> C | Output activity in a background pane |
| `0x0806` | SilenceDetected | S -> C | No output for configured duration |

### 5.1 PaneTitleChanged (0x0800)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "title": "vim - main.zig"
}
```

### 5.2 ProcessExited (0x0801)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "exit_code": 0,
  "process_name": "make",
  "pane_remains": true
}
```

| Field | Type | Description |
|-------|------|-------------|
| `exit_code` | number | Exit code (negative = killed by signal, e.g., -9 for SIGKILL) |
| `pane_remains` | boolean | true = pane stays open (remain-on-exit) |

### 5.3 Bell (0x0802)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "timestamp": 1709568000123
}
```

The client handles the bell according to its configuration (audible beep, visual flash, bounce dock icon, system notification, etc.).

### 5.4 RendererHealth (0x0803)

Periodic health report from the server's terminal processing pipeline. Useful for debugging performance issues. Now includes coalescing tier and ring buffer information.

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "frames_processed": 180,
  "frames_dropped": 2,
  "avg_frame_time_us": 450,
  "pty_bytes_read": 102400,
  "ring_usage_bytes": 524288,
  "ring_usage_percent": 25,
  "coalescing_tier": "active"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `coalescing_tier` | string | `"preedit"`, `"interactive"`, `"active"`, `"bulk"`, or `"idle"` |
| `ring_usage_bytes` | number | Current ring buffer usage for this pane |
| `ring_usage_percent` | number | Ring usage as percentage of capacity |

### 5.5 PaneCwdChanged (0x0804)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "cwd": "/home/user/project"
}
```

Triggered by shell integration sequences (OSC 7) or `/proc/<pid>/cwd` polling.

### 5.6 ActivityDetected (0x0805)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "timestamp": 1709568000123
}
```

Sent when output activity is detected in a pane that is not currently visible (non-focused pane). Allows the client to show activity indicators on panes.

### 5.7 SilenceDetected (0x0806)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "silence_duration_ms": 30000
}
```

Sent when a pane has produced no output for a configured duration. Useful for long-running build commands: the user gets notified when the build finishes (silence after activity).

---

## 6. Subscription System

Clients subscribe to specific per-pane or global events. The server only sends notification messages (Section 5) for events the client has subscribed to. This reduces unnecessary network traffic and processing.

### Message Types

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0810` | Subscribe | C -> S | Subscribe to events |
| `0x0811` | SubscribeAck | S -> C | Subscription confirmation |
| `0x0812` | Unsubscribe | C -> S | Unsubscribe from events |
| `0x0813` | UnsubscribeAck | S -> C | Unsubscription confirmation |

### 6.1 Subscribe (0x0810)

**Payload** (JSON):

```json
{
  "pane_id": 0,
  "event_mask": 127,
  "config": {
    "renderer_health_interval_ms": 5000,
    "silence_threshold_ms": 30000,
    "queue_status_interval_ms": 1000
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | 0 = subscribe for all panes |
| `event_mask` | number | Bitmask of events |
| `config` | object | Event-specific configuration (optional) |

**event_mask bits**:

| Bit | Value | Event | Config field |
|-----|-------|-------|-------------|
| 0 | 0x0001 | PaneTitleChanged | -- |
| 1 | 0x0002 | ProcessExited | -- |
| 2 | 0x0004 | Bell | -- |
| 3 | 0x0008 | RendererHealth | `renderer_health_interval_ms` (default 5000) |
| 4 | 0x0010 | PaneCwdChanged | -- |
| 5 | 0x0020 | ActivityDetected | -- |
| 6 | 0x0040 | SilenceDetected | `silence_threshold_ms` (default 30000) |
| 7 | 0x0080 | ClipboardChanged | -- |
| 8 | 0x0100 | OutputQueueStatus | `queue_status_interval_ms` (default 1000) |

### 6.2 SubscribeAck (0x0811)

**Payload** (JSON):

```json
{
  "status": 0,
  "active_mask": 511
}
```

### 6.3 Unsubscribe (0x0812)

**Payload** (JSON):

```json
{
  "pane_id": 0,
  "event_mask": 8
}
```

### 6.4 UnsubscribeAck (0x0813)

**Payload** (JSON):

```json
{
  "status": 0,
  "active_mask": 503
}
```

### Default Subscriptions

After AttachSession, the client automatically receives these notifications without explicit subscription:
- LayoutChanged (doc 03, always sent)
- SessionListChanged (doc 03, always sent)
- PaneMetadataChanged (doc 03, always sent)
- ClientAttached (doc 03, always sent)
- ClientDetached (doc 03, always sent)
- ClientHealthChanged (doc 03, always sent)

All Section 5 notifications require explicit subscription.

---

## 7. Heartbeat and Connection Health

Heartbeat and graceful disconnect messages are defined in the Handshake & Lifecycle range (doc 01, doc 02):

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0003` | Heartbeat | Bidirectional | Keepalive ping (carries `ping_id`) |
| `0x0004` | HeartbeatAck | Bidirectional | Keepalive pong (echoes `ping_id`) |
| `0x0005` | Disconnect | Bidirectional | Graceful disconnect with reason code |

See doc 01 Section 5.4 and doc 02 for message payload definitions.

The `0x0900-0x09FF` range is reserved for future connection health extensions, including `echo_nonce` (application-level heartbeat verification, v2 `HEARTBEAT_NONCE` capability).

### Heartbeat Wire Format

Heartbeat is liveness-only. The `timestamp` and `responder_timestamp` fields from v0.3 have been removed — no protocol-level consumer exists for either. Liveness detection requires only `ping_id`: did the ack arrive within the timeout?

**Heartbeat payload** (JSON):

```json
{
  "ping_id": 42
}
```

**HeartbeatAck payload** (JSON):

```json
{
  "ping_id": 42
}
```

| Field | Type | Description |
|-------|------|-------------|
| `ping_id` | u32 | Monotonic ping counter for correlation |

> **Local RTT diagnostics** (implementation-level, not wire protocol): The sender MAY maintain a local `HashMap(u32, u64)` mapping `ping_id -> send_time` for debugging purposes. `RTT = current_time - sent_times[ack.ping_id]`. This is an implementation choice, not a wire protocol concern. Note that with SSH tunneling, heartbeat RTT only measures the local Unix socket hop to sshd (~0ms), not true end-to-end latency. The client self-reports transport latency via `ClientDisplayInfo.estimated_rtt_ms`.

### Heartbeat Policy

| Parameter | Default | Description |
|-----------|---------|-------------|
| Heartbeat interval | 30 seconds | How often to send Heartbeat if no other messages sent |
| Connection timeout | 90 seconds | If no message of any kind received within this period, connection is considered dead |

Either side can send Heartbeat. The other side responds with HeartbeatAck. If no message (of any kind) is received within 90 seconds, the connection is considered dead and is closed with `Disconnect(TIMEOUT)`. The 90-second timeout corresponds to 3 missed heartbeat intervals.

For Unix domain sockets (local), heartbeat is optional — the OS detects dead sockets via `SO_KEEPALIVE` or write errors (`EPIPE`/`SIGPIPE`) much faster. Over SSH tunnels, heartbeats are complementary to SSH's own `ServerAliveInterval` keepalive and are recommended to detect tunnel failures that the OS may not report immediately.

### Heartbeat Orthogonality with Health States

Heartbeat (0x0003-0x0005) is a **connection liveness** mechanism. 90s timeout -> Disconnect. Health states are an **application responsiveness** mechanism, triggered by ring cursor lag and PausePane duration. These are independent systems:

| Combination | Meaning |
|-------------|---------|
| Heartbeat-healthy + output-stale | `stale` (app frozen, TCP alive) |
| Heartbeat-missed + output-healthy | Connection problem (will resolve or disconnect at 90s) |

**`echo_nonce`** (application-level heartbeat verification) is deferred to v2 in the `0x0900` reserved range. For v1, the combination of `latest` default resize policy + ring cursor stagnation detection + PausePane escalation covers practical scenarios.

The idle-PTY blind spot (no output = no ring cursor movement = no detection of frozen client) is mitigated by `latest` policy: an idle client's dimensions are irrelevant when another client is active. For `smallest` policy edge cases, `echo_nonce` can be added in v2 as a `HEARTBEAT_NONCE` capability.

**Server-side heartbeat RTT** measurement (time between sending Heartbeat and receiving HeartbeatAck) MAY be used as an implementation-level heuristic (e.g., RTT >60s for 2 consecutive heartbeats suggests event loop stall). This is non-normative implementation guidance, not a protocol state trigger.

---

## 8. Extension Negotiation

### Background

libitshell3 is designed for long-term evolution. The extension system allows clients and servers to negotiate optional features beyond the base protocol. This avoids the fragile version-guessing pattern that plagues tmux.

### Message Types

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0A00` | ExtensionList | C -> S or S -> C | Declare available extensions |
| `0x0A01` | ExtensionListAck | S -> C or C -> S | Acknowledge and accept/reject extensions |
| `0x0A02` | ExtensionMessage | Either | Message within a negotiated extension |

### 8.1 ExtensionList (0x0A00)

Sent during the handshake phase (after capability negotiation, before session attach). Both client and server declare the extensions they support.

**Payload** (JSON):

```json
{
  "extensions": [
    {
      "ext_id": 1,
      "version": "1.0",
      "name": "cjk-preedit",
      "config": {}
    }
  ]
}
```

### 8.2 ExtensionListAck (0x0A01)

**Payload** (JSON):

```json
{
  "results": [
    {
      "ext_id": 1,
      "status": 0,
      "accepted_version": "1.0"
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = accepted, 1 = rejected, 2 = version mismatch |

### 8.3 ExtensionMessage (0x0A02)

Generic wrapper for extension-specific messages. The extension defines its own payload format.

**Payload** (JSON):

```json
{
  "ext_id": 1,
  "ext_msg_type": 3,
  "payload": {}
}
```

### Extension ID Ranges

| Range | Purpose |
|-------|---------|
| `0x0001` - `0x00FF` | Core extensions (defined by libitshell3 spec) |
| `0x0100` - `0x0FFF` | Reserved for future official extensions |
| `0x1000` - `0x7FFF` | Registered vendor extensions (IANA-style registry, future) |
| `0x8000` - `0xFFFE` | Private/experimental extensions |
| `0xFFFF` | Reserved |

### Known Core Extensions

| ID | Name | Description |
|----|------|-------------|
| `0x0001` | `cjk-preedit` | CJK IME preedit sync (doc 05) |
| `0x0002` | `agent-mode` | AI agent detection and input mode switching |
| `0x0003` | `sixel` | Sixel graphics passthrough |
| `0x0004` | `kitty-images` | Kitty image protocol support |
| `0x0005` | `hyperlinks` | OSC 8 hyperlink support |
| `0x0006` | `shell-integration` | Shell integration (OSC 133, semantic zones) |

---

## 9. Reserved Message Type Ranges for Future Use

| Range | Purpose | Notes |
|-------|---------|-------|
| `0x0B00` - `0x0BFF` | File transfer | Drag-and-drop, SCP-like file transfer |
| `0x0C00` - `0x0CFF` | Plugin system | If we add a plugin architecture |
| `0x0D00` - `0x0DFF` | Audio | Audio passthrough, terminal bells |
| `0x0E00` - `0x0EFF` | Accessibility | Screen reader support, announcements |
| `0x0F00` - `0x0FFF` | Diagnostics | Debug tracing, profiling, metrics |
| `0xF000` - `0xFFFE` | Vendor/custom extensions | Via extension negotiation |
| `0xFFFF` | Invalid | Reserved sentinel, never used |

---

## 10. Error Handling

### Protocol Errors

If a client or server receives a message with:
- Unknown message type within a non-extension range: **ignore** the message (forward compatibility).
- Unknown message type within the extension range (0xF000+): ignore if no matching extension is negotiated.
- Payload shorter than expected: respond with `status = PROTOCOL_ERROR` in the next appropriate response, or send Disconnect (0x0005) with reason `"error"` and detail describing the protocol violation.
- Payload longer than expected: consume the full payload (based on header length), ignore extra fields (forward compatibility with JSON payloads).

### Timeout Handling

| Scenario | Timeout | Action |
|----------|---------|--------|
| Request without response | 30 seconds | Client may resend or Disconnect (0x0005) |
| PausePane without ContinuePane | 5s / 60s / 300s escalation | T=5s resize exclusion, T=60s/120s stale, T=300s eviction (see Section 2.8) |
| No message received (any kind) | 90 seconds | Send `Disconnect(TIMEOUT)`, close connection |
| Snapshot write | 60 seconds | Respond with I/O error |

---

## 11. Open Questions

1. **Clipboard size limit**: Should there be a maximum clipboard data size? Large clipboard contents (e.g., megabytes of text) could cause issues. Suggestion: 10 MB limit with chunked transfer for larger content.

2. **Snapshot format versioning**: How do we handle snapshot format evolution? Suggestion: include a format version number in the JSON snapshot. Newer servers can read older formats but not vice versa.

3. **Extension negotiation timing**: Should extensions be negotiated before or after authentication? Before auth risks information leakage (advertising capabilities to unauthenticated clients). After auth adds latency. Suggestion: after auth for SSH tunnel transport, during handshake for Unix sockets.

4. **Multi-session snapshots**: Should one snapshot file contain multiple sessions, or one file per session? cmux uses one file for the entire app state. Per-session files are simpler for partial restore. Suggestion: per-session files with a manifest.

5. **Clipboard sync mode**: Should clipboard sync be automatic (like iTerm2's auto mode), manual (user triggers), or configurable? Suggestion: configurable via capabilities, default to "ask" for security.

6. **RendererHealth interval**: How frequently should RendererHealth reports be sent? Too frequent = noise, too infrequent = useless for debugging. The subscription system allows per-client configuration, but what should the minimum be? Suggestion: 1000 ms minimum.

7. **Extension message ordering**: Should extension messages be ordered with respect to core messages, or can they be interleaved? For simplicity, all messages on a connection are strictly ordered. Extensions cannot bypass this.

8. **Silence detection scope**: Should SilenceDetected fire only for panes with recent activity (activity-then-silence pattern), or for any pane that has been silent? The activity-then-silence pattern is more useful (build completion notification). Suggestion: only fire after at least one byte of output has been seen since the last silence notification.

9. **~~Tier transition telemetry~~** **Closed (v0.7)**: RendererHealth's `coalescing_tier` field is sufficient. No dedicated notification needed. Owner confirmed.

---

## Changelog

### v0.7 (2026-03-05)

- **Shared per-pane ring buffer** (Issue 22, Resolutions 11-16): Replaced per-client output buffers with shared per-pane ring buffer (Section 2.1). Server serializes each frame once into the ring. Per-client read cursors track delivery position. Default 2 MB per pane. Ring invariant: at least one I-frame always present. Memory: O(panes * ring_size) + O(clients) for cursors, vs O(panes * clients * buffer_size) previously.
- **Preedit bypass buffer** (Resolution 17): Preedit-only frames (`frame_type=0` with preedit state change) delivered via per-client latest-wins priority buffer outside the ring. Socket write priority: preedit bypass > direct message queue > ring data. Satisfies <33ms preedit latency target regardless of ring cursor position.
- **Ring contents and frame_sequence scope** (Resolutions 18-20): Ring contains I-frames, P-frames, and non-preedit metadata frames. `frame_sequence` incremented only for ring frames. Dedicated preedit messages (0x0400-0x0405) remain outside the ring, delivered via direct message queue.
- **PausePane role shift** (Resolution 15): PausePane is now an advisory signal for the health escalation state machine. Ring writes unconditionally for all clients. PausePane trigger: client cursor lag >90% of ring capacity.
- **Recovery codepath unification** (Resolution 14): Three recovery procedures (ContinuePane, ring overwrite, stale recovery) unified into "advance cursor to latest I-frame." No special discard-and-resync codepath.
- **FlowControlConfig field changes** (Issue 12, Resolution 21): Retired `max_queue_bytes` and `max_queue_frames` (replaced by ring buffer model). Added `resize_exclusion_timeout_ms` (5000), `stale_timeout_ms` (60000/120000), `eviction_timeout_ms` (300000).
- **PausePane health escalation timeline** (Issue 14, Resolutions 7-12): Added Section 2.8 with T=0s/5s/60s/300s escalation: PausePane -> resize exclusion -> stale -> eviction. Two protocol-visible health states: `healthy` and `stale`. Transport-aware stale timeout (60s local, 120s SSH).
- **Stale triggers** (Issue 14, Resolutions 9-10): Stale timeout resets on application-level messages only (HeartbeatAck does NOT reset). Ring cursor stagnation as additional stale trigger.
- **Heartbeat orthogonality** (Issue 17, Resolution 11): Added Section 7 note clarifying heartbeat (connection liveness) is orthogonal to health states (application responsiveness). Reserved 0x0900 for v2 echo_nonce (HEARTBEAT_NONCE capability).
- **Idle coalescing suppression during resize** (Issue 18, Addendum C): Added Section 1.7 — 250ms debounce window + 500ms grace after TIOCSWINSZ before allowing Idle tier transition.
- **Preedit commit on eviction** (Issue 19, Addendum B): When server evicts stale client at T=300s, active preedit MUST be committed. PreeditEnd with `reason: "client_evicted"` sent to peer clients.
- **ClientHealthChanged in default subscriptions** (Issue 20): Added ClientHealthChanged (0x0185) to always-sent notifications list in Section 6 default subscriptions.
- **PausePane timeout updated** (Issue 16): Updated Section 10 timeout table from "no timeout, waits indefinitely" to 5s/60s/300s escalation timeline.
- **Per-pane dirty bitmap** (Resolution 10): Replaced per-(client, pane) dirty bitmap normative note in Section 1.4 with per-pane dirty bitmap. Single serialization per pane per interval.
- **Per-session IME in persistence** (IME cross-team): Updated RestoreSessionResponse (Section 4.4) for per-session engine model — one ImeEngine per session, session-level `input_method` and `keyboard_layout` in snapshots, no per-pane IME fields.
- **OutputQueueStatus updated** (Section 2.12): Updated payload to report ring cursor lag instead of per-client buffer metrics.
- **RendererHealth extended** (Section 5.4): Added `ring_usage_bytes` and `ring_usage_percent` fields.
- **PausePane payload updated** (Section 2.4): Replaced `queued_bytes`/`queued_frames`/`queue_age_ms` with `ring_lag_percent`/`ring_lag_bytes`.

### v0.6 (2026-03-05)

- **ConnectionClosing renamed to Disconnect** (Issue 7): Replaced remaining `ConnectionClosing` references with `Disconnect (0x0005)` in Section 8 (Protocol Errors and Timeout Handling).
- **num_dirty_rows terminology** (Issue 8): Standardized `dirty_row_count` to `num_dirty_rows` throughout, matching the authoritative binary wire format in doc 04.
- **4-tier coalescing terminology clarified** (Issue 20): Added terminology note in Section 1 explaining the model has 4 active coalescing tiers (Preedit, Interactive, Active, Bulk) plus an Idle quiescent state. Updated v0.3 changelog entry to match.
- **ClipboardReadResponse direction fix** (Round 4): Fixed Section 3.3 prose from "Client responds" to "Server responds" — ClipboardReadResponse (0x0602) is S->C.
- **Disconnect reason aligned with doc 02 enum** (Round 4): Changed `reason "protocol_error"` in Section 10 to `reason "error"` with descriptive detail, matching doc 02 Section 11.1 Disconnect reason enum.

### v0.5 (2026-03-05)

- **RestoreSession IME initialization** (cross-review): Added IME engine initialization sequence to RestoreSessionResponse (Section 4.4). Server MUST re-initialize per-pane ImeEngine with the saved `input_method` canonical string on session restore. Composition state is not restored (flushed on previous detach/shutdown). Session snapshot must persist `input_method` per pane.
- **Input method identifier unification** (identifier consensus): All references to `LanguageId` enum and `layout_id` in session restore replaced with single canonical `input_method` string. Mapping table removed from doc 05 — canonical registry now lives in IME Interface Contract, Section 3.7.

### v0.4 (2026-03-04)

- **Heartbeat simplified to liveness-only** (Issue 2): Removed `timestamp` and `responder_timestamp` from Heartbeat/HeartbeatAck. Payload is `ping_id` only. Server-measured RTT rejected — with SSH tunneling, heartbeat RTT only measures local socket hop to sshd (~0ms). Client self-reports transport latency via `ClientDisplayInfo.estimated_rtt_ms`.
- **Transport fields in ClientDisplayInfo** (Issue 4): Added `transport_type` (`"local"`, `"ssh_tunnel"`, `"unknown"`), `estimated_rtt_ms` (client-reported), and `bandwidth_hint` (`"local"`, `"lan"`, `"wan"`, `"cellular"`) to ClientDisplayInfo (0x0505). Server uses these to adapt coalescing tiers for remote clients.
- **WAN coalescing tier adjustments** (Issue 4): New Section 1.6 defining reduced frame rates for SSH tunnel clients: Active 33ms (30fps), Bulk 66ms (15fps). Preedit and Interactive remain immediate regardless of transport.
- **Preedit latency scoping** (Issue 4): Added normative statement that server adds no coalescing delay for preedit over any transport. End-to-end latency over SSH is dominated by network RTT.
- **Compression removed from flow control** (Issue 5): Removed all references to COMPRESSED flag interaction with flow control. Application-layer compression deferred to v2. SSH compression covers WAN scenarios.
- **OutputQueueStatus explicitly per-client** (Issue 9/Gap 11): Added normative statement that OutputQueueStatus (0x0504) reports per-client queue state for the receiving client's connection, not aggregate server state.
- **Preedit-only FrameUpdate for paused clients** (Issue 9/Gap 12): Defined preedit bypass FrameUpdate format: `num_dirty_rows=0` + JSON preedit metadata (~100-110 bytes). Documented commit-while-paused edge case.
- **Per-client dirty tracking semantics** (Issue 9): Added normative statement for dirty bitmap clearing — cleared only when FrameUpdate containing that row has been sent to the specific client.
- **Heartbeat policy for SSH tunnels** (Issue 4): Updated heartbeat guidance — heartbeat recommended for SSH tunnel transport to detect tunnel failures.
- **Default subscriptions updated** (Issue 9/Gap 4): Added ClientAttached and ClientDetached to default subscriptions.
- **Optional field convention** (Issue 3): Applied JSON optional field convention — absent fields are omitted, never null.

### v0.3 (2026-03-04)

**Major revision** to flow control and frame delivery model based on review-notes-02 consensus.

- **4-tier adaptive coalescing** (Section 1): Replaced the fixed cadence model with a 4-tier + Idle state (Preedit, Interactive, Active, Bulk + Idle) adaptive system informed by iTerm2's adaptive cadence and ghostty's event-driven rendering. Frame intervals range from immediate (0 ms) for preedit/interactive to 33 ms for bulk throughput. Idle is a quiescent state, not an active coalescing tier.
- **Transition thresholds with hysteresis** (Section 1.2): Defined explicit transition triggers with hysteresis to prevent oscillation (e.g., Active->Bulk at >100 KB/s for 500 ms, Bulk->Active at <50 KB/s for 1 s).
- **"Immediate first, batch rest"** (Section 1.3): First frame after idle always sends immediately, then coalescing applies.
- **Per-(client, pane) cadence** (Section 1.4): Server maintains independent coalescing timers and dirty bitmaps per client. Each client receives FrameUpdates at its own rate.
- **ClientDisplayInfo message** (Section 1.5): New message (0x0505/0x0506) for clients to report display refresh rate, power state, and preferred max fps.
- **Client power hints** (Section 1.5): Server reduces fps when client reports battery state. Active capped at 20 fps on battery, 10 fps on low battery. Preedit always immediate regardless of power.
- **Preedit exempt from PausePane** (Section 2.1): Preedit-only frames (~90 bytes) MUST be delivered even when a pane is paused.
- **Smooth degradation before PausePane** (Section 2): Queue filling triggers auto-downgrade (Active->Bulk) before PausePane. PausePane is a last resort.
- **Adaptive queue limits** (Section 2): Max queued frames now vary by coalescing tier instead of the fixed "~2 seconds at 60 fps" from v0.2.
- **RendererHealth extended** (Section 5.4): Added `coalescing_tier` field to health reports.
- **JSON payloads**: All control messages now use JSON encoding, consistent with doc 03 v0.3 and the hybrid encoding decision from review-notes-02.
- **Heartbeat deduplication** (Section 7): Removed duplicate Ping/Pong/ConnectionClosing (0x0900-0x0902) definitions. Heartbeat and disconnect are now defined canonically in doc 01 as Heartbeat (0x0003) / HeartbeatAck (0x0004) / Disconnect (0x0005). Section 7 retains heartbeat policy guidance and references doc 01/02.
- **Vendor range alignment**: Aligned vendor extension range to `0xF000-0xFFFE` (matching doc 01) with `0xFFFF` reserved sentinel.

### v0.2 (2026-03-04)

- Initial draft with binary field-level encoding and fixed-cadence frame delivery model.
