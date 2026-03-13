# 03 - Session and Pane Management Protocol

**Version**: v0.3
**Status**: Draft
**Date**: 2026-03-04
**Author**: systems-engineer (AI-assisted)

## Overview

This document specifies the wire protocol for managing the Session > Pane hierarchy in libitshell3. Each Session owns a single binary split tree of Panes. There is no intermediate "Tab" protocol entity — the host application (e.g., ghostty) provides tab management in its own UI, mapping each libitshell3 Session to one host tab.

### UI Tab Actions and Protocol Mapping

Tabs still exist visually in the client UI. The protocol models them as Sessions:

| UI Action | Protocol Message | Notes |
|-----------|-----------------|-------|
| New tab | `CreateSessionRequest` | Creates a new session with an initial pane |
| Close tab | `DestroySessionRequest` | Destroys the session and all its panes |
| Switch tab | Client-side only | Client switches which attached session it renders; no protocol message needed |
| Rename tab | `RenameSessionRequest` | Renames the session |
| Reorder tabs | Client-side only | Tab display order is a client UI concern, not server state |
| List tabs | `ListSessionsRequest` | Returns all sessions (the client renders them as tabs) |

All messages use the binary framing defined in document 01 (16-byte header: magic(2) + version(1) + flags(1) + msg_type(2) + reserved(2) + payload_len(4) + sequence(4), little-endian byte order).

Message type range: `0x0100` - `0x01FF` (session/pane management).

### Encoding

All session and pane management messages (this document) use **JSON payloads**. The binary framing header (16 bytes) wraps a JSON object as the payload body. Field names in the JSON object correspond to the field names specified in each message definition below.

> **Rationale**: Session/pane management messages are low-frequency control messages. JSON encoding provides debuggability (`socat | jq`), schema evolution via optional fields, and straightforward cross-language support (Swift `JSONDecoder`, etc.). See review-notes-02 Round 3 for the full analysis.

### Conventions

- All multi-byte integers in the binary header are little-endian.
- Payload bodies are UTF-8 JSON objects.
- Boolean fields use JSON `true`/`false`.
- String fields are JSON strings (UTF-8).
- Integer fields are JSON numbers.
- `payload_len` in the header is the JSON payload size in bytes (NOT including the 16-byte header). Total message size on wire = 16 + payload_len.
- All request messages expect a corresponding response message. The response carries the same sequence number as the request for correlation (RESPONSE flag = 1).
- Directions use integers: 0 = right, 1 = down, 2 = left, 3 = up (matches ghostty's `GHOSTTY_SPLIT_DIRECTION`).
- Ratios are floating-point numbers in the range [0.0, 1.0].

### ID Types

| Type | JSON Type | Description |
|------|-----------|-------------|
| `session_id` | number (u32) | Server-assigned, monotonically increasing. Never reused during daemon lifetime. |
| `pane_id` | number (u32) | Server-assigned, monotonically increasing. Never reused during daemon lifetime. |

ID counters are per-type: session IDs and pane IDs use independent counters (session 1 and pane 1 can coexist). ID 0 is reserved as a sentinel value (meaning "none" or "invalid").

### Cursor Blink

> **Normative note**: Cursor blink is a **client-side** concern. The server sends cursor state (style, visibility, position) in FrameUpdate (doc 04). The client is responsible for implementing blink timing locally. The server never sends blink timer state or blink-phase information. This avoids coupling frame delivery cadence to cosmetic cursor animation.

---

## Message Type Assignments

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| **Session Messages** | | | |
| `0x0100` | CreateSessionRequest | C -> S | Create a new session |
| `0x0101` | CreateSessionResponse | S -> C | Result of session creation |
| `0x0102` | ListSessionsRequest | C -> S | List all sessions |
| `0x0103` | ListSessionsResponse | S -> C | Session list |
| `0x0104` | AttachSessionRequest | C -> S | Attach client to session |
| `0x0105` | AttachSessionResponse | S -> C | Attach result |
| `0x0106` | DetachSessionRequest | C -> S | Detach client from session |
| `0x0107` | DetachSessionResponse | S -> C | Detach result |
| `0x0108` | DestroySessionRequest | C -> S | Destroy a session |
| `0x0109` | DestroySessionResponse | S -> C | Destroy result |
| `0x010A` | RenameSessionRequest | C -> S | Rename a session |
| `0x010B` | RenameSessionResponse | S -> C | Rename result |
| **Pane Messages** | | | |
| `0x0140` | CreatePaneRequest | C -> S | Create a standalone pane in a session |
| `0x0141` | CreatePaneResponse | S -> C | Result of pane creation |
| `0x0142` | SplitPaneRequest | C -> S | Split an existing pane |
| `0x0143` | SplitPaneResponse | S -> C | Split result |
| `0x0144` | ClosePaneRequest | C -> S | Close a pane |
| `0x0145` | ClosePaneResponse | S -> C | Close result |
| `0x0146` | FocusPaneRequest | C -> S | Set focused pane |
| `0x0147` | FocusPaneResponse | S -> C | Focus result |
| `0x0148` | NavigatePaneRequest | C -> S | Move focus in a direction |
| `0x0149` | NavigatePaneResponse | S -> C | Navigate result (new focused pane) |
| `0x014A` | ResizePaneRequest | C -> S | Adjust split divider |
| `0x014B` | ResizePaneResponse | S -> C | Resize result |
| `0x014C` | EqualizeSplitsRequest | C -> S | Equalize all splits in a session |
| `0x014D` | EqualizeSplitsResponse | S -> C | Equalize result |
| `0x014E` | ZoomPaneRequest | C -> S | Toggle pane zoom |
| `0x014F` | ZoomPaneResponse | S -> C | Zoom result |
| `0x0150` | SwapPanesRequest | C -> S | Swap two panes |
| `0x0151` | SwapPanesResponse | S -> C | Swap result |
| `0x0152` | LayoutGetRequest | C -> S | Query current layout tree |
| `0x0153` | LayoutGetResponse | S -> C | Current layout tree |
| **Notifications (Server -> Client)** | | | |
| `0x0180` | LayoutChanged | S -> C | Layout tree updated |
| `0x0181` | PaneMetadataChanged | S -> C | Pane metadata updated |
| `0x0182` | SessionListChanged | S -> C | Session list changed |
| **Window Resize** | | | |
| `0x0190` | WindowResize | C -> S | Client window resized |
| `0x0191` | WindowResizeAck | S -> C | Resize acknowledged |

---

## 1. Session Messages

### 1.1 CreateSessionRequest (0x0100)

Creates a new session. The server spawns a default shell in the initial pane.

```json
{
  "name": "my-session",       // string, optional (omit or "" for server default)
  "shell": "/bin/zsh",        // string, optional (omit or "" for default shell)
  "cwd": "/home/user",        // string, optional (omit or "" for default)
  "cols": 80,                 // number, optional (0 or omit = server decides)
  "rows": 24                  // number, optional (0 or omit = server decides)
}
```

### 1.2 CreateSessionResponse (0x0101)

```json
{
  "status": 0,                // 0 = success, non-zero = error code
  "session_id": 1,            // u32, valid if status=0
  "pane_id": 1,               // u32, ID of initial pane
  "error": ""                 // string, error description (empty if success)
}
```

### 1.3 ListSessionsRequest (0x0102)

No payload. The JSON body is an empty object `{}`.

### 1.4 ListSessionsResponse (0x0103)

```json
{
  "status": 0,
  "sessions": [
    {
      "session_id": 1,
      "name": "my-session",
      "created_at": 1709568000,   // Unix timestamp (seconds)
      "pane_count": 2,
      "client_count": 1
    }
  ]
}
```

### 1.5 AttachSessionRequest (0x0104)

```json
{
  "session_id": 1,
  "cols": 80,                 // client terminal columns
  "rows": 24,                 // client terminal rows
  "readonly": false           // true = read-only attachment (observer mode)
}
```

### 1.6 AttachSessionResponse (0x0105)

On success, the server follows this response with a `LayoutChanged` notification containing the full layout tree and a full `FrameUpdate` for each visible pane. If the session has active preedit on any pane, a `PreeditSync` is also sent.

```json
{
  "status": 0,                // 0 = success, 1 = session not found, 2 = access denied
  "session_id": 1,
  "name": "my-session",
  "active_pane_id": 1,
  "error": ""
}
```

### 1.7 DetachSessionRequest (0x0106)

```json
{
  "session_id": 1
}
```

### 1.8 DetachSessionResponse (0x0107)

```json
{
  "status": 0,                // 0 = success, 1 = not attached to this session
  "error": ""
}
```

### 1.9 DestroySessionRequest (0x0108)

Destroys a session. All panes are closed (shells receive SIGHUP), all PTYs are freed.

```json
{
  "session_id": 1,
  "force": false              // true = force-kill even if processes are running
}
```

### 1.10 DestroySessionResponse (0x0109)

```json
{
  "status": 0,                // 0 = success, 1 = session not found, 2 = processes still running (and force=false)
  "error": ""
}
```

### 1.11 RenameSessionRequest (0x010A)

```json
{
  "session_id": 1,
  "name": "new-name"
}
```

### 1.12 RenameSessionResponse (0x010B)

```json
{
  "status": 0,                // 0 = success, 1 = session not found, 2 = name already in use
  "error": ""
}
```

---

## 2. Pane Messages

### 2.1 CreatePaneRequest (0x0140)

Creates a standalone pane in the specified session. This is rarely used directly -- most panes are created via SplitPane. Useful for programmatic session population.

```json
{
  "session_id": 1,
  "shell": "/bin/zsh",        // optional, "" or omit for default
  "cwd": "/home/user"         // optional, "" or omit for default
}
```

**Note**: This replaces the current layout root. If the session already has panes, the new pane becomes the entire layout. To add a pane alongside existing panes, use SplitPane.

### 2.2 CreatePaneResponse (0x0141)

```json
{
  "status": 0,                // 0 = success, 1 = session not found
  "pane_id": 2,
  "error": ""
}
```

### 2.3 SplitPaneRequest (0x0142)

Splits an existing pane into two. The existing pane becomes one half; a new pane is spawned in the other half.

```json
{
  "session_id": 1,
  "pane_id": 1,
  "direction": 0,             // 0=right, 1=down, 2=left, 3=up
  "ratio": 0.5,               // initial split ratio (proportion of first child)
  "shell": "",                 // optional, shell path for new pane
  "cwd": "",                   // optional, working directory (empty = inherit)
  "focus_new": true            // true = focus new pane, false = keep focus on original
}
```

**Split direction semantics**:
- `right` (0): Vertical split. Original pane becomes left, new pane appears on right.
- `down` (1): Horizontal split. Original pane becomes top, new pane appears on bottom.
- `left` (2): Vertical split. New pane appears on left, original becomes right.
- `up` (3): Horizontal split. New pane appears on top, original becomes bottom.

The `ratio` describes the proportion of space given to the **first** child (the child containing the original pane in a right/down split, or the new pane in a left/up split).

### 2.4 SplitPaneResponse (0x0143)

On success, the server follows with a `LayoutChanged` notification.

```json
{
  "status": 0,                // 0 = success, 1 = pane not found, 2 = too small to split
  "new_pane_id": 3,
  "error": ""
}
```

### 2.5 ClosePaneRequest (0x0144)

Closes a pane. Its shell receives SIGHUP. In the layout tree, the parent split node is replaced by the sibling pane.

```json
{
  "session_id": 1,
  "pane_id": 1,
  "force": false              // true = SIGKILL if SIGHUP does not terminate within timeout
}
```

### 2.6 ClosePaneResponse (0x0145)

If the closed pane was the last pane in the session, the session is also destroyed. The response indicates what happened.

```json
{
  "status": 0,                // 0 = success, 1 = pane not found
  "side_effect": 0,           // 0 = none, 1 = session also destroyed
  "new_focus_pane_id": 2,     // new focused pane (0 if session destroyed)
  "error": ""
}
```

### 2.7 FocusPaneRequest (0x0146)

Sets the focused (active) pane within the session.

```json
{
  "session_id": 1,
  "pane_id": 2
}
```

### 2.8 FocusPaneResponse (0x0147)

```json
{
  "status": 0,                // 0 = success, 1 = pane not found
  "previous_pane_id": 1,
  "error": ""
}
```

### 2.9 NavigatePaneRequest (0x0148)

Moves focus to the nearest pane in the given direction from the current focused pane.

```json
{
  "session_id": 1,
  "direction": 0              // 0=right, 1=down, 2=left, 3=up
}
```

**Navigation algorithm**: The server computes the geometric position of each pane from the session's layout tree, then finds the nearest pane in the requested direction from the center of the currently focused pane. If no pane exists in that direction, the focus wraps around (configurable).

### 2.10 NavigatePaneResponse (0x0149)

```json
{
  "status": 0,                // 0 = success, 1 = no pane in that direction
  "focused_pane_id": 2,
  "error": ""
}
```

### 2.11 ResizePaneRequest (0x014A)

Adjusts the split divider adjacent to a pane. The `direction` indicates which edge to move, and `delta` is the number of cells to move the divider.

```json
{
  "session_id": 1,
  "pane_id": 1,
  "direction": 0,             // edge to move: 0=right, 1=down, 2=left, 3=up
  "delta": 5                  // number of cells to move (signed integer)
}
```

**Semantics**: A positive delta moves the divider in the stated direction. For example, `direction=right, delta=5` grows the pane 5 columns to the right (shrinking the neighbor). A negative delta moves it in the opposite direction.

### 2.12 ResizePaneResponse (0x014B)

On success, the server follows with a `LayoutChanged` notification.

```json
{
  "status": 0,                // 0 = success, 1 = pane not found, 2 = no split in that direction, 3 = minimum size reached
  "error": ""
}
```

### 2.13 EqualizeSplitsRequest (0x014C)

Sets all split ratios in a session's layout tree to 0.5 (equal distribution).

```json
{
  "session_id": 1
}
```

### 2.14 EqualizeSplitsResponse (0x014D)

On success, the server follows with a `LayoutChanged` notification.

```json
{
  "status": 0,                // 0 = success, 1 = session not found
  "error": ""
}
```

### 2.15 ZoomPaneRequest (0x014E)

Toggles zoom on a pane. When zoomed, the pane fills the entire session area. Other panes in the session are hidden but their PTYs continue running.

```json
{
  "session_id": 1,
  "pane_id": 1
}
```

### 2.16 ZoomPaneResponse (0x014F)

On success, the server follows with a `LayoutChanged` notification (with a flag indicating zoom state).

```json
{
  "status": 0,                // 0 = success, 1 = pane not found
  "zoomed": true,             // true = pane is now zoomed, false = unzoomed
  "error": ""
}
```

### 2.17 SwapPanesRequest (0x0150)

Swaps two panes in the layout tree. The PTY and shell process follow the pane -- only the position in the layout tree changes. Preedit state (if active) follows the pane.

```json
{
  "session_id": 1,
  "pane_a": 1,
  "pane_b": 2
}
```

### 2.18 SwapPanesResponse (0x0151)

On success, the server follows with a `LayoutChanged` notification.

```json
{
  "status": 0,                // 0 = success, 1 = pane_a not found, 2 = pane_b not found
  "error": ""
}
```

### 2.19 LayoutGetRequest (0x0152)

Requests the current layout tree for a session. Use case: client wants to refresh layout state after missing a notification, or a monitoring tool queries layout on demand.

```json
{
  "session_id": 1
}
```

### 2.20 LayoutGetResponse (0x0153)

Returns the same payload format as `LayoutChanged` (Section 4.1), with the RESPONSE flag set and echoing the request's sequence number.

---

## 3. Layout Tree Wire Format

The layout tree is a recursive binary tree serialized as a JSON object in a depth-first structure. Each node is either a **leaf** (pane) or a **split** (branch with exactly two children).

### Leaf Node (Pane)

```json
{
  "type": "leaf",
  "pane_id": 1,
  "cols": 40,
  "rows": 24,
  "x_off": 0,
  "y_off": 0,
  "preedit_active": false
}
```

### Split Node

```json
{
  "type": "split",
  "orientation": "horizontal",   // "horizontal" (left-right) or "vertical" (top-bottom)
  "ratio": 0.5,
  "cols": 80,
  "rows": 24,
  "x_off": 0,
  "y_off": 0,
  "first": { /* child node */ },
  "second": { /* child node */ }
}
```

### Example

A session with two panes side by side (80x24 total, 40 columns each):

```json
{
  "type": "split",
  "orientation": "horizontal",
  "ratio": 0.5,
  "cols": 80,
  "rows": 24,
  "x_off": 0,
  "y_off": 0,
  "first": {
    "type": "leaf",
    "pane_id": 1,
    "cols": 40,
    "rows": 24,
    "x_off": 0,
    "y_off": 0,
    "preedit_active": false
  },
  "second": {
    "type": "leaf",
    "pane_id": 2,
    "cols": 40,
    "rows": 24,
    "x_off": 40,
    "y_off": 0,
    "preedit_active": false
  }
}
```

### Maximum Tree Depth

The server enforces a maximum tree depth of 16 levels. This allows up to 65,536 panes theoretically (though practical limits are much lower due to minimum pane sizes). Clients must be prepared to handle trees up to this depth.

---

## 4. Notifications

### 4.1 LayoutChanged (0x0180)

Sent by the server whenever the layout tree changes (split, close, resize, swap, zoom, window resize). This is the authoritative representation of the current layout.

```json
{
  "session_id": 1,
  "active_pane_id": 1,
  "zoomed_pane_present": false,
  "zoomed_pane_id": 0,
  "layout_tree": { /* layout tree object (Section 3) */ }
}
```

**Delivery rules**:
- Sent to all clients attached to the affected session.
- After AttachSession success, one LayoutChanged is sent for the session.
- After SplitPane, ClosePane, ResizePane, EqualizeSplits, ZoomPane, SwapPanes, or WindowResize, one LayoutChanged is sent for the affected session.

### 4.2 PaneMetadataChanged (0x0181)

Sent when a pane's metadata changes. Sources include: OSC title sequences, shell integration CWD reporting, foreground process changes, and process exit.

```json
{
  "session_id": 1,
  "pane_id": 1,
  "title": "vim",                    // present only if changed
  "cwd": "/home/user/project",       // present only if changed
  "process_name": "vim",             // present only if changed
  "exit_status": 0,                  // present only if changed (negative = killed by signal)
  "pid": 12345,                      // present only if changed (foreground process PID)
  "is_running": true                 // present only if changed
}
```

Only changed fields are included in the JSON object. Clients detect which fields changed by checking for key presence.

### 4.3 SessionListChanged (0x0182)

Sent to all connected clients when sessions are created or destroyed.

```json
{
  "event": "created",           // "created" or "destroyed"
  "session_id": 1,
  "name": "my-session"
}
```

---

## 5. Window Resize

### 5.1 WindowResize (0x0190)

Sent by the client when its terminal window is resized. The server uses this to cascade-resize all panes in the session.

```json
{
  "session_id": 1,
  "cols": 120,
  "rows": 40,
  "pixel_width": 0,            // 0 if unknown
  "pixel_height": 0            // 0 if unknown
}
```

**Multi-client resize algorithm**:

When multiple clients are attached to the same session, the effective terminal size is `min(cols)` x `min(rows)` across all attached clients (like tmux). This ensures no client sees clipped content.

```
1. Update the sending client's recorded dimensions.
2. Recompute effective_cols = min(client.cols for all attached clients).
3. Recompute effective_rows = min(client.rows for all attached clients).
4. If (effective_cols, effective_rows) changed:
   a. Walk the layout tree, recompute pane dimensions based on split ratios.
   b. For each pane with changed dimensions:
      ioctl(pane.pty_fd, TIOCSWINSZ, &new_size)
   c. Send LayoutChanged to ALL attached clients.
   d. Send FrameUpdate for each pane whose content changed.
5. Send WindowResizeAck to the sending client.
```

When a client **detaches**:
```
1. Remove the client's dimensions from the tracking set.
2. Recompute effective size (may increase if the detaching client had
   the smallest dimensions).
3. If size changed: resize cascade (same as step 4 above).
```

Per-client viewports (where each client uses its own terminal dimensions independently) are deferred to v2.

Pixel dimensions are provided for applications that need sub-cell positioning (e.g., Sixel graphics, Kitty image protocol).

### 5.2 WindowResizeAck (0x0191)

```json
{
  "status": 0
}
```

---

## 6. Error Codes

Status codes used across all response messages:

| Code | Name | Description |
|------|------|-------------|
| 0 | `OK` | Success |
| 1 | `NOT_FOUND` | Referenced entity (session/pane) not found |
| 2 | `ALREADY_EXISTS` | Name collision or duplicate operation |
| 3 | `TOO_SMALL` | Cannot split -- pane below minimum size |
| 4 | `PROCESSES_RUNNING` | Cannot destroy -- processes still active |
| 5 | `ACCESS_DENIED` | Permission denied for this operation |
| 6 | `INVALID_ARGUMENT` | Invalid field value |
| 7 | `INTERNAL_ERROR` | Unexpected server error |

Each message type may map specific status values (e.g., DestroySession uses 2 for "processes running"), but the error codes above are the canonical set. The `error` string provides a human-readable description.

---

## 7. Sequence Number Correlation

All request/response pairs share the same `sequence` number from the message header. The client assigns monotonically increasing sequence numbers to outgoing requests. The server echoes the sequence number in the corresponding response (with the RESPONSE flag set).

Notifications (LayoutChanged, PaneMetadataChanged, etc.) use the server's next monotonic sequence number. Notifications are identifiable by their message type — notification types (0x0180-0x0183) are distinct from request/response types. Sequence number 0 is never sent on the wire; it is used only as a sentinel value in payload fields (e.g., `ref_sequence = 0` in Error messages means "no specific message triggered this error").

A notification that is a direct consequence of a request (e.g., LayoutChanged after SplitPane) is sent AFTER the response message, so the client can process the response first and then update the layout.

**Ordering guarantee**: For a given client connection, messages are delivered in order. The server never sends a response for request N+1 before the response for request N.

---

## 8. Multi-Client Behavior

Multiple clients can be attached to the same session simultaneously.

### Focus Model

**Decision for v1**: Per-session focus (like tmux). All clients share the same active pane. This simplifies the protocol and matches the multiplexer mental model. Per-client focus can be added later as an opt-in capability.

- FocusPane and NavigatePane change the session's active pane, affecting all attached clients.
- All attached clients receive a LayoutChanged notification when focus changes.

### Layout Mutations

- SplitPane, ClosePane, ResizePane, etc., affect the shared layout.
- All attached clients receive the resulting LayoutChanged notification.

### Window Size

The effective terminal size for a session is `min(cols)` x `min(rows)` across all attached clients. See Section 5.1 for the resize algorithm and detach behavior.

---

## 9. Open Questions

1. **Last-pane-close behavior**: Should closing the last pane in a session auto-destroy the session? Current design: yes, the session is destroyed when its last pane is closed (ClosePaneResponse `side_effect = 1`).

2. **Pane minimum size**: What is the minimum pane size below which splits are rejected? Suggestion: 2 columns x 1 row (matching tmux's minimum).

3. **Session auto-destroy**: Should sessions with no attached clients be destroyed after a timeout? Current design: never (daemon keeps sessions alive indefinitely until explicitly destroyed or the daemon exits).

4. **Zoom + split interaction**: If a pane is zoomed and the user requests a split, should we unzoom first and then split? Or reject the split while zoomed? tmux unzooms, which seems correct.

5. **Layout tree compression**: For deep trees or large numbers of panes, should we support a compressed layout wire format? The current JSON format is readable but verbose for large trees. This can be deferred -- the maximum practical size (~50 panes) would be under a few KB of JSON.

6. **Pane reuse after exit**: When a shell process exits, should the pane remain visible (showing exit status) until explicitly closed, or auto-close? tmux has the `remain-on-exit` option. We should support both modes via per-pane or per-session configuration.

---

## Changelog

### v0.3 (2026-03-04)

- **JSON encoding**: All session/pane management payloads now explicitly use JSON encoding. Added Encoding section and converted all message definitions from binary field tables to JSON examples. Rationale from review-notes-02 Round 3 consensus (hybrid encoding: binary for CellData, JSON for control messages).
- **Cursor blink**: Added normative note (Overview section) that cursor blink is client-side. Server sends cursor state; client implements blink timing locally.
- **Layout tree format**: Converted layout tree wire format from binary (depth-first pre-order with byte offsets) to JSON object representation, consistent with the JSON encoding decision.

### v0.2 (2026-03-04)

- Initial draft with binary field-level encoding for all messages.
