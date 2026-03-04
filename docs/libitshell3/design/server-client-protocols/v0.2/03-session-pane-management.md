# 03 - Session and Pane Management Protocol

**Version**: v0.2
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

### Conventions

- All multi-byte integers are little-endian.
- Strings are UTF-8 encoded, length-prefixed with a `u16` byte count (NOT null-terminated).
- Boolean fields are `u8`: 0 = false, 1 = true.
- "Payload offset" means byte offset from the start of the payload (i.e., after the 16-byte header).
- `payload_len` in the header is the payload size only (NOT including the 16-byte header). Total message size on wire = 16 + payload_len.
- All request messages expect a corresponding response message. The response carries the same sequence number as the request for correlation (RESPONSE flag = 1).
- Directions use `u8`: 0 = right, 1 = down, 2 = left, 3 = up (matches ghostty's `GHOSTTY_SPLIT_DIRECTION`).
- Ratios are `f32` (IEEE 754, 4 bytes) in the range [0.0, 1.0].

### ID Types

| Type | Wire Size | Description |
|------|-----------|-------------|
| `session_id` | u32 (4 bytes) | Server-assigned, monotonically increasing. Never reused during daemon lifetime. |
| `pane_id` | u32 (4 bytes) | Server-assigned, monotonically increasing. Never reused during daemon lifetime. |

ID counters are per-type: session IDs and pane IDs use independent counters (session 1 and pane 1 can coexist). ID 0 is reserved as a sentinel value (meaning "none" or "invalid").

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
| 1 | 4 | `session_id` | ID of created session (valid if status=0) |
| 5 | 4 | `pane_id` | ID of initial pane |
| 9 | 2 | `error_len` | Length of error message (0 if success) |
| 11 | `error_len` | `error_msg` | UTF-8 error description |

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
| 0 | 4 | `session_id` | Session ID |
| 4 | 2 | `name_len` | Session name length |
| 6 | `name_len` | `name` | UTF-8 session name |
| 6+N | 8 | `created_at` | Unix timestamp (seconds, u64) |
| 14+N | 2 | `pane_count` | Total panes in the session |
| 16+N | 2 | `client_count` | Number of attached clients |

### 1.5 AttachSessionRequest (0x0104)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Session to attach to |
| 4 | 2 | `cols` | Client terminal columns |
| 6 | 2 | `rows` | Client terminal rows |
| 8 | 1 | `readonly` | 1 = read-only attachment (observer mode) |

### 1.6 AttachSessionResponse (0x0105)

On success, the server follows this response with a `LayoutChanged` notification containing the full layout tree and a full `FrameUpdate` for each visible pane. If the session has active preedit on any pane, a `PreeditSync` is also sent.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = session not found, 2 = access denied |
| 1 | 4 | `session_id` | Confirmed session ID |
| 5 | 2 | `name_len` | Session name length |
| 7 | `name_len` | `name` | UTF-8 session name |
| 7+N | 4 | `active_pane_id` | Active pane ID |
| 11+N | 2 | `error_len` | Error message length (0 if success) |
| 13+N | `error_len` | `error_msg` | UTF-8 error description |

### 1.7 DetachSessionRequest (0x0106)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Session to detach from |

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
| 0 | 4 | `session_id` | Session to destroy |
| 4 | 1 | `force` | 1 = force-kill even if processes are running |

### 1.10 DestroySessionResponse (0x0109)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = session not found, 2 = processes still running (and force=0) |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

### 1.11 RenameSessionRequest (0x010A)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Session to rename |
| 4 | 2 | `name_len` | New name length |
| 6 | `name_len` | `name` | UTF-8 new session name |

### 1.12 RenameSessionResponse (0x010B)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = session not found, 2 = name already in use |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

---

## 2. Pane Messages

### 2.1 CreatePaneRequest (0x0140)

Creates a standalone pane in the specified session. This is rarely used directly -- most panes are created via SplitPane. Useful for programmatic session population.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Parent session |
| 4 | 2 | `shell_len` | Shell path length (0 = default) |
| 6 | `shell_len` | `shell` | UTF-8 shell path |
| 6+N | 2 | `cwd_len` | Working directory length (0 = default) |
| 8+N | `cwd_len` | `cwd` | UTF-8 working directory |

**Note**: This replaces the current layout root. If the session already has panes, the new pane becomes the entire layout. To add a pane alongside existing panes, use SplitPane.

### 2.2 CreatePaneResponse (0x0141)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = session not found |
| 1 | 4 | `pane_id` | ID of created pane |
| 5 | 2 | `error_len` | Error message length |
| 7 | `error_len` | `error_msg` | UTF-8 error description |

### 2.3 SplitPaneRequest (0x0142)

Splits an existing pane into two. The existing pane becomes one half; a new pane is spawned in the other half.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Parent session |
| 4 | 4 | `pane_id` | Pane to split |
| 8 | 1 | `direction` | Split direction: 0=right, 1=down, 2=left, 3=up |
| 9 | 4 | `ratio` | Initial split ratio as f32 (0.5 = equal split) |
| 13 | 2 | `shell_len` | Shell path for new pane (0 = default) |
| 15 | `shell_len` | `shell` | UTF-8 shell path |
| 15+N | 2 | `cwd_len` | Working directory (0 = inherit from split pane) |
| 17+N | `cwd_len` | `cwd` | UTF-8 working directory |
| 17+N+M | 1 | `focus_new` | 1 = focus the new pane, 0 = keep focus on original |

**Split direction semantics**:
- `right` (0): Vertical split. Original pane becomes left, new pane appears on right.
- `down` (1): Horizontal split. Original pane becomes top, new pane appears on bottom.
- `left` (2): Vertical split. New pane appears on left, original becomes right.
- `up` (3): Horizontal split. New pane appears on top, original becomes bottom.

The `ratio` describes the proportion of space given to the **first** child (the child containing the original pane in a right/down split, or the new pane in a left/up split).

### 2.4 SplitPaneResponse (0x0143)

On success, the server follows with a `LayoutChanged` notification.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane not found, 2 = too small to split |
| 1 | 4 | `new_pane_id` | ID of newly created pane |
| 5 | 2 | `error_len` | Error message length |
| 7 | `error_len` | `error_msg` | UTF-8 error description |

### 2.5 ClosePaneRequest (0x0144)

Closes a pane. Its shell receives SIGHUP. In the layout tree, the parent split node is replaced by the sibling pane.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Parent session |
| 4 | 4 | `pane_id` | Pane to close |
| 8 | 1 | `force` | 1 = SIGKILL if SIGHUP does not terminate within timeout |

### 2.6 ClosePaneResponse (0x0145)

If the closed pane was the last pane in the session, the session is also destroyed. The response indicates what happened.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane not found |
| 1 | 1 | `side_effect` | 0 = none, 1 = session also destroyed |
| 2 | 4 | `new_focus_pane_id` | New focused pane (0 if session destroyed) |
| 6 | 2 | `error_len` | Error message length |
| 8 | `error_len` | `error_msg` | UTF-8 error description |

### 2.7 FocusPaneRequest (0x0146)

Sets the focused (active) pane within the session.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Parent session |
| 4 | 4 | `pane_id` | Pane to focus |

### 2.8 FocusPaneResponse (0x0147)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane not found |
| 1 | 4 | `previous_pane_id` | Previously focused pane |
| 5 | 2 | `error_len` | Error message length |
| 7 | `error_len` | `error_msg` | UTF-8 error description |

### 2.9 NavigatePaneRequest (0x0148)

Moves focus to the nearest pane in the given direction from the current focused pane.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Parent session |
| 4 | 1 | `direction` | 0=right, 1=down, 2=left, 3=up |

**Navigation algorithm**: The server computes the geometric position of each pane from the session's layout tree, then finds the nearest pane in the requested direction from the center of the currently focused pane. If no pane exists in that direction, the focus wraps around (configurable).

### 2.10 NavigatePaneResponse (0x0149)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = no pane in that direction |
| 1 | 4 | `focused_pane_id` | Newly focused pane ID |
| 5 | 2 | `error_len` | Error message length |
| 7 | `error_len` | `error_msg` | UTF-8 error description |

### 2.11 ResizePaneRequest (0x014A)

Adjusts the split divider adjacent to a pane. The `direction` indicates which edge to move, and `delta` is the number of cells to move the divider.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Parent session |
| 4 | 4 | `pane_id` | Reference pane |
| 8 | 1 | `direction` | Edge to move: 0=right, 1=down, 2=left, 3=up |
| 9 | 2 | `delta` | Number of cells to move (signed, as i16) |

**Semantics**: A positive delta moves the divider in the stated direction. For example, `direction=right, delta=5` grows the pane 5 columns to the right (shrinking the neighbor). A negative delta moves it in the opposite direction.

### 2.12 ResizePaneResponse (0x014B)

On success, the server follows with a `LayoutChanged` notification.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane not found, 2 = no split in that direction, 3 = minimum size reached |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

### 2.13 EqualizeSplitsRequest (0x014C)

Sets all split ratios in a session's layout tree to 0.5 (equal distribution).

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Session to equalize |

### 2.14 EqualizeSplitsResponse (0x014D)

On success, the server follows with a `LayoutChanged` notification.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = session not found |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

### 2.15 ZoomPaneRequest (0x014E)

Toggles zoom on a pane. When zoomed, the pane fills the entire session area. Other panes in the session are hidden but their PTYs continue running.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Parent session |
| 4 | 4 | `pane_id` | Pane to zoom/unzoom |

### 2.16 ZoomPaneResponse (0x014F)

On success, the server follows with a `LayoutChanged` notification (with a flag indicating zoom state).

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane not found |
| 1 | 1 | `zoomed` | 1 = pane is now zoomed, 0 = pane is now unzoomed |
| 2 | 2 | `error_len` | Error message length |
| 4 | `error_len` | `error_msg` | UTF-8 error description |

### 2.17 SwapPanesRequest (0x0150)

Swaps two panes in the layout tree. The PTY and shell process follow the pane -- only the position in the layout tree changes. Preedit state (if active) follows the pane.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Parent session |
| 4 | 4 | `pane_a` | First pane |
| 8 | 4 | `pane_b` | Second pane |

### 2.18 SwapPanesResponse (0x0151)

On success, the server follows with a `LayoutChanged` notification.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success, 1 = pane_a not found, 2 = pane_b not found |
| 1 | 2 | `error_len` | Error message length |
| 3 | `error_len` | `error_msg` | UTF-8 error description |

### 2.19 LayoutGetRequest (0x0152)

Requests the current layout tree for a session. Use case: client wants to refresh layout state after missing a notification, or a monitoring tool queries layout on demand.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Session to query |

### 2.20 LayoutGetResponse (0x0153)

Returns the same payload format as `LayoutChanged` (Section 4.1), with the RESPONSE flag set and echoing the request's sequence number.

---

## 3. Layout Tree Wire Format

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
| 1 | 4 | `pane_id` | Pane ID (u32) |
| 5 | 2 | `cols` | Pane width in columns |
| 7 | 2 | `rows` | Pane height in rows |
| 9 | 2 | `x_off` | Column offset within session |
| 11 | 2 | `y_off` | Row offset within session |
| 13 | 1 | `flags` | Pane flags (see below) |

Total: 14 bytes per leaf.

**flags bitmask**:

| Bit | Value | Description |
|-----|-------|-------------|
| 0 | 0x01 | `preedit_active` — pane has active IME composition |
| 1-7 | | Reserved (must be 0) |

### Split Node

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `tag` | 0x01 (SPLIT) |
| 1 | 1 | `orientation` | 0 = horizontal (left-right), 1 = vertical (top-bottom) |
| 2 | 4 | `ratio` | Split ratio as f32 (proportion of first child) |
| 6 | 2 | `cols` | Total width in columns |
| 8 | 2 | `rows` | Total height in rows |
| 10 | 2 | `x_off` | Column offset within session |
| 12 | 2 | `y_off` | Row offset within session |
| 14 | ... | `first` | First child node (recursive) |
| ... | ... | `second` | Second child node (recursive) |

Total: 14 bytes overhead per split + children.

### Example

A session with two panes side by side (80x24 total, 40 columns each):

```
Split(horizontal, 0.5, 80x24)
  Leaf(pane_1, 40x24, 0,0)
  Leaf(pane_2, 40x24, 40,0)
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
  01 00 00 00           // pane_id = 1
  28 00                 // cols = 40
  18 00                 // rows = 24
  00 00                 // x_off = 0
  00 00                 // y_off = 0
  00                    // flags = 0 (no active preedit)
  00                    // tag = LEAF (second child)
  02 00 00 00           // pane_id = 2
  28 00                 // cols = 40
  18 00                 // rows = 24
  28 00                 // x_off = 40
  00 00                 // y_off = 0
  00                    // flags = 0 (no active preedit)
```

Total: 14 + 14 + 14 = 42 bytes for a 2-pane layout.

### Maximum Tree Depth

The server enforces a maximum tree depth of 16 levels. This allows up to 65,536 panes theoretically (though practical limits are much lower due to minimum pane sizes). Clients must be prepared to handle trees up to this depth.

---

## 4. Notifications

### 4.1 LayoutChanged (0x0180)

Sent by the server whenever the layout tree changes (split, close, resize, swap, zoom, window resize). This is the authoritative representation of the current layout.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Session ID |
| 4 | 4 | `active_pane_id` | Currently focused pane |
| 8 | 1 | `zoomed_pane_present` | 1 = a pane is zoomed |
| 9 | 4 | `zoomed_pane_id` | Zoomed pane ID (0 if none) |
| 13 | 4 | `tree_size` | Size of serialized layout tree in bytes |
| 17 | `tree_size` | `layout_tree` | Serialized layout tree (see Section 3) |

**Delivery rules**:
- Sent to all clients attached to the affected session.
- After AttachSession success, one LayoutChanged is sent for the session.
- After SplitPane, ClosePane, ResizePane, EqualizeSplits, ZoomPane, SwapPanes, or WindowResize, one LayoutChanged is sent for the affected session.

### 4.2 PaneMetadataChanged (0x0181)

Sent when a pane's metadata changes. Sources include: OSC title sequences, shell integration CWD reporting, foreground process changes, and process exit.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Session ID |
| 4 | 4 | `pane_id` | Pane ID |
| 8 | 4 | `changed_fields` | Bitmask of which fields changed |
| 12 | variable | `fields` | Only changed fields are included |

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
Offset 12: u16 title_len, UTF-8 title, u16 cwd_len, UTF-8 cwd
```

### 4.3 SessionListChanged (0x0182)

Sent to all connected clients when sessions are created or destroyed.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `event` | 0 = session created, 1 = session destroyed |
| 1 | 4 | `session_id` | Affected session ID |
| 5 | 2 | `name_len` | Session name length |
| 7 | `name_len` | `name` | UTF-8 session name |

---

## 5. Window Resize

### 5.1 WindowResize (0x0190)

Sent by the client when its terminal window is resized. The server uses this to cascade-resize all panes in the session.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | `session_id` | Session ID |
| 4 | 2 | `cols` | New window width in columns |
| 6 | 2 | `rows` | New window height in rows |
| 8 | 2 | `pixel_width` | Pixel width (0 if unknown) |
| 10 | 2 | `pixel_height` | Pixel height (0 if unknown) |

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

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `status` | 0 = success |

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

Each message type may map specific status values (e.g., DestroySession uses 2 for "processes running"), but the error codes above are the canonical set. The `error_msg` string provides a human-readable description.

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

5. **Layout tree compression**: For deep trees or large numbers of panes, should we support a compressed layout wire format? The current depth-first format is simple but verbose for large trees. This can be deferred -- the maximum practical size (~50 panes) would only be ~750 bytes with u32 IDs.

6. **Pane reuse after exit**: When a shell process exits, should the pane remain visible (showing exit status) until explicitly closed, or auto-close? tmux has the `remain-on-exit` option. We should support both modes via per-pane or per-session configuration.
