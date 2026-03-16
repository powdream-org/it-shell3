# Flow Control and Auxiliary Protocols

- **Date**: 2026-03-14

## Overview

This document specifies flow control (backpressure), adaptive frame coalescing,
clipboard, persistence, notification, subscription, heartbeat, and extension
negotiation protocols for libitshell3. These are auxiliary protocols that
complement the core session/pane management (doc 03), input forwarding and
render state streaming (both in doc 04).

All messages use the binary framing defined in document 01 (16-byte header:
magic(2) + version(1) + flags(1) + msg_type(2) + reserved(2) + payload_len(4) +
sequence(4), little-endian byte order).

### Conventions

Same as doc 03:

- Little-endian byte order for all multi-byte integers in the binary header.
- Control messages (this document) use JSON payloads unless otherwise noted.
- **Optional fields**: When a JSON field has no value, the field MUST be omitted
  from the JSON object. Senders MUST NOT include fields with `null` values.
  Receivers MUST tolerate both missing keys and `null` values as "absent"
  (defensive parsing for forward/backward compatibility).
- IDs are u32, server-assigned, monotonically increasing (see doc 03 ID Types).
- Boolean fields use JSON `true`/`false`.
- `payload_len` in the header is the payload size only (NOT including the
  16-byte header).

---

## Message Type Range Assignments

| Range               | Category                                         | Document                        |
| ------------------- | ------------------------------------------------ | ------------------------------- |
| `0x0001` - `0x00FF` | Handshake, capability negotiation                | Doc 02                          |
| `0x0100` - `0x01FF` | Session and pane management                      | Doc 03                          |
| `0x0200` - `0x02FF` | Input forwarding                                 | Doc 04                          |
| `0x0300` - `0x03FF` | Render state / frame updates                     | Doc 04                          |
| `0x0400` - `0x04FF` | CJK preedit / IME protocol                       | Doc 05                          |
| `0x0500` - `0x05FF` | Flow control and backpressure                    | **This doc**                    |
| `0x0600` - `0x06FF` | Clipboard                                        | **This doc**                    |
| `0x0700` - `0x07FF` | Persistence (snapshot/restore)                   | **This doc**                    |
| `0x0800` - `0x08FF` | Notifications and subscriptions                  | **This doc**                    |
| `0x0900` - `0x09FF` | Reserved for future connection health extensions | Doc 01 / Doc 02 (see Section 7) |
| `0x0A00` - `0x0AFF` | Extension negotiation                            | **This doc**                    |
| `0x0B00` - `0x0FFF` | Reserved for future use                          | --                              |
| `0xF000` - `0xFFFE` | Vendor/custom extensions                         | **This doc**                    |
| `0xFFFF`            | Reserved (never used)                            | --                              |

---

## 1. FrameUpdate Delivery and Client Display Info

### 1.1 Background

The server uses adaptive coalescing for FrameUpdate delivery. Coalescing tier
definitions and policies are defined in daemon design docs. See
[doc 01 Section 10](01-protocol-overview.md#10-frameupdate-delivery-model) for
the wire-observable delivery model.

### 1.2 Client Power Hints and Display Info

Clients communicate their display capabilities, power state, and transport
information via the `ClientDisplayInfo` message, allowing the server to optimize
frame delivery.

#### ClientDisplayInfo (0x0505)

Sent by the client during handshake (after capability negotiation) and whenever
display, power, or transport state changes. This is a runtime message, not
handshake-only — the client may send it at any time.

| Type Code | Name                 | Direction | Description                                        |
| --------- | -------------------- | --------- | -------------------------------------------------- |
| `0x0505`  | ClientDisplayInfo    | C -> S    | Client reports display, power, and transport state |
| `0x0506`  | ClientDisplayInfoAck | S -> C    | Server acknowledges display info                   |

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

| Field                | Type   | Values                                    | Description                                                   |
| -------------------- | ------ | ----------------------------------------- | ------------------------------------------------------------- |
| `display_refresh_hz` | number | 60, 120, etc.                             | Display refresh rate                                          |
| `power_state`        | string | `"ac"`, `"battery"`, `"low_battery"`      | Client power state                                            |
| `preferred_max_fps`  | number | 0 = no preference                         | Client's preferred fps cap (0 = use server default)           |
| `transport_type`     | string | `"local"`, `"ssh_tunnel"`, `"unknown"`    | How the client connects to the daemon                         |
| `estimated_rtt_ms`   | u16    | 0 = unknown/local                         | Client's measured or estimated round-trip time to the daemon. |
| `bandwidth_hint`     | string | `"local"`, `"lan"`, `"wan"`, `"cellular"` | Network bandwidth class                                       |

**ClientDisplayInfoAck payload** (JSON):

```json
{
  "status": 0,
  "effective_max_fps": 60
}
```

The server uses `ClientDisplayInfo` fields to adapt frame delivery. Power-aware
throttling caps, WAN coalescing tier adjustments, and idle suppression during
resize are defined in daemon design docs.

---

## 2. Flow Control and Backpressure

### 2.1 Background

Flow control manages delivery when pane output exceeds client consumption. Ring
buffer architecture is defined in daemon design docs. See
[doc 04 Section 4](04-input-and-renderstate.md#4-frameupdate-delivery) for the
I/P-frame model.

### 2.2 Message Types

| Type Code | Name                 | Direction | Description                               |
| --------- | -------------------- | --------- | ----------------------------------------- |
| `0x0500`  | PausePane            | S -> C    | Server signals client is falling behind   |
| `0x0501`  | ContinuePane         | C -> S    | Client signals readiness to resume        |
| `0x0502`  | FlowControlConfig    | C -> S    | Client configures flow control parameters |
| `0x0503`  | FlowControlConfigAck | S -> C    | Server acknowledges configuration         |
| `0x0504`  | OutputQueueStatus    | S -> C    | Server reports delivery pressure          |

### 2.3 Delivery Model Overview

The server maintains a shared per-pane ring buffer for frame delivery. All frame
data (I-frames and P-frames) is written once to the ring. Per-client read
cursors track each client's delivery position. Ring buffer architecture, sizing,
implementation model, and concurrency details are defined in daemon design docs.

### 2.4 PausePane (0x0500)

PausePane is advisory. Trigger conditions and health escalation are defined in
daemon design docs.

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "ring_lag_percent": 92,
  "ring_lag_bytes": 1884160
}
```

| Field              | Type   | Description                                            |
| ------------------ | ------ | ------------------------------------------------------ |
| `pane_id`          | u32    | Pane for which the client is falling behind            |
| `ring_lag_percent` | number | Client cursor's lag as percentage of ring capacity     |
| `ring_lag_bytes`   | number | Absolute byte lag between client cursor and write head |

### 2.5 ContinuePane (0x0501)

Sent by the client when it has finished processing queued frames and is ready to
resume normal delivery.

**Payload** (JSON):

```json
{
  "pane_id": 1
}
```

After ContinuePane, the server resumes delivery from the latest I-frame. The
client receives a complete terminal state and resumes incremental delivery from
that point.

### 2.6 FlowControlConfig (0x0502)

Client configures per-connection flow control parameters. Sent once during the
handshake phase, and may be sent again at any time to adjust.

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

| Field                         | Type    | Default (local) | Default (SSH) | Description                                                  |
| ----------------------------- | ------- | --------------- | ------------- | ------------------------------------------------------------ |
| `max_queue_age_ms`            | number  | 5000            | 5000          | Time-based staleness trigger (orthogonal to ring lag)        |
| `auto_continue`               | boolean | true            | true          | Server auto-continues after PausePane when client catches up |
| `resize_exclusion_timeout_ms` | number  | 5000            | 5000          | Grace period before resize exclusion after PausePane         |
| `stale_timeout_ms`            | number  | 60000           | 120000        | PausePane duration before `stale` health transition          |
| `eviction_timeout_ms`         | number  | 300000          | 300000        | Total duration before forced disconnect                      |

The server selects transport-aware defaults based on
`ClientDisplayInfo.transport_type`. The client can override via this message.

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

| Field    | Type   | Description                                        |
| -------- | ------ | -------------------------------------------------- |
| `status` | number | 0 = accepted, 1 = adjusted (server clamped values) |

### 2.8 Client Health Model

The protocol defines two health states orthogonal to connection lifecycle:

| State     | Definition                              | Resize participation | Frame delivery                      |
| --------- | --------------------------------------- | -------------------- | ----------------------------------- |
| `healthy` | Normal operation                        | Yes                  | Full (per coalescing tier) via ring |
| `stale`   | Paused too long or ring cursor stagnant | No                   | None (ring cursor stagnant)         |

`paused` (PausePane active) is an orthogonal flow-control state, not a health
state. Health state transitions are communicated via `ClientHealthChanged`
(0x0185) notifications. Server MAY send `Disconnect` with reason `stale_client`
to evict unresponsive clients.

Health escalation timeline, stale triggers, timeout values, smooth degradation,
and recovery procedures are defined in daemon design docs.

### 2.9 Recovery Wire Behavior

On stale recovery, the server sends `LayoutChanged` and `PreeditSync` (if
applicable), followed by an I-frame (complete terminal state).

### 2.10 OutputQueueStatus (0x0504)

Periodic notification (configurable interval) reporting delivery pressure for
the client's subscribed panes. Allows the client to proactively adjust rendering
behavior.

> **Normative**: OutputQueueStatus reports **per-client** delivery state for the
> receiving client's connection, not aggregate server state. Each client sees
> only its own ring cursor lag metrics. In a multi-client scenario, Client A's
> OutputQueueStatus reflects Client A's ring cursor position, which may differ
> from Client B's for the same pane (due to different consumption rates,
> coalescing tiers, or flow control states).

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

### 3.1 Background

Clipboard integration bridges the terminal application (OSC 52) and the host OS
clipboard (macOS pasteboard, Linux X11/Wayland). The server intercepts OSC 52
sequences from PTY output and translates them into structured clipboard
messages.

### 3.2 Message Types

| Type Code | Name                     | Direction | Description                                   |
| --------- | ------------------------ | --------- | --------------------------------------------- |
| `0x0600`  | ClipboardWrite           | S -> C    | Server requests client write to OS clipboard  |
| `0x0601`  | ClipboardRead            | C -> S    | Client requests clipboard contents for a pane |
| `0x0602`  | ClipboardReadResponse    | S -> C    | Server returns clipboard contents             |
| `0x0603`  | ClipboardChanged         | S -> C    | Clipboard content changed notification        |
| `0x0604`  | ClipboardWriteFromClient | C -> S    | Client pushes clipboard content to server     |

### 3.3 ClipboardWrite (0x0600)

Sent by the server when a shell application writes to the clipboard via OSC 52.
The client should write the data to the host OS clipboard.

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "clipboard_type": "system",
  "data": "copied text here",
  "encoding": "utf8"
}
```

| Field            | Type   | Description                                           |
| ---------------- | ------ | ----------------------------------------------------- |
| `pane_id`        | u32    | Source pane                                           |
| `clipboard_type` | string | `"system"` (clipboard) or `"selection"` (primary/X11) |
| `data`           | string | Clipboard content                                     |
| `encoding`       | string | `"utf8"` or `"base64"` (for binary data)              |

**OSC 52 integration**: When the server's terminal emulator processes
`ESC ] 52 ; c ; <base64-data> ST`, it:

1. Decodes the base64 data.
2. Sends a ClipboardWrite to all attached clients with the decoded data.
3. The `clipboard_type` maps from the OSC 52 selection parameter: `c` = system,
   `p`/`s` = selection.

**Security**: How the client handles clipboard requests (auto-allow, prompt the
user, or deny) is implementation-defined. The protocol delivers the clipboard
data; the client decides the policy. For example, a client may auto-allow
clipboard writes from local Unix socket connections but prompt the user for SSH
tunnel connections. This is a client app concern, not a protocol concern.

### 3.4 ClipboardRead (0x0601)

Sent by the client when a shell application requests clipboard contents via OSC
52 query (`ESC ] 52 ; c ; ? ST`) and the server's terminal emulator forwards the
request.

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "clipboard_type": "system"
}
```

### 3.5 ClipboardReadResponse (0x0602)

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

| Field    | Type   | Description                              |
| -------- | ------ | ---------------------------------------- |
| `status` | number | 0 = success, 1 = denied, 2 = unavailable |

### 3.6 ClipboardChanged (0x0603)

Optional notification sent by the server when its internal clipboard buffer
changes (e.g., copy from scrollback selection). Clients subscribed to clipboard
events receive this.

**Payload** (JSON):

```json
{
  "clipboard_type": "system",
  "data": "new clipboard contents"
}
```

### 3.7 ClipboardWriteFromClient (0x0604)

Bidirectional clipboard sync: client pushes its OS clipboard content to the
server, e.g., for paste operations or to sync across multiple clients.

**Payload** (JSON):

```json
{
  "clipboard_type": "system",
  "data": "pasted text"
}
```

---

## 4. Persistence (Snapshot/Restore)

### 4.1 Background

Session persistence uses periodic snapshots. Persistence model and snapshot
internals are defined in daemon design docs.

### 4.2 Message Types

| Type Code | Name                      | Direction | Description                                   |
| --------- | ------------------------- | --------- | --------------------------------------------- |
| `0x0700`  | SnapshotRequest           | C -> S    | Client requests a session snapshot            |
| `0x0701`  | SnapshotResponse          | S -> C    | Snapshot result                               |
| `0x0702`  | RestoreSessionRequest     | C -> S    | Client requests session restore from snapshot |
| `0x0703`  | RestoreSessionResponse    | S -> C    | Restore result                                |
| `0x0704`  | SnapshotListRequest       | C -> S    | List available snapshots                      |
| `0x0705`  | SnapshotListResponse      | S -> C    | Available snapshots                           |
| `0x0706`  | SnapshotAutoSaveConfig    | C -> S    | Configure auto-save                           |
| `0x0707`  | SnapshotAutoSaveConfigAck | S -> C    | Auto-save configuration result                |

### 4.3 SnapshotRequest (0x0700)

Triggers an immediate snapshot of the specified session to disk.

**Payload** (JSON):

```json
{
  "session_id": 0,
  "include_scrollback": true,
  "max_scrollback_lines": 4000
}
```

| Field                  | Type    | Description                          |
| ---------------------- | ------- | ------------------------------------ |
| `session_id`           | u32     | 0 = all sessions                     |
| `include_scrollback`   | boolean | Whether to include scrollback buffer |
| `max_scrollback_lines` | number  | 0 = use default, max 4000            |

### 4.4 SnapshotResponse (0x0701)

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

### 4.5 RestoreSessionRequest (0x0702)

Requests the server to restore a session from a previously saved snapshot.

**Payload** (JSON):

```json
{
  "path": "",
  "snapshot_session_name": "",
  "restore_scrollback": true
}
```

| Field                   | Type    | Description                                           |
| ----------------------- | ------- | ----------------------------------------------------- |
| `path`                  | string  | Snapshot file path (empty = restore from most recent) |
| `snapshot_session_name` | string  | Session name from snapshot (empty = restore all)      |
| `restore_scrollback`    | boolean | Whether to restore scrollback buffer                  |

### 4.6 RestoreSessionResponse (0x0703)

On success, the server follows with CreateSessionResponse-like data and
LayoutChanged notifications.

**Payload** (JSON):

```json
{
  "status": 0,
  "session_id": 5,
  "pane_count": 3,
  "error": ""
}
```

| Field        | Type   | Description                                                     |
| ------------ | ------ | --------------------------------------------------------------- |
| `status`     | number | 0 = success, 1 = snapshot not found, 2 = corrupt, 3 = I/O error |
| `session_id` | u32    | Newly assigned by server                                        |
| `pane_count` | number | Number of restored panes                                        |

**Wire behavior**: On success, the server sends `RestoreSessionResponse`,
followed by `LayoutChanged` for the restored session, followed by `FrameUpdate`
(I-frame) for each pane. The restored session includes `active_input_method` and
`active_keyboard_layout` fields.

Session restore procedure (snapshot reading, pane creation, IME engine
re-initialization, scrollback restoration) is defined in daemon design docs.

### 4.7 SnapshotListRequest (0x0704)

No payload. JSON body is `{}`.

### 4.8 SnapshotListResponse (0x0705)

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

### 4.9 SnapshotAutoSaveConfig (0x0706)

**Payload** (JSON):

```json
{
  "interval_ms": 8000,
  "include_scrollback": true,
  "max_scrollback_lines": 4000
}
```

| Field                  | Type    | Description                                 |
| ---------------------- | ------- | ------------------------------------------- |
| `interval_ms`          | number  | 0 = disable auto-save                       |
| `include_scrollback`   | boolean | Whether to include scrollback in auto-saves |
| `max_scrollback_lines` | number  | Maximum scrollback lines per pane           |

### 4.10 SnapshotAutoSaveConfigAck (0x0707)

**Payload** (JSON):

```json
{
  "status": 0,
  "effective_interval_ms": 8000
}
```

**Default auto-save**: 8000 ms (8 seconds), matching cmux. Minimum: 1000 ms.
Scrollback included by default with a 4000-line limit per pane.

---

## 5. Notifications

Server-initiated notifications for events that clients may want to track. Unlike
the notifications in doc 03 (which are always sent), these are opt-in via the
subscription system (Section 6).

### 5.1 Message Types

| Type Code | Name             | Direction | Description                          |
| --------- | ---------------- | --------- | ------------------------------------ |
| `0x0800`  | PaneTitleChanged | S -> C    | Pane title changed (OSC 0/2)         |
| `0x0801`  | ProcessExited    | S -> C    | Foreground process exited            |
| `0x0802`  | Bell             | S -> C    | Bell character received (BEL / \a)   |
| `0x0803`  | RendererHealth   | S -> C    | Server-side rendering health report  |
| `0x0804`  | PaneCwdChanged   | S -> C    | Pane working directory changed       |
| `0x0805`  | ActivityDetected | S -> C    | Output activity in a background pane |
| `0x0806`  | SilenceDetected  | S -> C    | No output for configured duration    |

### 5.2 PaneTitleChanged (0x0800)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "title": "vim - main.zig"
}
```

### 5.3 ProcessExited (0x0801)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "exit_code": 0,
  "process_name": "make"
}
```

| Field       | Type   | Description                                                   |
| ----------- | ------ | ------------------------------------------------------------- |
| `exit_code` | number | Exit code (negative = killed by signal, e.g., -9 for SIGKILL) |

In v1, the server always auto-closes the pane after sending ProcessExited (see
Doc 03 auto-close rules). A `pane_remains` field for remain-on-exit semantics is
deferred to post-v1 (see `99-post-v1-features.md`).

### 5.4 Bell (0x0802)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "timestamp": 1709568000123
}
```

The client handles the bell according to its configuration (audible beep, visual
flash, bounce dock icon, system notification, etc.).

### 5.5 RendererHealth (0x0803)

Periodic health report from the server's terminal processing pipeline. Useful
for debugging performance issues. Now includes coalescing tier and ring buffer
information.

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

| Field                | Type   | Description                                                     |
| -------------------- | ------ | --------------------------------------------------------------- |
| `coalescing_tier`    | string | `"preedit"`, `"interactive"`, `"active"`, `"bulk"`, or `"idle"` |
| `ring_usage_bytes`   | number | Current ring buffer usage for this pane                         |
| `ring_usage_percent` | number | Ring usage as percentage of capacity                            |

### 5.6 PaneCwdChanged (0x0804)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "cwd": "/home/user/project"
}
```

Triggered by shell integration sequences (OSC 7) or `/proc/<pid>/cwd` polling.

### 5.7 ActivityDetected (0x0805)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "timestamp": 1709568000123
}
```

Sent when output activity is detected in a pane that is not currently visible
(non-focused pane). Allows the client to show activity indicators on panes.

### 5.8 SilenceDetected (0x0806)

**Payload** (JSON):

```json
{
  "pane_id": 1,
  "silence_duration_ms": 30000
}
```

Sent when a pane has produced no output for a configured duration. Useful for
long-running build commands: the user gets notified when the build finishes
(silence after activity).

---

## 6. Subscription System

Clients subscribe to specific per-pane or global events. The server only sends
notification messages (Section 5) for events the client has subscribed to. This
reduces unnecessary network traffic and processing.

### 6.1 Message Types

| Type Code | Name           | Direction | Description                 |
| --------- | -------------- | --------- | --------------------------- |
| `0x0810`  | Subscribe      | C -> S    | Subscribe to events         |
| `0x0811`  | SubscribeAck   | S -> C    | Subscription confirmation   |
| `0x0812`  | Unsubscribe    | C -> S    | Unsubscribe from events     |
| `0x0813`  | UnsubscribeAck | S -> C    | Unsubscription confirmation |

### 6.2 Subscribe (0x0810)

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

| Field        | Type   | Description                             |
| ------------ | ------ | --------------------------------------- |
| `pane_id`    | u32    | 0 = subscribe for all panes             |
| `event_mask` | number | Bitmask of events                       |
| `config`     | object | Event-specific configuration (optional) |

**event_mask bits**:

| Bit | Value  | Event             | Config field                                 |
| --- | ------ | ----------------- | -------------------------------------------- |
| 0   | 0x0001 | PaneTitleChanged  | --                                           |
| 1   | 0x0002 | ProcessExited     | --                                           |
| 2   | 0x0004 | Bell              | --                                           |
| 3   | 0x0008 | RendererHealth    | `renderer_health_interval_ms` (default 5000) |
| 4   | 0x0010 | PaneCwdChanged    | --                                           |
| 5   | 0x0020 | ActivityDetected  | --                                           |
| 6   | 0x0040 | SilenceDetected   | `silence_threshold_ms` (default 30000)       |
| 7   | 0x0080 | ClipboardChanged  | --                                           |
| 8   | 0x0100 | OutputQueueStatus | `queue_status_interval_ms` (default 1000)    |

### 6.3 SubscribeAck (0x0811)

**Payload** (JSON):

```json
{
  "status": 0,
  "active_mask": 511
}
```

### 6.4 Unsubscribe (0x0812)

**Payload** (JSON):

```json
{
  "pane_id": 0,
  "event_mask": 8
}
```

### 6.5 UnsubscribeAck (0x0813)

**Payload** (JSON):

```json
{
  "status": 0,
  "active_mask": 503
}
```

### 6.6 Default Subscriptions

After AttachSession, the client automatically receives these notifications
without explicit subscription:

- LayoutChanged (doc 03, always sent)
- SessionListChanged (doc 03, always sent)
- PaneMetadataChanged (doc 03, always sent)
- ClientAttached (doc 03, always sent)
- ClientDetached (doc 03, always sent)
- ClientHealthChanged (doc 03, always sent)

All Section 5 notifications require explicit subscription.

> **Note**: The default subscription list above is wire-observable protocol
> behavior — clients depend on receiving these notifications without
> subscribing. Subscription management implementation is server-side; see daemon
> design docs for notification delivery internals.

---

## 7. Heartbeat and Connection Health

Heartbeat and graceful disconnect messages are defined in the Handshake &
Lifecycle range (doc 01, doc 02):

| Type Code | Name         | Direction     | Description                          |
| --------- | ------------ | ------------- | ------------------------------------ |
| `0x0003`  | Heartbeat    | Bidirectional | Keepalive ping (carries `ping_id`)   |
| `0x0004`  | HeartbeatAck | Bidirectional | Keepalive pong (echoes `ping_id`)    |
| `0x0005`  | Disconnect   | Bidirectional | Graceful disconnect with reason code |

See doc 01 Section 5.4 and doc 02 for message payload definitions.

The `0x0900-0x09FF` range is reserved for future connection health extensions,
including `echo_nonce` (application-level heartbeat verification, v2
`HEARTBEAT_NONCE` capability).

### 7.1 Heartbeat Wire Format

Heartbeat is liveness-only. The `timestamp` and `responder_timestamp` fields
from v0.3 have been removed — no protocol-level consumer exists for either.
Liveness detection requires only `ping_id`: did the ack arrive within the
timeout?

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

| Field     | Type | Description                            |
| --------- | ---- | -------------------------------------- |
| `ping_id` | u32  | Monotonic ping counter for correlation |

### 7.2 Heartbeat Policy

| Parameter          | Default    | Description                                                                          |
| ------------------ | ---------- | ------------------------------------------------------------------------------------ |
| Heartbeat interval | 30 seconds | How often to send Heartbeat if no other messages sent                                |
| Connection timeout | 90 seconds | If no message of any kind received within this period, connection is considered dead |

Either side can send Heartbeat. The other side responds with HeartbeatAck. If no
message (of any kind) is received within 90 seconds, the connection is
considered dead and is closed with `Disconnect(TIMEOUT)`. The 90-second timeout
corresponds to 3 missed heartbeat intervals.

For Unix domain sockets (local), heartbeat is optional — the OS detects dead
sockets via `SO_KEEPALIVE` or write errors (`EPIPE`/`SIGPIPE`) much faster. Over
SSH tunnels, heartbeats are complementary to SSH's own `ServerAliveInterval`
keepalive and are recommended to detect tunnel failures that the OS may not
report immediately.

### 7.3 Heartbeat Orthogonality with Health States

Heartbeat (0x0003-0x0005) is a **connection liveness** mechanism. 90s timeout ->
Disconnect. Health states are an **application responsiveness** mechanism,
triggered by ring cursor lag and PausePane duration. These are independent
systems:

| Combination                       | Meaning                                                |
| --------------------------------- | ------------------------------------------------------ |
| Heartbeat-healthy + output-stale  | `stale` (app frozen, TCP alive)                        |
| Heartbeat-missed + output-healthy | Connection problem (will resolve or disconnect at 90s) |

---

## 8. Extension Negotiation

### 8.1 Message Types

| Type Code | Name             | Direction        | Description                              |
| --------- | ---------------- | ---------------- | ---------------------------------------- |
| `0x0A00`  | ExtensionList    | C -> S or S -> C | Declare available extensions             |
| `0x0A01`  | ExtensionListAck | S -> C or C -> S | Acknowledge and accept/reject extensions |
| `0x0A02`  | ExtensionMessage | Either           | Message within a negotiated extension    |

### 8.2 ExtensionList (0x0A00)

Sent during the handshake phase (after capability negotiation, before session
attach). Both client and server declare the extensions they support.

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

### 8.3 ExtensionListAck (0x0A01)

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

| Field    | Type   | Description                                      |
| -------- | ------ | ------------------------------------------------ |
| `status` | number | 0 = accepted, 1 = rejected, 2 = version mismatch |

### 8.4 ExtensionMessage (0x0A02)

Generic wrapper for extension-specific messages. The extension defines its own
payload format.

**Payload** (JSON):

```json
{
  "ext_id": 1,
  "ext_msg_type": 3,
  "payload": {}
}
```

### 8.5 Extension ID Ranges

| Range               | Purpose                                                    |
| ------------------- | ---------------------------------------------------------- |
| `0x0001` - `0x00FF` | Core extensions (defined by libitshell3 spec)              |
| `0x0100` - `0x0FFF` | Reserved for future official extensions                    |
| `0x1000` - `0x7FFF` | Registered vendor extensions (IANA-style registry, future) |
| `0x8000` - `0xFFFE` | Private/experimental extensions                            |
| `0xFFFF`            | Reserved                                                   |

### 8.6 Known Core Extensions

| ID       | Name                | Description                                 |
| -------- | ------------------- | ------------------------------------------- |
| `0x0001` | `cjk-preedit`       | CJK IME preedit sync (doc 05)               |
| `0x0002` | `agent-mode`        | AI agent detection and input mode switching |
| `0x0003` | `sixel`             | Sixel graphics passthrough                  |
| `0x0004` | `kitty-images`      | Kitty image protocol support                |
| `0x0005` | `hyperlinks`        | OSC 8 hyperlink support                     |
| `0x0006` | `shell-integration` | Shell integration (OSC 133, semantic zones) |

---

## 9. Reserved Message Type Ranges for Future Use

| Range               | Purpose                  | Notes                                 |
| ------------------- | ------------------------ | ------------------------------------- |
| `0x0B00` - `0x0BFF` | File transfer            | Drag-and-drop, SCP-like file transfer |
| `0x0C00` - `0x0CFF` | Plugin system            | If we add a plugin architecture       |
| `0x0D00` - `0x0DFF` | Audio                    | Audio passthrough, terminal bells     |
| `0x0E00` - `0x0EFF` | Accessibility            | Screen reader support, announcements  |
| `0x0F00` - `0x0FFF` | Diagnostics              | Debug tracing, profiling, metrics     |
| `0xF000` - `0xFFFE` | Vendor/custom extensions | Via extension negotiation             |
| `0xFFFF`            | Invalid                  | Reserved sentinel, never used         |

---

## 10. Error Handling

### Protocol Errors

If a client or server receives a message with:

- Unknown message type within a non-extension range: **ignore** the message
  (forward compatibility).
- Unknown message type within the extension range (0xF000+): ignore if no
  matching extension is negotiated.
- Payload shorter than expected: respond with `status = PROTOCOL_ERROR` in the
  next appropriate response, or send Disconnect (0x0005) with reason `"error"`
  and detail describing the protocol violation.
- Payload longer than expected: consume the full payload (based on header
  length), ignore extra fields (forward compatibility with JSON payloads).

### Timeout Handling

| Scenario                       | Timeout                    | Action                                                                                                |
| ------------------------------ | -------------------------- | ----------------------------------------------------------------------------------------------------- |
| Request without response       | 30 seconds                 | Client may resend or Disconnect (0x0005)                                                              |
| PausePane without ContinuePane | 5s / 60s / 300s escalation | T=5s resize exclusion, T=60s/120s stale, T=300s eviction (see [Section 2.8](#28-client-health-model)) |
| No message received (any kind) | 90 seconds                 | Send `Disconnect(TIMEOUT)`, close connection                                                          |
| Snapshot write                 | 60 seconds                 | Respond with I/O error                                                                                |

---

## 11. Open Questions

1. **Clipboard size limit**: Should there be a maximum clipboard data size?
   Large clipboard contents (e.g., megabytes of text) could cause issues.
   Suggestion: 10 MB limit with chunked transfer for larger content.

2. **Snapshot format versioning**: How do we handle snapshot format evolution?
   Suggestion: include a format version number in the JSON snapshot. Newer
   servers can read older formats but not vice versa.

3. **Extension negotiation timing**: Should extensions be negotiated before or
   after authentication? Before auth risks information leakage (advertising
   capabilities to unauthenticated clients). After auth adds latency.
   Suggestion: after auth for SSH tunnel transport, during handshake for Unix
   sockets.

4. **Multi-session snapshots**: Should one snapshot file contain multiple
   sessions, or one file per session? cmux uses one file for the entire app
   state. Per-session files are simpler for partial restore. Suggestion:
   per-session files with a manifest.

5. **~~Clipboard sync mode~~** **Closed (v0.7)**: Not a protocol concern.
   Clipboard access policy (auto-allow, prompt, deny) is implementation-defined
   by the client app. Normative note added to Section 3.1. Owner decision.

6. **RendererHealth interval**: How frequently should RendererHealth reports be
   sent? Too frequent = noise, too infrequent = useless for debugging. The
   subscription system allows per-client configuration, but what should the
   minimum be? Suggestion: 1000 ms minimum.

7. **Extension message ordering**: Should extension messages be ordered with
   respect to core messages, or can they be interleaved? For simplicity, all
   messages on a connection are strictly ordered. Extensions cannot bypass this.

8. **Silence detection scope**: Should SilenceDetected fire only for panes with
   recent activity (activity-then-silence pattern), or for any pane that has
   been silent? The activity-then-silence pattern is more useful (build
   completion notification). Suggestion: only fire after at least one byte of
   output has been seen since the last silence notification.

9. **~~Tier transition telemetry~~** **Closed (v0.7)**: RendererHealth's
   `coalescing_tier` field is sufficient. No dedicated notification needed.
   Owner confirmed.
