# 04 — Input Forwarding and RenderState Protocol

**Status**: Draft v0.4
**Author**: rendering-cjk-specialist
**Date**: 2026-03-04
**Depends on**: 01-protocol-overview.md (header format), 03-session-pane-management.md (session/pane IDs)

**Changes from v0.3**:
- **Issue 6: String-based input method identifiers**: Replaced numeric `active_layout_id: u16` with string `input_method` in KeyEvent. Removed numeric layout ID table. Input methods use self-documenting strings (`"direct"`, `"korean_2set"`, etc.) throughout the protocol.
- **Issue 9/Gap 2: Optional `pane_id` in KeyEvent**: Added optional `pane_id` field for explicit input routing. Omitted = route to session's focused pane. Prevents focus-change races during IME composition.
- **Issue 9/Gap 7: Readonly input rejection**: Added normative table defining which input messages readonly clients may and may not send.
- **Issue 9/Gap 9: FrameUpdate delivery scope**: Added normative statement that clients receive FrameUpdates for ALL panes in their attached session.
- **Issue 9/Gap 10: frame_sequence scope**: Added normative statement defining frame_sequence as per-pane global monotonic counter.
- **Issue 9: Per-client dirty tracking semantics**: Added normative statement for when dirty bits are cleared.
- **CO-1: Cursor during composition**: Promoted cursor behavior during CJK composition from descriptive to normative MUST requirements.
- **Issue 3: JSON optional field convention**: Updated JSON examples to omit absent fields rather than using `null`.
- **Issue 5: Compression deferred**: Updated Section 9 to reflect compression removal from v1.

---

## 1. Overview

This document specifies the wire protocols for two core data flows:

1. **Input (client -> server)**: Raw key events, text input, mouse events, paste data
2. **RenderState (server -> client)**: Structured terminal cell data, cursor, colors, preedit overlay

The server IS the terminal emulator. The client is a remote keyboard + GPU display. The client has no VT parser, no Terminal state machine, no PTY. It receives structured cell data from the server and renders using libghostty's font subsystem (SharedGrid, Atlas, HarfBuzz) and Metal GPU shaders.

### Message Type Ranges

| Range | Category | Direction |
|-------|----------|-----------|
| `0x0200`-`0x02FF` | Input messages | Client -> Server |
| `0x0300`-`0x03FF` | RenderState messages | Server -> Client |

### Common Message Header (16 bytes)

All messages share a 16-byte binary header as defined in doc 01:

```
Offset  Size  Field        Description
------  ----  -----        -----------
 0      2     magic        0x49 0x54 ("IT" in ASCII), little-endian
 2      1     version      Protocol version (starts at 1)
 3      1     flags        Per-message flags (bit 0 = ENCODING: 0=JSON/1=binary,
                                       bit 1 = COMPRESSED (reserved, v1 MUST NOT set),
                                       bit 2 = RESPONSE,
                                       bit 3 = ERROR, bit 4 = MORE_FRAGMENTS,
                                       bits 5-7 reserved)
 4      2     msg_type     Message type ID (u16 LE)
 6      2     reserved     Must be 0
 8      4     payload_len  Payload length in bytes, NOT including header (u32 LE)
12      4     sequence     Monotonic sequence number (u32 LE)
```

- **payload_len**: Size of the payload only. Total message size on wire = 16 + payload_len.
- The 2-byte reserved field provides natural 4-byte alignment for `payload_len` and `sequence`.

All multi-byte fields are little-endian.

---

## 2. Input Messages (Client -> Server)

All input messages use **JSON payloads**. Each input message consists of the 16-byte binary header (for O(1) dispatch and framing) followed by a JSON-encoded payload body. This provides schema evolution, cross-language client support (Swift `JSONDecoder`), and `socat | jq` debuggability for the low-frequency input path.

### 2.1 KeyEvent (type = 0x0200)

The primary input message. The client sends raw HID keycodes and modifiers. The server derives text through the native IME engine (libitshell3-ime) — the client never sends composed text for key input. The client does not track IME composition state; the server determines composition state internally from the IME engine.

#### JSON Payload

```json
{
  "keycode": 11,
  "action": 0,
  "modifiers": 0,
  "input_method": "korean_2set",
  "pane_id": 1
}
```

| Field | Type | Description |
|-------|------|-------------|
| `keycode` | u16 | HID usage code, e.g., `0x04` = 'A' |
| `action` | u8 | 0=press, 1=release, 2=repeat |
| `modifiers` | u8 | Bitflags (see below) |
| `input_method` | string | Active input method identifier (see below) |
| `pane_id` | u32 | Target pane (optional; omit or 0 = route to session's focused pane) |

**`pane_id` routing**: When `pane_id` is omitted or 0, the server routes the KeyEvent to the session's currently focused pane. When present and non-zero, the server validates that the pane exists in the client's attached session and routes directly. During IME composition, the client SHOULD specify `pane_id` to prevent focus-change races — if another client changes focus mid-composition, explicitly routed KeyEvents continue to reach the correct pane.

#### Modifier Bitflags (u8)

```
Bit  Modifier
---  --------
 0   Shift
 1   Ctrl
 2   Alt (Option on macOS)
 3   Super (Cmd on macOS)
 4   Caps Lock
 5   Num Lock
 6   (reserved)
 7   (reserved)
```

#### HID Keycodes

The `keycode` field uses USB HID Usage Table codes (same address space as `UIKeyboardHIDUsage` on iOS and macOS `kHIDUsage_Keyboard*` constants). Common values:

| HID Code | Key | Notes |
|----------|-----|-------|
| `0x04`-`0x1D` | A-Z | |
| `0x1E`-`0x27` | 1-0 | |
| `0x28` | Enter/Return | |
| `0x29` | Escape | |
| `0x2A` | Backspace | Critical for Jamo decomposition |
| `0x2B` | Tab | |
| `0x2C` | Space | |
| `0x4F`-`0x52` | Arrow Right/Left/Down/Up | |
| `0xE0`-`0xE7` | Modifier keys themselves | LCtrl, LShift, LAlt, LSuper, R* |

#### Input Method Identifiers

The `input_method` field identifies which input method the client has active, so the server's IME engine can apply the correct keycode-to-character mapping. Input methods use string identifiers throughout the protocol (no numeric IDs):

| Identifier | Description | v1 Support |
|------------|-------------|------------|
| `"direct"` | Direct passthrough (US QWERTY English) | Yes |
| `"korean_2set"` | Korean 2-set (Dubeolsik) | Yes |
| `"korean_3set_390"` | Korean 3-set (390 layout) | Planned |
| `"korean_3set_final"` | Korean 3-set (Final layout) | Planned |
| `"japanese_romaji"` | Japanese Romaji input | Future |
| `"japanese_kana"` | Japanese Kana input | Future |
| `"chinese_pinyin"` | Chinese Pinyin input | Future |

String identifiers are self-documenting on the wire, require no mapping table, no reserved numeric ranges, and adding new input methods is just a new string value with zero schema migration. The overhead of ~13 bytes per KeyEvent is irrelevant at typing speeds (~15/s) over a >1 GB/s Unix socket.

Input methods are negotiated during handshake: the server advertises `supported_input_methods` in ServerHello, the client selects from them in ClientHello's `preferred_input_methods` (see doc 02).

The `keyboard_layout` axis (e.g., `"qwerty"`, `"dvorak"`) is a separate concept established at handshake and omitted from KeyEvent. In v1, only `"qwerty"` is supported.

#### Example: Typing Korean "한"

```
1. User presses 'H' key (HID 0x0B), input_method=korean_2set
   KeyEvent: {"keycode": 11, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Server IME: maps H -> ㅎ, enters composing state, emits preedit "ㅎ"

2. User presses 'A' key (HID 0x04)
   KeyEvent: {"keycode": 4, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Server IME: maps A -> ㅏ, composes ㅎ+ㅏ=하, emits preedit "하"

3. User presses 'N' key (HID 0x11)
   KeyEvent: {"keycode": 17, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Server IME: maps N -> ㄴ, composes 하+ㄴ=한, emits preedit "한"

4. User presses Space (HID 0x2C), commits
   KeyEvent: {"keycode": 44, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Server IME: commits "한" to PTY, clears preedit
```

Note: The client sends identical KeyEvent messages regardless of whether composition is active. The server's IME engine tracks composition state internally.

### 2.2 TextInput (type = 0x0201)

For direct text insertion that bypasses IME processing. Primary use case: programmatic text injection (e.g., from clipboard managers, automation tools).

#### JSON Payload

```json
{
  "pane_id": 1,
  "text": "Hello, world!"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `text` | string | UTF-8 encoded text (max 65535 bytes) |

For text larger than 65535 bytes, use PasteData (0x0205).

### 2.3 MouseButton (type = 0x0202)

#### JSON Payload

```json
{
  "pane_id": 1,
  "button": 0,
  "action": 0,
  "modifiers": 0,
  "click_count": 1,
  "x": 5.0,
  "y": 10.0
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `button` | u8 | 0=left, 1=middle, 2=right, 3-7=extra |
| `action` | u8 | 0=press, 1=release |
| `modifiers` | u8 | Same bitflags as KeyEvent |
| `click_count` | u8 | 1=single, 2=double, 3=triple |
| `x` | f32 | Column position in cell coords |
| `y` | f32 | Row position in cell coords |

Sub-cell precision is provided via f32 for `x` and `y` to support fractional cell positioning (useful for future sixel/image region click detection).

### 2.4 MouseMove (type = 0x0203)

Sent when the mouse moves and mouse tracking is active (the server notifies the client whether mouse tracking is enabled via a flag in FrameUpdate).

#### JSON Payload

```json
{
  "pane_id": 1,
  "modifiers": 0,
  "buttons_held": 1,
  "x": 5.5,
  "y": 10.2
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `modifiers` | u8 | Active modifiers |
| `buttons_held` | u8 | Bitflags: bit 0=left, 1=middle, 2=right |
| `x` | f32 | Column position |
| `y` | f32 | Row position |

**Rate limiting**: The client SHOULD throttle MouseMove messages to at most 60/second per pane. The server MAY drop excess MouseMove messages.

### 2.5 MouseScroll (type = 0x0204)

#### JSON Payload

```json
{
  "pane_id": 1,
  "modifiers": 0,
  "dx": 0.0,
  "dy": -3.0,
  "precise": false
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `modifiers` | u8 | Active modifiers |
| `dx` | f32 | Horizontal scroll delta |
| `dy` | f32 | Vertical scroll delta |
| `precise` | bool | false=line-based (mouse wheel), true=pixel-precise (trackpad) |

### 2.6 PasteData (type = 0x0205)

For clipboard paste operations. Supports large payloads via chunking.

#### JSON Payload

```json
{
  "pane_id": 1,
  "bracketed_paste": true,
  "first_chunk": true,
  "final_chunk": true,
  "data": "pasted text here"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `bracketed_paste` | bool | Wrap in `\e[200~` / `\e[201~` |
| `first_chunk` | bool | This is the first chunk |
| `final_chunk` | bool | This is the last chunk |
| `data` | string | UTF-8 paste data for this chunk |

**Chunking protocol**:
- Small pastes (<=64 KB): Single message with first_chunk=true AND final_chunk=true
- Large pastes: Multiple messages. First has first_chunk=true. Last has final_chunk=true.
- The server assembles chunks in sequence order before writing to PTY.
- The server applies bracketed paste wrapping around the assembled text if `bracketed_paste=true` and the terminal has bracketed paste mode enabled.

### 2.7 FocusEvent (type = 0x0206)

Notifies the server when the client terminal gains or loses OS-level focus. This enables focus reporting (CSI ? 1004 h).

#### JSON Payload

```json
{
  "pane_id": 1,
  "focused": true
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `focused` | bool | true=gained focus, false=lost focus |

### 2.8 Readonly Client Input Restrictions

Clients attached with the `readonly` flag (see doc 02, AttachSessionRequest) are restricted in which input messages they may send. The server MUST reject prohibited messages with ERR_ACCESS_DENIED (error code 0x00000203).

**Readonly clients MAY send (non-mutating)**:

| Message | Rationale |
|---------|-----------|
| MouseScroll (0x0204) | Viewport navigation, does not alter terminal state |
| FocusEvent (0x0206) | Advisory, does not alter terminal state |
| ScrollRequest (0x0301) | Viewport navigation |
| SearchRequest (0x0303) | Read-only query |
| SearchCancel (0x0305) | Cancels own search |

**Readonly clients MUST NOT send (mutating)**:

| Message | Rationale |
|---------|-----------|
| KeyEvent (0x0200) | Generates terminal input |
| TextInput (0x0201) | Injects text into PTY |
| MouseButton (0x0202) | Can trigger terminal mouse reporting |
| MouseMove (0x0203) | Can trigger terminal mouse tracking |
| PasteData (0x0205) | Writes to PTY |
| InputMethodSwitch (0x0404) | Mutates pane IME state |

---

## 3. Input Channel Architecture

### 3.1 Multiplexed vs. Dedicated Channel

**Decision: Multiplexed with priority.**

All input messages share the same Unix domain socket connection as other protocol messages. However, input messages receive processing priority on the server side.

**Rationale**:
- A separate input channel adds connection management complexity (two sockets per client)
- Unix domain sockets have sufficient bandwidth (>1 GB/s) — congestion is not a realistic concern
- The server's event loop processes input messages with higher priority than control/management messages
- Key-to-screen latency target: <1ms on Unix socket (verified in Doc 13's analysis)

**Server processing priority order**:
1. KeyEvent, TextInput (highest — affects what the user sees immediately)
2. MouseButton, MouseScroll (user interaction)
3. MouseMove (bulk, can be coalesced)
4. PasteData (bulk transfer)
5. FocusEvent (advisory)

### 3.2 Input Flow Summary

```
Client                                    Server
------                                    ------

 [User presses key]
     |
     v
 KeyEvent(JSON: HID keycode, mods, input_method)
     |
     +--- Unix socket ------------------>  Input Dispatcher
     |                                       |
     |                                       v
     |                                   libitshell3-ime
     |                                   (Layout Mapper + Composition Engine)
     |                                       |
     |                                       +-- Preedit? --> Update preedit state
     |                                       |                     |
     |                                       +-- Commit? --> Write to PTY
     |                                                            |
     |                                                            v
     |                                                       libghostty-vt
     |                                                       Terminal.vtStream()
     |                                                            |
     |                                                            v
     |                                                       RenderState.update()
     |                                                            |
     <---- FrameUpdate (binary cells + JSON metadata) -----------+
     |
     v
 Font subsystem (SharedGrid, Atlas)
     |
     v
 Metal GPU render (CellText, CellBg shaders)
```

---

## 4. RenderState Messages (Server -> Client)

### 4.1 FrameUpdate (type = 0x0300)

The primary rendering message. Carries the full or partial terminal viewport state.

A FrameUpdate uses **hybrid encoding**: a binary section (frame header, DirtyRows, CellData) for the performance-critical cell data path, followed by an optional JSON metadata blob for cursor, preedit, colors, dimensions, mouse state, and terminal modes.

> **Normative note — CellData is SEMANTIC**: CellData carries semantic content (codepoint, style attributes, foreground/background color, wide-char flag). The client performs font shaping (HarfBuzz), glyph atlas lookup, and GPU buffer construction locally. Zero-copy wire-to-GPU is not a design goal. The GPU struct (e.g., ghostty's `CellText`, 32 bytes) is 70%+ client-local data (font shaping results, atlas coordinates, GPU-specific layout). The wire CellData format is optimized for compact semantic transport, not GPU alignment.

> **Normative note — FrameUpdate delivery scope**: The server sends FrameUpdate messages for ALL panes in the client's attached session that have dirty state, not just the focused pane. Each FrameUpdate carries a `pane_id` identifying which pane's state it contains. The client receives and renders updates for all visible panes.

> **Normative note — Per-client dirty tracking**: The server maintains independent dirty bitmaps per (client, pane) pair. A row's dirty flag for a specific client is cleared only when a FrameUpdate containing that row's data has been sent to that client. Different clients may receive different dirty row sets in their FrameUpdates depending on which rows each client has already received.

#### Wire Format Overview

A FrameUpdate is a variable-length message composed of a binary section followed by an optional JSON metadata blob.

```
[16-byte binary header] [binary frame header] [binary DirtyRows + CellData] [JSON metadata blob]
```

##### Binary Frame Header

```
Offset  Size  Field                Description
------  ----  -----                -----------
 0      16    [header]             type=0x0300, payload_len=variable
16       4    session_id           Session identifier (u32 LE)
20       4    pane_id              Pane identifier (u32 LE)
24       8    frame_sequence       Monotonic frame counter (u64 LE)
32       1    dirty                0=none, 1=partial, 2=full
33       1    screen               0=primary, 1=alternate
34       2    section_flags        Bitflags indicating which sections follow (u16 LE)
```

> **Normative note — `frame_sequence` scope**: `frame_sequence` is a per-pane monotonic counter incremented each time the server produces a new terminal state for that pane, regardless of which clients receive it. Clients may observe gaps in `frame_sequence` due to coalescing (intermediate states skipped) or flow control (PausePane dropping frames). The counter is NOT per-client — all clients observing the same pane see values from the same monotonic sequence, but each client may see a different subset of values.

**Section Flags (u16)**:

```
Bit  Section             When present
---  -------             ------------
 0   (reserved)          Formerly Dimensions (now in JSON metadata)
 1   (reserved)          Formerly Colors (now in JSON metadata)
 2   (reserved)          Formerly Cursor (now in JSON metadata)
 3   (reserved)          Formerly Preedit (now in JSON metadata)
 4   DirtyRows           When dirty=partial or dirty=full
 5   (reserved)          Formerly MouseState (now in JSON metadata)
 6   (reserved)          Formerly TerminalModes (now in JSON metadata)
 7   JSONMetadata        When JSON metadata blob is present (see Section 4.2)
 8-15 (reserved)
```

### 4.2 JSON Metadata Blob (section_flags bit 7)

When bit 7 of `section_flags` is set, a JSON metadata blob follows the binary DirtyRows/CellData section (or immediately after the binary frame header if no DirtyRows are present).

The JSON metadata blob is length-prefixed:

```
Offset  Size  Field               Description
------  ----  -----               -----------
 0       4    json_len             Length of JSON blob in bytes (u32 LE)
 4       N    json_data            UTF-8 JSON object
```

The JSON blob contains whichever metadata sections are relevant for this frame. All fields are optional — only changed or required fields are included (per Issue 3, absent fields are omitted, never `null`):

```json
{
  "cursor": {
    "x": 5,
    "y": 10,
    "visible": true,
    "style": 0,
    "blinking": true
  },
  "preedit": {
    "active": true,
    "cursor_x": 5,
    "cursor_y": 10,
    "text": "한"
  },
  "dimensions": {
    "cols": 80,
    "rows": 24
  },
  "colors": {
    "fg": [255, 255, 255],
    "bg": [0, 0, 0],
    "cursor_color": [255, 200, 0],
    "palette_changes": [[1, [255, 0, 0]], [4, [0, 0, 255]]]
  },
  "mouse": {
    "tracking": 0,
    "format": 0
  },
  "terminal_modes": {
    "bracketed_paste": true,
    "focus_reporting": true,
    "application_cursor_keys": false,
    "application_keypad": false,
    "kitty_keyboard_flags": 0
  }
}
```

#### Cursor fields

| Field | Type | Description |
|-------|------|-------------|
| `x` | u16 | Column |
| `y` | u16 | Row |
| `visible` | bool | Cursor visible |
| `style` | u8 | 0=block, 1=bar, 2=underline |
| `blinking` | bool | Whether cursor blinks |
| `password_input` | bool | Password mode detected |

**Cursor behavior during CJK composition (normative)**: The following requirements apply when `preedit.active` is true (see Preedit below):

1. **Server MUST set block cursor**: The server MUST set `cursor.style` to block (0) and `cursor.blinking` to false for the duration of composition. These values MUST appear in every FrameUpdate while preedit is active.
2. **Server MUST align cursor with preedit**: `cursor.x` and `cursor.y` MUST equal `preedit.cursor_x` and `preedit.cursor_y` — the block cursor visually encloses the composing character. When composition commits, `cursor.x` advances past the committed character to the normal insertion point.
3. **Server MUST restore pre-composition cursor style**: In the FrameUpdate following PreeditEnd, the server MUST restore `cursor.style` and `cursor.blinking` to their pre-composition values.

**Cursor blink (normative)**: When `cursor.blinking` is true, the client runs a local blink timer. The server does NOT send FrameUpdates for blink animation. The blink cadence (typically 500ms on/500ms off) is a client-local rendering concern. This avoids unnecessary frame traffic for a purely visual effect.

#### Preedit fields

| Field | Type | Description |
|-------|------|-------------|
| `active` | bool | Whether preedit is active |
| `cursor_x` | u16 | Cursor column for preedit overlay |
| `cursor_y` | u16 | Cursor row for preedit overlay |
| `text` | string | UTF-8 preedit string (e.g., `"한"`) |

When `active` is false, the client clears its preedit overlay. The `text` field is absent.

The preedit text is rendered as an overlay at the specified cursor position, typically with an underline decoration. The client draws it on top of the terminal grid after the main cell rendering pass.

**Capability interaction**: The preedit section is part of the visual render state and is always included in FrameUpdate when preedit is active, regardless of whether the client negotiated `CJK_CAP_PREEDIT`. Any client that can render cells can also render the preedit overlay. The `CJK_CAP_PREEDIT` capability controls only the dedicated preedit messages (PreeditStart/Update/End/Sync in the 0x0400 range, see doc 05), which provide composition metadata for state tracking, observer UIs, and conflict resolution.

#### Dimensions fields

| Field | Type | Description |
|-------|------|-------------|
| `cols` | u16 | Viewport width in cells |
| `rows` | u16 | Viewport height in cells |

Present on full updates or terminal resize.

#### Colors fields

| Field | Type | Description |
|-------|------|-------------|
| `fg` | [r, g, b] | Default foreground RGB |
| `bg` | [r, g, b] | Default background RGB |
| `cursor_color` | [r, g, b] | Cursor RGB (omit when no cursor color override) |
| `palette` | [[r,g,b], ...] | Full 256-entry palette (omit when unchanged) |
| `palette_changes` | [[index, [r,g,b]], ...] | Partial palette updates (omit when none) |

Present on full updates or when any color changes (e.g., OSC 10/11/12 sequences).

#### Mouse fields

| Field | Type | Description |
|-------|------|-------------|
| `tracking` | u8 | 0=off, 1=button, 2=any (motion), 3=sgr |
| `format` | u8 | 0=normal, 1=sgr, 2=urxvt |

When `tracking` is 0, the client handles mouse events locally (selection, scrollback). When non-zero, the client forwards mouse events to the server.

#### Terminal modes fields

| Field | Type | Description |
|-------|------|-------------|
| `bracketed_paste` | bool | Bracketed paste mode enabled |
| `focus_reporting` | bool | Focus reporting enabled |
| `application_cursor_keys` | bool | Application cursor key mode |
| `application_keypad` | bool | Application keypad mode |
| `kitty_keyboard_flags` | u8 | Kitty keyboard protocol flags (4-bit value) |

### 4.3 DirtyRows Section (section_flags bit 4)

Contains the actual cell data for rows that changed. This section uses **binary encoding** for compact, RLE-compatible transport.

```
Offset  Size  Field               Description
------  ----  -----               -----------
 0       2    num_dirty_rows       Count of dirty rows (u16 LE)
```

Followed by `num_dirty_rows` entries of `RowData`:

```
Offset  Size  Field               Description
------  ----  -----               -----------
 0       2    y                    Row index (u16 LE)
 2       1    selection_flags      Bit 0: has selection
 3       2    selection_start      Start column of selection (u16 LE, if bit 0)
 5       2    selection_end        End column of selection (u16 LE, if bit 0)
 ?       2    num_cells            Number of cell entries (u16 LE)
```

Followed by `num_cells` entries of `CellData`.

**Note**: `num_cells` may be less than `cols` when trailing cells are default/empty. The client fills remaining cells with the default background.

### 4.4 CellData Encoding

Each cell in a dirty row is encoded as follows:

```
Offset  Size  Field               Description
------  ----  -----               -----------
 0       4    codepoint            Primary codepoint (u32 LE, only lower 21 bits meaningful)
                                   0 = empty cell
 4       1    extra_count          Number of extra codepoints (0 for most cells)
 5      4*N   extra_codepoints     Extra codepoints for grapheme clusters (u32 LE each)
 ?       1    wide                 0=narrow, 1=wide, 2=spacer_tail, 3=spacer_head
 ?       4    fg_color             PackedColor (4 bytes)
 ?       4    bg_color             PackedColor (4 bytes)
 ?       4    underline_color      PackedColor (4 bytes)
 ?       2    flags                Style flags (u16 LE, see below)
```

**Typical cell size**: 20 bytes (single codepoint, no extras).
**Wide character**: The wide cell (wide=1) carries the codepoint. The spacer_tail (wide=2) immediately follows and has codepoint=0.

#### PackedColor (4 bytes)

```
Byte 0: tag
  0x00 = default (use terminal's default fg or bg)
  0x01 = palette index (byte 1 = index 0-255, bytes 2-3 unused)
  0x02 = direct RGB (byte 1 = R, byte 2 = G, byte 3 = B)

Bytes 1-3: data (interpretation depends on tag)
```

#### Style Flags (u16)

```
Bit   Flag
---   ----
 0    bold
 1    italic
 2    faint (dim)
 3    blink
 4    inverse (reverse video)
 5    invisible (hidden)
 6    strikethrough
 7    overline
 8-10 underline_style: 0=none, 1=single, 2=double, 3=curly, 4=dotted, 5=dashed
11    (reserved)
12-15 (reserved)
```

---

## 5. RenderState: Run-Length Encoding Optimization

For rows with many consecutive cells sharing the same style (common for blank lines, monochrome text), an optional RLE encoding reduces bandwidth.

### RLE Cell Encoding

When a row uses RLE (indicated by a flag in the row header), cells are encoded as runs:

```
Offset  Size  Field               Description
------  ----  -----               -----------
 0       2    run_length           Number of consecutive cells with this style (u16 LE)
 2      var   cell_data            CellData for the prototype cell
```

The client replicates the cell `run_length` times, advancing the column index. For RLE rows, `num_cells` in the RowData header represents the number of *runs*, not individual cells.

**Heuristic**: The server uses RLE when it reduces the row size by at least 25%. Otherwise, it sends individual cells.

### Row Header Extension for RLE

Add bit 1 to `selection_flags`:

```
Bit 0: has_selection
Bit 1: rle_encoded (0=individual cells, 1=run-length encoded)
```

---

## 6. Scrollback Messages

The client does not hold scrollback data. All scrollback access is request/response through the server. All scrollback and search messages use **JSON payloads** (ENCODING=0).

### 6.1 ScrollRequest (type = 0x0301)

Client -> server. Requests scrolling the viewport.

#### JSON Payload

```json
{
  "pane_id": 1,
  "direction": 0,
  "lines": 10
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `direction` | u8 | 0=up, 1=down, 2=top, 3=bottom |
| `lines` | u32 | Number of lines to scroll (ignored for direction=top/bottom) |

**Server response**: A FrameUpdate with `dirty=full` showing the scrolled viewport.

### 6.2 ScrollPosition (type = 0x0302)

Server -> client notification of current scroll position (sent with or after FrameUpdate).

#### JSON Payload

```json
{
  "pane_id": 1,
  "viewport_top": 0,
  "total_lines": 5000,
  "viewport_rows": 24
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `viewport_top` | u32 | Top line of viewport (0=most recent) |
| `total_lines` | u32 | Total lines in scrollback |
| `viewport_rows` | u32 | Number of visible rows |

This allows the client to render a scrollbar indicator.

### 6.3 SearchRequest (type = 0x0303)

Client -> server. Initiates a search in the scrollback buffer.

#### JSON Payload

```json
{
  "pane_id": 1,
  "direction": 0,
  "case_sensitive": false,
  "regex": false,
  "wrap_around": true,
  "query": "search term"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `direction` | u8 | 0=forward, 1=backward |
| `case_sensitive` | bool | Case-sensitive search |
| `regex` | bool | Treat query as regex |
| `wrap_around` | bool | Wrap around at buffer boundaries |
| `query` | string | UTF-8 search string |

### 6.4 SearchResult (type = 0x0304)

Server -> client. Reports the result of a search.

#### JSON Payload

```json
{
  "pane_id": 1,
  "total_matches": 42,
  "current_match": 7,
  "match_row": 10,
  "match_start_col": 5,
  "match_end_col": 15
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `total_matches` | u32 | Total match count (0=none found) |
| `current_match` | u32 | Index of highlighted match |
| `match_row` | u16 | Row of current match in viewport |
| `match_start_col` | u16 | Start column of match |
| `match_end_col` | u16 | End column of match |

The server also sends a FrameUpdate scrolling the viewport to show the match and highlighting the matched range in the selection.

### 6.5 SearchCancel (type = 0x0305)

Client -> server. Cancels an active search.

#### JSON Payload

```json
{
  "pane_id": 1
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |

---

## 7. FrameUpdate Dirty Modes

The `dirty` field in FrameUpdate controls what sections are present:

### 7.1 dirty=0 (None)

Nothing changed in the terminal grid. This is sent when only non-grid state changes (e.g., cursor position moved without grid changes).

**Note**: Cursor blink does NOT trigger FrameUpdates. When `cursor.blinking` is true, the client runs a local blink timer autonomously.

**Required sections**: JSON metadata blob with changed fields (typically just cursor).
**Typical size**: 16 (header) + 20 (frame header) + 4 (json_len) + ~60 (JSON) = **~100 bytes**.

### 7.2 dirty=1 (Partial)

Some rows changed. Common for keystroke echo (1-2 rows), scrolling (a few rows), command output.

**Required sections**: DirtyRows (binary), JSON metadata blob (cursor, optionally preedit).
**Typical size for 2 changed rows (80 cols)**:

```
Header:          16 bytes
Frame header:    20 bytes
DirtyRows header: 2 bytes
Row 0 header:     7 bytes
Row 0 cells:   ~80 * 20 = 1,600 bytes
Row 1 header:     7 bytes
Row 1 cells:   ~80 * 20 = 1,600 bytes
JSON metadata:   ~80 bytes (cursor)
---------------------------------
Total:         ~3,332 bytes
```

With RLE (mostly empty rows): **~400-800 bytes**.

### 7.3 dirty=2 (Full)

Everything changed. Sent on resize, screen switch (primary/alternate), initial attach, scroll-to-position.

**Required sections**: DirtyRows (all rows, binary), JSON metadata blob (dimensions, colors, cursor, terminal modes, mouse state).
**Typical size for 80x24 terminal**:

```
Header:          16 bytes
Frame header:    20 bytes
DirtyRows header: 2 bytes
24 rows * ~1,607 bytes per row = ~38,568 bytes
JSON metadata:  ~900 bytes (all sections)
---------------------------------
Total:         ~39,506 bytes (worst case, all unique styles)
```

With typical styling (most cells default): **~8,000-12,000 bytes**.
With RLE: **~3,000-5,000 bytes**.

---

## 8. Bandwidth Analysis

### 8.1 Scenario Estimates

| Scenario | Message Size | Frequency | Bandwidth | Notes |
|----------|-------------|-----------|-----------|-------|
| Cursor-only move | ~100 B | Event-driven | ~2.6 KB/s | |
| Preedit update (Korean composition) | ~120 B | Per keystroke (~5/s) | ~0.6 KB/s | |
| Single row change (keystroke echo) | ~1.8 KB | Per keystroke (~5/s) | ~9.0 KB/s | |
| Partial update (2 rows, command output) | ~3.3 KB | ~30/s | ~99 KB/s | |
| Full frame (80x24, typical) | ~8 KB | Occasional (resize, attach) | N/A | |
| Full frame (80x24, worst case) | ~40 KB | Rare | N/A | |
| Scrolling (24 rows dirty) | ~8 KB | ~30/s during active scroll | ~240 KB/s | |
| Heavy output (e.g., `cat large_file`) | ~8 KB | Coalesced ceiling ~60/s | ~480 KB/s | Coalesced ceiling, not sustained target |

### 8.2 Bandwidth Budget

- **Unix domain socket**: >1 GB/s throughput, <0.1ms latency
- **LAN (iOS -> macOS)**: ~100 MB/s, 1-5ms latency
- **WAN (SSH tunnel)**: 1-10 MB/s, 20-100ms latency

**Conclusion**: All scenarios are well within bandwidth limits, even over WAN via SSH tunnel. The bottleneck over WAN is latency, not bandwidth.

### 8.3 Event-Driven Coalescing

The server uses **event-driven coalescing** with a **16ms minimum interval** (coalescing ceiling) for FrameUpdate output. FrameUpdates are sent only when dirty state exists. There is no fixed fps target.

**Coalescing model**:
- **Event-driven**: FrameUpdates are triggered by PTY output or preedit state changes, not by a fixed timer.
- **Coalescing ceiling**: If multiple PTY output events arrive within one frame interval (~16ms), the server sends a single FrameUpdate covering all changes.
- **Idle suppression**: If nothing changes, no FrameUpdate is sent (the client continues rendering the last frame).
- **Typical cadence**: 0-30 updates/second for normal terminal workloads. Burst output is coalesced; idle terminals produce zero frames.

The 16ms coalescing ceiling aligns with 60 Hz display refresh but is NOT a "60 fps target." The server never generates frames to fill a target rate — it only sends frames when there is dirty state to communicate. See doc 06 for the full 4-tier adaptive cadence model (Preedit, Interactive, Active, Bulk) and per-pane coalescing rules.

---

## 9. Compression

### 9.1 Reserved for Future Use

The COMPRESSED flag (bit 1 of the header flags byte) is reserved for future use. In protocol version 1, compression is not implemented. Senders MUST NOT set the COMPRESSED flag. Receivers that encounter COMPRESSED=1 SHOULD send `ERR_DECOMPRESSION_FAILED`.

Application-layer compression is deferred to v2. For remote access via SSH tunnel, SSH's built-in compression (`Compression yes`) provides transport-layer compression without protocol complexity. Neither tmux nor zellij implements application-layer compression.

If benchmarking in v2 shows benefit beyond SSH compression, application-layer compression will be added with explicit exclusion of Preedit and Interactive tier messages to preserve latency guarantees.

---

## 10. Message Type Summary

### Input Messages (Client -> Server): 0x0200-0x02FF

All input messages use JSON payloads (16-byte binary header + JSON body).

| Type | Name | Description |
|------|------|-------------|
| `0x0200` | KeyEvent | Raw HID keycode + modifiers + input_method (JSON) |
| `0x0201` | TextInput | Direct UTF-8 text insertion (JSON) |
| `0x0202` | MouseButton | Mouse button press/release (JSON) |
| `0x0203` | MouseMove | Mouse motion, rate limited (JSON) |
| `0x0204` | MouseScroll | Scroll wheel / trackpad (JSON) |
| `0x0205` | PasteData | Clipboard paste, chunked (JSON) |
| `0x0206` | FocusEvent | Window focus gained/lost (JSON) |

### RenderState Messages (Server -> Client): 0x0300-0x03FF

| Type | Name | Encoding | Description |
|------|------|----------|-------------|
| `0x0300` | FrameUpdate | Hybrid (binary + JSON) | Terminal viewport state (binary cells + JSON metadata) |
| `0x0301` | ScrollRequest | JSON | Client requests scroll (client -> server) |
| `0x0302` | ScrollPosition | JSON | Current scroll position |
| `0x0303` | SearchRequest | JSON | Search in scrollback (client -> server) |
| `0x0304` | SearchResult | JSON | Search match result |
| `0x0305` | SearchCancel | JSON | Cancel active search (client -> server) |

**Note**: ScrollRequest, SearchRequest, and SearchCancel are client -> server messages that use the 0x0300 range because they are conceptually part of the render state subsystem (they trigger FrameUpdate responses). All messages except FrameUpdate use JSON payloads (ENCODING=0).

---

## 11. Open Questions

1. **Cell deduplication**: Should the server maintain a cell style palette (assign IDs to unique style combinations) and send style IDs per cell instead of inline PackedColor+flags? This could reduce per-cell size from 20 bytes to ~10 bytes but adds complexity.

2. **Image protocol**: Sixel and Kitty image protocol support is not covered here. Image data is potentially large and may need a dedicated message type with out-of-band transfer. Deferred to a future spec.

3. **Selection protocol**: Text selection is currently encoded as a range per row in DirtyRows. Should there be dedicated SelectionStart/SelectionUpdate/SelectionEnd messages for multi-client selection sync?

4. **Hyperlink data**: OSC 8 hyperlinks in cell data are not currently encoded in CellData. They may need an extension field or a separate hyperlink table.

5. **FrameUpdate acknowledgment**: Should the client acknowledge FrameUpdate messages? This could enable flow control (server pauses if client falls behind). Currently not specified — the server sends at its own rate. May be needed for slow WAN connections via SSH tunnel.

6. **Notification coalescing**: When multiple panes have updates in the same frame interval, should they be batched into a single message or sent as separate FrameUpdate messages? Separate messages are simpler; batching reduces syscall overhead.

---

## Appendix A: Example FrameUpdate Hex Dump

A partial update: cursor moved to (5, 10), one row changed, with preedit active showing "한".

```
Offset  Hex                                       Description
------  ---                                       -----------
0000    49 54                                     magic "IT"
0002    01                                        version 1
0003    01                                        flags (ENCODING=1 binary, no compression)
0004    00 03                                     type 0x0300 (FrameUpdate)
0006    00 00                                     reserved
0008    XX XX XX XX                               payload_len (varies)
000C    XX XX XX XX                               sequence

0010    01 00 00 00                               session_id = 1
0014    01 00 00 00                               pane_id = 1
0018    2A 00 00 00 00 00 00 00                   frame_sequence = 42
0020    01                                        dirty = partial
0021    00                                        screen = primary
0022    90 00                                     section_flags = 0x0090 (DirtyRows + JSONMetadata)

        -- DirtyRows Section (binary) --
0024    01 00                                     num_dirty_rows = 1

        -- Row 0 --
0026    0A 00                                     y = 10
0028    00                                        selection_flags = 0 (no selection, no RLE)
0029    04 00                                     selection_start (ignored)
002B    04 00                                     selection_end (ignored)
002D    05 00                                     num_cells = 5

        -- Cell 0: 'H' --
002F    48 00 00 00                               codepoint = 0x48 ('H')
0033    00                                        extra_count = 0
0034    00                                        wide = narrow
0035    00 00 00 00                               fg = default
0039    00 00 00 00                               bg = default
003D    00 00 00 00                               underline_color = default
0041    01 00                                     flags = bold

        -- Cell 1: 'e' --
0043    65 00 00 00                               codepoint = 0x65 ('e')
0047    00                                        extra_count = 0
0048    00                                        wide = narrow
0049    00 00 00 00                               fg = default
004D    00 00 00 00                               bg = default
0051    00 00 00 00                               underline_color = default
0055    01 00                                     flags = bold

        ... (cells 2-4 follow same pattern) ...

        -- JSON Metadata Blob --
XXXX    YY YY YY YY                               json_len = N
XXXX    7B 22 63 75 72 73 6F 72 ...               {"cursor":{"x":5,"y":10,"visible":true,
                                                    "style":0,"blinking":true},
                                                   "preedit":{"active":true,
                                                    "cursor_x":5,"cursor_y":10,
                                                    "text":"한"}}
```

## Appendix B: CellData Size Analysis

| Cell type | Size | Frequency |
|-----------|------|-----------|
| Simple ASCII (no style) | 20 B | ~70% of cells |
| Simple ASCII (styled) | 20 B | ~20% of cells |
| Wide CJK character | 20 B | ~5% (the spacer_tail adds another 20 B) |
| Grapheme cluster (emoji + ZWJ) | 20 + 4*N B | <1% |
| Empty (trailing) | 20 B, or omitted with short num_cells | ~varies |

**Effective average**: ~20 bytes/cell for the vast majority of terminal content. Grapheme clusters with multiple codepoints (e.g., family emoji: base + ZWJ + person + ZWJ + child) are rare in terminal usage but handled correctly via `extra_codepoints`.

## Appendix C: Hybrid Encoding Rationale

The hybrid encoding (binary CellData + JSON metadata) was chosen based on analysis of ghostty and iTerm2 reference implementations (see review-notes-02):

| Component | Encoding | Rationale |
|-----------|----------|-----------|
| Message header | Binary (16B) | O(1) dispatch, unambiguous framing |
| DirtyRows + CellData | Binary | 70-95% of payload, 3x smaller than JSON, RLE-compatible |
| Cursor, Preedit, Colors, Dimensions | JSON blob | Debuggable; preedit shows `"한"` not hex bytes |
| Input messages (key, mouse, focus) | JSON | Low frequency, schema evolution, cross-language `JSONDecoder` |
| Handshake/negotiation | JSON | Self-describing, version discovery |

**What killed uniform binary**: GPU structs are 70%+ client-local data (font shaping, atlas coords). Zero-copy wire-to-GPU is impossible. JSON at 480 KB/s worst case is <0.01% CPU. The debuggability/maintainability benefit of JSON for non-cell-data sections outweighs the marginal bandwidth difference.

**What justifies binary CellData**: 38 KB binary vs 120 KB+ JSON per full 80x24 frame. Fixed-size cells enable efficient RLE. Deterministic sizing enables client pre-allocation. Avoids JSON tokenization of 2000+ cells on mobile/iPad.
