# Session and Pane Management Protocol

- **Date**: 2026-03-15

## Overview

This document specifies the wire protocol for managing the Session > Pane
hierarchy in libitshell3. Each Session owns a single binary split tree of Panes.
There is no intermediate "Tab" protocol entity — the host application (e.g.,
ghostty) provides tab management in its own UI, mapping each libitshell3 Session
to one host tab.

### UI Tab Actions and Protocol Mapping

Tabs still exist visually in the client UI. The protocol models them as
Sessions:

| UI Action    | Protocol Message        | Notes                                                                         |
| ------------ | ----------------------- | ----------------------------------------------------------------------------- |
| New tab      | `CreateSessionRequest`  | Creates a new session with an initial pane                                    |
| Close tab    | `DestroySessionRequest` | Destroys the session and all its panes                                        |
| Switch tab   | Client-side only        | Client switches which attached session it renders; no protocol message needed |
| Rename tab   | `RenameSessionRequest`  | Renames the session                                                           |
| Reorder tabs | Client-side only        | Tab display order is a client UI concern, not server state                    |
| List tabs    | `ListSessionsRequest`   | Returns all sessions (the client renders them as tabs)                        |

All messages use the binary framing defined in document 01 (16-byte header:
magic(2) + version(1) + flags(1) + msg_type(2) + reserved(2) + payload_len(4) +
sequence(4), little-endian byte order).

Message type range: `0x0100` - `0x01FF` (session/pane management).

### Encoding

All session and pane management messages (this document) use **JSON payloads**.
The binary framing header (16 bytes) wraps a JSON object as the payload body.
Field names in the JSON object correspond to the field names specified in each
message definition below.

### Conventions

See [Doc 01](./01-protocol-overview.md) for common wire conventions (byte order,
JSON payload rules, optional field convention, sequence number correlation).

- Directions use integers: 0 = right, 1 = down, 2 = left, 3 = up (matches
  ghostty's `GHOSTTY_SPLIT_DIRECTION`).
- Ratios are floating-point numbers in the range [0.0, 1.0].

### ID Types

| Type         | JSON Type    | Description                                                                     |
| ------------ | ------------ | ------------------------------------------------------------------------------- |
| `session_id` | number (u32) | Server-assigned, monotonically increasing. Never reused during daemon lifetime. |
| `pane_id`    | number (u32) | Server-assigned, monotonically increasing. Never reused during daemon lifetime. |

ID counters are per-type: session IDs and pane IDs use independent counters
(session 1 and pane 1 can coexist). ID 0 is reserved as a sentinel value
(meaning "none" or "invalid").

---

## Message Type Assignments

### Session Messages

| Type Code | Name                   | Direction | Description                              |
| --------- | ---------------------- | --------- | ---------------------------------------- |
| `0x0100`  | CreateSessionRequest   | C -> S    | Create a new session                     |
| `0x0101`  | CreateSessionResponse  | S -> C    | Result of session creation               |
| `0x0102`  | ListSessionsRequest    | C -> S    | List all sessions                        |
| `0x0103`  | ListSessionsResponse   | S -> C    | Session list                             |
| `0x0104`  | AttachSessionRequest   | C -> S    | Attach client to session                 |
| `0x0105`  | AttachSessionResponse  | S -> C    | Attach result                            |
| `0x0106`  | DetachSessionRequest   | C -> S    | Detach client from session               |
| `0x0107`  | DetachSessionResponse  | S -> C    | Detach result                            |
| `0x0108`  | DestroySessionRequest  | C -> S    | Destroy a session                        |
| `0x0109`  | DestroySessionResponse | S -> C    | Destroy result                           |
| `0x010A`  | RenameSessionRequest   | C -> S    | Rename a session                         |
| `0x010B`  | RenameSessionResponse  | S -> C    | Rename result                            |
| `0x010C`  | AttachOrCreateRequest  | C -> S    | Attach to existing session or create new |
| `0x010D`  | AttachOrCreateResponse | S -> C    | Attach-or-create result                  |

### Pane Messages

| Type Code | Name                   | Direction | Description                           |
| --------- | ---------------------- | --------- | ------------------------------------- |
| `0x0140`  | CreatePaneRequest      | C -> S    | Create a standalone pane in a session |
| `0x0141`  | CreatePaneResponse     | S -> C    | Result of pane creation               |
| `0x0142`  | SplitPaneRequest       | C -> S    | Split an existing pane                |
| `0x0143`  | SplitPaneResponse      | S -> C    | Split result                          |
| `0x0144`  | ClosePaneRequest       | C -> S    | Close a pane                          |
| `0x0145`  | ClosePaneResponse      | S -> C    | Close result                          |
| `0x0146`  | FocusPaneRequest       | C -> S    | Set focused pane                      |
| `0x0147`  | FocusPaneResponse      | S -> C    | Focus result                          |
| `0x0148`  | NavigatePaneRequest    | C -> S    | Move focus in a direction             |
| `0x0149`  | NavigatePaneResponse   | S -> C    | Navigate result (new focused pane)    |
| `0x014A`  | ResizePaneRequest      | C -> S    | Adjust split divider                  |
| `0x014B`  | ResizePaneResponse     | S -> C    | Resize result                         |
| `0x014C`  | EqualizeSplitsRequest  | C -> S    | Equalize all splits in a session      |
| `0x014D`  | EqualizeSplitsResponse | S -> C    | Equalize result                       |
| `0x014E`  | ZoomPaneRequest        | C -> S    | Toggle pane zoom                      |
| `0x014F`  | ZoomPaneResponse       | S -> C    | Zoom result                           |
| `0x0150`  | SwapPanesRequest       | C -> S    | Swap two panes                        |
| `0x0151`  | SwapPanesResponse      | S -> C    | Swap result                           |
| `0x0152`  | LayoutGetRequest       | C -> S    | Query current layout tree             |
| `0x0153`  | LayoutGetResponse      | S -> C    | Current layout tree                   |

### Notifications (Server -> Client)

| Type Code | Name                | Direction | Description                      |
| --------- | ------------------- | --------- | -------------------------------- |
| `0x0180`  | LayoutChanged       | S -> C    | Layout tree updated              |
| `0x0181`  | PaneMetadataChanged | S -> C    | Pane metadata updated            |
| `0x0182`  | SessionListChanged  | S -> C    | Session list changed             |
| `0x0183`  | ClientAttached      | S -> C    | A client attached to a session   |
| `0x0184`  | ClientDetached      | S -> C    | A client detached from a session |
| `0x0185`  | ClientHealthChanged | S -> C    | A client's health state changed  |

### Window Resize

| Type Code | Name            | Direction | Description           |
| --------- | --------------- | --------- | --------------------- |
| `0x0190`  | WindowResize    | C -> S    | Client window resized |
| `0x0191`  | WindowResizeAck | S -> C    | Resize acknowledged   |

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

All fields are optional. Omit or use `""` for strings and `0` for integers to
use server defaults.

### 1.2 CreateSessionResponse (0x0101)

```json
{
  "status": 0,
  "session_id": 1,
  "pane_id": 1
}
```

| Field        | Type   | Description                               |
| ------------ | ------ | ----------------------------------------- |
| `status`     | number | 0 = success, non-zero = error code        |
| `session_id` | u32    | Valid if status=0                         |
| `pane_id`    | u32    | ID of initial pane                        |
| `error`      | string | Error description (present only on error) |

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

A client connection is attached to **at most one session** at a time. Sending
AttachSessionRequest while already attached to a session returns
`ERR_SESSION_ALREADY_ATTACHED` (status code 3). To switch sessions, the client
MUST first detach (DetachSessionRequest) then attach to the new session. This
matches tmux behavior.

```json
{
  "session_id": 1,
  "cols": 80,
  "rows": 24,
  "readonly": false,
  "detach_others": false
}
```

| Field           | Type    | Description                                                                 |
| --------------- | ------- | --------------------------------------------------------------------------- |
| `session_id`    | u32     | Session to attach to                                                        |
| `cols`          | number  | Client terminal columns                                                     |
| `rows`          | number  | Client terminal rows                                                        |
| `readonly`      | boolean | true = read-only attachment (observer mode). See Section 9 for permissions. |
| `detach_others` | boolean | true = force-detach all other clients from this session                     |

**`detach_others` behavior**: When `detach_others` is true and other clients are
attached to the same session, those clients receive a forced
`DetachSessionResponse` with `reason: "force_detached_by_other_client"` and
transition back to READY state. The requesting client then attaches normally.

### 1.6 AttachSessionResponse (0x0105)

On success, the server follows this response with:

1. A `LayoutChanged` notification containing the full layout tree (with per-pane
   `active_input_method` and `active_keyboard_layout` in leaf nodes).
2. If the session has active preedit on any pane, a `PreeditSync` is sent (via
   the direct message queue, priority 1). Per the "context before content"
   principle (doc 06 Section 2.3), composition metadata arrives BEFORE the
   I-frame containing preedit cells.
3. A full I-frame (`frame_type=1`) for each visible pane from the shared ring
   buffer.
4. A `ClientAttached` notification to all other clients attached to the session.

```json
{
  "status": 0,
  "session_id": 1,
  "name": "my-session",
  "active_pane_id": 1,
  "active_input_method": "korean_2set",
  "active_keyboard_layout": "qwerty",
  "resize_policy": "latest"
}
```

| Field                    | Type   | Description                                                                                                |
| ------------------------ | ------ | ---------------------------------------------------------------------------------------------------------- |
| `status`                 | number | 0 = success, 1 = session not found, 2 = access denied, 3 = already attached to a session                   |
| `session_id`             | u32    | Session ID                                                                                                 |
| `name`                   | string | Session name                                                                                               |
| `active_pane_id`         | u32    | Currently focused pane                                                                                     |
| `active_input_method`    | string | Session-level active input method (e.g., `"direct"`, `"korean_2set"`)                                      |
| `active_keyboard_layout` | string | Session-level active keyboard layout (e.g., `"qwerty"`)                                                    |
| `resize_policy`          | string | Server's active resize policy for this session: `"latest"` or `"smallest"` (informational, not negotiated) |
| `error`                  | string | Error description (present only on error)                                                                  |

The `active_input_method` and `active_keyboard_layout` fields provide the
session-level input method state. All panes in a session share the same engine
(per-session architecture). Leaf nodes in `LayoutChanged` carry the same values
for self-containedness. See Section 3 for details.

### 1.7 DetachSessionRequest (0x0106)

```json
{
  "session_id": 1
}
```

### 1.8 DetachSessionResponse (0x0107)

This message serves as both a response to client-initiated detach and a
server-initiated forced detach notification.

```json
{
  "status": 0,
  "reason": "client_requested"
}
```

| Field    | Type   | Description                                   |
| -------- | ------ | --------------------------------------------- |
| `status` | number | 0 = success, 1 = not attached to this session |
| `reason` | string | Detach reason (see table below)               |
| `error`  | string | Error description (present only on error)     |

**Detach reason values**:

| Reason                             | Trigger                                            | Description               |
| ---------------------------------- | -------------------------------------------------- | ------------------------- |
| `"client_requested"`               | Client sends DetachSessionRequest                  | Normal voluntary detach   |
| `"force_detached_by_other_client"` | Another client attaches with `detach_others: true` | Evicted by another client |
| `"session_destroyed"`              | Session destroyed via DestroySessionRequest        | Session no longer exists  |

When a client receives a forced DetachSessionResponse (any reason other than
`"client_requested"`), it transitions back to the READY state and may
auto-attach to another session or present a session picker.

### 1.9 DestroySessionRequest (0x0108)

Destroys a session. All panes are closed and all PTYs are freed. PTY cleanup
details (signal handling, resource teardown) are defined in daemon design docs.

```json
{
  "session_id": 1,
  "force": false
}
```

| Field        | Type    | Description                                     |
| ------------ | ------- | ----------------------------------------------- |
| `session_id` | u32     | Session to destroy                              |
| `force`      | boolean | true = force-kill even if processes are running |

**Cascade behavior for attached clients**: When a session is destroyed while
other clients are attached, the server:

1. Sends `SessionListChanged` with `event: "destroyed"` to ALL connected
   clients.
2. Sends forced `DetachSessionResponse` with `reason: "session_destroyed"` to
   every client attached to the destroyed session (except the requesting client,
   which receives the DestroySessionResponse).
3. Those clients transition back to READY state.
4. Sends `ClientDetached` notification to the requesting client for each
   detached client.

### 1.10 DestroySessionResponse (0x0109)

```json
{
  "status": 0
}
```

| Field    | Type   | Description                                                                       |
| -------- | ------ | --------------------------------------------------------------------------------- |
| `status` | number | 0 = success, 1 = session not found, 2 = processes still running (and force=false) |
| `error`  | string | Error description (present only on error)                                         |

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

| Field    | Type   | Description                                                 |
| -------- | ------ | ----------------------------------------------------------- |
| `status` | number | 0 = success, 1 = session not found, 2 = name already in use |
| `error`  | string | Error description (present only on error)                   |

### 1.13 AttachOrCreateRequest (0x010C)

Attaches to an existing session or creates a new one if it does not exist.
Equivalent to tmux's `new-session -A`. Subject to the same
single-session-per-connection rule as AttachSessionRequest (returns
`ERR_SESSION_ALREADY_ATTACHED` if already attached).

```json
{
  "session_name": "main",
  "cols": 80,
  "rows": 24,
  "shell": "",
  "cwd": ""
}
```

| Field          | Type   | Description                                                                                                                                                   |
| -------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `session_name` | string | Session name to attach to or create. Empty string = attach to most recently active session, or create a new session with server-generated name if none exist. |
| `cols`         | number | Client terminal columns                                                                                                                                       |
| `rows`         | number | Client terminal rows                                                                                                                                          |
| `shell`        | string | Shell path for new session (only used if creating). Empty = default shell (`$SHELL` or `/bin/sh`).                                                            |
| `cwd`          | string | Working directory for new session (only used if creating). Empty = `$HOME`.                                                                                   |

**Semantics**: If a session with the given name exists, attach to it. If not,
create a new session with that name, then attach. When `session_name` is empty,
attach to the most recently active session; if no sessions exist, create a new
one with default parameters.

### 1.14 AttachOrCreateResponse (0x010D)

On success, the same post-attach sequence applies as for AttachSessionResponse:
LayoutChanged, PreeditSync (if applicable), I-frame (`frame_type=1`),
ClientAttached notification.

```json
{
  "action_taken": "attached",
  "session_id": 1,
  "pane_id": 1,
  "session_name": "main",
  "active_pane_id": 1,
  "active_input_method": "korean_2set",
  "active_keyboard_layout": "qwerty",
  "resize_policy": "latest"
}
```

| Field                    | Type   | Description                                                          |
| ------------------------ | ------ | -------------------------------------------------------------------- |
| `action_taken`           | string | `"attached"` or `"created"`                                          |
| `session_id`             | u32    | Session ID                                                           |
| `pane_id`                | u32    | Initial pane ID (only meaningful if `action_taken` = `"created"`)    |
| `session_name`           | string | Actual session name                                                  |
| `active_pane_id`         | u32    | Currently focused pane                                               |
| `active_input_method`    | string | Session-level active input method (same as AttachSessionResponse)    |
| `active_keyboard_layout` | string | Session-level active keyboard layout (same as AttachSessionResponse) |
| `resize_policy`          | string | Server's active resize policy (same as AttachSessionResponse)        |
| `error`                  | string | Error description (present only on error)                            |

---

## 2. Pane Messages

### 2.1 CreatePaneRequest (0x0140)

Creates a standalone pane in the specified session. This is rarely used directly
-- most panes are created via SplitPane. Useful for programmatic session
population.

```json
{
  "session_id": 1,
  "shell": "/bin/zsh",
  "cwd": "/home/user"
}
```

`shell` and `cwd` are optional; omit or use `""` for defaults.

**Note**: This replaces the current layout root. If the session already has
panes, the new pane becomes the entire layout. To add a pane alongside existing
panes, use SplitPane.

> **Normative**: The new pane inherits the session's current
> `active_input_method`. No per-pane override is supported. To change the input
> method, send an InputMethodSwitch message (0x0404) after the pane is created.

### 2.2 CreatePaneResponse (0x0141)

```json
{
  "status": 0,
  "pane_id": 2
}
```

### 2.3 SplitPaneRequest (0x0142)

Splits an existing pane into two. The existing pane becomes one half; a new pane
is spawned in the other half.

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

- `right` (0): Vertical split. Original pane becomes left, new pane appears on
  right.
- `down` (1): Horizontal split. Original pane becomes top, new pane appears on
  bottom.
- `left` (2): Vertical split. New pane appears on left, original becomes right.
- `up` (3): Horizontal split. New pane appears on top, original becomes bottom.

The `ratio` describes the proportion of space given to the **first** child (the
child containing the original pane in a right/down split, or the new pane in a
left/up split).

> **Normative**: The new pane inherits the session's current
> `active_input_method`. No per-pane override is supported. To change the input
> method, send an InputMethodSwitch message (0x0404) after the pane is created.

> **Normative**: If the session has a zoomed pane, the server MUST unzoom
> (restore the original layout) before performing the split. The resulting
> `LayoutChanged` will have `zoomed_pane_present=false`. Active preedit MUST NOT
> be committed or disrupted by the unzoom operation.

### 2.4 SplitPaneResponse (0x0143)

On success, the server follows with a `LayoutChanged` notification.

```json
{
  "status": 0,
  "new_pane_id": 3
}
```

| Field         | Type   | Description                                            |
| ------------- | ------ | ------------------------------------------------------ |
| `status`      | number | 0 = success, 3 = TOO_SMALL, 8 = PANE_LIMIT_EXCEEDED    |
| `new_pane_id` | u32    | ID of the newly created pane (present only on success) |

On failure, the response contains only `status` and `error`:

```json
{
  "status": 8,
  "error": "PANE_LIMIT_EXCEEDED"
}
```

### 2.5 Auto-Close on Process Exit

> **Normative**: When a pane's process exits, the server MUST automatically
> close the pane. The server sends `PaneMetadataChanged` with
> `is_running: false`, followed by the same sequence as ClosePaneRequest (layout
> reflow, `LayoutChanged` notification). If the auto-closed pane was the last
> pane in the session, the session is auto-destroyed (`side_effect=1`).
> Remain-on-exit is deferred to post-v1 (see `99-post-v1-features.md` Section
> 2).

### 2.6 ClosePaneRequest (0x0144)

Closes a pane. In the layout tree, the parent split node is replaced by the
sibling pane. PTY cleanup details (signal handling, layout reflow) are defined
in daemon design docs.

```json
{
  "session_id": 1,
  "pane_id": 1,
  "force": false
}
```

| Field   | Type    | Description                                                                |
| ------- | ------- | -------------------------------------------------------------------------- |
| `force` | boolean | true = force-kill if graceful termination does not complete within timeout |

### 2.7 ClosePaneResponse (0x0145)

If the closed pane was the last pane in the session, the session is also
destroyed. The response indicates what happened.

```json
{
  "status": 0,
  "side_effect": 0,
  "new_focus_pane_id": 2
}
```

| Field               | Type   | Description                               |
| ------------------- | ------ | ----------------------------------------- |
| `status`            | number | 0 = success, 1 = pane not found           |
| `side_effect`       | number | 0 = none, 1 = session also destroyed      |
| `new_focus_pane_id` | u32    | New focused pane (0 if session destroyed) |

### 2.8 FocusPaneRequest (0x0146)

Sets the focused (active) pane within the session.

```json
{
  "session_id": 1,
  "pane_id": 2
}
```

**Preedit interaction**: FocusPaneRequest may trigger `PreeditEnd` with
`reason: "focus_changed"` to all attached clients before processing the focus
change. Preedit flush-to-PTY details are defined in daemon design docs. See doc
05 Section 6.7 for the PreeditEnd reason enum.

### 2.9 FocusPaneResponse (0x0147)

```json
{
  "status": 0,
  "previous_pane_id": 1
}
```

### 2.10 NavigatePaneRequest (0x0148)

Moves focus to the nearest pane in the given direction from the current focused
pane.

```json
{
  "session_id": 1,
  "direction": 0
}
```

**Navigation algorithm**: The server computes the geometric position of each
pane from the session's layout tree, then finds the nearest pane in the
requested direction from the center of the currently focused pane. If no pane
exists in that direction, the focus wraps around (configurable).

**Preedit interaction**: Same rule as FocusPaneRequest — if the current pane has
active preedit, flush before navigating. See Section 2.8.

### 2.11 NavigatePaneResponse (0x0149)

```json
{
  "status": 0,
  "focused_pane_id": 2
}
```

### 2.12 ResizePaneRequest (0x014A)

Adjusts the split divider adjacent to a pane. The `direction` indicates which
edge to move, and `delta` is the number of cells to move the divider.

```json
{
  "session_id": 1,
  "pane_id": 1,
  "direction": 0,
  "delta": 5
}
```

**Semantics**: A positive delta moves the divider in the stated direction. For
example, `direction=right, delta=5` grows the pane 5 columns to the right
(shrinking the neighbor). A negative delta moves it in the opposite direction.

### 2.13 ResizePaneResponse (0x014B)

On success, the server follows with a `LayoutChanged` notification.

```json
{
  "status": 0
}
```

| Field    | Type   | Description                                                                               |
| -------- | ------ | ----------------------------------------------------------------------------------------- |
| `status` | number | 0 = success, 1 = pane not found, 2 = no split in that direction, 3 = minimum size reached |

### 2.14 EqualizeSplitsRequest (0x014C)

Sets all split ratios in a session's layout tree to 0.5 (equal distribution).

```json
{
  "session_id": 1
}
```

### 2.15 EqualizeSplitsResponse (0x014D)

On success, the server follows with a `LayoutChanged` notification.

```json
{
  "status": 0
}
```

### 2.16 ZoomPaneRequest (0x014E)

Toggles zoom on a pane. When zoomed, the pane fills the entire session area.
Other panes in the session are hidden but their PTYs continue running.

```json
{
  "session_id": 1,
  "pane_id": 1
}
```

### 2.17 ZoomPaneResponse (0x014F)

On success, the server follows with a `LayoutChanged` notification (with a flag
indicating zoom state).

```json
{
  "status": 0,
  "zoomed": true
}
```

### 2.18 SwapPanesRequest (0x0150)

Swaps two panes in the layout tree. The PTY and shell process follow the pane --
only the position in the layout tree changes. Preedit state (if active) follows
the pane.

```json
{
  "session_id": 1,
  "pane_a": 1,
  "pane_b": 2
}
```

### 2.19 SwapPanesResponse (0x0151)

On success, the server follows with a `LayoutChanged` notification.

```json
{
  "status": 0
}
```

| Field    | Type   | Description                                             |
| -------- | ------ | ------------------------------------------------------- |
| `status` | number | 0 = success, 1 = pane_a not found, 2 = pane_b not found |

### 2.20 LayoutGetRequest (0x0152)

Requests the current layout tree for a session. Use case: client wants to
refresh layout state after missing a notification, or a monitoring tool queries
layout on demand.

```json
{
  "session_id": 1
}
```

### 2.21 LayoutGetResponse (0x0153)

Returns the same payload format as `LayoutChanged` (Section 4.1), with the
RESPONSE flag set and echoing the request's sequence number.

---

## 3. Layout Tree Wire Format

The layout tree is a recursive binary tree serialized as a JSON object in a
depth-first structure. Each node is either a **leaf** (pane) or a **split**
(branch with exactly two children).

### 3.1 Leaf Node (Pane)

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

| Field                    | Type    | Description                                                            |
| ------------------------ | ------- | ---------------------------------------------------------------------- |
| `type`                   | string  | Always `"leaf"`                                                        |
| `pane_id`                | u32     | Pane ID                                                                |
| `cols`                   | number  | Pane width in columns                                                  |
| `rows`                   | number  | Pane height in rows                                                    |
| `x_off`                  | number  | X offset within the session area                                       |
| `y_off`                  | number  | Y offset within the session area                                       |
| `preedit_active`         | boolean | Whether preedit composition is active on this pane                     |
| `active_input_method`    | string  | Current input method for this pane (e.g., `"direct"`, `"korean_2set"`) |
| `active_keyboard_layout` | string  | Current keyboard layout for this pane (e.g., `"qwerty"`)               |

> **Normative**: All leaf nodes in a session MUST have identical
> `active_input_method` and `active_keyboard_layout` values. The server
> populates these from the session's shared engine state. Clients MUST NOT
> interpret per-leaf differences as intentional per-pane overrides — they
> represent a server bug if they occur.

**Input method state** in leaf nodes provides authoritative initial/refresh
state for input methods. This is one channel of the two-channel input method
state model:

1. **LayoutChanged** (this message): Full layout tree with per-leaf
   `active_input_method` + `active_keyboard_layout`. Fires on structural changes
   (split, close, resize, zoom, swap) and on attach. Provides authoritative
   initial/refresh state. All leaf values are identical (per-session engine).
2. **InputMethodAck** (0x0405, doc 05): Broadcast to ALL attached clients on
   input method changes. Carries `pane_id` (identifying the focused pane when
   the switch occurred) + new method. Clients MUST update the input method state
   for ALL panes in the session, not just the identified pane.

Client state maintenance:

1. Initialize session-level input method from
   `AttachSessionResponse.active_input_method` or `LayoutChanged` leaf nodes on
   attach.
2. Update incrementally from `InputMethodAck` broadcasts (applying to all panes
   in the session).
3. Refresh from `LayoutChanged` on structural changes.

### 3.2 Split Node

```json
{
  "type": "split",
  "orientation": "horizontal",
  "ratio": 0.5,
  "cols": 80,
  "rows": 24,
  "x_off": 0,
  "y_off": 0,
  "first": {/* child node */},
  "second": {/* child node */}
}
```

### 3.3 Example

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
    "active_input_method": "korean_2set",
    "active_keyboard_layout": "qwerty"
  }
}
```

Note that both leaf nodes share the same `active_input_method` value
(`"korean_2set"`) because input method state is per-session, not per-pane.

### 3.4 Maximum Tree Depth

The server enforces a maximum tree depth of 16 levels. This allows up to 65,536
panes theoretically (though practical limits are much lower due to minimum pane
sizes). Clients must be prepared to handle trees up to this depth.

---

## 4. Notifications

> **Always-sent vs opt-in notifications**: The notifications in this section
> (0x0180-0x0185: LayoutChanged, PaneMetadataChanged, SessionListChanged,
> ClientAttached, ClientDetached, ClientHealthChanged) are **always sent** to
> all clients attached to the affected session -- no subscription is required.
> In contrast, doc 06 Section 5 defines opt-in notifications (0x0800-0x0806:
> PaneTitleChanged, ProcessExited, Bell, RendererHealth, PaneCwdChanged,
> ActivityDetected, SilenceDetected) that require explicit subscription via the
> Subscribe/Unsubscribe mechanism (doc 06 Section 6).

### 4.1 LayoutChanged (0x0180)

Sent by the server whenever the layout tree changes (split, close, resize, swap,
zoom, window resize). This is the authoritative representation of the current
layout.

```json
{
  "session_id": 1,
  "active_pane_id": 1,
  "zoomed_pane_present": false,
  "zoomed_pane_id": 0,
  "layout_tree": {/* layout tree object (Section 3) */}
}
```

**Delivery rules**:

- Sent to all clients attached to the affected session.
- After AttachSession success, one LayoutChanged is sent for the session.
- After SplitPane, ClosePane, ResizePane, EqualizeSplits, ZoomPane, SwapPanes,
  or WindowResize, one LayoutChanged is sent for the affected session.

> **Note on input method state**: LayoutChanged does NOT fire solely for input
> method changes. Input method changes are communicated via `InputMethodAck`
> (0x0405, doc 05), which is broadcast to all attached clients. LayoutChanged
> includes per-pane `active_input_method` and `active_keyboard_layout` in leaf
> nodes to provide authoritative state on structural changes and attach. All
> leaf values are identical (per-session engine). See Section 3 for the
> two-channel model.

### 4.2 PaneMetadataChanged (0x0181)

Sent when a pane's metadata changes. Sources include: OSC title sequences, shell
integration CWD reporting, foreground process changes, and process exit.

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

Only changed fields are included in the JSON object. Clients detect which fields
changed by checking for key presence.

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

Sent to all clients attached to a session when a new client attaches to the same
session.

```json
{
  "session_id": 1,
  "client_id": 5,
  "client_name": "iPad-Pro",
  "attached_clients": 3
}
```

| Field              | Type   | Description                                                           |
| ------------------ | ------ | --------------------------------------------------------------------- |
| `session_id`       | u32    | Affected session                                                      |
| `client_id`        | u32    | ID of the newly attached client (assigned in ServerHello, see doc 02) |
| `client_name`      | string | Human-readable client name (from ClientHello)                         |
| `attached_clients` | number | Total number of clients now attached to this session                  |

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

| Field              | Type   | Description                                                                                                                   |
| ------------------ | ------ | ----------------------------------------------------------------------------------------------------------------------------- |
| `session_id`       | u32    | Affected session                                                                                                              |
| `client_id`        | u32    | ID of the detached client                                                                                                     |
| `client_name`      | string | Human-readable client name                                                                                                    |
| `reason`           | string | Why the client detached: `"client_requested"`, `"force_detached_by_other_client"`, `"session_destroyed"`, `"connection_lost"` |
| `attached_clients` | number | Total number of clients still attached to this session                                                                        |

### 4.6 ClientHealthChanged (0x0185)

Sent to all peer clients attached to the same session when a client's health
state changes. NOT sent to the affected client itself (it already knows — it
received PausePane or is processing its recovery).

```json
{
  "session_id": 1,
  "client_id": 5,
  "client_name": "iPad-Pro",
  "health": "stale",
  "previous_health": "healthy",
  "reason": "pause_timeout",
  "excluded_from_resize": true
}
```

| Field                  | Type         | Description                                                |
| ---------------------- | ------------ | ---------------------------------------------------------- |
| `session_id`           | number (u32) | Session the affected client is attached to                 |
| `client_id`            | number (u32) | The affected client                                        |
| `client_name`          | string       | Human-readable client name (from ClientHello)              |
| `health`               | string       | New health state: `"healthy"` or `"stale"`                 |
| `previous_health`      | string       | Previous health state                                      |
| `reason`               | string       | Reason for transition (see below)                          |
| `excluded_from_resize` | boolean      | Whether the client is now excluded from resize calculation |

**`reason` values:**

| Value                | Description                                                       |
| -------------------- | ----------------------------------------------------------------- |
| `"pause_timeout"`    | PausePane duration exceeded stale timeout                         |
| `"queue_stagnation"` | Ring cursor lag >90% for stale timeout with no app-level messages |
| `"recovered"`        | Client sent ContinuePane or resumed processing                    |

This extends the existing notification block: `ClientAttached` (0x0183),
`ClientDetached` (0x0184), `ClientHealthChanged` (0x0185). Always-sent (no
subscription required), matching the convention for 0x0180-0x018x notifications.

---

## 5. Window Resize

### 5.1 WindowResize (0x0190)

Sent by the client when its terminal window is resized. The server uses this to
cascade-resize all panes in the session.

```json
{
  "session_id": 1,
  "cols": 120,
  "rows": 40,
  "pixel_width": 0,
  "pixel_height": 0
}
```

`pixel_width` and `pixel_height` are optional (0 if unknown). Provided for
applications that need sub-cell positioning (e.g., Sixel graphics, Kitty image
protocol).

### 5.2 Multi-Client Resize Policy

The server supports two resize policies, configured per-session as a server-side
setting (not protocol-negotiated). The active policy is reported in
`AttachSessionResponse.resize_policy` (informational). See ADR 00012 for the
design rationale.

| Policy     | Behavior                                                                    | Default           |
| ---------- | --------------------------------------------------------------------------- | ----------------- |
| `latest`   | PTY dimensions set to the most recently active client's reported size       | **Yes** (default) |
| `smallest` | PTY dimensions set to `min(cols)` x `min(rows)` across all eligible clients | Opt-in            |

> **Normative**: When the effective terminal size exceeds a client's reported
> dimensions (WindowResize cols/rows), the client MUST render only the top-left
> region corresponding to its own dimensions. Content beyond the client's
> viewport boundary is clipped.

### 5.3 `latest_client_id` Tracking

The server tracks `latest_client_id` per session, updated on:

- KeyEvent received from a client
- WindowResize received from a client
- NOT on HeartbeatAck (passive liveness does not indicate active use)

When the latest client detaches or becomes stale, the server falls back to the
next most-recently-active healthy client. If no client has any recorded
activity, fall back to the client with the largest terminal dimensions.

### 5.4 Resize Wire Behavior

When the server determines the effective terminal size has changed, it:

1. Sends `LayoutChanged` to ALL attached clients with updated pane dimensions.
2. Writes I-frame(s) for affected panes to the ring buffer.
3. Sends `WindowResizeAck` to the sending client.

The resize algorithm internals (policy computation, debounce, PTY ioctl,
coalescing tier suppression during resize) are defined in daemon design docs.

### 5.5 Stale Client Exclusion

Clients in the `stale` health state are excluded from the resize calculation.
Stale exclusion policy, re-inclusion hysteresis, and client detach resize
behavior are defined in daemon design docs.

### 5.6 Client Detach Resize

When a client detaches, the server recomputes the effective size and sends
`LayoutChanged` if the size changes.

### 5.7 WindowResizeAck (0x0191)

```json
{
  "status": 0
}
```

---

## 6. Error Codes

Status codes used across all response messages:

| Code | Name                  | Description                                          |
| ---- | --------------------- | ---------------------------------------------------- |
| 0    | `OK`                  | Success                                              |
| 1    | `NOT_FOUND`           | Referenced entity (session/pane) not found           |
| 2    | `ALREADY_EXISTS`      | Name collision or duplicate operation                |
| 3    | `TOO_SMALL`           | Cannot split -- pane below minimum size              |
| 4    | `PROCESSES_RUNNING`   | Cannot destroy -- processes still active             |
| 5    | `ACCESS_DENIED`       | Permission denied for this operation (see Section 9) |
| 6    | `INVALID_ARGUMENT`    | Invalid field value                                  |
| 7    | `INTERNAL_ERROR`      | Unexpected server error                              |
| 8    | `PANE_LIMIT_EXCEEDED` | Cannot create pane — session pane limit reached      |

These are common status codes shared across multiple response messages.
Individual messages may assign message-specific meanings to certain codes (e.g.,
AttachSessionResponse uses status 3 for "already attached to a session" rather
than TOO_SMALL).

> **Two-layer error model**: Per-message `status` codes (above) are distinct
> from protocol-level `error_code` values in the Error message (`0x00FF`, see
> doc 01). Response `status` codes handle expected failure cases (session not
> found, already attached, etc.) within typed response messages. The Error
> message (`0x00FF`) handles unexpected or cross-cutting errors where the server
> cannot produce a typed response (unknown message type, malformed payload,
> state violations). For expected failures, the server SHOULD send the typed
> response with an appropriate status code, NOT a formal Error message.

**ERR_ACCESS_DENIED (0x00000203)**: Returned when a readonly client attempts a
prohibited operation. See Section 9 for the full permissions table. The server
sends the typed response (e.g., FocusPaneResponse) with `status: 5`, not a
formal Error message.

**ERR_SESSION_ALREADY_ATTACHED (0x00000201)**: A client connection is attached
to at most one session at a time. Sending AttachSessionRequest or
AttachOrCreateRequest while already attached returns `status: 3` in
AttachSessionResponse. The client must first detach via DetachSessionRequest.

---

## 7. Sequence Number Correlation

All request/response pairs share the same `sequence` number from the message
header. The client assigns monotonically increasing sequence numbers to outgoing
requests. The server echoes the sequence number in the corresponding response
(with the RESPONSE flag set).

Notifications (LayoutChanged, PaneMetadataChanged, etc.) use the server's next
monotonic sequence number. Notifications are identifiable by their message type
— notification types (0x0180-0x0185) are distinct from request/response types.
Sequence number 0 is never sent on the wire; it is used only as a sentinel value
in payload fields (e.g., `ref_sequence = 0` in Error messages means "no specific
message triggered this error").

A notification that is a direct consequence of a request (e.g., LayoutChanged
after SplitPane) is sent AFTER the response message, so the client can process
the response first and then update the layout.

**Ordering guarantee**: For a given client connection, messages are delivered in
order. The server never sends a response for request N+1 before the response for
request N.

---

## 8. Multi-Client Behavior

Multiple clients can be attached to the same session simultaneously.

### 8.1 Focus Model

**Decision for v1**: Per-session focus (like tmux). All clients share the same
active pane. This simplifies the protocol and matches the multiplexer mental
model. Per-client focus can be added later as an opt-in capability.

- FocusPane and NavigatePane change the session's active pane, affecting all
  attached clients.
- All attached clients receive a LayoutChanged notification when focus changes.
- **Preedit interaction**: Focus changes flush active preedit before processing.
  See Section 2.8.

### 8.2 Layout Mutations

- SplitPane, ClosePane, ResizePane, etc., affect the shared layout.
- All attached clients receive the resulting LayoutChanged notification.

### 8.3 Input Method State

Input method state is communicated per-session through the following wire fields
and messages:

- `AttachSessionResponse` includes `active_input_method` and
  `active_keyboard_layout` fields.
- `LayoutChanged` leaf nodes include `active_input_method` and
  `active_keyboard_layout` (all panes in a session share the same values).
- Input method changes are broadcast to all attached clients via
  `InputMethodAck` (0x0405, doc 05).

Per-session IME engine lifecycle (creation, activation, deactivation, detach
preservation, session restore) is defined in daemon design docs.

### 8.4 Client Health

The protocol defines two health states orthogonal to connection lifecycle:
`healthy` and `stale`. Health transitions are communicated via
`ClientHealthChanged` (0x0185). Stale clients are excluded from resize
calculation and stop receiving frames (ring cursor stagnant). See doc 06 Section
2 for the health escalation timeline, stale triggers, and recovery procedures.

---

## 9. Readonly Client Permissions

When a client attaches with `readonly: true`, it operates in observer mode. The
server enforces the following permissions:

### 9.1 Permitted Messages (readonly MAY send)

| Category              | Messages                                                                               |
| --------------------- | -------------------------------------------------------------------------------------- |
| Session queries       | ListSessionsRequest, LayoutGetRequest                                                  |
| Viewport              | ScrollRequest, MouseScroll, FocusEvent                                                 |
| Connection management | Heartbeat, Disconnect, DetachSessionRequest, ClientDisplayInfo, Subscribe, Unsubscribe |
| Search                | SearchRequest, SearchCancel                                                            |

### 9.2 Prohibited Messages (readonly MUST NOT send)

| Category              | Messages                                                                                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Input                 | KeyEvent, TextInput, MouseButton, MouseMove, PasteData                                                                                                                    |
| IME                   | InputMethodSwitch                                                                                                                                                         |
| Session/pane mutation | CreateSessionRequest, DestroySessionRequest, RenameSessionRequest, AttachOrCreateRequest (with create semantics)                                                          |
| Pane mutation         | CreatePaneRequest, SplitPaneRequest, ClosePaneRequest, FocusPaneRequest, NavigatePaneRequest, ResizePaneRequest, EqualizeSplitsRequest, ZoomPaneRequest, SwapPanesRequest |
| Window                | WindowResize                                                                                                                                                              |
| Persistence           | SnapshotRequest, RestoreSessionRequest                                                                                                                                    |
| Clipboard (write)     | ClipboardWriteFromClient                                                                                                                                                  |

When a readonly client sends a prohibited message, the server responds with
`ERR_ACCESS_DENIED` (status code 5, error code `0x00000203`).

### 9.3 Readonly Receives

Readonly clients receive ALL server-to-client messages, including:

- FrameUpdate (full terminal content)
- LayoutChanged, PaneMetadataChanged, SessionListChanged
- ClientAttached, ClientDetached, ClientHealthChanged
- Preedit broadcasts: PreeditStart, PreeditUpdate, PreeditEnd, PreeditSync,
  InputMethodAck (as observer — they see composition from other clients)
- Flow control: PausePane, OutputQueueStatus
- Subscribed notifications

---

## 10. Open Questions

1. **~~Last-pane-close behavior~~** **Closed (v0.7)**: Yes, auto-destroy.
   Already reflected in the design (`ClosePaneResponse` `side_effect = 1`).
   Owner confirmed.

2. **Pane minimum size**: What is the minimum pane size below which splits are
   rejected? Suggestion: 2 columns x 1 row (matching tmux's minimum).

3. **~~Session auto-destroy~~** **Closed (v0.7)**: Never. Keeping sessions alive
   indefinitely with no attached clients is a core design principle — the daemon
   preserves session state so users can reconnect later. Owner confirmed.

4. **~~Zoom + split interaction~~** **Closed (v1.0-r12)**: Unzoom first, then
   split. The server MUST unzoom (restore the original layout) before performing
   the split. Active preedit MUST NOT be committed or disrupted by the unzoom
   operation. See Section 2.3.

5. **~~Layout tree compression~~** **Closed (v0.7)**: Unnecessary. Maximum
   practical size (~50 panes) produces a few KB of JSON — no compression needed.
   Owner decision.

6. **~~Pane reuse after exit~~** **Closed (v0.7)**: Auto-close. When a pane's
   process exits, the server automatically closes the pane. If the auto-closed
   pane was the last pane in the session, the session is auto-destroyed.
   Remain-on-exit functionality deferred to post-v1 (see
   `99-post-v1-features.md`). See Section 2.5. Owner decision.
