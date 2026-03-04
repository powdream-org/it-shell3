# Handshake and Capability Negotiation

**Status**: Draft v0.2
**Date**: 2026-03-04
**Depends on**: [01-protocol-overview.md](./01-protocol-overview.md) (framing format, message type IDs, connection lifecycle)
**Scope**: `ClientHello` / `ServerHello` message formats, capability flags, negotiation algorithm, attach/detach semantics
**Changes from v0.1**: Removed Tab concept (Session = ghostty tab), updated preedit capability semantics for server-authoritative IME, updated message type IDs to unified range allocation, added resize algorithm for multi-client attach

---

## 1. Overview

The handshake phase occurs immediately after transport-layer connection. The client sends a `ClientHello` message declaring its identity and capabilities. The server responds with `ServerHello` declaring its capabilities and the negotiated feature set. The connection transitions from `HANDSHAKING` to `READY` on success.

```
Client                                  Server
  │                                       │
  │──── [transport connect] ─────────────►│
  │                                       │
  │──── ClientHello (0x0001) ────────────►│
  │     {version, client_type, name,      │
  │      capabilities, cjk_caps, ...}     │
  │                                       │  validate version
  │                                       │  validate auth (UID)
  │                                       │  compute negotiated caps
  │                                       │
  │◄──── ServerHello (0x0002) ────────────│
  │      {version, server_name,           │
  │       negotiated_caps, session_list}  │
  │                                       │
  │      [state → READY]                  │
  │                                       │
  │──── AttachSessionRequest (0x0104) ───►│
  │  or CreateSessionRequest (0x0100) ───►│
  │                                       │
  │◄──── AttachSessionResponse (0x0105) ──│
  │   or CreateSessionResponse (0x0101) ──│
  │                                       │
  │      [state → OPERATING]             │
```

---

## 2. ClientHello Message (`0x0001`)

### 2.1 Payload Layout

All multi-byte integers are little-endian. Strings are UTF-8, length-prefixed with a u16 byte count.

```
Offset  Size     Field                 Description
──────  ────     ─────                 ───────────
 0      1        protocol_version_min  Minimum protocol version the client supports
 1      1        protocol_version_max  Maximum protocol version the client supports
 2      1        client_type           Client type enum (see 2.2)
 3      1        reserved_0            Reserved, must be 0
 4      8        capabilities          Client capability flags (u64 bitfield, see Section 4)
12      4        cjk_capabilities      CJK capability flags (u32 bitfield, see Section 5)
16      4        render_capabilities   Render capability flags (u32 bitfield, see Section 6)
20      2        client_name_len       Length of client name string in bytes
22      N        client_name           UTF-8 client name (e.g., "it-shell3-macos", "it-shell3-ios")
22+N    2        client_version_len    Length of client version string in bytes
24+N    M        client_version        UTF-8 version string (e.g., "1.0.0")
24+N+M  2        terminal_type_len     Length of terminal type string in bytes
26+N+M  P        terminal_type         UTF-8 terminal type (e.g., "xterm-256color", "ghostty")
26+N+M+P 2       cols                  Initial terminal width in columns
28+N+M+P 2       rows                  Initial terminal height in rows
30+N+M+P 2       pixel_width           Pixel width of the terminal area (0 if unknown)
32+N+M+P 2       pixel_height          Pixel height of the terminal area (0 if unknown)
```

### 2.2 Client Type Enum

| Value | Name | Description |
|-------|------|-------------|
| `0x00` | `NATIVE` | it-shell3 native client (macOS or iOS) with Metal GPU rendering |
| `0x01` | `CONTROL` | Control/scripting client (no rendering, command-only) |
| `0x02` | `HEADLESS` | Headless client (testing, CI, automation) |
| `0x03` | `REMOTE` | Remote client over TCP/TLS |
| `0x04-0xFF` | Reserved | Future client types |

### 2.3 Example ClientHello

A macOS native client connecting for the first time:

```
Hex dump of ClientHello payload (example):

 0000: 01 01 00 00   version_min=1, version_max=1, client_type=NATIVE, reserved=0
 0004: 3F 00 00 00   capabilities = 0x0000_0000_0000_003F (bits 0-5 set)
       00 00 00 00
 000C: 0F 00 00 00   cjk_capabilities = 0x0000_000F (bits 0-3 set)
 0010: 07 00 00 00   render_capabilities = 0x0000_0007 (bits 0-2 set)
 0014: 10 00         client_name_len = 16
 0016: 69 74 2D 73   "it-shell3-macos"
       68 65 6C 6C
       33 2D 6D 61
       63 6F 73 00
 0026: 05 00         client_version_len = 5
 0028: 31 2E 30 2E   "1.0.0"
       30
 002D: 06 00         terminal_type_len = 6
 002F: 78 74 65 72   "xterm-"
       6D 2D
 0035: 00 50         cols = 80 (0x0050)
 0037: 00 18         rows = 24 (0x0018)
 0039: 00 00         pixel_width = 0
 003B: 00 00         pixel_height = 0
```

---

## 3. ServerHello Message (`0x0002`)

### 3.1 Payload Layout

```
Offset  Size     Field                   Description
──────  ────     ─────                   ───────────
 0      1        protocol_version        Negotiated protocol version
 1      1        reserved_0              Reserved, must be 0
 2      2        reserved_1              Reserved, must be 0
 4      8        negotiated_caps         Negotiated capability flags (u64 bitfield)
12      4        negotiated_cjk_caps     Negotiated CJK capability flags (u32 bitfield)
16      4        negotiated_render_caps  Negotiated render capability flags (u32 bitfield)
20      4        server_pid              Server daemon PID (for debugging)
24      2        server_name_len         Length of server name string in bytes
26      N        server_name             UTF-8 server name (e.g., "itshell3d")
26+N    2        server_version_len      Length of server version string in bytes
28+N    M        server_version          UTF-8 version string
28+N+M  4        heartbeat_interval_ms   Heartbeat interval in milliseconds (0 = no heartbeat)
32+N+M  2        max_panes_per_session   Maximum panes per session (0 = unlimited)
34+N+M  2        max_sessions            Maximum concurrent sessions (0 = unlimited)
36+N+M  2        session_count           Number of session descriptors that follow
38+N+M  ...      sessions[]              Array of SessionDescriptor (see 3.2)
```

### 3.2 SessionDescriptor (variable size)

Each existing session is described by a `SessionDescriptor`. This allows the client to display available sessions for attachment.

```
Offset  Size     Field              Description
──────  ────     ─────              ───────────
 0      4        session_id         Server-assigned session ID (u32)
 4      2        session_name_len   Length of session name in bytes
 6      N        session_name       UTF-8 session name (e.g., "main", "dev")
 6+N    1        attached_clients   Number of clients currently attached (u8)
 7+N    2        pane_count         Number of panes in this session (u16)
 9+N    8        created_at         Creation timestamp (milliseconds since Unix epoch, u64)
17+N    8        last_activity      Last activity timestamp (u64)
```

**v0.2 change**: Removed `tab_count` field. There is no Tab as a protocol entity in libitshell3. Each Session has one layout tree (a binary split tree of panes). The client UI presents Sessions as tabs — "new tab" creates a Session, "close tab" destroys a Session, "switch tab" is a client-local display switch, "rename tab" renames a Session. Tab functionality is fully preserved in the UI; only the intermediate Tab object between Session and Pane is removed from the wire protocol.

### 3.3 Example ServerHello

Server responding with one existing session:

```
Hex dump of ServerHello payload (example):

 0000: 01 00 00 00   protocol_version=1, reserved
 0004: 3F 00 00 00   negotiated_caps (same as client in this example)
       00 00 00 00
 000C: 0F 00 00 00   negotiated_cjk_caps
 0010: 07 00 00 00   negotiated_render_caps
 0014: B7 1A 00 00   server_pid = 6839
 0018: 09 00         server_name_len = 9
 001A: 69 74 73 68   "itshell3d"
       65 6C 6C 33
       64
 0023: 05 00         server_version_len = 5
 0025: 31 2E 30 2E   "1.0.0"
       30
 002A: 30 75 00 00   heartbeat_interval_ms = 30000 (30s)
 002E: 00 00         max_panes_per_session = 0 (unlimited)
 0030: 00 00         max_sessions = 0 (unlimited)
 0032: 01 00         session_count = 1

 -- SessionDescriptor[0] --
 0034: 01 00 00 00   session_id = 1
 0038: 04 00         session_name_len = 4
 003A: 6D 61 69 6E   "main"
 003E: 00            attached_clients = 0
 003F: 01 00         pane_count = 1
 0041: (8 bytes)     created_at = <timestamp>
 0049: (8 bytes)     last_activity = <timestamp>
```

---

## 4. General Capability Flags (u64)

The `capabilities` field in `ClientHello` and `negotiated_caps` field in `ServerHello` use the following bit assignments:

| Bit | Name | Description |
|-----|------|-------------|
| 0 | `CAP_COMPRESSION` | Supports zstd payload compression |
| 1 | `CAP_CLIPBOARD_SYNC` | Supports bidirectional clipboard synchronization |
| 2 | `CAP_MOUSE` | Supports mouse event forwarding |
| 3 | `CAP_SELECTION` | Supports text selection synchronization |
| 4 | `CAP_SEARCH` | Supports scrollback search |
| 5 | `CAP_FD_PASSING` | Supports file descriptor passing (Unix socket only) |
| 6 | `CAP_AGENT_DETECTION` | Supports AI agent input mode detection and profiles |
| 7 | `CAP_FLOW_CONTROL` | Supports pause/resume flow control messages |
| 8 | `CAP_PIXEL_DIMENSIONS` | Client provides pixel dimensions for cell size calculation |
| 9 | `CAP_SIXEL` | Supports Sixel graphics passthrough |
| 10 | `CAP_KITTY_GRAPHICS` | Supports Kitty graphics protocol passthrough |
| 11 | `CAP_NOTIFICATIONS` | Supports OSC notification forwarding |
| 12-63 | Reserved | Must be 0. Future protocol versions may define additional flags. |

### Capability Notes

- `CAP_COMPRESSION` is meaningful primarily over TCP/TLS transport. Over Unix sockets, compression adds CPU overhead with minimal bandwidth benefit.
- `CAP_FD_PASSING` is only valid for `AF_UNIX` transport. The server ignores this flag for TCP connections.
- `CAP_AGENT_DETECTION`: When negotiated, the server sends process-detection notifications when an AI agent is detected in a pane's foreground process, and the client can activate agent-specific input profiles.

---

## 5. CJK Capability Flags (u32)

The `cjk_capabilities` field uses the following bit assignments. These are separate from general capabilities because CJK support involves multiple independent features that compose differently.

| Bit | Name | Description |
|-----|------|-------------|
| 0 | `CJK_CAP_PREEDIT` | Supports IME preedit synchronization (`PreeditStart/Update/End`) |
| 1 | `CJK_CAP_AMBIGUOUS_WIDTH` | Supports ambiguous-width character configuration sync |
| 2 | `CJK_CAP_DOUBLE_WIDTH` | Supports double-width (fullwidth) character rendering |
| 3 | `CJK_CAP_PREEDIT_SYNC` | Supports multi-client preedit broadcast (`PreeditSync`) |
| 4 | `CJK_CAP_JAMO_DECOMPOSITION` | Supports Korean Jamo decomposition-aware backspace |
| 5 | `CJK_CAP_COMPOSITION_ENGINE` | Server has a native IME composition engine (libitshell3-ime) |
| 6-31 | Reserved | Must be 0. |

### CJK Capability Semantics

**`CJK_CAP_PREEDIT` (bit 0)**: The fundamental CJK feature. When negotiated:
- The server sends `PreeditStart` (`0x0400`), `PreeditUpdate` (`0x0401`), and `PreeditEnd` (`0x0402`) messages to the client
- The server tracks per-pane preedit state using its native IME engine (libitshell3-ime)
- Preedit state is included in `FrameUpdate` messages (preedit section) for the active pane
- The client sends raw HID keycodes via `KeyEvent`; the server processes them through the composition engine and pushes preedit state to all attached clients

**`CJK_CAP_AMBIGUOUS_WIDTH` (bit 1)**: When negotiated:
- Client and server sync `unicode-ambiguous-is-wide` configuration via `AmbiguousWidthConfig` (`0x0406`)
- Both sides agree on whether ambiguous-width characters occupy 1 or 2 cells

**`CJK_CAP_DOUBLE_WIDTH` (bit 2)**: When negotiated:
- The server sends proper `wide` cell attributes in `FrameUpdate`
- The client renders CJK ideographs at double width
- (This is expected to be supported by all it-shell3 clients; the flag exists for forward compatibility with minimal third-party clients)

**`CJK_CAP_PREEDIT_SYNC` (bit 3)**: Requires `CJK_CAP_PREEDIT`. When negotiated:
- The server broadcasts preedit state changes to all attached clients via `PreeditSync` (`0x0403`)
- Non-composing clients see the preedit overlay from the composing client
- Enables multi-viewer CJK composition (e.g., pair programming, shared terminal session)

**`CJK_CAP_JAMO_DECOMPOSITION` (bit 4)**: Requires `CJK_CAP_PREEDIT`. When negotiated:
- The server understands Korean Jamo decomposition rules
- Backspace during Korean composition correctly decomposes (`한` → `하` → `ㅎ` → empty)
- Without this flag, the server treats backspace as a simple character deletion

**`CJK_CAP_COMPOSITION_ENGINE` (bit 5)**: Informational flag. When set:
- Indicates the server runs libitshell3-ime's native composition engine (not relying on OS IME)
- The server can guarantee deterministic composition behavior
- Affects how preedit state is validated (native engine produces only valid Hangul sequences)

---

## 6. Render Capability Flags (u32)

| Bit | Name | Description |
|-----|------|-------------|
| 0 | `RENDER_CAP_CELL_DATA` | Supports structured cell data in FrameUpdate (RenderState protocol) |
| 1 | `RENDER_CAP_DIRTY_TRACKING` | Supports partial (delta) FrameUpdate with per-row dirty flags |
| 2 | `RENDER_CAP_CURSOR_STYLE` | Supports all cursor styles (block, bar, underline) |
| 3 | `RENDER_CAP_TRUE_COLOR` | Supports 24-bit RGB colors in cell data |
| 4 | `RENDER_CAP_256_COLOR` | Supports 256-color palette in cell data |
| 5 | `RENDER_CAP_UNDERLINE_STYLES` | Supports underline style variants (single, double, curly, dotted, dashed) |
| 6 | `RENDER_CAP_HYPERLINKS` | Supports OSC 8 hyperlink passthrough |
| 7 | `RENDER_CAP_VT_FALLBACK` | Supports VT re-serialization as a fallback rendering mode |
| 8-31 | Reserved | Must be 0. |

### Render Capability Notes

- `RENDER_CAP_CELL_DATA` is the primary rendering mode. All native it-shell3 clients support this.
- `RENDER_CAP_VT_FALLBACK` is for minimal/debug clients that prefer receiving raw VT escape sequences (via `TerminalFormatter`) instead of structured cell data. This is never the default.
- `RENDER_CAP_DIRTY_TRACKING` should be supported by all clients. Without it, the server sends full frames on every update (wasteful).

---

## 7. Negotiation Algorithm

### 7.1 Protocol Version

The server selects the negotiated protocol version as:

```
negotiated_version = min(server_max_version, client.protocol_version_max)

if negotiated_version < client.protocol_version_min:
    → send Error(ERR_VERSION_MISMATCH), disconnect
if negotiated_version < server_min_version:
    → send Error(ERR_VERSION_MISMATCH), disconnect
```

In v1, both `protocol_version_min` and `protocol_version_max` are `1`. This field exists for future version negotiation.

### 7.2 General Capabilities

```
negotiated_caps = client.capabilities & server.capabilities
```

Each capability is independently negotiated as the bitwise AND of client and server flags. A capability is active only if both sides support it.

### 7.3 CJK Capabilities

```
negotiated_cjk_caps = client.cjk_capabilities & server.cjk_capabilities
```

With dependency enforcement:

```
if not (negotiated_cjk_caps & CJK_CAP_PREEDIT):
    # Preedit is the foundation; without it, dependent caps are meaningless
    negotiated_cjk_caps &= ~CJK_CAP_PREEDIT_SYNC
    negotiated_cjk_caps &= ~CJK_CAP_JAMO_DECOMPOSITION
```

### 7.4 Render Capabilities

```
negotiated_render_caps = client.render_capabilities & server.render_capabilities
```

The server validates that at least one rendering mode is supported:

```
if not (negotiated_render_caps & (RENDER_CAP_CELL_DATA | RENDER_CAP_VT_FALLBACK)):
    → send Error(ERR_CAPABILITY_REQUIRED, detail="No common rendering mode"), disconnect
```

### 7.5 Negotiation Summary

```
Client                                  Server
  │                                       │
  │  ClientHello:                         │
  │    version_min=1, version_max=1       │
  │    caps = 0x3F                        │
  │    cjk = 0x0F                         │
  │    render = 0x07                      │
  │                                       │
  │                                       │  server_caps = 0x1F
  │                                       │  server_cjk = 0x07
  │                                       │  server_render = 0x07
  │                                       │
  │                                       │  negotiated_caps = 0x3F & 0x1F = 0x1F
  │                                       │  negotiated_cjk = 0x0F & 0x07 = 0x07
  │                                       │  negotiated_render = 0x07 & 0x07 = 0x07
  │                                       │
  │  ServerHello:                         │
  │    version = 1                        │
  │    caps = 0x1F (negotiated)           │
  │    cjk = 0x07 (negotiated)            │
  │    render = 0x07 (negotiated)         │
  │                                       │
  │  Both sides now use negotiated caps   │
```

---

## 8. Attach/Detach Semantics

### 8.1 Session Attach (`0x0104`)

After handshake completes (state = `READY`), the client attaches to a session.

**AttachSessionRequest payload:**

```
Offset  Size  Field              Description
──────  ────  ─────              ───────────
 0      4     session_id         ID of session to attach to (from SessionDescriptor in ServerHello)
 4      2     cols               Client terminal width in columns
 6      2     rows               Client terminal height in rows
 8      2     pixel_width        Client pixel width (0 if unknown)
10      2     pixel_height       Client pixel height (0 if unknown)
12      1     attach_flags       Attach behavior flags (see below)
13      1     reserved           Must be 0
```

**Attach flags:**

| Bit | Name | Description |
|-----|------|-------------|
| 0 | `ATTACH_READONLY` | Attach as read-only viewer (no input forwarding) |
| 1 | `ATTACH_DETACH_OTHERS` | Detach other clients from this session (exclusive mode) |
| 2-7 | Reserved | Must be 0. |

### 8.2 Session Attached Response (`0x0105`)

**AttachSessionResponse payload:**

```
Offset  Size  Field              Description
──────  ────  ─────              ───────────
 0      4     session_id         Session ID
 4      4     active_pane_id     Currently focused pane ID (u32)
 8      2     session_cols       Session terminal width (may differ from requested if other clients attached)
10      2     session_rows       Session terminal height
12      2     layout_data_len    Length of layout data (serialized pane tree)
14      N     layout_data        JSON-encoded layout tree (pane hierarchy with split positions)
14+N    ...   (FrameUpdate)      Immediately followed by a FrameUpdate (msg_type=0x0300) with dirty=full
```

**v0.2 changes**: Removed `active_tab_id` field (no Tab protocol entity — the client UI presents Sessions as tabs). The `layout_data` now encodes the session's single pane tree (binary splits), not a tab-pane hierarchy. FrameUpdate message type updated to `0x0300` per unified range allocation.

After receiving `AttachSessionResponse`, the client:
1. Parses the layout tree to create local pane views
2. Processes the following `FrameUpdate` (with `dirty=full`) to render the initial viewport
3. Transitions to `OPERATING` state

### 8.3 Session Create (`0x0100`)

If the client wants a new session instead of attaching to an existing one:

**CreateSessionRequest payload:**

```
Offset  Size  Field              Description
──────  ────  ─────              ───────────
 0      2     session_name_len   Desired session name length (0 for auto-generated)
 2      N     session_name       UTF-8 session name
 2+N    2     cols               Terminal width
 4+N    2     rows               Terminal height
 6+N    2     pixel_width        Pixel width (0 if unknown)
 8+N    2     pixel_height       Pixel height (0 if unknown)
10+N    2     shell_cmd_len      Custom shell command length (0 for default)
12+N    M     shell_cmd          UTF-8 shell command (e.g., "/bin/zsh")
12+N+M  2     cwd_len            Working directory length (0 for $HOME)
14+N+M  P     cwd                UTF-8 working directory path
```

**CreateSessionResponse (`0x0101`):**

```
Offset  Size  Field              Description
──────  ────  ─────              ───────────
 0      4     session_id         Newly assigned session ID (u32)
 4      4     pane_id            ID of the initial pane (u32)
 8      2     session_name_len   Actual session name length (may differ from requested)
10      N     session_name       UTF-8 session name
```

**v0.2 change**: Removed `tab_id` field. There is no Tab protocol entity — each Session directly owns one pane tree. The initial pane is the root of the session's layout tree.

This is immediately followed by a `FrameUpdate` with `dirty=full` for the initial pane.

### 8.4 Session Detach (`0x0106`)

**DetachSessionRequest payload:**

```
Offset  Size  Field         Description
──────  ────  ─────         ───────────
 0      4     session_id    Session to detach from (must be currently attached)
 4      1     reason        Detach reason enum:
                              0x00 = CLIENT_REQUEST (user initiated)
                              0x01 = SESSION_SWITCH (switching to another session)
                              0x02 = CLIENT_SHUTDOWN (client is closing)
```

**DetachSessionResponse (`0x0107`):**

```
Offset  Size  Field         Description
──────  ────  ─────         ───────────
 0      4     session_id    Session detached from
 4      1     session_alive Whether the session is still running (u8 bool)
```

After detach:
- Connection state returns to `READY`
- The client can attach to another session or disconnect
- The session continues running in the daemon (sessions survive client detach)

### 8.5 Multi-Client Attach

Multiple clients can attach to the same session simultaneously. The server handles this by:

1. **Terminal dimensions**: Uses the minimum (cols, rows) across all attached clients (like tmux `aggressive-resize`). See resize algorithm below.
2. **Input forwarding**: All non-readonly clients can send input. The server processes input in arrival order.
3. **Preedit exclusivity**: Only one client can have active preedit per pane. The server owns the IME engine — if a client sends a `KeyEvent` that triggers composition while another client's composition is already active on the same pane, the server cancels the first client's composition (sends `PreeditEnd` with reason `CANCELLED` to the first client) before starting the new one.
4. **Frame updates**: All clients receive `FrameUpdate` messages. Each client renders at its own pace; `FrameAck` is per-client.
5. **Detach notification**: When a client detaches, other clients receive a `ServerNotification` about the client count change.

### 8.6 Multi-Client Resize Algorithm

When any client sends `WindowResize`:

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
5. If unchanged: send WindowResizeAck to the sending client only.
```

When a client **detaches**:

```
1. Remove the client's dimensions from the tracking set.
2. Recompute effective size (may increase if the detaching client had
   the smallest dimensions).
3. If size changed: resize cascade (same as above).
```

Per-client virtual viewports (where each client sees a viewport into a larger terminal) are deferred to v2.

---

## 9. Graceful Fallback Matrix

This matrix shows behavior when capabilities differ between client and server:

### 9.1 CJK Capability Fallback

| Client | Server | Behavior |
|--------|--------|----------|
| `CJK_CAP_PREEDIT` = 1 | `CJK_CAP_PREEDIT` = 1 | Full preedit sync: server sends preedit messages to client, server tracks IME state, FrameUpdate includes preedit section |
| `CJK_CAP_PREEDIT` = 1 | `CJK_CAP_PREEDIT` = 0 | No server-side composition. Client handles composition locally if it has its own IME. Committed text goes through normal `KeyInput`. |
| `CJK_CAP_PREEDIT` = 0 | `CJK_CAP_PREEDIT` = 1 | Standard input: server does not send PreeditStart/Update/End to this client. Client sends committed text only. FrameUpdate preedit section is still included (it is part of the visual render state). |
| `CJK_CAP_PREEDIT` = 0 | `CJK_CAP_PREEDIT` = 0 | Standard input. No CJK composition awareness. |

| Client | Server | Behavior |
|--------|--------|----------|
| `CJK_CAP_PREEDIT_SYNC` = 1 | `CJK_CAP_PREEDIT_SYNC` = 1 | Multi-client preedit: all attached clients see preedit overlays from the composing client |
| `CJK_CAP_PREEDIT_SYNC` = 1 | `CJK_CAP_PREEDIT_SYNC` = 0 | Single-client preedit: only the composing client sees its own preedit. Server does not broadcast. |
| `CJK_CAP_PREEDIT_SYNC` = 0 | `CJK_CAP_PREEDIT_SYNC` = 1 | This client opts out of preedit broadcast. Server does not send `PreeditSync` to this client. Other clients may still see synced preedit. |

| Client | Server | Behavior |
|--------|--------|----------|
| `CJK_CAP_JAMO_DECOMPOSITION` = 1 | `CJK_CAP_JAMO_DECOMPOSITION` = 1 | Korean backspace decomposes Jamo (`한` → `하` → `ㅎ`). Server's IME engine updates preedit state accordingly. |
| `CJK_CAP_JAMO_DECOMPOSITION` = 1 | `CJK_CAP_JAMO_DECOMPOSITION` = 0 | Server's IME engine does not support Jamo decomposition. Backspace during Korean composition deletes the entire composed character. |
| `CJK_CAP_JAMO_DECOMPOSITION` = 0 | `CJK_CAP_JAMO_DECOMPOSITION` = 1 | Server has the capability but client does not need it. No effect. |

| Client | Server | Behavior |
|--------|--------|----------|
| `CJK_CAP_AMBIGUOUS_WIDTH` = 1 | `CJK_CAP_AMBIGUOUS_WIDTH` = 1 | Ambiguous width setting synced via `AmbiguousWidthConfig`. Both sides render consistently. |
| Either side = 0 | | Default ambiguous width (1 cell). No sync. Minor rendering inconsistencies possible for ambiguous characters. |

### 9.2 Render Capability Fallback

| Client | Server | Behavior |
|--------|--------|----------|
| `RENDER_CAP_CELL_DATA` = 1 | `RENDER_CAP_CELL_DATA` = 1 | Structured cell data rendering (primary mode) |
| `RENDER_CAP_CELL_DATA` = 0, `RENDER_CAP_VT_FALLBACK` = 1 | `RENDER_CAP_VT_FALLBACK` = 1 | VT re-serialization mode: server sends raw VT escape sequences |
| Neither rendering mode | | Handshake fails with `ERR_CAPABILITY_REQUIRED` |

| Client | Server | Behavior |
|--------|--------|----------|
| `RENDER_CAP_DIRTY_TRACKING` = 1 | `RENDER_CAP_DIRTY_TRACKING` = 1 | Delta updates: only changed rows sent in FrameUpdate |
| `RENDER_CAP_DIRTY_TRACKING` = 0 | | Full frame on every update. Higher bandwidth, but always works. |

### 9.3 General Capability Fallback

| Capability | When Not Negotiated |
|------------|---------------------|
| `CAP_COMPRESSION` | All payloads sent uncompressed. No impact on correctness. |
| `CAP_CLIPBOARD_SYNC` | No clipboard synchronization. Client clipboard is local only. |
| `CAP_MOUSE` | Mouse events not forwarded. Terminal applications that need mouse input will not work correctly. |
| `CAP_SELECTION` | No selection sync across clients. Each client manages selection locally. |
| `CAP_SEARCH` | Scrollback search not available. Client can still scroll. |
| `CAP_FD_PASSING` | No file descriptor passing. All data goes through the protocol. |
| `CAP_FLOW_CONTROL` | Server drops frames when client is slow instead of pausing. May cause visible frame skipping. |

---

## 10. Disconnect and Reconnection

### 10.1 Graceful Disconnect (`0x0005`)

**Disconnect payload:**

```
Offset  Size  Field         Description
──────  ────  ─────         ───────────
 0      1     reason        Disconnect reason enum:
                              0x00 = NORMAL (graceful shutdown)
                              0x01 = ERROR (unrecoverable error)
                              0x02 = TIMEOUT (heartbeat timeout)
                              0x03 = VERSION_MISMATCH (during handshake)
                              0x04 = AUTH_FAILED (during handshake)
                              0x05 = SERVER_SHUTDOWN (server is shutting down)
                              0x06 = REPLACED (another client with ATTACH_DETACH_OTHERS)
 1      2     detail_len    Length of detail string
 3      N     detail        UTF-8 detail string
```

### 10.2 Reconnection

When a client reconnects to a running daemon:

1. Client establishes a new connection
2. Normal `ClientHello` / `ServerHello` handshake
3. Client sees its previous session in the `ServerHello` session list
4. Client sends `AttachSessionRequest` with the previous session ID
5. Server responds with `AttachSessionResponse` + full `FrameUpdate`
6. Client is fully resynchronized

There is no incremental reconnection (no "replay from sequence N"). Every reconnection is a full state resync via `FrameUpdate` with `dirty=full`. This is simple and reliable; the full state is typically under 35 KB.

---

## 11. Security Considerations

### 11.1 Unix Socket Authentication

On Unix domain sockets, the server authenticates clients by:

1. **Kernel-level UID check**: `getpeereid()` (macOS) or `SO_PEERCRED` (Linux) provides the peer's UID. Only connections from the same UID as the daemon are accepted.
2. **Socket file permissions**: `0600` (owner-only read/write). Prevents non-owner access at the filesystem level.
3. **Directory permissions**: `0700` on the socket directory.

No additional authentication is needed for Unix socket transport because the OS kernel guarantees the peer identity.

### 11.2 TCP/TLS Authentication (Future)

For network transport, mutual TLS authentication is planned:

1. Server and client each have a TLS certificate
2. Pre-shared CA or certificate pinning
3. SRP (Secure Remote Password) as an alternative for password-based auth without PKI

The handshake protocol is transport-agnostic — the same `ClientHello`/`ServerHello` messages are used. Authentication is handled at the transport layer (TLS) before the application-layer handshake begins.

### 11.3 Handshake Timeouts

| Timeout | Duration | Action |
|---------|----------|--------|
| Transport connection | 5 seconds | Close socket, report connection failure |
| `ClientHello` → `ServerHello` | 5 seconds | Send `Error(ERR_INVALID_STATE)`, close |
| `READY` → `AttachSessionRequest`/`CreateSessionRequest` | 60 seconds | Send `Disconnect(TIMEOUT)`, close |
| Heartbeat response | 90 seconds | Send `Disconnect(TIMEOUT)`, close |

---

## 12. Design Decisions Needing Validation

| Decision | Status | Notes |
|----------|--------|-------|
| u64 for general capabilities | **Proposed** | 64 bits provides room for growth. Currently using 12 of 64. If more are needed, a second capability word can be added in a future protocol version. |
| Separate CJK capability field | **Proposed** | Keeps CJK concerns in a dedicated namespace. Could have been bits in the general capabilities field, but separation makes the CJK feature matrix clearer. |
| JSON for layout data in AttachSessionResponse | **Proposed** | JSON is simple to implement (`std.json` in Zig) and human-readable for debugging. Binary layout encoding would be more compact but harder to debug. Layout data is sent infrequently (only on attach/layout change), so JSON overhead is acceptable. |
| Full state resync on reconnect (no incremental replay) | **Proposed** | Simpler to implement and reason about. Full FrameUpdate is under 35 KB. If reconnection latency becomes a problem, incremental replay can be added later by tracking per-client sequence watermarks. |
| Heartbeat interval 30s | **Proposed** | Matches common practice (SSH default is 15s with 3 retries = 45s). Adjustable via `heartbeat_interval_ms` in ServerHello. |
| Preedit exclusivity (one compositor per pane) | **Decided** | Two users composing CJK in the same pane simultaneously is an unlikely and confusing scenario. Server owns IME — incoming `KeyEvent` that triggers composition cancels any existing composition on that pane from another client. |
| No Tab protocol entity | **Decided** | Hierarchy is Daemon > Session > Pane tree. The client UI presents Sessions as tabs (new tab = CreateSession, close tab = DestroySession, switch tab = client-local, rename tab = RenameSession). Tab functionality is preserved in the UI; only the intermediate Tab object is removed from the wire protocol. |
| Minimum (cols, rows) for multi-client | **Decided** | Per-client viewports deferred to v2. Minimum sizing matches tmux's proven approach. |
