# 03 - Session, Tab, and Pane Management Protocol

**Status**: Draft
**Date**: 2026-03-04
**Author**: systems-engineer (AI-assisted)

## Overview

This document specifies the wire protocol for managing the Session > Tab > Pane hierarchy in libitshell3. All messages use the binary framing defined in document 01 (14-byte header: magic(2) + version(1) + flags(1) + type(2) + length(4) + sequence(4), little-endian byte order).

Message type range: `0x0100` - `0x01FF` (session/tab/pane management).

### Conventions

- All multi-byte integers are little-endian.
- Strings are UTF-8 encoded, length-prefixed with a `u16` byte count (NOT null-terminated).
- UUIDs are 16 bytes in binary (RFC 4122 format, network byte order within the UUID itself).
- Boolean fields are `u8`: 0 = false, 1 = true.
- "Payload offset" means byte offset from the start of the payload (i.e., after the 14-byte header).
- All request messages expect a corresponding response message. The response carries the same sequence number as the request for correlation.
- Directions use `u8`: 0 = right, 1 = down, 2 = left, 3 = up (matches ghostty's `GHOSTTY_SPLIT_DIRECTION`).
- Ratios are `f32` (IEEE 754, 4 bytes) in the range [0.0, 1.0].

### ID Types

| Type | Wire Size | Description |
|------|-----------|-------------|
| `session_id` | 16 bytes (UUID) | Stable session identifier |
| `tab_id` | 16 bytes (UUID) | Stable tab identifier |
| `pane_id` | 16 bytes (UUID) | Stable pane identifier |

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
| **Tab Messages** | | | |
| `0x0120` | CreateTabRequest | C -> S | Create a new tab |
| `0x0121` | CreateTabResponse | S -> C | Result of tab creation |
| `0x0122` | CloseTabRequest | C -> S | Close a tab |
| `0x0123` | CloseTabResponse | S -> C | Close result |
| `0x0124` | RenameTabRequest | C -> S | Rename a tab |
| `0x0125` | RenameTabResponse | S -> C | Rename result |
| `0x0126` | SwitchTabRequest | C -> S | Switch active tab |
| `0x0127` | SwitchTabResponse | S -> C | Switch result |
| `0x0128` | ReorderTabRequest | C -> S | Change tab position |
| `0x0129` | ReorderTabResponse | S -> C | Reorder result |
| **Pane Messages** | | | |
| `0x0140` | CreatePaneRequest | C -> S | Create a standalone pane in a tab |
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
| `0x014C` | EqualizeSplitsRequest | C -> S | Equalize all splits in a tab |
| `0x014D` | EqualizeSplitsResponse | S -> C | Equalize result |
| `0x014E` | ZoomPaneRequest | C -> S | Toggle pane zoom |
| `0x014F` | ZoomPaneResponse | S -> C | Zoom result |
| `0x0150` | SwapPanesRequest | C -> S | Swap two panes |
| `0x0151` | SwapPanesResponse | S -> C | Swap result |
| **Notifications (Server -> Client, unsolicited)** | | | |
| `0x0180` | LayoutChanged | S -> C | Layout tree updated |
| `0x0181` | PaneMetadataChanged | S -> C | Pane metadata updated |
| `0x0182` | SessionListChanged | S -> C | Session list changed |
| `0x0183` | TabListChanged | S -> C | Tab list in session changed |
| **Window Resize** | | | |
| `0x0190` | WindowResize | C -> S | Client window resized |
| `0x0191` | WindowResizeAck | S -> C | Resize acknowledged |

---

## 1. Session Messages

### 1.1 CreateSessionRequest (0x0100)

Creates a new session. The server spawns a default shell in the initial pane.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 2 | `name_len` | Length of session name in bytes (0 = use default) |
| 2 | `name_len` | `name` | UTF-8 session name |
| 2+N | 2 | `shell_len` | Length of shell path (0 = use default shell) |
| 4+N | `shell_len` | `shell` | UTF-8 shell path (e.g., "/bin/zsh") |
| 4+N+M | 2 | `cwd_len` | Length of working directory (0 = use default) |
| 6+N+M | `cwd_len` | `cwd` | UTF-8 working directory path |
| 6+N+M+P | 2 | `cols` | Initial terminal columns (0 = server decides) |
| 8+N+M+P | 2 | `rows` | Initial terminal rows (0 = server decides) |

### 1.2 CreateSessionResponse (0x0101)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, non-zero = error code |
| 1 | 16 | `session_id` | UUID of created session (valid if status=0) |
| 17 | 16 | `tab_id` | UUID of initial tab |
| 33 | 16 | `pane_id` | UUID of initial pane |
| 49 | 2 | `error_len` | Length of error message (0 if success) |
| 51 | `error_len` | `error_msg` | UTF-8 error description |

### 1.3 ListSessionsRequest (0x0102)

No payload. The request header alone is sufficient.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| (empty) | 0 | | No payload |

### 1.4 ListSessionsResponse (0x0103)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success |
| 1 | 2 | `count` | Number of sessions |
| 3 | variable | `sessions[]` | Array of session entries |

Each session entry:

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Session UUID |
| 16 | 2 | `name_len` | Session name length |
| 18 | `name_len` | `name` | UTF-8 session name |
| 18+N | 8 | `created_at` | Unix timestamp (seconds, u64) |
| 26+N | 2 | `tab_count` | Number of tabs |
| 28+N | 2 | `pane_count` | Total panes across all tabs |
| 30+N | 2 | `client_count` | Number of attached clients |
| 32+N | 16 | `active_tab_id` | Currently active tab UUID |

### 1.5 AttachSessionRequest (0x0104)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Session to attach to |
| 16 | 2 | `cols` | Client terminal columns |
| 18 | 2 | `rows` | Client terminal rows |
| 20 | 1 | `readonly` | 1 = read-only attachment (observer mode) |

### 1.6 AttachSessionResponse (0x0105)

On success, the server follows this response with a `LayoutChanged` notification containing the full layout tree and a full `FrameUpdate` for each visible pane.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = session not found, 2 = access denied |
| 1 | 16 | `session_id` | Confirmed session UUID |
| 17 | 2 | `name_len` | Session name length |
| 19 | `name_len` | `name` | UTF-8 session name |
| 19+N | 16 | `active_tab_id` | Active tab UUID |
| 35+N | 16 | `active_pane_id` | Active pane UUID |
| 51+N | 2 | `error_len` | Error message length (0 if success) |
| 53+N | `error_len` | `error_msg` | UTF-8 error description |

### 1.7 DetachSessionRequest (0x0106)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Session to detach from |

### 1.8 DetachSessionResponse (0x0107)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = not attached to this session |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

### 1.9 DestroySessionRequest (0x0108)

Destroys a session. All panes are closed (shells receive SIGHUP), all PTYs are freed.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Session to destroy |
| 16 | 1 | `force` | 1 = force-kill even if processes are running |

### 1.10 DestroySessionResponse (0x0109)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = session not found, 2 = processes still running (and force=0) |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

### 1.11 RenameSessionRequest (0x010A)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Session to rename |
| 16 | 2 | `name_len` | New name length |
| 18 | `name_len` | `name` | UTF-8 new session name |

### 1.12 RenameSessionResponse (0x010B)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = session not found, 2 = name already in use |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

---

## 2. Tab Messages

### 2.1 CreateTabRequest (0x0120)

Creates a new tab in the specified session. The server spawns a shell in the initial pane.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 2 | `name_len` | Tab name length (0 = auto-name) |
| 18 | `name_len` | `name` | UTF-8 tab name |
| 18+N | 2 | `shell_len` | Shell path length (0 = use session default) |
| 20+N | `shell_len` | `shell` | UTF-8 shell path |
| 20+N+M | 2 | `cwd_len` | Working directory length (0 = inherit from active pane) |
| 22+N+M | `cwd_len` | `cwd` | UTF-8 working directory |
| 22+N+M+P | 2 | `position` | Insert position (0xFFFF = append at end) |

### 2.2 CreateTabResponse (0x0121)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = session not found |
| 1 | 16 | `tab_id` | UUID of created tab |
| 17 | 16 | `pane_id` | UUID of initial pane |
| 33 | 2 | `position` | Actual tab position (0-based) |
| 35 | 2 | `error_len` | Error message length |
| 37 | `error_len` | `error_msg` | UTF-8 error description |

### 2.3 CloseTabRequest (0x0122)

Closes a tab. All panes in the tab are closed.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `tab_id` | Tab to close |
| 32 | 1 | `force` | 1 = force-kill running processes |

### 2.4 CloseTabResponse (0x0123)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = tab not found, 2 = last tab (cannot close) |
| 1 | 16 | `new_active_tab_id` | New active tab (if the closed tab was active) |
| 17 | 2 | `error_len` | Error message length |
| 19 | `error_len` | `error_msg` | UTF-8 error description |

**Open question**: Should closing the last tab destroy the session, or should we always require at least one tab? tmux destroys the session when the last window is closed. We follow tmux: return status=2 and the client must explicitly destroy the session if desired.

### 2.5 RenameTabRequest (0x0124)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `tab_id` | Tab to rename |
| 32 | 2 | `name_len` | New name length |
| 34 | `name_len` | `name` | UTF-8 new tab name |

### 2.6 RenameTabResponse (0x0125)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = tab not found |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

### 2.7 SwitchTabRequest (0x0126)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `tab_id` | Tab to switch to |

### 2.8 SwitchTabResponse (0x0127)

On success, the server follows this with a `LayoutChanged` notification for the new tab and `FrameUpdate` messages for visible panes.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = tab not found |
| 1 | 16 | `previous_tab_id` | Previously active tab |
| 17 | 2 | `error_len` | Error message length |
| 19 | `error_len` | `error_msg` | UTF-8 error description |

### 2.9 ReorderTabRequest (0x0128)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `tab_id` | Tab to move |
| 32 | 2 | `new_position` | New 0-based display position |

### 2.10 ReorderTabResponse (0x0129)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = tab not found, 2 = invalid position |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

---

## 3. Pane Messages

### 3.1 CreatePaneRequest (0x0140)

Creates a standalone pane in the specified tab. This is rarely used directly -- most panes are created via SplitPane. Useful for programmatic tab population.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `tab_id` | Parent tab |
| 32 | 2 | `shell_len` | Shell path length (0 = default) |
| 34 | `shell_len` | `shell` | UTF-8 shell path |
| 34+N | 2 | `cwd_len` | Working directory length (0 = default) |
| 36+N | `cwd_len` | `cwd` | UTF-8 working directory |

**Note**: This replaces the current layout root. If the tab already has panes, the new pane becomes the entire layout. To add a pane alongside existing panes, use SplitPane.

### 3.2 CreatePaneResponse (0x0141)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = tab not found |
| 1 | 16 | `pane_id` | UUID of created pane |
| 17 | 2 | `error_len` | Error message length |
| 19 | `error_len` | `error_msg` | UTF-8 error description |

### 3.3 SplitPaneRequest (0x0142)

Splits an existing pane into two. The existing pane becomes one half; a new pane is spawned in the other half.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `pane_id` | Pane to split |
| 32 | 1 | `direction` | Split direction: 0=right, 1=down, 2=left, 3=up |
| 33 | 4 | `ratio` | Initial split ratio as f32 (0.5 = equal split) |
| 37 | 2 | `shell_len` | Shell path for new pane (0 = default) |
| 39 | `shell_len` | `shell` | UTF-8 shell path |
| 39+N | 2 | `cwd_len` | Working directory (0 = inherit from split pane) |
| 41+N | `cwd_len` | `cwd` | UTF-8 working directory |
| 41+N+M | 1 | `focus_new` | 1 = focus the new pane, 0 = keep focus on original |

**Split direction semantics**:
- `right` (0): Vertical split. Original pane becomes left, new pane appears on right.
- `down` (1): Horizontal split. Original pane becomes top, new pane appears on bottom.
- `left` (2): Vertical split. New pane appears on left, original becomes right.
- `up` (3): Horizontal split. New pane appears on top, original becomes bottom.

The `ratio` describes the proportion of space given to the **first** child (the child containing the original pane in a right/down split, or the new pane in a left/up split).

### 3.4 SplitPaneResponse (0x0143)

On success, the server follows with a `LayoutChanged` notification.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane not found, 2 = too small to split |
| 1 | 16 | `new_pane_id` | UUID of newly created pane |
| 17 | 2 | `error_len` | Error message length |
| 19 | `error_len` | `error_msg` | UTF-8 error description |

### 3.5 ClosePaneRequest (0x0144)

Closes a pane. Its shell receives SIGHUP. In the layout tree, the parent split node is replaced by the sibling pane.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `pane_id` | Pane to close |
| 32 | 1 | `force` | 1 = SIGKILL if SIGHUP does not terminate within timeout |

### 3.6 ClosePaneResponse (0x0145)

If the closed pane was the last pane in the tab, the tab is also closed (or the session, if it was the last tab). The response indicates what happened.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane not found |
| 1 | 1 | `side_effect` | 0 = none, 1 = tab also closed, 2 = session also destroyed |
| 2 | 16 | `new_focus_pane_id` | New focused pane (zero UUID if tab/session closed) |
| 18 | 2 | `error_len` | Error message length |
| 20 | `error_len` | `error_msg` | UTF-8 error description |

### 3.7 FocusPaneRequest (0x0146)

Sets the focused (active) pane within the current tab.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `pane_id` | Pane to focus |

### 3.8 FocusPaneResponse (0x0147)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane not found |
| 1 | 16 | `previous_pane_id` | Previously focused pane |
| 17 | 2 | `error_len` | Error message length |
| 19 | `error_len` | `error_msg` | UTF-8 error description |

### 3.9 NavigatePaneRequest (0x0148)

Moves focus to the nearest pane in the given direction from the current focused pane.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `tab_id` | Tab context (required for direction calculation) |
| 32 | 1 | `direction` | 0=right, 1=down, 2=left, 3=up |

**Navigation algorithm**: The server computes the geometric position of each pane from the layout tree, then finds the nearest pane in the requested direction from the center of the currently focused pane. If no pane exists in that direction, the focus wraps around (configurable).

### 3.10 NavigatePaneResponse (0x0149)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = no pane in that direction, 2 = tab not found |
| 1 | 16 | `focused_pane_id` | Newly focused pane UUID |
| 17 | 2 | `error_len` | Error message length |
| 19 | `error_len` | `error_msg` | UTF-8 error description |

### 3.11 ResizePaneRequest (0x014A)

Adjusts the split divider adjacent to a pane. The `direction` indicates which edge to move, and `delta` is the number of cells to move the divider.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `pane_id` | Reference pane |
| 32 | 1 | `direction` | Edge to move: 0=right, 1=down, 2=left, 3=up |
| 33 | 2 | `delta` | Number of cells to move (signed, as i16) |

**Semantics**: A positive delta moves the divider in the stated direction. For example, `direction=right, delta=5` grows the pane 5 columns to the right (shrinking the neighbor). A negative delta moves it in the opposite direction.

### 3.12 ResizePaneResponse (0x014B)

On success, the server follows with a `LayoutChanged` notification.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane not found, 2 = no split in that direction, 3 = minimum size reached |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

### 3.13 EqualizeSplitsRequest (0x014C)

Sets all split ratios in a tab to 0.5 (equal distribution).

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `tab_id` | Tab to equalize |

### 3.14 EqualizeSplitsResponse (0x014D)

On success, the server follows with a `LayoutChanged` notification.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = tab not found |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

### 3.15 ZoomPaneRequest (0x014E)

Toggles zoom on a pane. When zoomed, the pane fills the entire tab area. Other panes in the tab are hidden but their PTYs continue running.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `pane_id` | Pane to zoom/unzoom |

### 3.16 ZoomPaneResponse (0x014F)

On success, the server follows with a `LayoutChanged` notification (with a flag indicating zoom state).

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane not found |
| 1 | 1 | `zoomed` | 1 = pane is now zoomed, 0 = pane is now unzoomed |
| 2 | 2 | `error_len` | Error message length |
| 4 | `error_len` | `error_msg` | UTF-8 error description |

### 3.17 SwapPanesRequest (0x0150)

Swaps two panes in the layout tree. The PTY and shell process follow the pane -- only the position in the layout tree changes.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Parent session |
| 16 | 16 | `pane_a` | First pane |
| 32 | 16 | `pane_b` | Second pane |

### 3.18 SwapPanesResponse (0x0151)

On success, the server follows with a `LayoutChanged` notification.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane_a not found, 2 = pane_b not found, 3 = panes in different tabs |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

---

## 4. Layout Tree Wire Format

The layout tree is a recursive binary tree serialized in a depth-first pre-order traversal. Each node is either a **leaf** (pane) or a **split** (branch with exactly two children).

### Node Types

| Tag | Value | Description |
|-----|-------|-------------|
| `LEAF` | 0x00 | Pane node |
| `SPLIT` | 0x01 | Split node (has two children) |

### Leaf Node (Pane)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `tag` | 0x00 (LEAF) |
| 1 | 16 | `pane_id` | Pane UUID |
| 17 | 2 | `cols` | Pane width in columns |
| 19 | 2 | `rows` | Pane height in rows |
| 21 | 2 | `x_off` | Column offset within tab |
| 23 | 2 | `y_off` | Row offset within tab |

Total: 25 bytes per leaf.

### Split Node

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `tag` | 0x01 (SPLIT) |
| 1 | 1 | `orientation` | 0 = horizontal (left-right), 1 = vertical (top-bottom) |
| 2 | 4 | `ratio` | Split ratio as f32 (proportion of first child) |
| 6 | 2 | `cols` | Total width in columns |
| 8 | 2 | `rows` | Total height in rows |
| 10 | 2 | `x_off` | Column offset within tab |
| 12 | 2 | `y_off` | Row offset within tab |
| 14 | ... | `first` | First child node (recursive) |
| ... | ... | `second` | Second child node (recursive) |

Total: 14 bytes overhead per split + children.

### Example

A tab with two panes side by side (80x24 total, 40 columns each):

```
Split(horizontal, 0.5, 80x24)
  Leaf(pane_a, 40x24, 0,0)
  Leaf(pane_b, 40x24, 40,0)
```

Wire bytes (hex):
```
01                      // tag = SPLIT
00                      // orientation = horizontal (left-right)
00 00 00 3F             // ratio = 0.5 (IEEE 754 f32)
50 00                   // cols = 80
18 00                   // rows = 24
00 00                   // x_off = 0
00 00                   // y_off = 0
  00                    // tag = LEAF (first child)
  <16 bytes pane_a_uuid>
  28 00                 // cols = 40
  18 00                 // rows = 24
  00 00                 // x_off = 0
  00 00                 // y_off = 0
  00                    // tag = LEAF (second child)
  <16 bytes pane_b_uuid>
  28 00                 // cols = 40
  18 00                 // rows = 24
  28 00                 // x_off = 40
  00 00                 // y_off = 0
```

Total: 14 + 25 + 25 = 64 bytes for a 2-pane layout.

### Maximum Tree Depth

The server enforces a maximum tree depth of 16 levels. This allows up to 65,536 panes theoretically (though practical limits are much lower due to minimum pane sizes). Clients must be prepared to handle trees up to this depth.

---

## 5. Notifications

### 5.1 LayoutChanged (0x0180)

Sent by the server whenever the layout tree changes (split, close, resize, swap, zoom, window resize). This is the authoritative representation of the current layout.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Session UUID |
| 16 | 16 | `tab_id` | Tab UUID |
| 32 | 16 | `active_pane_id` | Currently focused pane |
| 48 | 1 | `zoomed_pane_present` | 1 = a pane is zoomed |
| 49 | 16 | `zoomed_pane_id` | Zoomed pane UUID (zero UUID if none) |
| 65 | 4 | `tree_size` | Size of serialized layout tree in bytes |
| 69 | `tree_size` | `layout_tree` | Serialized layout tree (see Section 4) |

**Delivery rules**:
- Sent to all clients attached to the affected session.
- After AttachSession success, one LayoutChanged is sent per tab (active tab first).
- After SplitPane, ClosePane, ResizePane, EqualizeSplits, ZoomPane, SwapPanes, or WindowResize, one LayoutChanged is sent for the affected tab.

### 5.2 PaneMetadataChanged (0x0181)

Sent when a pane's metadata changes. Sources include: OSC title sequences, shell integration CWD reporting, foreground process changes, and process exit.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Session UUID |
| 16 | 16 | `pane_id` | Pane UUID |
| 32 | 4 | `changed_fields` | Bitmask of which fields changed |
| 36 | variable | `fields` | Only changed fields are included |

**changed_fields bitmask**:

| Bit | Value | Field | Wire format |
|-----|-------|-------|-------------|
| 0 | 0x01 | `title` | u16 len + UTF-8 string |
| 1 | 0x02 | `cwd` | u16 len + UTF-8 string |
| 2 | 0x04 | `process_name` | u16 len + UTF-8 string |
| 3 | 0x08 | `exit_status` | i32 (exit code, or -signal_number) |
| 4 | 0x10 | `pid` | u32 (foreground process PID) |
| 5 | 0x20 | `is_running` | u8 (0 = exited, 1 = running) |

Fields are serialized in bitmask order (lowest bit first). Only fields whose bit is set in `changed_fields` are present in the payload.

**Example**: If title and cwd both changed (changed_fields = 0x03):
```
Offset 36: u16 title_len, UTF-8 title, u16 cwd_len, UTF-8 cwd
```

### 5.3 SessionListChanged (0x0182)

Sent to all connected clients when sessions are created or destroyed.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `event` | 0 = session created, 1 = session destroyed |
| 1 | 16 | `session_id` | Affected session UUID |
| 17 | 2 | `name_len` | Session name length |
| 19 | `name_len` | `name` | UTF-8 session name |

### 5.4 TabListChanged (0x0183)

Sent to all clients attached to a session when tabs are created, closed, renamed, or reordered.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Session UUID |
| 16 | 1 | `event` | 0 = tab created, 1 = tab closed, 2 = tab renamed, 3 = tab reordered |
| 17 | 16 | `tab_id` | Affected tab UUID |
| 33 | 2 | `position` | Current tab display position |
| 35 | 2 | `name_len` | Tab name length |
| 37 | `name_len` | `name` | UTF-8 tab name |
| 37+N | 2 | `total_tabs` | Total number of tabs after this event |
| 39+N | 16 | `active_tab_id` | Currently active tab UUID |

---

## 6. Window Resize

### 6.1 WindowResize (0x0190)

Sent by the client when its terminal window is resized. The server uses this to cascade-resize all panes in the active tab.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 16 | `session_id` | Session UUID |
| 16 | 2 | `cols` | New window width in columns |
| 18 | 2 | `rows` | New window height in rows |
| 20 | 2 | `pixel_width` | Pixel width (0 if unknown) |
| 22 | 2 | `pixel_height` | Pixel height (0 if unknown) |

**Resize cascade**:
1. Server receives WindowResize.
2. Server walks the layout tree, computing new cell dimensions for each pane based on split ratios.
3. For each pane with changed dimensions, the server calls `ioctl(pty_fd, TIOCSWINSZ, &new_size)` to notify the shell.
4. Server sends LayoutChanged with updated geometry.
5. Server sends FrameUpdate for each pane whose content changed due to resize.

Pixel dimensions are provided for applications that need sub-cell positioning (e.g., Sixel graphics, Kitty image protocol).

### 6.2 WindowResizeAck (0x0191)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success |

---

## 7. Error Codes

Status codes used across all response messages:

| Code | Name | Description |
|------|------|-------------|
| 0 | `OK` | Success |
| 1 | `NOT_FOUND` | Referenced entity (session/tab/pane) not found |
| 2 | `ALREADY_EXISTS` | Name collision or duplicate operation |
| 3 | `TOO_SMALL` | Cannot split -- pane below minimum size |
| 4 | `PROCESSES_RUNNING` | Cannot destroy -- processes still active |
| 5 | `ACCESS_DENIED` | Permission denied for this operation |
| 6 | `INVALID_ARGUMENT` | Invalid field value |
| 7 | `INTERNAL_ERROR` | Unexpected server error |

Each message type may map specific status values (e.g., DestroySession uses 2 for "processes running"), but the error codes above are the canonical set. The `error_msg` string provides a human-readable description.

---

## 8. Sequence Number Correlation

All request/response pairs share the same `sequence` number from the message header. The client assigns monotonically increasing sequence numbers to outgoing requests. The server echoes the sequence number in the corresponding response.

Notifications (LayoutChanged, PaneMetadataChanged, etc.) use sequence number 0, indicating they are not correlated to any specific client request. However, a notification that is a direct consequence of a request (e.g., LayoutChanged after SplitPane) is sent AFTER the response message, so the client can process the response first and then update the layout.

**Ordering guarantee**: For a given client connection, messages are delivered in order. The server never sends a response for request N+1 before the response for request N.

---

## 9. Multi-Client Behavior

Multiple clients can be attached to the same session simultaneously.

### Focus Model

- Each client tracks its own notion of which tab and pane is active.
- FocusPane and NavigatePane affect only the requesting client's focus state.
- **Open question**: Should focus be per-client or per-session? tmux uses per-session focus (all clients see the same active pane). Zellij is similar. Per-session focus is simpler but means one user's navigation affects all viewers.

**Decision for v1**: Per-session focus (like tmux). All clients share the same active tab and pane. This simplifies the protocol and matches the multiplexer mental model. Per-client focus can be added later as an opt-in capability.

### Layout Mutations

- SplitPane, ClosePane, ResizePane, etc., affect the shared layout.
- All attached clients receive the resulting LayoutChanged notification.
- WindowResize is per-client. If two clients have different window sizes, the server uses the **most recently attached** client's dimensions for the session's terminal size. Other clients may see padding or clipping.

**Open question**: Should we support independent sizes per client (like tmux's `aggressive-resize`)? This requires per-client viewport tracking, which is complex. Deferring to v2.

---

## 10. Open Questions

1. **Last-tab-close behavior**: Should closing the last tab in a session auto-destroy the session? Current design: no, require explicit DestroySession. This allows the client to show a "session has no tabs" state and offer to create a new tab or destroy.

2. **Pane minimum size**: What is the minimum pane size below which splits are rejected? Suggestion: 2 columns x 1 row (matching tmux's minimum).

3. **Tab limit**: Should there be a maximum number of tabs per session? Suggestion: soft limit of 256, configurable.

4. **Session auto-destroy**: Should sessions with no attached clients be destroyed after a timeout? Current design: never (daemon keeps sessions alive indefinitely until explicitly destroyed or the daemon exits).

5. **Zoom + split interaction**: If a pane is zoomed and the user requests a split, should we unzoom first and then split? Or reject the split while zoomed? tmux unzooms, which seems correct.

6. **Layout tree compression**: For deep trees or large numbers of panes, should we support a compressed layout wire format? The current depth-first format is simple but verbose for large trees. This can be deferred -- the maximum practical size (~50 panes) would only be ~1300 bytes.

7. **Pane reuse after exit**: When a shell process exits, should the pane remain visible (showing exit status) until explicitly closed, or auto-close? tmux has the `remain-on-exit` option. We should support both modes via per-pane or per-session configuration.
