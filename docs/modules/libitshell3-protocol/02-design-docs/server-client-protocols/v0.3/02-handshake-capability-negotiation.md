# Handshake and Capability Negotiation

**Status**: Draft v0.3
**Date**: 2026-03-04
**Depends on**: [01-protocol-overview.md](./01-protocol-overview.md) (framing format, message type IDs, connection lifecycle)
**Scope**: `ClientHello` / `ServerHello` message formats, capability flags, negotiation algorithm, attach/detach semantics, ClientDisplayInfo
**Changes from v0.2**: Added CELLDATA_ENCODING capability flag, added ClientDisplayInfo message with display_refresh_hz/power_state/preferred_max_fps, added adaptive cadence parameters to negotiation, all handshake payloads are now JSON-encoded (ENCODING=0)

---

## 1. Overview

The handshake phase occurs immediately after transport-layer connection. All handshake messages use JSON payloads (ENCODING flag = 0 in the frame header). The client sends a `ClientHello` message declaring its identity and capabilities. The server responds with `ServerHello` declaring its capabilities and the negotiated feature set. The connection transitions from `HANDSHAKING` to `READY` on success.

After the handshake, the client SHOULD send a `ClientDisplayInfo` message to provide display characteristics that inform the server's adaptive coalescing model.

```
Client                                  Server
  |                                       |
  |---- [transport connect] ------------>|
  |                                       |
  |---- ClientHello (0x0001) ----------->|
  |     {version, client_type, name,     |
  |      capabilities, cjk_caps, ...}    |
  |                                       |  validate version
  |                                       |  validate auth (UID)
  |                                       |  compute negotiated caps
  |                                       |
  |<---- ServerHello (0x0002) -----------|
  |      {version, server_name,          |
  |       negotiated_caps, session_list, |
  |       coalescing_config}             |
  |                                       |
  |      [state -> READY]                |
  |                                       |
  |---- ClientDisplayInfo (0x0505) ----->|  (optional, recommended)
  |     {display_refresh_hz, power_state,|
  |      preferred_max_fps}              |
  |                                       |
  |---- AttachSessionRequest (0x0104) -->|
  |  or CreateSessionRequest (0x0100) -->|
  |                                       |
  |<---- AttachSessionResponse (0x0105) -|
  |   or CreateSessionResponse (0x0101) -|
  |                                       |
  |      [state -> OPERATING]            |
```

---

## 2. ClientHello Message (`0x0001`)

### 2.1 JSON Payload Schema

All handshake messages use JSON encoding (ENCODING flag = 0). The ClientHello payload is a JSON object.

```json
{
  "protocol_version_min": 1,
  "protocol_version_max": 1,
  "client_type": "native",
  "capabilities": ["compression", "clipboard_sync", "mouse", "selection", "search", "fd_passing"],
  "cjk_capabilities": ["preedit", "ambiguous_width", "double_width", "preedit_sync"],
  "render_capabilities": ["cell_data", "dirty_tracking", "cursor_style"],
  "client_name": "it-shell3-macos",
  "client_version": "1.0.0",
  "terminal_type": "xterm-256color",
  "cols": 80,
  "rows": 24,
  "pixel_width": 0,
  "pixel_height": 0
}
```

| Field | Type | Description |
|-------|------|-------------|
| `protocol_version_min` | u8 | Minimum protocol version the client supports |
| `protocol_version_max` | u8 | Maximum protocol version the client supports |
| `client_type` | string | Client type (see 2.2) |
| `capabilities` | string[] | General capability flag names (see Section 4) |
| `cjk_capabilities` | string[] | CJK capability flag names (see Section 5) |
| `render_capabilities` | string[] | Render capability flag names (see Section 6) |
| `client_name` | string | Client name (e.g., "it-shell3-macos", "it-shell3-ios") |
| `client_version` | string | Version string (e.g., "1.0.0") |
| `terminal_type` | string | Terminal type (e.g., "xterm-256color", "ghostty") |
| `cols` | u16 | Initial terminal width in columns |
| `rows` | u16 | Initial terminal height in rows |
| `pixel_width` | u16 | Pixel width of the terminal area (0 if unknown) |
| `pixel_height` | u16 | Pixel height of the terminal area (0 if unknown) |

**Capability arrays**: Instead of bitmasks, JSON payloads use arrays of string names for self-documentation and debuggability. The server maps these to internal bitmask representations. Unknown capability names are ignored (forward compatibility).

### 2.2 Client Type Enum

| Value | Name | Description |
|-------|------|-------------|
| `"native"` | NATIVE | it-shell3 native client (macOS or iOS) with Metal GPU rendering |
| `"control"` | CONTROL | Control/scripting client (no rendering, command-only) |
| `"headless"` | HEADLESS | Headless client (testing, CI, automation) |
| `"remote"` | REMOTE | Remote client over TCP/TLS |

### 2.3 Example ClientHello

A macOS native client connecting for the first time:

```json
{
  "protocol_version_min": 1,
  "protocol_version_max": 1,
  "client_type": "native",
  "capabilities": [
    "compression",
    "clipboard_sync",
    "mouse",
    "selection",
    "search",
    "fd_passing"
  ],
  "cjk_capabilities": [
    "preedit",
    "ambiguous_width",
    "double_width",
    "preedit_sync"
  ],
  "render_capabilities": [
    "cell_data",
    "dirty_tracking",
    "cursor_style"
  ],
  "client_name": "it-shell3-macos",
  "client_version": "1.0.0",
  "terminal_type": "xterm-256color",
  "cols": 80,
  "rows": 24,
  "pixel_width": 0,
  "pixel_height": 0
}
```

On the wire, this is sent as:

```
[16-byte header: magic=IT, version=1, flags=0x00 (ENCODING=0, JSON), msg_type=0x0001, payload_len=<N>, seq=1]
[N bytes: UTF-8 JSON payload]
```

---

## 3. ServerHello Message (`0x0002`)

### 3.1 JSON Payload Schema

```json
{
  "protocol_version": 1,
  "negotiated_caps": ["compression", "clipboard_sync", "mouse", "selection", "search"],
  "negotiated_cjk_caps": ["preedit", "ambiguous_width", "double_width"],
  "negotiated_render_caps": ["cell_data", "dirty_tracking", "cursor_style"],
  "server_pid": 6839,
  "server_name": "itshell3d",
  "server_version": "1.0.0",
  "heartbeat_interval_ms": 30000,
  "max_panes_per_session": 0,
  "max_sessions": 0,
  "coalescing_config": {
    "interactive_threshold_kbps": 1,
    "active_interval_ms": 16,
    "bulk_threshold_kbps": 100,
    "bulk_interval_ms": 33,
    "idle_timeout_ms": 500,
    "preedit_fallback_ms": 200
  },
  "sessions": [
    {
      "session_id": 1,
      "session_name": "main",
      "attached_clients": 0,
      "pane_count": 1,
      "created_at": 1709500000000,
      "last_activity": 1709500100000
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `protocol_version` | u8 | Negotiated protocol version |
| `negotiated_caps` | string[] | Negotiated general capability flag names |
| `negotiated_cjk_caps` | string[] | Negotiated CJK capability flag names |
| `negotiated_render_caps` | string[] | Negotiated render capability flag names |
| `server_pid` | u32 | Server daemon PID (for debugging) |
| `server_name` | string | Server name (e.g., "itshell3d") |
| `server_version` | string | Version string |
| `heartbeat_interval_ms` | u32 | Heartbeat interval in milliseconds (0 = no heartbeat) |
| `max_panes_per_session` | u16 | Maximum panes per session (0 = unlimited) |
| `max_sessions` | u16 | Maximum concurrent sessions (0 = unlimited) |
| `coalescing_config` | object | Server's adaptive coalescing parameters (see 3.3) |
| `sessions` | array | Array of SessionDescriptor objects (see 3.2) |

### 3.2 SessionDescriptor

Each existing session is described by a `SessionDescriptor`. This allows the client to display available sessions for attachment.

```json
{
  "session_id": 1,
  "session_name": "main",
  "attached_clients": 0,
  "pane_count": 1,
  "created_at": 1709500000000,
  "last_activity": 1709500100000
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | u32 | Server-assigned session ID |
| `session_name` | string | Session name (e.g., "main", "dev") |
| `attached_clients` | u8 | Number of clients currently attached |
| `pane_count` | u16 | Number of panes in this session |
| `created_at` | u64 | Creation timestamp (milliseconds since Unix epoch) |
| `last_activity` | u64 | Last activity timestamp |

**v0.2 change**: Removed `tab_count` field. There is no Tab as a protocol entity in libitshell3. Each Session has one layout tree (a binary split tree of panes). The client UI presents Sessions as tabs -- "new tab" creates a Session, "close tab" destroys a Session, "switch tab" is a client-local display switch, "rename tab" renames a Session. Tab functionality is fully preserved in the UI; only the intermediate Tab object between Session and Pane is removed from the wire protocol.

### 3.3 Coalescing Configuration

The `coalescing_config` object in ServerHello informs the client of the server's adaptive cadence parameters. This is informational — the server controls coalescing; the client uses these values for UI expectations (e.g., estimating latency).

| Field | Type | Description |
|-------|------|-------------|
| `interactive_threshold_kbps` | u32 | PTY throughput threshold for Interactive tier (KB/s) |
| `active_interval_ms` | u16 | Frame interval for Active tier (typically 16ms = 60Hz) |
| `bulk_threshold_kbps` | u32 | PTY throughput threshold for Bulk tier (KB/s) |
| `bulk_interval_ms` | u16 | Frame interval for Bulk tier (typically 33ms = 30Hz) |
| `idle_timeout_ms` | u16 | No-output duration before Idle tier (ms) |
| `preedit_fallback_ms` | u16 | Timeout before preedit tier falls back to previous tier (ms) |

### 3.4 Example ServerHello

Server responding with one existing session:

```json
{
  "protocol_version": 1,
  "negotiated_caps": ["compression", "clipboard_sync", "mouse", "selection", "search"],
  "negotiated_cjk_caps": ["preedit", "ambiguous_width", "double_width"],
  "negotiated_render_caps": ["cell_data", "dirty_tracking", "cursor_style"],
  "server_pid": 6839,
  "server_name": "itshell3d",
  "server_version": "1.0.0",
  "heartbeat_interval_ms": 30000,
  "max_panes_per_session": 0,
  "max_sessions": 0,
  "coalescing_config": {
    "interactive_threshold_kbps": 1,
    "active_interval_ms": 16,
    "bulk_threshold_kbps": 100,
    "bulk_interval_ms": 33,
    "idle_timeout_ms": 500,
    "preedit_fallback_ms": 200
  },
  "sessions": [
    {
      "session_id": 1,
      "session_name": "main",
      "attached_clients": 0,
      "pane_count": 1,
      "created_at": 1709500000000,
      "last_activity": 1709500100000
    }
  ]
}
```

---

## 4. General Capability Flags

The `capabilities` array in `ClientHello` and `negotiated_caps` array in `ServerHello` use the following names:

| Name | Internal Bit | Description |
|------|-------------|-------------|
| `"compression"` | 0 | Supports zstd payload compression |
| `"clipboard_sync"` | 1 | Supports bidirectional clipboard synchronization |
| `"mouse"` | 2 | Supports mouse event forwarding |
| `"selection"` | 3 | Supports text selection synchronization |
| `"search"` | 4 | Supports scrollback search |
| `"fd_passing"` | 5 | Supports file descriptor passing (Unix socket only) |
| `"agent_detection"` | 6 | Supports AI agent input mode detection and profiles |
| `"flow_control"` | 7 | Supports pause/resume flow control messages |
| `"pixel_dimensions"` | 8 | Client provides pixel dimensions for cell size calculation |
| `"sixel"` | 9 | Supports Sixel graphics passthrough |
| `"kitty_graphics"` | 10 | Supports Kitty graphics protocol passthrough |
| `"notifications"` | 11 | Supports OSC notification forwarding |
| `"celldata_encoding"` | 12 | Supports negotiation of alternative CellData encodings (see Section 4.2) |

### 4.1 Capability Notes

- `"compression"` is meaningful primarily over TCP/TLS transport. Over Unix sockets, compression adds CPU overhead with minimal bandwidth benefit.
- `"fd_passing"` is only valid for `AF_UNIX` transport. The server ignores this flag for TCP connections.
- `"agent_detection"`: When negotiated, the server sends process-detection notifications when an AI agent is detected in a pane's foreground process, and the client can activate agent-specific input profiles.

### 4.2 CELLDATA_ENCODING Capability

The `"celldata_encoding"` capability flag enables negotiation of alternative CellData binary encodings in future protocol versions.

**v1 behavior**: CellData always uses raw binary encoding (fixed-size cell structs with optional RLE). The `"celldata_encoding"` flag is declared but has no effect on v1 wire format.

**Future v2+ behavior**: When both sides declare `"celldata_encoding"`, the `ClientHello` may include a `celldata_encodings` array listing supported encodings in preference order:

```json
{
  "celldata_encodings": ["raw_binary", "flatbuffers", "protobuf"]
}
```

The server selects the best mutually supported encoding and reports it in `ServerHello`:

```json
{
  "celldata_encoding": "raw_binary"
}
```

**Rationale**: Raw binary with RLE outperforms protobuf for cell data today (blank 80-col row: 22B RLE vs 400B protobuf). However, the ecosystem evolves — FlatBuffers or other formats may prove valuable as the protocol matures. The capability flag reserves this negotiation path without adding v1 complexity.

---

## 5. CJK Capability Flags

The `cjk_capabilities` array uses the following names. These are separate from general capabilities because CJK support involves multiple independent features that compose differently.

| Name | Internal Bit | Description |
|------|-------------|-------------|
| `"preedit"` | 0 | Supports IME preedit synchronization (`PreeditStart/Update/End`) |
| `"ambiguous_width"` | 1 | Supports ambiguous-width character configuration sync |
| `"double_width"` | 2 | Supports double-width (fullwidth) character rendering |
| `"preedit_sync"` | 3 | Supports multi-client preedit broadcast (`PreeditSync`) |
| `"jamo_decomposition"` | 4 | Supports Korean Jamo decomposition-aware backspace |
| `"composition_engine"` | 5 | Server has a native IME composition engine (libitshell3-ime) |

### CJK Capability Semantics

**`"preedit"` (bit 0)**: The fundamental CJK feature. When negotiated:
- The server sends `PreeditStart` (`0x0400`), `PreeditUpdate` (`0x0401`), and `PreeditEnd` (`0x0402`) messages to the client
- The server tracks per-pane preedit state using its native IME engine (libitshell3-ime)
- Preedit state is included in `FrameUpdate` messages (preedit section in the JSON metadata blob) for the active pane
- The client sends raw HID keycodes via `KeyEvent`; the server processes them through the composition engine and pushes preedit state to all attached clients

**`"ambiguous_width"` (bit 1)**: When negotiated:
- Client and server sync `unicode-ambiguous-is-wide` configuration via `AmbiguousWidthConfig` (`0x0406`)
- Both sides agree on whether ambiguous-width characters occupy 1 or 2 cells

**`"double_width"` (bit 2)**: When negotiated:
- The server sends proper `wide` cell attributes in `FrameUpdate` binary CellData
- The client renders CJK ideographs at double width
- (This is expected to be supported by all it-shell3 clients; the flag exists for forward compatibility with minimal third-party clients)

**`"preedit_sync"` (bit 3)**: Requires `"preedit"`. When negotiated:
- The server broadcasts preedit state changes to all attached clients via `PreeditSync` (`0x0403`)
- Non-composing clients see the preedit overlay from the composing client
- Enables multi-viewer CJK composition (e.g., pair programming, shared terminal session)

**`"jamo_decomposition"` (bit 4)**: Requires `"preedit"`. When negotiated:
- The server understands Korean Jamo decomposition rules
- Backspace during Korean composition correctly decomposes (`han` -> `ha` -> `h-ieung` -> empty)
- Without this flag, the server treats backspace as a simple character deletion

**`"composition_engine"` (bit 5)**: Informational flag. When set:
- Indicates the server runs libitshell3-ime's native composition engine (not relying on OS IME)
- The server can guarantee deterministic composition behavior
- Affects how preedit state is validated (native engine produces only valid Hangul sequences)

---

## 6. Render Capability Flags

| Name | Internal Bit | Description |
|------|-------------|-------------|
| `"cell_data"` | 0 | Supports structured binary cell data in FrameUpdate (RenderState protocol) |
| `"dirty_tracking"` | 1 | Supports partial (delta) FrameUpdate with per-row dirty flags |
| `"cursor_style"` | 2 | Supports all cursor styles (block, bar, underline) |
| `"true_color"` | 3 | Supports 24-bit RGB colors in cell data |
| `"256_color"` | 4 | Supports 256-color palette in cell data |
| `"underline_styles"` | 5 | Supports underline style variants (single, double, curly, dotted, dashed) |
| `"hyperlinks"` | 6 | Supports OSC 8 hyperlink passthrough |
| `"vt_fallback"` | 7 | Supports VT re-serialization as a fallback rendering mode |

### Render Capability Notes

- `"cell_data"` is the primary rendering mode. All native it-shell3 clients support this. When negotiated, the server sends `FrameUpdate` with binary CellData (ENCODING=1 in header).
- `"vt_fallback"` is for minimal/debug clients that prefer receiving raw VT escape sequences (via `TerminalFormatter`) instead of structured cell data. This is never the default.
- `"dirty_tracking"` should be supported by all clients. Without it, the server sends full frames on every update (wasteful).

---

## 7. ClientDisplayInfo Message (`0x0505`)

### 7.1 Overview

`ClientDisplayInfo` is an early post-handshake message sent by the client to inform the server of display characteristics that affect the adaptive coalescing model. This message is sent in the `READY` or `OPERATING` state and can be re-sent whenever display conditions change (e.g., moving window to a different monitor, plugging/unplugging power).

| Property | Value |
|----------|-------|
| Message type | `0x0505` |
| Direction | C->S |
| Encoding | JSON (ENCODING=0) |
| State | `READY` or `OPERATING` |
| Required | No (recommended for native clients) |

### 7.2 JSON Payload Schema

```json
{
  "display_refresh_hz": 60,
  "power_state": "ac",
  "preferred_max_fps": 60
}
```

| Field | Type | Description |
|-------|------|-------------|
| `display_refresh_hz` | u16 | Client's primary display refresh rate in Hz (e.g., 60, 120 for ProMotion). 0 = unknown. |
| `power_state` | string | Power state enum: `"ac"`, `"battery"`, `"low_battery"` |
| `preferred_max_fps` | u16 | Client's preferred maximum frame rate. 0 = no preference (use server default). |

### 7.3 Power State Enum

| Value | Description | Server behavior |
|-------|-------------|-----------------|
| `"ac"` | AC power connected | No throttling. Use display_refresh_hz for Active tier. |
| `"battery"` | Battery power, normal level | Moderate throttling: cap Active tier at 20fps, Bulk at 10fps. |
| `"low_battery"` | Battery power, low level | Aggressive throttling: cap Active tier at 10fps, Bulk at 5fps. |

### 7.4 Server Response

The server acknowledges `ClientDisplayInfo` with a `ClientDisplayInfoAck` message (see doc 06 for details) reporting the effective fps cap it will apply. If the server receives `display_refresh_hz = 120` (ProMotion), it adjusts the Active tier interval to 8ms for that client (matching iTerm2's 120fps on ProMotion ARM Macs).

The canonical definition of `ClientDisplayInfo` (`0x0505`) and `ClientDisplayInfoAck` is in doc 06 (Flow Control & Auxiliary). This section describes the message semantics; see doc 06 for the full wire-level specification.

### 7.5 Example: iOS Client on Battery

```json
{
  "display_refresh_hz": 60,
  "power_state": "battery",
  "preferred_max_fps": 30
}
```

The server receives this and caps FrameUpdate delivery:
- Active tier: 50ms interval (20fps, capped by battery power state; `preferred_max_fps=30` is overridden by battery cap of 20fps)
- Bulk tier: 100ms interval (10fps, power-throttled)
- Preedit tier: Unchanged (immediate, always bypasses throttling)

---

## 8. Negotiation Algorithm

### 8.1 Protocol Version

The server selects the negotiated protocol version as:

```
negotiated_version = min(server_max_version, client.protocol_version_max)

if negotiated_version < client.protocol_version_min:
    -> send Error(ERR_VERSION_MISMATCH), disconnect
if negotiated_version < server_min_version:
    -> send Error(ERR_VERSION_MISMATCH), disconnect
```

In v1, both `protocol_version_min` and `protocol_version_max` are `1`. This field exists for future version negotiation.

### 8.2 General Capabilities

```
negotiated_caps = intersection(client.capabilities, server.capabilities)
```

Each capability is independently negotiated as the intersection of client and server flag sets. A capability is active only if both sides support it. Unknown capability names are ignored (forward compatibility).

### 8.3 CJK Capabilities

```
negotiated_cjk_caps = intersection(client.cjk_capabilities, server.cjk_capabilities)
```

With dependency enforcement:

```
if "preedit" not in negotiated_cjk_caps:
    # Preedit is the foundation; without it, dependent caps are meaningless
    remove "preedit_sync" from negotiated_cjk_caps
    remove "jamo_decomposition" from negotiated_cjk_caps
```

### 8.4 Render Capabilities

```
negotiated_render_caps = intersection(client.render_capabilities, server.render_capabilities)
```

The server validates that at least one rendering mode is supported:

```
if "cell_data" not in negotiated_render_caps and "vt_fallback" not in negotiated_render_caps:
    -> send Error(ERR_CAPABILITY_REQUIRED, detail="No common rendering mode"), disconnect
```

### 8.5 CELLDATA_ENCODING Negotiation (v2+)

In v1, this is a no-op. For future reference:

```
if "celldata_encoding" in negotiated_caps:
    # Both sides support alternative encodings
    if client.celldata_encodings is present:
        selected = first item in client.celldata_encodings that server also supports
        if selected is None:
            selected = "raw_binary"  # always supported
    else:
        selected = "raw_binary"
    # Report in ServerHello
    server_hello.celldata_encoding = selected
```

### 8.6 Negotiation Summary

```
Client                                  Server
  |                                       |
  |  ClientHello:                         |
  |    version_min=1, version_max=1       |
  |    caps = [compression, clipboard_sync, mouse, |
  |            selection, search, fd_passing]       |
  |    cjk = [preedit, ambiguous_width,   |
  |           double_width, preedit_sync] |
  |    render = [cell_data, dirty_tracking,|
  |              cursor_style]             |
  |                                       |
  |                                       |  server_caps = [compression, clipboard_sync,
  |                                       |                 mouse, selection, search]
  |                                       |  server_cjk = [preedit, ambiguous_width,
  |                                       |                double_width]
  |                                       |  server_render = [cell_data, dirty_tracking,
  |                                       |                   cursor_style]
  |                                       |
  |                                       |  negotiated_caps = intersection
  |                                       |    = [compression, clipboard_sync,
  |                                       |       mouse, selection, search]
  |                                       |  negotiated_cjk = [preedit, ambiguous_width,
  |                                       |                    double_width]
  |                                       |  negotiated_render = [cell_data, dirty_tracking,
  |                                       |                       cursor_style]
  |                                       |
  |  ServerHello:                         |
  |    version = 1                        |
  |    caps = [negotiated set]            |
  |    cjk = [negotiated set]             |
  |    render = [negotiated set]          |
  |    coalescing_config = {...}          |
  |                                       |
  |  Both sides now use negotiated caps   |
```

---

## 9. Attach/Detach Semantics

### 9.1 Session Attach (`0x0104`)

After handshake completes (state = `READY`), the client attaches to a session. All attach/detach messages use JSON encoding.

**AttachSessionRequest payload:**

```json
{
  "session_id": 1,
  "cols": 80,
  "rows": 24,
  "pixel_width": 0,
  "pixel_height": 0,
  "readonly": false,
  "detach_others": false
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | u32 | ID of session to attach to (from SessionDescriptor in ServerHello) |
| `cols` | u16 | Client terminal width in columns |
| `rows` | u16 | Client terminal height in rows |
| `pixel_width` | u16 | Client pixel width (0 if unknown) |
| `pixel_height` | u16 | Client pixel height (0 if unknown) |
| `readonly` | bool | Attach as read-only viewer (no input forwarding) |
| `detach_others` | bool | Detach other clients from this session (exclusive mode) |

### 9.2 Session Attached Response (`0x0105`)

**AttachSessionResponse payload:**

```json
{
  "session_id": 1,
  "active_pane_id": 1,
  "session_cols": 80,
  "session_rows": 24,
  "layout_data": { ... }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | u32 | Session ID |
| `active_pane_id` | u32 | Currently focused pane ID |
| `session_cols` | u16 | Session terminal width (may differ from requested if other clients attached) |
| `session_rows` | u16 | Session terminal height |
| `layout_data` | object | JSON-encoded layout tree (pane hierarchy with split positions) |

**v0.2 changes**: Removed `active_tab_id` field (no Tab protocol entity -- the client UI presents Sessions as tabs). The `layout_data` now encodes the session's single pane tree (binary splits), not a tab-pane hierarchy.

After receiving `AttachSessionResponse`, the client:
1. Parses the layout tree to create local pane views
2. Processes the following `FrameUpdate` (msg_type=0x0300, ENCODING=1, with `dirty=full`) to render the initial viewport
3. Transitions to `OPERATING` state

This is immediately followed by a `FrameUpdate` with `dirty=full` for all panes.

### 9.3 Session Create (`0x0100`)

If the client wants a new session instead of attaching to an existing one:

**CreateSessionRequest payload:**

```json
{
  "session_name": "dev",
  "cols": 80,
  "rows": 24,
  "pixel_width": 0,
  "pixel_height": 0,
  "shell_cmd": "/bin/zsh",
  "cwd": "/Users/user/projects"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_name` | string | Desired session name (empty string for auto-generated) |
| `cols` | u16 | Terminal width |
| `rows` | u16 | Terminal height |
| `pixel_width` | u16 | Pixel width (0 if unknown) |
| `pixel_height` | u16 | Pixel height (0 if unknown) |
| `shell_cmd` | string | Custom shell command (empty for default) |
| `cwd` | string | Working directory (empty for $HOME) |

**CreateSessionResponse (`0x0101`):**

```json
{
  "session_id": 2,
  "pane_id": 3,
  "session_name": "dev"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | u32 | Newly assigned session ID |
| `pane_id` | u32 | ID of the initial pane |
| `session_name` | string | Actual session name (may differ from requested) |

**v0.2 change**: Removed `tab_id` field. There is no Tab protocol entity -- each Session directly owns one pane tree. The initial pane is the root of the session's layout tree.

This is immediately followed by a `FrameUpdate` with `dirty=full` for the initial pane.

### 9.4 Session Detach (`0x0106`)

**DetachSessionRequest payload:**

```json
{
  "session_id": 1,
  "reason": "client_request"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | u32 | Session to detach from (must be currently attached) |
| `reason` | string | Detach reason: `"client_request"`, `"session_switch"`, `"client_shutdown"` |

**DetachSessionResponse (`0x0107`):**

```json
{
  "session_id": 1,
  "session_alive": true
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | u32 | Session detached from |
| `session_alive` | bool | Whether the session is still running |

After detach:
- Connection state returns to `READY`
- The client can attach to another session or disconnect
- The session continues running in the daemon (sessions survive client detach)

### 9.5 Multi-Client Attach

Multiple clients can attach to the same session simultaneously. The server handles this by:

1. **Terminal dimensions**: Uses the minimum (cols, rows) across all attached clients (like tmux `aggressive-resize`). See resize algorithm below.
2. **Input forwarding**: All non-readonly clients can send input. The server processes input in arrival order.
3. **Preedit exclusivity**: Only one client can have active preedit per pane. The server owns the IME engine -- if a client sends a `KeyEvent` that triggers composition while another client's composition is already active on the same pane, the server cancels the first client's composition (sends `PreeditEnd` with reason `CANCELLED` to the first client) before starting the new one.
4. **Frame updates**: All clients receive `FrameUpdate` messages. Each client renders at its own pace; `FrameAck` is per-client. Coalescing tiers are per-(client, pane).
5. **Detach notification**: When a client detaches, other clients receive a `ServerNotification` about the client count change.

### 9.6 Multi-Client Resize Algorithm

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

## 10. Graceful Fallback Matrix

This matrix shows behavior when capabilities differ between client and server:

### 10.1 CJK Capability Fallback

| Client | Server | Behavior |
|--------|--------|----------|
| `"preedit"` = yes | `"preedit"` = yes | Full preedit sync: server sends preedit messages to client, server tracks IME state, FrameUpdate includes preedit section in JSON metadata blob |
| `"preedit"` = yes | `"preedit"` = no | No server-side composition. Client handles composition locally if it has its own IME. Committed text goes through normal `KeyInput`. |
| `"preedit"` = no | `"preedit"` = yes | Standard input: server does not send PreeditStart/Update/End to this client. Client sends committed text only. FrameUpdate preedit section is still included (it is part of the visual render state). |
| `"preedit"` = no | `"preedit"` = no | Standard input. No CJK composition awareness. |

| Client | Server | Behavior |
|--------|--------|----------|
| `"preedit_sync"` = yes | `"preedit_sync"` = yes | Multi-client preedit: all attached clients see preedit overlays from the composing client |
| `"preedit_sync"` = yes | `"preedit_sync"` = no | Single-client preedit: only the composing client sees its own preedit. Server does not broadcast. |
| `"preedit_sync"` = no | `"preedit_sync"` = yes | This client opts out of preedit broadcast. Server does not send `PreeditSync` to this client. Other clients may still see synced preedit. |

| Client | Server | Behavior |
|--------|--------|----------|
| `"jamo_decomposition"` = yes | `"jamo_decomposition"` = yes | Korean backspace decomposes Jamo. Server's IME engine updates preedit state accordingly. |
| `"jamo_decomposition"` = yes | `"jamo_decomposition"` = no | Server's IME engine does not support Jamo decomposition. Backspace during Korean composition deletes the entire composed character. |
| `"jamo_decomposition"` = no | `"jamo_decomposition"` = yes | Server has the capability but client does not need it. No effect. |

| Client | Server | Behavior |
|--------|--------|----------|
| `"ambiguous_width"` = yes | `"ambiguous_width"` = yes | Ambiguous width setting synced via `AmbiguousWidthConfig`. Both sides render consistently. |
| Either side = no | | Default ambiguous width (1 cell). No sync. Minor rendering inconsistencies possible for ambiguous characters. |

### 10.2 Render Capability Fallback

| Client | Server | Behavior |
|--------|--------|----------|
| `"cell_data"` = yes | `"cell_data"` = yes | Structured binary cell data rendering (primary mode). FrameUpdate sent with ENCODING=1. |
| `"cell_data"` = no, `"vt_fallback"` = yes | `"vt_fallback"` = yes | VT re-serialization mode: server sends raw VT escape sequences in JSON payload |
| Neither rendering mode | | Handshake fails with `ERR_CAPABILITY_REQUIRED` |

| Client | Server | Behavior |
|--------|--------|----------|
| `"dirty_tracking"` = yes | `"dirty_tracking"` = yes | Delta updates: only changed rows sent in FrameUpdate |
| `"dirty_tracking"` = no | | Full frame on every update. Higher bandwidth, but always works. |

### 10.3 General Capability Fallback

| Capability | When Not Negotiated |
|------------|---------------------|
| `"compression"` | All payloads sent uncompressed. No impact on correctness. |
| `"clipboard_sync"` | No clipboard synchronization. Client clipboard is local only. |
| `"mouse"` | Mouse events not forwarded. Terminal applications that need mouse input will not work correctly. |
| `"selection"` | No selection sync across clients. Each client manages selection locally. |
| `"search"` | Scrollback search not available. Client can still scroll. |
| `"fd_passing"` | No file descriptor passing. All data goes through the protocol. |
| `"flow_control"` | Server drops frames when client is slow instead of pausing. May cause visible frame skipping. |
| `"celldata_encoding"` | v1: no effect (raw binary always used). v2+: no alternative encoding negotiation; raw binary used. |

---

## 11. Disconnect and Reconnection

### 11.1 Graceful Disconnect (`0x0005`)

**Disconnect payload (JSON):**

```json
{
  "reason": "normal",
  "detail": "Client shutting down"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `reason` | string | Disconnect reason: `"normal"`, `"error"`, `"timeout"`, `"version_mismatch"`, `"auth_failed"`, `"server_shutdown"`, `"replaced"` |
| `detail` | string | Human-readable detail string |

### 11.2 Reconnection

When a client reconnects to a running daemon:

1. Client establishes a new connection
2. Normal `ClientHello` / `ServerHello` handshake
3. Client sees its previous session in the `ServerHello` session list
4. Client sends `ClientDisplayInfo` (if applicable)
5. Client sends `AttachSessionRequest` with the previous session ID
6. Server responds with `AttachSessionResponse` + full `FrameUpdate`
7. Client is fully resynchronized

There is no incremental reconnection (no "replay from sequence N"). Every reconnection is a full state resync via `FrameUpdate` with `dirty=full`. This is simple and reliable; the full state is typically under 35 KB.

---

## 12. Security Considerations

### 12.1 Unix Socket Authentication

On Unix domain sockets, the server authenticates clients by:

1. **Kernel-level UID check**: `getpeereid()` (macOS) or `SO_PEERCRED` (Linux) provides the peer's UID. Only connections from the same UID as the daemon are accepted.
2. **Socket file permissions**: `0600` (owner-only read/write). Prevents non-owner access at the filesystem level.
3. **Directory permissions**: `0700` on the socket directory.

No additional authentication is needed for Unix socket transport because the OS kernel guarantees the peer identity.

### 12.2 TCP/TLS Authentication (Future)

For network transport, mutual TLS authentication is planned:

1. Server and client each have a TLS certificate
2. Pre-shared CA or certificate pinning
3. SRP (Secure Remote Password) as an alternative for password-based auth without PKI

The handshake protocol is transport-agnostic -- the same `ClientHello`/`ServerHello` messages are used. Authentication is handled at the transport layer (TLS) before the application-layer handshake begins.

### 12.3 Handshake Timeouts

| Timeout | Duration | Action |
|---------|----------|--------|
| Transport connection | 5 seconds | Close socket, report connection failure |
| `ClientHello` -> `ServerHello` | 5 seconds | Send `Error(ERR_INVALID_STATE)`, close |
| `READY` -> `AttachSessionRequest`/`CreateSessionRequest` | 60 seconds | Send `Disconnect(TIMEOUT)`, close |
| Heartbeat response | 90 seconds | Send `Disconnect(TIMEOUT)`, close |

---

## 13. Design Decisions Needing Validation

| Decision | Status | Notes |
|----------|--------|-------|
| JSON encoding for all handshake messages | **Decided** | Self-describing, debuggable, cross-language (Swift JSONDecoder). Capability arrays use string names instead of bitmasks for readability. Internal implementation maps to bitmasks. |
| String-based capability names (not bitmasks) in JSON | **Decided** | Self-documenting on the wire. Unknown names are ignored for forward compatibility. Server maps to internal bitmask representation for O(1) lookups. |
| Separate CJK capability field | **Proposed** | Keeps CJK concerns in a dedicated namespace. Could have been in the general capabilities, but separation makes the CJK feature matrix clearer. |
| JSON for layout data in AttachSessionResponse | **Proposed** | JSON is simple to implement (`std.json` in Zig) and human-readable for debugging. Layout data is sent infrequently (only on attach/layout change), so JSON overhead is acceptable. |
| Full state resync on reconnect (no incremental replay) | **Proposed** | Simpler to implement and reason about. Full FrameUpdate is under 35 KB. If reconnection latency becomes a problem, incremental replay can be added later by tracking per-client sequence watermarks. |
| Heartbeat interval 30s | **Proposed** | Matches common practice (SSH default is 15s with 3 retries = 45s). Adjustable via `heartbeat_interval_ms` in ServerHello. |
| Preedit exclusivity (one compositor per pane) | **Decided** | Two users composing CJK in the same pane simultaneously is an unlikely and confusing scenario. Server owns IME -- incoming `KeyEvent` that triggers composition cancels any existing composition on that pane from another client. |
| No Tab protocol entity | **Decided** | Hierarchy is Daemon > Session > Pane tree. The client UI presents Sessions as tabs (new tab = CreateSession, close tab = DestroySession, switch tab = client-local, rename tab = RenameSession). Tab functionality is preserved in the UI; only the intermediate Tab object is removed from the wire protocol. |
| Minimum (cols, rows) for multi-client | **Decided** | Per-client viewports deferred to v2. Minimum sizing matches tmux's proven approach. |
| ClientDisplayInfo as separate message (not part of ClientHello) | **Decided** | Display conditions change at runtime (monitor switch, power state). A separate message allows re-sending without re-handshaking. Also keeps ClientHello focused on capability negotiation. |
| CELLDATA_ENCODING capability flag | **Decided** | No-op in v1. Reserves negotiation path for v2 alternative encodings (FlatBuffers, protobuf) without v1 complexity. Raw binary + RLE outperforms alternatives today. |
| Coalescing config in ServerHello | **Decided** | Informational for the client. Server controls actual coalescing. Exposing parameters enables client-side latency estimation and debugging. |
