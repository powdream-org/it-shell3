# 03 - Session and Pane Management Protocol

**Version**: v0.4
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
- **Optional fields**: When a JSON field has no value, the field MUST be omitted from the JSON object. Senders MUST NOT include fields with `null` values. Receivers MUST tolerate both missing keys and `null` values as "absent" (defensive parsing for forward/backward compatibility).
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
| `0x010C` | AttachOrCreateRequest | C -> S | Attach to existing session or create new |
| `0x010D` | AttachOrCreateResponse | S -> C | Attach-or-create result |
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
| `0x0183` | ClientAttached | S -> C | A client attached to a session |
| `0x0184` | ClientDetached | S -> C | A client detached from a session |
| **Window Resize** | | | |
| `0x0190` | WindowResize | C -> S | Client window resized |
| `0x0191` | WindowResizeAck | S -> C | Resize acknowledged |

---

## 1. Session Messages

### 1.1 CreateSessionRequest (0x0100)

Creates a new session. The server spawns a default shell in the initial pane.

```json
{
  "name": "my-session",
  "shell": "/bin/zsh",
  "cwd": "/home/user",
  "cols": 80,
  "rows": 24
}
```

All fields are optional. Omit or use `""` for strings and `0` for integers to use server defaults.

### 1.2 CreateSessionResponse (0x0101)

```json
{
  "status": 0,
  "session_id": 1,
  "pane_id": 1
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = success, non-zero = error code |
| `session_id` | u32 | Valid if status=0 |
| `pane_id` | u32 | ID of initial pane |
| `error` | string | Error description (present only on error) |

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
      "created_at": 1709568000,
      "pane_count": 2,
      "attached_clients": 1
    }
  ]
}
```

### 1.5 AttachSessionRequest (0x0104)

A client connection is attached to **at most one session** at a time. Sending AttachSessionRequest while already attached to a session returns `ERR_SESSION_ALREADY_ATTACHED` (status code 3). To switch sessions, the client MUST first detach (DetachSessionRequest) then attach to the new session. This matches tmux behavior.

```json
{
  "session_id": 1,
  "cols": 80,
  "rows": 24,
  "readonly": false,
  "detach_others": false
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | u32 | Session to attach to |
| `cols` | number | Client terminal columns |
| `rows` | number | Client terminal rows |
| `readonly` | boolean | true = read-only attachment (observer mode). See Section 9 for permissions. |
| `detach_others` | boolean | true = force-detach all other clients from this session |

**`detach_others` behavior**: When `detach_others` is true and other clients are attached to the same session, those clients receive a forced `DetachSessionResponse` with `reason: "force_detached_by_other_client"` and transition back to READY state. The requesting client then attaches normally.

### 1.6 AttachSessionResponse (0x0105)

On success, the server follows this response with:
1. A `LayoutChanged` notification containing the full layout tree (with per-pane `active_input_method` and `active_keyboard_layout` in leaf nodes).
2. A full `FrameUpdate` for each visible pane.
3. If the session has active preedit on any pane, a `PreeditSync` is also sent.
4. A `ClientAttached` notification to all other clients attached to the session.

```json
{
  "status": 0,
  "session_id": 1,
  "name": "my-session",
  "active_pane_id": 1,
  "pane_input_methods": [
    {"pane_id": 1, "active_input_method": "direct", "active_keyboard_layout": "qwerty"},
    {"pane_id": 3, "active_input_method": "korean_2set", "active_keyboard_layout": "qwerty"}
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = success, 1 = session not found, 2 = access denied, 3 = already attached to a session |
| `session_id` | u32 | Session ID |
| `name` | string | Session name |
| `active_pane_id` | u32 | Currently focused pane |
| `pane_input_methods` | array | Per-pane input method state for ALL panes (not just panes with active preedit) |
| `error` | string | Error description (present only on error) |

The `pane_input_methods` array provides newly-attached clients with input method state for ALL panes. This complements `PreeditSync`, which only covers panes with active preedit.

### 1.7 DetachSessionRequest (0x0106)

```json
{
  "session_id": 1
}
```

### 1.8 DetachSessionResponse (0x0107)

This message serves as both a response to client-initiated detach and a server-initiated forced detach notification.

```json
{
  "status": 0,
  "reason": "client_requested"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = success, 1 = not attached to this session |
| `reason` | string | Detach reason (see table below) |
| `error` | string | Error description (present only on error) |

**Detach reason values**:

| Reason | Trigger | Description |
|--------|---------|-------------|
| `"client_requested"` | Client sends DetachSessionRequest | Normal voluntary detach |
| `"force_detached_by_other_client"` | Another client attaches with `detach_others: true` | Evicted by another client |
| `"session_destroyed"` | Session destroyed via DestroySessionRequest | Session no longer exists |

When a client receives a forced DetachSessionResponse (any reason other than `"client_requested"`), it transitions back to the READY state and may auto-attach to another session or present a session picker.

### 1.9 DestroySessionRequest (0x0108)

Destroys a session. All panes are closed (shells receive SIGHUP), all PTYs are freed.

```json
{
  "session_id": 1,
  "force": false
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | u32 | Session to destroy |
| `force` | boolean | true = force-kill even if processes are running |

**Cascade behavior for attached clients**: When a session is destroyed while other clients are attached, the server:

1. Sends `SessionListChanged` with `event: "destroyed"` to ALL connected clients.
2. Sends forced `DetachSessionResponse` with `reason: "session_destroyed"` to every client attached to the destroyed session (except the requesting client, which receives the DestroySessionResponse).
3. Those clients transition back to READY state.
4. Sends `ClientDetached` notification to the requesting client for each detached client.

### 1.10 DestroySessionResponse (0x0109)

```json
{
  "status": 0
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = success, 1 = session not found, 2 = processes still running (and force=false) |
| `error` | string | Error description (present only on error) |

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
  "status": 0
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = success, 1 = session not found, 2 = name already in use |
| `error` | string | Error description (present only on error) |

### 1.13 AttachOrCreateRequest (0x010C)

Attaches to an existing session or creates a new one if it does not exist. Equivalent to tmux's `new-session -A`. Subject to the same single-session-per-connection rule as AttachSessionRequest (returns `ERR_SESSION_ALREADY_ATTACHED` if already attached).

```json
{
  "session_name": "main",
  "cols": 80,
  "rows": 24,
  "shell": "",
  "cwd": ""
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_name` | string | Session name to attach to or create. Empty string = attach to most recently active session, or create a new session with server-generated name if none exist. |
| `cols` | number | Client terminal columns |
| `rows` | number | Client terminal rows |
| `shell` | string | Shell path for new session (only used if creating). Empty = default shell (`$SHELL` or `/bin/sh`). |
| `cwd` | string | Working directory for new session (only used if creating). Empty = `$HOME`. |

**Semantics**: If a session with the given name exists, attach to it. If not, create a new session with that name, then attach. When `session_name` is empty, attach to the most recently active session; if no sessions exist, create a new one with default parameters.

### 1.14 AttachOrCreateResponse (0x010D)

On success, the same post-attach sequence applies as for AttachSessionResponse: LayoutChanged, FrameUpdate, PreeditSync (if applicable), ClientAttached notification.

```json
{
  "action_taken": "attached",
  "session_id": 1,
  "pane_id": 1,
  "session_name": "main",
  "active_pane_id": 1,
  "pane_input_methods": [
    {"pane_id": 1, "active_input_method": "direct", "active_keyboard_layout": "qwerty"}
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `action_taken` | string | `"attached"` or `"created"` |
| `session_id` | u32 | Session ID |
| `pane_id` | u32 | Initial pane ID (only meaningful if `action_taken` = `"created"`) |
| `session_name` | string | Actual session name |
| `active_pane_id` | u32 | Currently focused pane |
| `pane_input_methods` | array | Per-pane input method state (same format as AttachSessionResponse) |
| `error` | string | Error description (present only on error) |

---

## 2. Pane Messages

### 2.1 CreatePaneRequest (0x0140)

Creates a standalone pane in the specified session. This is rarely used directly -- most panes are created via SplitPane. Useful for programmatic session population.

```json
{
  "session_id": 1,
  "shell": "/bin/zsh",
  "cwd": "/home/user"
}
```

`shell` and `cwd` are optional; omit or use `""` for defaults.

**Note**: This replaces the current layout root. If the session already has panes, the new pane becomes the entire layout. To add a pane alongside existing panes, use SplitPane.

**Default input method**: New panes are initialized with `input_method: "direct"` and `keyboard_layout: "qwerty"`. This is normative.

### 2.2 CreatePaneResponse (0x0141)

```json
{
  "status": 0,
  "pane_id": 2
}
```

### 2.3 SplitPaneRequest (0x0142)

Splits an existing pane into two. The existing pane becomes one half; a new pane is spawned in the other half.

```json
{
  "session_id": 1,
  "pane_id": 1,
  "direction": 0,
  "ratio": 0.5,
  "shell": "",
  "cwd": "",
  "focus_new": true
}
```

**Split direction semantics**:
- `right` (0): Vertical split. Original pane becomes left, new pane appears on right.
- `down` (1): Horizontal split. Original pane becomes top, new pane appears on bottom.
- `left` (2): Vertical split. New pane appears on left, original becomes right.
- `up` (3): Horizontal split. New pane appears on top, original becomes bottom.

The `ratio` describes the proportion of space given to the **first** child (the child containing the original pane in a right/down split, or the new pane in a left/up split).

**Default input method**: The new pane is initialized with `input_method: "direct"` and `keyboard_layout: "qwerty"`.

### 2.4 SplitPaneResponse (0x0143)

On success, the server follows with a `LayoutChanged` notification.

```json
{
  "status": 0,
  "new_pane_id": 3
}
```

### 2.5 ClosePaneRequest (0x0144)

Closes a pane. Its shell receives SIGHUP. In the layout tree, the parent split node is replaced by the sibling pane.

```json
{
  "session_id": 1,
  "pane_id": 1,
  "force": false
}
```

| Field | Type | Description |
|-------|------|-------------|
| `force` | boolean | true = SIGKILL if SIGHUP does not terminate within timeout |

### 2.6 ClosePaneResponse (0x0145)

If the closed pane was the last pane in the session, the session is also destroyed. The response indicates what happened.

```json
{
  "status": 0,
  "side_effect": 0,
  "new_focus_pane_id": 2
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = success, 1 = pane not found |
| `side_effect` | number | 0 = none, 1 = session also destroyed |
| `new_focus_pane_id` | u32 | New focused pane (0 if session destroyed) |

### 2.7 FocusPaneRequest (0x0146)

Sets the focused (active) pane within the session.

```json
{
  "session_id": 1,
  "pane_id": 2
}
```

**Preedit interaction**: If the currently focused pane has an active preedit composition (from any client), the server MUST commit the current preedit to the PTY and send `PreeditEnd` with `reason: "focus_changed"` to all attached clients **before** processing the focus change. This prevents composition state from becoming inconsistent when focus moves away from a pane with active IME input. See doc 05 Section 7.7 for the full race condition analysis.

### 2.8 FocusPaneResponse (0x0147)

```json
{
  "status": 0,
  "previous_pane_id": 1
}
```

### 2.9 NavigatePaneRequest (0x0148)

Moves focus to the nearest pane in the given direction from the current focused pane.

```json
{
  "session_id": 1,
  "direction": 0
}
```

**Navigation algorithm**: The server computes the geometric position of each pane from the session's layout tree, then finds the nearest pane in the requested direction from the center of the currently focused pane. If no pane exists in that direction, the focus wraps around (configurable).

**Preedit interaction**: Same rule as FocusPaneRequest — if the current pane has active preedit, commit before navigating. See Section 2.7.

### 2.10 NavigatePaneResponse (0x0149)

```json
{
  "status": 0,
  "focused_pane_id": 2
}
```

### 2.11 ResizePaneRequest (0x014A)

Adjusts the split divider adjacent to a pane. The `direction` indicates which edge to move, and `delta` is the number of cells to move the divider.

```json
{
  "session_id": 1,
  "pane_id": 1,
  "direction": 0,
  "delta": 5
}
```

**Semantics**: A positive delta moves the divider in the stated direction. For example, `direction=right, delta=5` grows the pane 5 columns to the right (shrinking the neighbor). A negative delta moves it in the opposite direction.

### 2.12 ResizePaneResponse (0x014B)

On success, the server follows with a `LayoutChanged` notification.

```json
{
  "status": 0
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = success, 1 = pane not found, 2 = no split in that direction, 3 = minimum size reached |

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
  "status": 0
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
  "status": 0,
  "zoomed": true
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
  "status": 0
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | number | 0 = success, 1 = pane_a not found, 2 = pane_b not found |

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
  "preedit_active": false,
  "active_input_method": "direct",
  "active_keyboard_layout": "qwerty"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"leaf"` |
| `pane_id` | u32 | Pane ID |
| `cols` | number | Pane width in columns |
| `rows` | number | Pane height in rows |
| `x_off` | number | X offset within the session area |
| `y_off` | number | Y offset within the session area |
| `preedit_active` | boolean | Whether preedit composition is active on this pane |
| `active_input_method` | string | Current input method for this pane (e.g., `"direct"`, `"korean_2set"`) |
| `active_keyboard_layout` | string | Current keyboard layout for this pane (e.g., `"qwerty"`) |

**Input method state** in leaf nodes provides authoritative initial/refresh state for input methods. This is one channel of the two-channel input method state model:
1. **LayoutChanged** (this message): Full layout tree with per-pane `active_input_method` + `active_keyboard_layout`. Fires on structural changes (split, close, resize, zoom, swap) and on attach. Provides authoritative initial/refresh state.
2. **InputMethodAck** (0x0405, doc 05): Broadcast to ALL attached clients on input method changes. Carries `pane_id` + new method. Provides incremental updates.

Client state maintenance:
1. Initialize per-pane input method from `LayoutChanged` leaf nodes on attach.
2. Update incrementally from `InputMethodAck` broadcasts.
3. Refresh from `LayoutChanged` on structural changes.

### Split Node

```json
{
  "type": "split",
  "orientation": "horizontal",
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
    "preedit_active": false,
    "active_input_method": "korean_2set",
    "active_keyboard_layout": "qwerty"
  },
  "second": {
    "type": "leaf",
    "pane_id": 2,
    "cols": 40,
    "rows": 24,
    "x_off": 40,
    "y_off": 0,
    "preedit_active": false,
    "active_input_method": "direct",
    "active_keyboard_layout": "qwerty"
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

> **Note on input method state**: LayoutChanged does NOT fire solely for input method changes. Input method changes are communicated via `InputMethodAck` (0x0405, doc 05), which is broadcast to all attached clients. LayoutChanged includes per-pane `active_input_method` and `active_keyboard_layout` in leaf nodes to provide authoritative state on structural changes and attach. See Section 3 for the two-channel model.

### 4.2 PaneMetadataChanged (0x0181)

Sent when a pane's metadata changes. Sources include: OSC title sequences, shell integration CWD reporting, foreground process changes, and process exit.

```json
{
  "session_id": 1,
  "pane_id": 1,
  "title": "vim",
  "cwd": "/home/user/project",
  "process_name": "vim",
  "exit_status": 0,
  "pid": 12345,
  "is_running": true
}
```

Only changed fields are included in the JSON object. Clients detect which fields changed by checking for key presence.

### 4.3 SessionListChanged (0x0182)

Sent to all connected clients when sessions are created or destroyed.

```json
{
  "event": "created",
  "session_id": 1,
  "name": "my-session"
}
```

### 4.4 ClientAttached (0x0183)

Sent to all clients attached to a session when a new client attaches to the same session.

```json
{
  "session_id": 1,
  "client_id": 5,
  "client_name": "iPad-Pro",
  "attached_clients": 3
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | u32 | Affected session |
| `client_id` | u32 | ID of the newly attached client (assigned in ServerHello, see doc 02) |
| `client_name` | string | Human-readable client name (from ClientHello) |
| `attached_clients` | number | Total number of clients now attached to this session |

### 4.5 ClientDetached (0x0184)

Sent to all clients still attached to a session when another client detaches.

```json
{
  "session_id": 1,
  "client_id": 5,
  "client_name": "iPad-Pro",
  "reason": "client_requested",
  "attached_clients": 2
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | u32 | Affected session |
| `client_id` | u32 | ID of the detached client |
| `client_name` | string | Human-readable client name |
| `reason` | string | Why the client detached: `"client_requested"`, `"force_detached_by_other_client"`, `"session_destroyed"`, `"connection_lost"` |
| `attached_clients` | number | Total number of clients still attached to this session |

---

## 5. Window Resize

### 5.1 WindowResize (0x0190)

Sent by the client when its terminal window is resized. The server uses this to cascade-resize all panes in the session.

```json
{
  "session_id": 1,
  "cols": 120,
  "rows": 40,
  "pixel_width": 0,
  "pixel_height": 0
}
```

`pixel_width` and `pixel_height` are optional (0 if unknown). Provided for applications that need sub-cell positioning (e.g., Sixel graphics, Kitty image protocol).

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
| 5 | `ACCESS_DENIED` | Permission denied for this operation (see Section 9) |
| 6 | `INVALID_ARGUMENT` | Invalid field value |
| 7 | `INTERNAL_ERROR` | Unexpected server error |

These are common status codes shared across multiple response messages. Individual messages may assign message-specific meanings to certain codes (e.g., AttachSessionResponse uses status 3 for "already attached to a session" rather than TOO_SMALL).

> **Two-layer error model**: Per-message `status` codes (above) are distinct from protocol-level `error_code` values in the Error message (`0x00FF`, see doc 01). Response `status` codes handle expected failure cases (session not found, already attached, etc.) within typed response messages. The Error message (`0x00FF`) handles unexpected or cross-cutting errors where the server cannot produce a typed response (unknown message type, malformed payload, state violations). For expected failures, the server SHOULD send the typed response with an appropriate status code, NOT a formal Error message.

**ERR_ACCESS_DENIED (0x00000203)**: Returned when a readonly client attempts a prohibited operation. See Section 9 for the full permissions table. The server sends the typed response (e.g., FocusPaneResponse) with `status: 5`, not a formal Error message.

**ERR_SESSION_ALREADY_ATTACHED (0x00000201)**: A client connection is attached to at most one session at a time. Sending AttachSessionRequest or AttachOrCreateRequest while already attached returns `status: 3` in AttachSessionResponse. The client must first detach via DetachSessionRequest.

---

## 7. Sequence Number Correlation

All request/response pairs share the same `sequence` number from the message header. The client assigns monotonically increasing sequence numbers to outgoing requests. The server echoes the sequence number in the corresponding response (with the RESPONSE flag set).

Notifications (LayoutChanged, PaneMetadataChanged, etc.) use the server's next monotonic sequence number. Notifications are identifiable by their message type — notification types (0x0180-0x0184) are distinct from request/response types. Sequence number 0 is never sent on the wire; it is used only as a sentinel value in payload fields (e.g., `ref_sequence = 0` in Error messages means "no specific message triggered this error").

A notification that is a direct consequence of a request (e.g., LayoutChanged after SplitPane) is sent AFTER the response message, so the client can process the response first and then update the layout.

**Ordering guarantee**: For a given client connection, messages are delivered in order. The server never sends a response for request N+1 before the response for request N.

---

## 8. Multi-Client Behavior

Multiple clients can be attached to the same session simultaneously.

### Focus Model

**Decision for v1**: Per-session focus (like tmux). All clients share the same active pane. This simplifies the protocol and matches the multiplexer mental model. Per-client focus can be added later as an opt-in capability.

- FocusPane and NavigatePane change the session's active pane, affecting all attached clients.
- All attached clients receive a LayoutChanged notification when focus changes.
- **Preedit interaction**: Focus changes commit active preedit before processing. See Section 2.7.

### Layout Mutations

- SplitPane, ClosePane, ResizePane, etc., affect the shared layout.
- All attached clients receive the resulting LayoutChanged notification.

### Window Size

The effective terminal size for a session is `min(cols)` x `min(rows)` across all attached clients. See Section 5.1 for the resize algorithm and detach behavior.

### Input Method State

Input method state is maintained per-pane and preserved across detach/reattach:
- When a client detaches, pane input method states are not reset.
- When a client attaches, it receives per-pane input method state in `AttachSessionResponse.pane_input_methods` and in `LayoutChanged` leaf nodes.
- Input method changes are broadcast to all attached clients via `InputMethodAck` (0x0405, doc 05).

---

## 9. Readonly Client Permissions

When a client attaches with `readonly: true`, it operates in observer mode. The server enforces the following permissions:

### Permitted Messages (readonly MAY send)

| Category | Messages |
|----------|----------|
| Session queries | ListSessionsRequest, LayoutGetRequest |
| Viewport | ScrollRequest, MouseScroll |
| Connection management | Heartbeat, Disconnect, DetachSessionRequest, ClientDisplayInfo, Subscribe, Unsubscribe |
| Search | SearchRequest |

### Prohibited Messages (readonly MUST NOT send)

| Category | Messages |
|----------|----------|
| Input | KeyEvent, TextInput, MouseButton, PasteData |
| IME | InputMethodSwitch |
| Session/pane mutation | CreateSessionRequest, DestroySessionRequest, RenameSessionRequest, AttachOrCreateRequest (with create semantics) |
| Pane mutation | CreatePaneRequest, SplitPaneRequest, ClosePaneRequest, FocusPaneRequest, NavigatePaneRequest, ResizePaneRequest, EqualizeSplitsRequest, ZoomPaneRequest, SwapPanesRequest |
| Window | WindowResize |
| Persistence | SnapshotRequest, RestoreSessionRequest |
| Clipboard (write) | ClipboardWriteFromClient |

When a readonly client sends a prohibited message, the server responds with `ERR_ACCESS_DENIED` (status code 5, error code `0x00000203`).

### Readonly Receives

Readonly clients receive ALL server-to-client messages, including:
- FrameUpdate (full terminal content)
- LayoutChanged, PaneMetadataChanged, SessionListChanged
- ClientAttached, ClientDetached
- Preedit broadcasts: PreeditStart, PreeditUpdate, PreeditEnd, PreeditSync, InputMethodAck (as observer — they see composition from other clients)
- Flow control: PausePane, OutputQueueStatus
- Subscribed notifications

---

## 10. Open Questions

1. **Last-pane-close behavior**: Should closing the last pane in a session auto-destroy the session? Current design: yes, the session is destroyed when its last pane is closed (ClosePaneResponse `side_effect = 1`).

2. **Pane minimum size**: What is the minimum pane size below which splits are rejected? Suggestion: 2 columns x 1 row (matching tmux's minimum).

3. **Session auto-destroy**: Should sessions with no attached clients be destroyed after a timeout? Current design: never (daemon keeps sessions alive indefinitely until explicitly destroyed or the daemon exits).

4. **Zoom + split interaction**: If a pane is zoomed and the user requests a split, should we unzoom first and then split? Or reject the split while zoomed? tmux unzooms, which seems correct.

5. **Layout tree compression**: For deep trees or large numbers of panes, should we support a compressed layout wire format? The current JSON format is readable but verbose for large trees. This can be deferred -- the maximum practical size (~50 panes) would be under a few KB of JSON.

6. **Pane reuse after exit**: When a shell process exits, should the pane remain visible (showing exit status) until explicitly closed, or auto-close? tmux has the `remain-on-exit` option. We should support both modes via per-pane or per-session configuration.

---

## Changelog

### v0.4 (2026-03-04)

- **AttachOrCreateRequest (0x010C/0x010D)** (Issue 7): New message pair for "attach if exists, create otherwise" semantics. Equivalent to tmux `new-session -A`. Subject to single-session-per-connection rule.
- **Input method state in layout tree** (Issue 6): Added `active_input_method` and `active_keyboard_layout` to leaf nodes in the layout tree wire format (Section 3). Two-channel state model: LayoutChanged provides authoritative state on structural changes; InputMethodAck (doc 05) provides incremental updates.
- **Default input method for new panes** (Issue 6): New panes are initialized with `input_method: "direct"`, `keyboard_layout: "qwerty"`. Normative.
- **InputMethodAck broadcast** (Issue 6): InputMethodAck (0x0405) is broadcast to ALL attached clients on input method changes (referenced from doc 05).
- **Per-pane input method in AttachSessionResponse** (Issue 6): Added `pane_input_methods` array to AttachSessionResponse and AttachOrCreateResponse for newly-attached clients.
- **Focus change commits active preedit** (Issue 9/Gap 3): FocusPaneRequest and NavigatePaneRequest now require the server to commit active preedit and send PreeditEnd with `reason: "focus_changed"` before processing the focus change.
- **ClientAttached (0x0183) / ClientDetached (0x0184)** (Issue 9/Gap 4): New notification messages sent to all clients attached to a session when another client joins or leaves.
- **ERR_SESSION_ALREADY_ATTACHED** (Issue 9/Gap 5): AttachSessionRequest and AttachOrCreateRequest return status 3 when the client is already attached to a session. Protocol-level Error message uses error code `0x00000201`. Client must detach first.
- **DestroySession cascade** (Issue 9/Gap 6): Defined behavior when destroying a session with attached clients: forced DetachSessionResponse with `reason: "session_destroyed"`, SessionListChanged, ClientDetached notifications.
- **Readonly permissions table** (Issue 9/Gap 7): Added Section 9 defining which messages readonly clients may and may not send. ERR_ACCESS_DENIED (error code 0x00000203) for prohibited operations.
- **Forced DetachSessionResponse reasons** (Issue 9/Gap 8): DetachSessionResponse now includes a `reason` field with values: `"client_requested"`, `"force_detached_by_other_client"`, `"session_destroyed"`.
- **Optional field convention** (Issue 3): Applied JSON optional field convention — absent fields are omitted, never null.

### v0.3 (2026-03-04)

- **JSON encoding**: All session/pane management payloads now explicitly use JSON encoding. Added Encoding section and converted all message definitions from binary field tables to JSON examples. Rationale from review-notes-02 Round 3 consensus (hybrid encoding: binary for CellData, JSON for control messages).
- **Cursor blink**: Added normative note (Overview section) that cursor blink is client-side. Server sends cursor state; client implements blink timing locally.
- **Layout tree format**: Converted layout tree wire format from binary (depth-first pre-order with byte offsets) to JSON object representation, consistent with the JSON encoding decision.

### v0.2 (2026-03-04)

- Initial draft with binary field-level encoding for all messages.
