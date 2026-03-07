# 06 - Flow Control and Auxiliary Protocols

**Version**: v0.4
**Status**: Draft
**Date**: 2026-03-04
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

libitshell3 does not use a fixed frame rate. Instead, the server employs a **4-tier adaptive coalescing model** informed by iTerm2's adaptive cadence and ghostty's event-driven rendering. The coalescing tier is determined per-(client, pane) pair based on PTY throughput, keystroke recency, and preedit state.

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
| Idle → Interactive | KeyEvent received + PTY output within 5 ms | None |
| Idle → Active | PTY output arrives without recent keystroke | None |
| Active → Bulk | >100 KB/s sustained for 500 ms | Drop back to Active at <50 KB/s for 1 s |
| Active → Idle | No PTY output for 500 ms | None |
| Any → Preedit | Preedit state changed (composition started/updated) | 200 ms timeout back to previous tier after composition ends |

The Active→Bulk hysteresis prevents rapid tier flapping during bursty output (e.g., compiler output interspersed with linking pauses).

### 1.3 "Immediate First, Batch Rest"

When a pane transitions from Idle to any active tier, the **first frame is sent immediately** without coalescing delay. Subsequent frames follow the tier's coalescing interval. This ensures that the first character of output after a prompt never has artificial latency, matching ghostty's observed behavior (removed 10 ms coalescing timer because immediate first frame was strictly better).

### 1.4 Per-(Client, Pane) Cadence

The server maintains coalescing state independently for each (client, pane) pair:

- **Per-client coalescing timers**: Each client receives FrameUpdates at its own rate. A fast desktop client on AC power gets Active-tier frames at 16 ms while a battery-constrained iPad client simultaneously receives the same pane's updates at 50 ms.
- **Per-client dirty bitmaps**: The server tracks which rows are dirty for each client independently. When a client's coalescing timer fires, the FrameUpdate contains exactly the rows that changed since that client's last frame. **Normative**: The server maintains independent dirty bitmaps per (client, pane) pair. A row's dirty flag for a specific client is cleared only when a FrameUpdate containing that row's data has been sent to that client.
- **Independent tier state**: Pane 1 can be at Preedit tier (user composing CJK) while pane 2 is at Bulk tier (running `make -j16`), and both are tracked independently for each attached client.

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

> **Preedit is always immediate regardless of power state.** A preedit-only frame is ~90 bytes, which is negligible for both bandwidth and power. Throttling preedit would make CJK input unusable.

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

---

## 2. Flow Control and Backpressure

### Background

When a pane produces output faster than the client can consume it (e.g., `cat /dev/urandom`), the server must buffer output. Without flow control, the buffer grows unboundedly, consuming memory and introducing latency. libitshell3 implements per-pane, per-client flow control modeled on tmux 3.2+ `%pause`/`%continue` semantics and iTerm2's `iTermTmuxBufferSizeMonitor`.

### Message Types

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0500` | PausePane | S -> C | Server pauses output for a pane |
| `0x0501` | ContinuePane | C -> S | Client signals readiness to resume |
| `0x0502` | FlowControlConfig | C -> S | Client configures flow control parameters |
| `0x0503` | FlowControlConfigAck | S -> C | Server acknowledges configuration |
| `0x0504` | OutputQueueStatus | S -> C | Server reports queue pressure |

### 2.1 PausePane (0x0500)

Sent by the server when the output queue for a specific pane exceeds the configured threshold for this client. After sending PausePane, the server stops sending FrameUpdate messages for this pane to this client. PTY output continues to be read and processed by the server's terminal emulator; only client delivery is paused.

> **Preedit exception**: Preedit-only frames MUST be delivered even when a pane is paused. A PausePane affects FrameUpdate delivery of terminal content, but preedit state changes are exempt. Without this exception, CJK composition would freeze during backpressure, making input unusable.
>
> **Preedit-only FrameUpdate format for paused clients**: When a pane is paused for a client but preedit state changes, the server sends a FrameUpdate with `dirty_row_count=0` (no grid data) plus JSON preedit metadata only. This is approximately 100-110 bytes. The client uses this to update the preedit overlay without receiving or processing the full terminal grid state.
>
> **Edge case — preedit commit while paused**: If a preedit composition is committed (PreeditEnd) while the pane is paused, the client sees PreeditEnd and can remove the preedit overlay, but the committed text in the terminal grid is not visible until ContinuePane. This is acceptable because: (1) the commit is a single-character insertion, not a visual layout change; (2) the client will receive a full FrameUpdate on ContinuePane reflecting the committed state.

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "queued_bytes": 524288,
  "queued_frames": 90,
  "queue_age_ms": 3000
}
```

### 2.2 ContinuePane (0x0501)

Sent by the client when it has finished processing queued frames and is ready to receive more output for the paused pane. The server resumes sending FrameUpdate messages.

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "last_processed_seq": 42
}
```

The server uses `last_processed_seq` to determine which frames the client has already consumed. It discards frames older than this sequence and sends a fresh full FrameUpdate reflecting the current terminal state, followed by incremental updates going forward.

### 2.3 FlowControlConfig (0x0502)

Client configures per-connection flow control parameters. Sent once during the handshake phase, and may be sent again at any time to adjust.

**Payload** (JSON):

```json
{
  "max_queue_bytes": 1048576,
  "max_queue_frames": 120,
  "max_queue_age_ms": 5000,
  "auto_continue": true
}
```

| Field | Type | Description |
|-------|------|-------------|
| `max_queue_bytes` | number | Maximum output queue size in bytes (0 = server default) |
| `max_queue_frames` | number | Maximum queued frames (0 = server default) |
| `max_queue_age_ms` | number | Maximum queue age in milliseconds (0 = server default) |
| `auto_continue` | boolean | true = server auto-continues after queue drains |

### 2.4 FlowControlConfigAck (0x0503)

**Payload** (JSON):

```json
{
  "status": 0,
  "effective_max_bytes": 1048576,
  "effective_max_frames": 120,
  "effective_max_age_ms": 5000
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = accepted, 1 = adjusted (server clamped values) |

### 2.5 OutputQueueStatus (0x0504)

Periodic notification (configurable interval) reporting queue pressure for the client's subscribed panes. Allows the client to proactively adjust rendering behavior.

> **Normative**: OutputQueueStatus reports **per-client** queue state for the receiving client's connection, not aggregate server state. Each client sees only its own output queue metrics. In a multi-client scenario, Client A's OutputQueueStatus reflects Client A's queue depth, which may differ from Client B's queue depth for the same pane (due to different consumption rates, coalescing tiers, or flow control states).

**Payload** (JSON):

```json
{
  "panes": [
    {
      "pane_id": 1,
      "queued_bytes": 102400,
      "queued_frames": 15,
      "paused": false
    }
  ]
}
```

### Server Output Queue Management

The server maintains a per-pane, per-client output queue with these eviction policies:

| Policy | Default | Description |
|--------|---------|-------------|
| Max size per pane per client | 1 MB | Oldest frames evicted when exceeded |
| Max frames per pane per client | Tier-dependent (see below) | Oldest evicted |
| Max age | 5000 ms | Frames older than 5 s are discarded |
| Eviction strategy | Drop oldest, send full refresh | When frames are dropped, the next delivered frame is a full FrameUpdate (dirty=full) |

**Adaptive max-frames by tier**:

| Tier | Max queued frames | Rationale |
|------|-------------------|-----------|
| Preedit | 4 | Preedit frames are tiny; only need latest state |
| Interactive | 8 | Interactive output is sparse |
| Active | ~2 s worth at tier fps (e.g., 120 at 60 fps) | Matches v0.2 default |
| Bulk | ~2 s worth at tier fps (e.g., 60 at 30 fps) | Reduced since frames are larger |

### Smooth Degradation Before PausePane

Before resorting to PausePane, the server applies smooth degradation:

```
1. Queue filling above 50% capacity:
   → Auto-downgrade tier (Active → Bulk).
   → Increase coalescing interval within the tier.

2. Queue filling above 75% capacity:
   → Force Bulk tier regardless of throughput.
   → Compact queue: merge pending partial frames into a single full frame.

3. Queue filling above 90% capacity:
   → Send PausePane to the client.
   → Continue reading PTY output and updating terminal state server-side.
   → Continue delivering preedit-only FrameUpdates (dirty_row_count=0 + preedit metadata).

4. Client sends ContinuePane (or auto_continue triggers):
   → Send one full FrameUpdate reflecting current state.
   → Resume incremental updates.
   → Restore original tier based on current throughput.
```

This graduated approach keeps the client receiving updates for as long as possible. PausePane is a last resort, not a routine flow control mechanism.

**Key insight**: Unlike tmux (which buffers raw bytes), libitshell3 buffers structured frames. This means the server can always compact the queue to a single full frame, bounding memory usage.

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

Client responds with the current OS clipboard contents.

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
5. If `restore_scrollback=true`, server writes saved scrollback to a temp file and sets `ITSHELL3_RESTORE_SCROLLBACK_FILE` in the shell environment (following cmux's pattern).
6. Server sends RestoreSessionResponse.
7. Server sends LayoutChanged for the restored session.
8. Server sends FrameUpdate for each pane.

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

Periodic health report from the server's terminal processing pipeline. Useful for debugging performance issues. Now includes coalescing tier information.

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "frames_processed": 180,
  "frames_dropped": 2,
  "avg_frame_time_us": 450,
  "pty_bytes_read": 102400,
  "queue_depth": 8192,
  "coalescing_tier": "active"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `coalescing_tier` | string | `"preedit"`, `"interactive"`, `"active"`, `"bulk"`, or `"idle"` |

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

The `0x0900-0x09FF` range is reserved for future connection health extensions.

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

> **Local RTT diagnostics** (implementation-level, not wire protocol): The sender MAY maintain a local `HashMap(u32, u64)` mapping `ping_id → send_time` for debugging purposes. `RTT = current_time - sent_times[ack.ping_id]`. This is an implementation choice, not a wire protocol concern. Note that with SSH tunneling, heartbeat RTT only measures the local Unix socket hop to sshd (~0ms), not true end-to-end latency. The client self-reports transport latency via `ClientDisplayInfo.estimated_rtt_ms`.

### Heartbeat Policy

| Parameter | Default | Description |
|-----------|---------|-------------|
| Heartbeat interval | 30 seconds | How often to send Heartbeat if no other messages sent |
| Connection timeout | 90 seconds | If no message of any kind received within this period, connection is considered dead |

Either side can send Heartbeat. The other side responds with HeartbeatAck. If no message (of any kind) is received within 90 seconds, the connection is considered dead and is closed with `Disconnect(TIMEOUT)`. The 90-second timeout corresponds to 3 missed heartbeat intervals.

For Unix domain sockets (local), heartbeat is optional — the OS detects dead sockets via `SO_KEEPALIVE` or write errors (`EPIPE`/`SIGPIPE`) much faster. Over SSH tunnels, heartbeats are complementary to SSH's own `ServerAliveInterval` keepalive and are recommended to detect tunnel failures that the OS may not report immediately.

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
- Payload shorter than expected: respond with `status = PROTOCOL_ERROR` in the next appropriate response, or send ConnectionClosing with reason `"protocol_error"`.
- Payload longer than expected: consume the full payload (based on header length), ignore extra fields (forward compatibility with JSON payloads).

### Timeout Handling

| Scenario | Timeout | Action |
|----------|---------|--------|
| Request without response | 30 seconds | Client may resend or ConnectionClosing |
| PausePane without ContinuePane | No timeout | Server compacts queue, waits indefinitely |
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

9. **Tier transition telemetry**: Should the server notify clients when a pane's coalescing tier changes? Currently exposed via RendererHealth's `coalescing_tier` field. A dedicated notification might be useful for debugging but adds protocol surface. Suggestion: defer; RendererHealth is sufficient for v1.

---

## Changelog

### v0.4 (2026-03-04)

- **Heartbeat simplified to liveness-only** (Issue 2): Removed `timestamp` and `responder_timestamp` from Heartbeat/HeartbeatAck. Payload is `ping_id` only. Server-measured RTT rejected — with SSH tunneling, heartbeat RTT only measures local socket hop to sshd (~0ms). Client self-reports transport latency via `ClientDisplayInfo.estimated_rtt_ms`.
- **Transport fields in ClientDisplayInfo** (Issue 4): Added `transport_type` (`"local"`, `"ssh_tunnel"`, `"unknown"`), `estimated_rtt_ms` (client-reported), and `bandwidth_hint` (`"local"`, `"lan"`, `"wan"`, `"cellular"`) to ClientDisplayInfo (0x0505). Server uses these to adapt coalescing tiers for remote clients.
- **WAN coalescing tier adjustments** (Issue 4): New Section 1.6 defining reduced frame rates for SSH tunnel clients: Active 33ms (30fps), Bulk 66ms (15fps). Preedit and Interactive remain immediate regardless of transport.
- **Preedit latency scoping** (Issue 4): Added normative statement that server adds no coalescing delay for preedit over any transport. End-to-end latency over SSH is dominated by network RTT.
- **Compression removed from flow control** (Issue 5): Removed all references to COMPRESSED flag interaction with flow control. Application-layer compression deferred to v2. SSH compression covers WAN scenarios.
- **OutputQueueStatus explicitly per-client** (Issue 9/Gap 11): Added normative statement that OutputQueueStatus (0x0504) reports per-client queue state for the receiving client's connection, not aggregate server state.
- **Preedit-only FrameUpdate for paused clients** (Issue 9/Gap 12): Defined preedit bypass FrameUpdate format: `dirty_row_count=0` + JSON preedit metadata (~100-110 bytes). Documented commit-while-paused edge case.
- **Per-client dirty tracking semantics** (Issue 9): Added normative statement for dirty bitmap clearing — cleared only when FrameUpdate containing that row has been sent to the specific client.
- **Heartbeat policy for SSH tunnels** (Issue 4): Updated heartbeat guidance — heartbeat recommended for SSH tunnel transport to detect tunnel failures.
- **Default subscriptions updated** (Issue 9/Gap 4): Added ClientAttached and ClientDetached to default subscriptions.
- **Optional field convention** (Issue 3): Applied JSON optional field convention — absent fields are omitted, never null.

### v0.3 (2026-03-04)

**Major revision** to flow control and frame delivery model based on review-notes-02 consensus.

- **4-tier adaptive coalescing** (Section 1): Replaced the fixed cadence model with a 5-state (Preedit, Interactive, Active, Bulk, Idle) adaptive system informed by iTerm2's adaptive cadence and ghostty's event-driven rendering. Frame intervals range from immediate (0 ms) for preedit/interactive to 33 ms for bulk throughput.
- **Transition thresholds with hysteresis** (Section 1.2): Defined explicit transition triggers with hysteresis to prevent oscillation (e.g., Active→Bulk at >100 KB/s for 500 ms, Bulk→Active at <50 KB/s for 1 s).
- **"Immediate first, batch rest"** (Section 1.3): First frame after idle always sends immediately, then coalescing applies.
- **Per-(client, pane) cadence** (Section 1.4): Server maintains independent coalescing timers and dirty bitmaps per client. Each client receives FrameUpdates at its own rate.
- **ClientDisplayInfo message** (Section 1.5): New message (0x0505/0x0506) for clients to report display refresh rate, power state, and preferred max fps.
- **Client power hints** (Section 1.5): Server reduces fps when client reports battery state. Active capped at 20 fps on battery, 10 fps on low battery. Preedit always immediate regardless of power.
- **Preedit exempt from PausePane** (Section 2.1): Preedit-only frames (~90 bytes) MUST be delivered even when a pane is paused.
- **Smooth degradation before PausePane** (Section 2): Queue filling triggers auto-downgrade (Active→Bulk) before PausePane. PausePane is a last resort.
- **Adaptive queue limits** (Section 2): Max queued frames now vary by coalescing tier instead of the fixed "~2 seconds at 60 fps" from v0.2.
- **RendererHealth extended** (Section 5.4): Added `coalescing_tier` field to health reports.
- **JSON payloads**: All control messages now use JSON encoding, consistent with doc 03 v0.3 and the hybrid encoding decision from review-notes-02.
- **Heartbeat deduplication** (Section 7): Removed duplicate Ping/Pong/ConnectionClosing (0x0900-0x0902) definitions. Heartbeat and disconnect are now defined canonically in doc 01 as Heartbeat (0x0003) / HeartbeatAck (0x0004) / Disconnect (0x0005). Section 7 retains heartbeat policy guidance and references doc 01/02.
- **Vendor range alignment**: Aligned vendor extension range to `0xF000-0xFFFE` (matching doc 01) with `0xFFFF` reserved sentinel.

### v0.2 (2026-03-04)

- Initial draft with binary field-level encoding and fixed-cadence frame delivery model.
