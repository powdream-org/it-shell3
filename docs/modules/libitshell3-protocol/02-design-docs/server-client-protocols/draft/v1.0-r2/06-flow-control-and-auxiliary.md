# 06 - Flow Control and Auxiliary Protocols

**Version**: v0.2
**Status**: Draft
**Date**: 2026-03-04
**Author**: systems-engineer (AI-assisted)

## Overview

This document specifies flow control (backpressure), clipboard, persistence, notification, subscription, heartbeat, and extension negotiation protocols for libitshell3. These are auxiliary protocols that complement the core session/pane management (doc 03), input forwarding (doc 04), and render state streaming (doc 04).

All messages use the binary framing defined in document 01 (16-byte header: magic(2) + version(1) + flags(1) + msg_type(2) + reserved(2) + payload_len(4) + sequence(4), little-endian byte order).

### Conventions

Same as doc 03:
- Little-endian byte order for all multi-byte integers.
- Strings are UTF-8, length-prefixed with `u16` byte count.
- IDs are u32 (4 bytes), server-assigned, monotonically increasing (see doc 03 ID Types).
- Boolean fields are `u8`: 0 = false, 1 = true.
- "Payload offset" means byte offset after the 16-byte header.
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
| `0x0900` - `0x09FF` | Heartbeat and connection health | **This doc** |
| `0x0A00` - `0x0AFF` | Extension negotiation | **This doc** |
| `0x0B00` - `0x0FFF` | Reserved for future use | -- |
| `0xF000` - `0xFFFF` | Vendor/custom extensions | **This doc** |

---

## 1. Flow Control and Backpressure

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

### 1.1 PausePane (0x0500)

Sent by the server when the output queue for a specific pane exceeds the configured threshold for this client. After sending PausePane, the server stops sending FrameUpdate messages for this pane to this client. PTY output continues to be read and processed by the server's terminal emulator; only client delivery is paused.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (u32) |
| 4 | 4 | `queued_bytes` | Current queue size in bytes |
| 8 | 4 | `queued_frames` | Number of frames queued |
| 12 | 4 | `queue_age_ms` | Age of oldest queued frame in milliseconds |

### 1.2 ContinuePane (0x0501)

Sent by the client when it has finished processing queued frames and is ready to receive more output for the paused pane. The server resumes sending FrameUpdate messages.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (u32) |
| 4 | 4 | `last_processed_seq` | Sequence number of the last FrameUpdate the client processed |

The server uses `last_processed_seq` to determine which frames the client has already consumed. It discards frames older than this sequence and sends a fresh full FrameUpdate reflecting the current terminal state, followed by incremental updates going forward.

### 1.3 FlowControlConfig (0x0502)

Client configures per-connection flow control parameters. Sent once during the handshake phase, and may be sent again at any time to adjust.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `max_queue_bytes` | Maximum queue size before PausePane (0 = server default) |
| 4 | 4 | `max_queue_frames` | Maximum queued frames before PausePane (0 = server default) |
| 8 | 4 | `max_queue_age_ms` | Maximum frame age before PausePane (0 = server default) |
| 12 | 1 | `auto_continue` | 1 = server auto-continues after queue drains (no explicit ContinuePane needed) |

### 1.4 FlowControlConfigAck (0x0503)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = accepted, 1 = adjusted (server clamped values) |
| 1 | 4 | `effective_max_bytes` | Actual max bytes the server will use |
| 5 | 4 | `effective_max_frames` | Actual max frames |
| 9 | 4 | `effective_max_age_ms` | Actual max age |

### 1.5 OutputQueueStatus (0x0504)

Periodic notification (configurable interval) reporting queue pressure for the client's subscribed panes. Allows the client to proactively adjust rendering behavior (e.g., reduce frame rate, skip intermediate frames).

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 2 | `pane_count` | Number of pane entries |
| 2 | variable | `panes[]` | Array of per-pane status |

Per-pane entry:

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (u32) |
| 4 | 4 | `queued_bytes` | Current queue size |
| 8 | 4 | `queued_frames` | Queued frame count |
| 12 | 1 | `paused` | 1 = pane is paused for this client |

### Server Output Queue Management

The server maintains a per-pane, per-client output queue with these eviction policies:

| Policy | Default | Description |
|--------|---------|-------------|
| Max size per pane per client | 1 MB | Oldest frames evicted when exceeded |
| Max frames per pane per client | 120 | ~2 seconds at 60fps; oldest evicted |
| Max age | 5000 ms | Frames older than 5s are discarded |
| Eviction strategy | Drop oldest, send full refresh | When frames are dropped, the next delivered frame is a full FrameUpdate (dirty=full) |

When the queue exceeds thresholds:
1. Server sends PausePane to the client.
2. Server continues reading PTY output and updating the terminal state.
3. Server compacts the queue: replaces multiple partial frames with a single full frame reflecting current state.
4. When the client sends ContinuePane (or auto_continue triggers), the server sends one full FrameUpdate followed by incremental updates.

**Key insight**: Unlike tmux (which buffers raw bytes), libitshell3 buffers structured frames. This means the server can always compact the queue to a single full frame, bounding memory usage.

---

## 2. Clipboard

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

### 2.1 ClipboardWrite (0x0600)

Sent by the server when a shell application writes to the clipboard via OSC 52. The client should write the data to the host OS clipboard.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Source pane ID (u32) |
| 4 | 1 | `clipboard_type` | 0 = system (clipboard), 1 = selection (primary/X11) |
| 5 | 4 | `data_len` | Length of clipboard data in bytes |
| 9 | `data_len` | `data` | Clipboard content (UTF-8 text or base64-encoded binary) |
| 9+D | 1 | `encoding` | 0 = UTF-8 text, 1 = base64 (binary data) |

**OSC 52 integration**: When the server's terminal emulator processes `ESC ] 52 ; c ; <base64-data> ST`, it:
1. Decodes the base64 data.
2. Sends a ClipboardWrite to all attached clients with the decoded data.
3. The `clipboard_type` maps from the OSC 52 selection parameter: `c` = system, `p`/`s` = selection.

**Security**: The server may be configured to prompt before clipboard writes (matching iTerm2's security model). If prompting is enabled, the ClipboardWrite message includes a confirmation token and the client must display a user prompt before writing to the OS clipboard. This is controlled via capabilities negotiation.

### 2.2 ClipboardRead (0x0601)

Sent by the client when a shell application requests clipboard contents via OSC 52 query (`ESC ] 52 ; c ; ? ST`) and the server's terminal emulator forwards the request.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Requesting pane ID (u32) |
| 4 | 1 | `clipboard_type` | 0 = system, 1 = selection |

### 2.3 ClipboardReadResponse (0x0602)

Client responds with the current OS clipboard contents.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Requesting pane ID (u32) |
| 4 | 1 | `clipboard_type` | 0 = system, 1 = selection |
| 5 | 1 | `status` | 0 = success, 1 = denied (user refused), 2 = unavailable |
| 6 | 4 | `data_len` | Length of clipboard data |
| 10 | `data_len` | `data` | Clipboard content (UTF-8) |

### 2.4 ClipboardChanged (0x0603)

Optional notification sent by the server when its internal clipboard buffer changes (e.g., copy from scrollback selection). Clients subscribed to clipboard events receive this.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `clipboard_type` | 0 = system, 1 = selection |
| 1 | 4 | `data_len` | Length of clipboard data |
| 5 | `data_len` | `data` | Clipboard content (UTF-8) |

### 2.5 ClipboardWriteFromClient (0x0604)

Bidirectional clipboard sync: client pushes its OS clipboard content to the server, e.g., for paste operations or to sync across multiple clients.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `clipboard_type` | 0 = system, 1 = selection |
| 1 | 4 | `data_len` | Length of clipboard data |
| 5 | `data_len` | `data` | Clipboard content (UTF-8) |

---

## 3. Persistence (Snapshot/Restore)

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

### 3.1 SnapshotRequest (0x0700)

Triggers an immediate snapshot of the specified session to disk.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Session to snapshot (0 = all sessions) |
| 4 | 1 | `include_scrollback` | 1 = include scrollback in snapshot |
| 5 | 4 | `max_scrollback_lines` | Max scrollback lines per pane (0 = use default, max 4000) |

### 3.2 SnapshotResponse (0x0701)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = session not found, 2 = I/O error |
| 1 | 2 | `path_len` | Snapshot file path length |
| 3 | `path_len` | `path` | UTF-8 path to saved snapshot file |
| 3+N | 4 | `snapshot_size` | Size of snapshot file in bytes |
| 7+N | 8 | `timestamp` | Snapshot timestamp (Unix seconds, u64) |
| 15+N | 2 | `error_len` | Error message length |
| 17+N | `error_len` | `error_msg` | UTF-8 error description |

### 3.3 RestoreSessionRequest (0x0702)

Requests the server to restore a session from a previously saved snapshot. The server creates new PTYs, spawns shells, and applies the saved layout. Scrollback is replayed if available.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 2 | `path_len` | Snapshot file path length (0 = restore from most recent) |
| 2 | `path_len` | `path` | UTF-8 path to snapshot file |
| 2+N | 2 | `snapshot_session_name_len` | Length of session name from snapshot (0 = restore all) |
| 4+N | `name_len` | `snapshot_session_name` | UTF-8 session name from snapshot to restore |
| 4+N+M | 1 | `restore_scrollback` | 1 = replay saved scrollback into new PTYs |

### 3.4 RestoreSessionResponse (0x0703)

On success, the server follows with CreateSessionResponse-like data and LayoutChanged notifications.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = snapshot not found, 2 = corrupt snapshot, 3 = I/O error |
| 1 | 4 | `session_id` | ID of the restored session (newly assigned by server) |
| 5 | 2 | `pane_count` | Number of restored panes |
| 7 | 2 | `error_len` | Error message length |
| 9 | `error_len` | `error_msg` | UTF-8 error description |

**Restore sequence**:
1. Client sends RestoreSessionRequest.
2. Server reads snapshot file, validates format.
3. Server creates the session with the saved name and a fresh server-assigned session_id.
4. Server walks the saved layout tree, creating panes (with fresh pane_ids) and spawning shells.
5. If `restore_scrollback=1`, server writes saved scrollback to a temp file and sets `ITSHELL3_RESTORE_SCROLLBACK_FILE` in the shell environment (following cmux's pattern).
6. Server sends RestoreSessionResponse.
7. Server sends LayoutChanged for the restored session.
8. Server sends FrameUpdate for each pane.

### 3.5 SnapshotListRequest (0x0704)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| (empty) | 0 | | No payload |

### 3.6 SnapshotListResponse (0x0705)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success |
| 1 | 2 | `count` | Number of snapshot entries |
| 3 | variable | `snapshots[]` | Array of snapshot entries |

Per-snapshot entry:

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 2 | `path_len` | File path length |
| 2 | `path_len` | `path` | UTF-8 path |
| 2+N | 2 | `name_len` | Session name length |
| 4+N | `name_len` | `name` | UTF-8 session name |
| 4+N+M | 8 | `timestamp` | Unix timestamp (u64) |
| 12+N+M | 4 | `file_size` | Snapshot file size |
| 16+N+M | 1 | `has_scrollback` | 1 = snapshot includes scrollback |

### 3.7 SnapshotAutoSaveConfig (0x0706)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `interval_ms` | Auto-save interval in milliseconds (0 = disable auto-save) |
| 4 | 1 | `include_scrollback` | 1 = include scrollback in auto-saves |
| 5 | 4 | `max_scrollback_lines` | Max lines per pane in auto-saves |

### 3.8 SnapshotAutoSaveConfigAck (0x0707)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = accepted, 1 = adjusted |
| 1 | 4 | `effective_interval_ms` | Actual interval (server may enforce minimum) |

**Default auto-save**: 8000 ms (8 seconds), matching cmux. Minimum: 1000 ms. Scrollback included by default with a 4000-line limit per pane.

---

## 4. Notifications

Server-initiated notifications for events that clients may want to track. Unlike the notifications in doc 03 (which are always sent), these are opt-in via the subscription system (Section 5).

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

### 4.1 PaneTitleChanged (0x0800)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (u32) |
| 4 | 2 | `title_len` | Title length |
| 6 | `title_len` | `title` | UTF-8 pane title |

### 4.2 ProcessExited (0x0801)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (u32) |
| 4 | 4 | `exit_code` | Exit code (i32; negative = killed by signal, e.g., -9 for SIGKILL) |
| 8 | 2 | `process_name_len` | Process name length |
| 10 | `process_name_len` | `process_name` | UTF-8 process name |
| 10+N | 1 | `pane_remains` | 1 = pane stays open (remain-on-exit), 0 = pane will close |

### 4.3 Bell (0x0802)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (u32) |
| 4 | 8 | `timestamp` | Unix timestamp with milliseconds (u64, ms since epoch) |

The client handles the bell according to its configuration (audible beep, visual flash, bounce dock icon, system notification, etc.).

### 4.4 RendererHealth (0x0803)

Periodic health report from the server's terminal processing pipeline. Useful for debugging performance issues.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (u32) |
| 4 | 4 | `frames_processed` | Frames processed since last report |
| 8 | 4 | `frames_dropped` | Frames dropped due to backpressure |
| 12 | 4 | `avg_frame_time_us` | Average frame processing time (microseconds) |
| 16 | 4 | `pty_bytes_read` | PTY bytes read since last report |
| 20 | 4 | `queue_depth` | Current output queue depth (bytes) |

### 4.5 PaneCwdChanged (0x0804)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (u32) |
| 4 | 2 | `cwd_len` | Working directory length |
| 6 | `cwd_len` | `cwd` | UTF-8 new working directory |

Triggered by shell integration sequences (OSC 7) or `/proc/<pid>/cwd` polling.

### 4.6 ActivityDetected (0x0805)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (u32) |
| 4 | 8 | `timestamp` | Unix timestamp (ms since epoch, u64) |

Sent when output activity is detected in a pane that is not currently visible (non-focused pane). Allows the client to show activity indicators on panes.

### 4.7 SilenceDetected (0x0806)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (u32) |
| 4 | 4 | `silence_duration_ms` | How long the pane has been silent (ms) |

Sent when a pane has produced no output for a configured duration. Useful for long-running build commands: the user gets notified when the build finishes (silence after activity).

---

## 5. Subscription System

Clients subscribe to specific per-pane or global events. The server only sends notification messages (Section 4) for events the client has subscribed to. This reduces unnecessary network traffic and processing.

### Message Types

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0810` | Subscribe | C -> S | Subscribe to events |
| `0x0811` | SubscribeAck | S -> C | Subscription confirmation |
| `0x0812` | Unsubscribe | C -> S | Unsubscribe from events |
| `0x0813` | UnsubscribeAck | S -> C | Unsubscription confirmation |

### 5.1 Subscribe (0x0810)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (0 = subscribe for all panes) |
| 4 | 4 | `event_mask` | Bitmask of events to subscribe to |
| 8 | 4 | `config` | Event-specific configuration (see below) |

**event_mask bits**:

| Bit | Value | Event | Config meaning |
|-----|-------|-------|----------------|
| 0 | 0x0001 | PaneTitleChanged | (unused) |
| 1 | 0x0002 | ProcessExited | (unused) |
| 2 | 0x0004 | Bell | (unused) |
| 3 | 0x0008 | RendererHealth | config = report interval in ms (0 = default 5000) |
| 4 | 0x0010 | PaneCwdChanged | (unused) |
| 5 | 0x0020 | ActivityDetected | (unused) |
| 6 | 0x0040 | SilenceDetected | config = silence threshold in ms (0 = default 30000) |
| 7 | 0x0080 | ClipboardChanged | (unused) |
| 8 | 0x0100 | OutputQueueStatus | config = report interval in ms (0 = default 1000) |

### 5.2 SubscribeAck (0x0811)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane not found |
| 1 | 4 | `active_mask` | Bitmask of events now active for this pane |

### 5.3 Unsubscribe (0x0812)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `pane_id` | Pane ID (0 = all panes) |
| 4 | 4 | `event_mask` | Bitmask of events to unsubscribe from |

### 5.4 UnsubscribeAck (0x0813)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success |
| 1 | 4 | `active_mask` | Bitmask of events still active |

### Default Subscriptions

After AttachSession, the client automatically receives these notifications without explicit subscription:
- LayoutChanged (doc 03, always sent)
- SessionListChanged (doc 03, always sent)
- PaneMetadataChanged (doc 03, always sent)

All Section 4 notifications require explicit subscription.

---

## 6. Heartbeat and Connection Health

### Background

The client and server exchange periodic heartbeats to detect dead connections. This is especially important for future network transport (iOS client over TCP/TLS) where connections can drop silently.

### Message Types

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0900` | Ping | C -> S or S -> C | Heartbeat request |
| `0x0901` | Pong | S -> C or C -> S | Heartbeat response |
| `0x0902` | ConnectionClosing | C -> S or S -> C | Graceful disconnect |

### 6.1 Ping (0x0900)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 8 | `timestamp` | Sender's timestamp (ms since epoch, u64) |
| 8 | 4 | `ping_id` | Opaque ID for correlation (echoed in Pong) |

### 6.2 Pong (0x0901)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 8 | `timestamp` | Original ping timestamp (echoed) |
| 8 | 4 | `ping_id` | Echoed ping ID |
| 12 | 8 | `server_timestamp` | Responder's timestamp (for RTT calculation) |

**RTT calculation**: `RTT = current_time - pong.timestamp`. One-way latency is approximately `RTT / 2`.

### 6.3 ConnectionClosing (0x0902)

Graceful connection teardown. The sender indicates why the connection is closing.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `reason` | Reason code (see below) |
| 1 | 2 | `message_len` | Message length |
| 3 | `message_len` | `message` | UTF-8 human-readable reason |

**Reason codes**:

| Code | Name | Description |
|------|------|-------------|
| 0 | `NORMAL` | Normal shutdown |
| 1 | `DETACHING` | Client is detaching from session |
| 2 | `SERVER_SHUTDOWN` | Server is shutting down |
| 3 | `PROTOCOL_ERROR` | Protocol violation detected |
| 4 | `TIMEOUT` | Heartbeat timeout |
| 5 | `VERSION_MISMATCH` | Incompatible protocol version |

### Heartbeat Policy

| Parameter | Default | Description |
|-----------|---------|-------------|
| Ping interval | 30 seconds | How often to send Ping |
| Pong timeout | 10 seconds | How long to wait for Pong before considering connection dead |
| Max missed pongs | 3 | Number of missed pongs before ConnectionClosing |

Either side can send Ping. The other side must respond with Pong within the timeout.

For Unix domain sockets (local), heartbeat is optional (the OS detects dead sockets via `SO_KEEPALIVE` or write errors). For network transport (future iOS), heartbeat is mandatory.

---

## 7. Extension Negotiation

### Background

libitshell3 is designed for long-term evolution. The extension system allows clients and servers to negotiate optional features beyond the base protocol. This avoids the fragile version-guessing pattern that plagues tmux.

### Message Types

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0A00` | ExtensionList | C -> S or S -> C | Declare available extensions |
| `0x0A01` | ExtensionListAck | S -> C or C -> S | Acknowledge and accept/reject extensions |
| `0x0A02` | ExtensionMessage | Either | Message within a negotiated extension |

### 7.1 ExtensionList (0x0A00)

Sent during the handshake phase (after capability negotiation, before session attach). Both client and server declare the extensions they support.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 2 | `count` | Number of extensions declared |
| 2 | variable | `extensions[]` | Array of extension entries |

Per-extension entry:

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 2 | `ext_id` | Extension ID (see ranges below) |
| 2 | 2 | `version` | Extension version (major.minor packed as u8.u8) |
| 4 | 2 | `name_len` | Extension name length |
| 6 | `name_len` | `name` | UTF-8 extension name (e.g., "cjk-preedit") |
| 6+N | 2 | `config_len` | Extension-specific config length (0 = no config) |
| 8+N | `config_len` | `config` | Extension-specific configuration (opaque bytes) |

### 7.2 ExtensionListAck (0x0A01)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 2 | `count` | Number of extension results |
| 2 | variable | `results[]` | Array of results |

Per-extension result:

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 2 | `ext_id` | Extension ID |
| 2 | 1 | `status` | 0 = accepted, 1 = rejected, 2 = version mismatch |
| 3 | 2 | `accepted_version` | Negotiated version (if accepted) |

### 7.3 ExtensionMessage (0x0A02)

Generic wrapper for extension-specific messages. The extension defines its own payload format.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 2 | `ext_id` | Extension ID |
| 2 | 2 | `ext_msg_type` | Extension-defined message type |
| 4 | 4 | `payload_len` | Payload length |
| 8 | `payload_len` | `payload` | Extension-specific payload |

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

## 8. Reserved Message Type Ranges for Future Use

| Range | Purpose | Notes |
|-------|---------|-------|
| `0x0B00` - `0x0BFF` | File transfer | Drag-and-drop, SCP-like file transfer |
| `0x0C00` - `0x0CFF` | Plugin system | If we add a plugin architecture |
| `0x0D00` - `0x0DFF` | Audio | Audio passthrough, terminal bells |
| `0x0E00` - `0x0EFF` | Accessibility | Screen reader support, announcements |
| `0x0F00` - `0x0FFF` | Diagnostics | Debug tracing, profiling, metrics |
| `0xF000` - `0xFEFF` | Vendor custom messages | Via extension negotiation |
| `0xFF00` - `0xFFFE` | Experimental | Unstable, may change without notice |
| `0xFFFF` | Invalid | Reserved sentinel, never used |

---

## 9. Error Handling

### Protocol Errors

If a client or server receives a message with:
- Unknown message type within a non-extension range: **ignore** the message (forward compatibility).
- Unknown message type within the extension range (0xF000+): ignore if no matching extension is negotiated.
- Payload shorter than expected: respond with `status = PROTOCOL_ERROR` in the next appropriate response, or send ConnectionClosing with reason `PROTOCOL_ERROR`.
- Payload longer than expected: consume the full payload (based on header length), ignore extra bytes.

### Timeout Handling

| Scenario | Timeout | Action |
|----------|---------|--------|
| Request without response | 30 seconds | Client may resend or ConnectionClosing |
| PausePane without ContinuePane | No timeout | Server compacts queue, waits indefinitely |
| Heartbeat Pong | 10 seconds | Increment missed pong counter |
| Snapshot write | 60 seconds | Respond with I/O error |

---

## 10. Open Questions

1. **Clipboard size limit**: Should there be a maximum clipboard data size? Large clipboard contents (e.g., megabytes of text) could cause issues. Suggestion: 10 MB limit with chunked transfer for larger content.

2. **Snapshot format versioning**: How do we handle snapshot format evolution? Suggestion: include a format version number in the JSON snapshot. Newer servers can read older formats but not vice versa.

3. **Extension negotiation timing**: Should extensions be negotiated before or after authentication? Before auth risks information leakage (advertising capabilities to unauthenticated clients). After auth adds latency. Suggestion: after auth for network transport, during handshake for Unix sockets.

4. **Multi-session snapshots**: Should one snapshot file contain multiple sessions, or one file per session? cmux uses one file for the entire app state. Per-session files are simpler for partial restore. Suggestion: per-session files with a manifest.

5. **Clipboard sync mode**: Should clipboard sync be automatic (like iTerm2's auto mode), manual (user triggers), or configurable? Suggestion: configurable via capabilities, default to "ask" for security.

6. **RendererHealth interval**: How frequently should RendererHealth reports be sent? Too frequent = noise, too infrequent = useless for debugging. The subscription system allows per-client configuration, but what should the minimum be? Suggestion: 1000 ms minimum.

7. **Extension message ordering**: Should extension messages be ordered with respect to core messages, or can they be interleaved? For simplicity, all messages on a connection are strictly ordered. Extensions cannot bypass this.

8. **Silence detection scope**: Should SilenceDetected fire only for panes with recent activity (activity-then-silence pattern), or for any pane that has been silent? The activity-then-silence pattern is more useful (build completion notification). Suggestion: only fire after at least one byte of output has been seen since the last silence notification.
