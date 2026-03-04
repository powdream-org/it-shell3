# 04 — Input Forwarding and RenderState Protocol

**Status**: Draft v0.2
**Author**: rendering-cjk-specialist
**Date**: 2026-03-04
**Depends on**: 01-protocol-overview.md (header format), 03-session-pane-management.md (session/pane IDs)

**Changes from v0.1**:
- Header updated from 14 bytes to 16 bytes (canonical format per doc 01)
- `length` field renamed to `payload_len` (payload only, not including header)
- KeyEvent: removed `composing` field (replaced with `reserved`); client does not track composition state
- KeyEvent example: removed `composing` references
- Cursor Section (4.4): added normative text for cursor behavior during CJK composition
- Preedit Section (4.5): added capability interaction note (always present regardless of CJK_CAP_PREEDIT)
- All wire format offsets updated for 16-byte header
- All message sizes updated for 16-byte header
- Compression section updated for 16-byte header

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
──────  ────  ─────        ───────────
 0      2     magic        0x49 0x54 ("IT" in ASCII), little-endian
 2      1     version      Protocol version (starts at 1)
 3      1     flags        Per-message flags (bit 0 = compressed, bits 1-7 reserved)
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

### 2.1 KeyEvent (type = 0x0200)

The primary input message. The client sends raw HID keycodes and modifiers. The server derives text through the native IME engine (libitshell3-ime) — the client never sends composed text for key input. The client does not track IME composition state; the server determines composition state internally from the IME engine.

#### Wire Format

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0200, payload_len=8
16       2    keycode             HID usage code (u16 LE), e.g., 0x04='A'
18       1    action              0=press, 1=release, 2=repeat
19       1    modifiers           Bitflags (see below)
20       1    reserved            Must be 0
21       1    reserved            Must be 0
22       2    active_layout_id    Keyboard layout identifier (u16 LE)
```

**Total payload**: 8 bytes. **Total with header**: 24 bytes.

#### Modifier Bitflags (u8)

```
Bit  Modifier
───  ────────
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

#### Active Layout ID

The `active_layout_id` identifies which keyboard layout the client has active, so the server's IME engine can apply the correct keycode-to-character mapping:

| ID | Layout |
|----|--------|
| `0x0000` | US QWERTY (English) |
| `0x0001` | Korean 2-set |
| `0x0002` | Korean 3-set (390) |
| `0x0003` | Korean 3-set (Final) |
| `0x0100`-`0x01FF` | Reserved for Japanese layouts |
| `0x0200`-`0x02FF` | Reserved for Chinese layouts |
| `0xFFFF` | Unknown/passthrough |

Layout IDs are negotiated during handshake (the server advertises supported layouts, the client selects from them).

#### Example: Typing Korean "한"

```
1. User presses 'H' key (HID 0x0B), layout=Korean 2-set
   KeyEvent: keycode=0x000B, action=0, mods=0x00, layout=0x0001
   Server IME: maps H -> ㅎ, enters composing state, emits preedit "ㅎ"

2. User presses 'A' key (HID 0x04)
   KeyEvent: keycode=0x0004, action=0, mods=0x00, layout=0x0001
   Server IME: maps A -> ㅏ, composes ㅎ+ㅏ=하, emits preedit "하"

3. User presses 'N' key (HID 0x11)
   KeyEvent: keycode=0x0011, action=0, mods=0x00, layout=0x0001
   Server IME: maps N -> ㄴ, composes 하+ㄴ=한, emits preedit "한"

4. User presses Space (HID 0x2C), commits
   KeyEvent: keycode=0x002C, action=0, mods=0x00, layout=0x0001
   Server IME: commits "한" to PTY, clears preedit
```

Note: The client sends identical KeyEvent messages regardless of whether composition is active. The server's IME engine tracks composition state internally.

### 2.2 TextInput (type = 0x0201)

For direct text insertion that bypasses IME processing. Primary use case: programmatic text injection (e.g., from clipboard managers, automation tools).

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0201, payload_len=6+N
16       4    pane_id             Target pane (u32 LE)
20       2    text_len            Length of UTF-8 text in bytes (u16 LE)
22       N    text                UTF-8 encoded text (N = text_len)
```

**Maximum text_len**: 65535 bytes. For larger text, use PasteData (0x0205).

### 2.3 MouseButton (type = 0x0202)

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0202, payload_len=16
16       4    pane_id             Target pane (u32 LE)
20       1    button              0=left, 1=middle, 2=right, 3-7=extra
21       1    action              0=press, 1=release
22       1    modifiers           Same bitflags as KeyEvent
23       1    click_count         1=single, 2=double, 3=triple
24       4    x                   Column position in cell coords (f32 LE)
28       4    y                   Row position in cell coords (f32 LE)
```

**Total payload**: 16 bytes. **Total with header**: 32 bytes.

Sub-cell precision is provided via f32 for `x` and `y` to support fractional cell positioning (useful for future sixel/image region click detection).

### 2.4 MouseMove (type = 0x0203)

Sent when the mouse moves and mouse tracking is active (the server notifies the client whether mouse tracking is enabled via a flag in FrameUpdate).

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0203, payload_len=14
16       4    pane_id             Target pane (u32 LE)
20       1    modifiers           Active modifiers
21       1    buttons_held        Bitflags: bit 0=left, 1=middle, 2=right
22       4    x                   Column (f32 LE)
26       4    y                   Row (f32 LE)
```

**Total payload**: 14 bytes. **Total with header**: 30 bytes.

**Rate limiting**: The client SHOULD throttle MouseMove messages to at most 60/second per pane. The server MAY drop excess MouseMove messages.

### 2.5 MouseScroll (type = 0x0204)

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0204, payload_len=16
16       4    pane_id             Target pane (u32 LE)
20       1    modifiers           Active modifiers
21       1    reserved            Must be 0
22       4    dx                  Horizontal scroll delta (f32 LE)
26       4    dy                  Vertical scroll delta (f32 LE)
30       1    precise             0=line-based (mouse wheel), 1=pixel-precise (trackpad)
31       1    reserved            Must be 0
```

**Total payload**: 16 bytes. **Total with header**: 32 bytes.

### 2.6 PasteData (type = 0x0205)

For clipboard paste operations. Supports large payloads via chunking.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0205, payload_len=8+N
16       4    pane_id             Target pane (u32 LE)
20       1    flags               Bit 0: bracketed_paste (1=wrap in \e[200~ / \e[201~)
                                  Bit 1: final_chunk (1=this is the last chunk)
                                  Bit 2: first_chunk (1=this is the first chunk)
21       1    reserved            Must be 0
22       2    chunk_len           Length of this chunk in bytes (u16 LE)
24       N    data                UTF-8 paste data (N = chunk_len)
```

**Chunking protocol**:
- Small pastes (<=64 KB): Single message with first_chunk=1 AND final_chunk=1
- Large pastes: Multiple messages. First has first_chunk=1. Last has final_chunk=1.
- The server assembles chunks in sequence order before writing to PTY.
- The server applies bracketed paste wrapping around the assembled text if `bracketed_paste=1` and the terminal has bracketed paste mode enabled.

### 2.7 FocusEvent (type = 0x0206)

Notifies the server when the client terminal gains or loses OS-level focus. This enables focus reporting (CSI ? 1004 h).

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0206, payload_len=5
16       4    pane_id             Target pane (u32 LE)
20       1    focused             0=lost focus, 1=gained focus
```

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
──────                                    ──────

 [User presses key]
     │
     ▼
 KeyEvent(HID keycode, mods, layout)
     │
     ├─── Unix socket ────────────────►  Input Dispatcher
     │                                       │
     │                                       ▼
     │                                   libitshell3-ime
     │                                   (Layout Mapper + Composition Engine)
     │                                       │
     │                                       ├── Preedit? ──► Update preedit state
     │                                       │                     │
     │                                       └── Commit? ──► Write to PTY
     │                                                            │
     │                                                            ▼
     │                                                       libghostty-vt
     │                                                       Terminal.vtStream()
     │                                                            │
     │                                                            ▼
     │                                                       RenderState.update()
     │                                                            │
     ◄──── FrameUpdate (dirty rows + cursor + preedit) ──────────┘
     │
     ▼
 Font subsystem (SharedGrid, Atlas)
     │
     ▼
 Metal GPU render (CellText, CellBg shaders)
```

---

## 4. RenderState Messages (Server -> Client)

### 4.1 FrameUpdate (type = 0x0300)

The primary rendering message. Carries the full or partial terminal viewport state.

#### Wire Format Overview

A FrameUpdate is a variable-length message composed of sections, each conditionally present based on the `dirty` flag and section presence flags.

```
Offset  Size  Field                Description
──────  ────  ─────                ───────────
 0      16    [header]             type=0x0300, payload_len=variable
16       4    session_id           Session identifier (u32 LE)
20       4    pane_id              Pane identifier (u32 LE)
24       8    frame_sequence       Monotonic frame counter (u64 LE)
32       1    dirty                0=none, 1=partial, 2=full
33       1    screen               0=primary, 1=alternate
34       2    section_flags        Bitflags indicating which sections follow (u16 LE)
```

**Section Flags (u16)**:

```
Bit  Section             When present
───  ───────             ────────────
 0   Dimensions          Full update, or resize
 1   Colors              Full update, or color change
 2   Cursor              Always (unless dirty=none AND cursor unchanged)
 3   Preedit             When preedit is active or just became inactive
 4   DirtyRows           When dirty=partial or dirty=full
 5   MouseState          When mouse tracking mode changed
 6   TerminalModes       When relevant terminal modes changed
 7-15 (reserved)
```

### 4.2 Dimensions Section (bit 0)

Present on full updates or terminal resize.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0       2    cols                 Viewport width in cells (u16 LE)
 2       2    rows                 Viewport height in cells (u16 LE)
```

### 4.3 Colors Section (bit 1)

Present on full updates or when any color changes (e.g., OSC 10/11/12 sequences).

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0       3    fg                   Default foreground RGB (3 bytes: r, g, b)
 3       3    bg                   Default background RGB
 6       1    cursor_color_present 0=no cursor color, 1=cursor color follows
 7       3    cursor_color         Cursor RGB (only if cursor_color_present=1)
 ?       1    palette_flags        Bit 0: full palette follows
                                   Bit 1: partial palette (index + color pairs)
```

If `palette_flags` bit 0:
```
 ?     768    palette              256 RGB entries (256 * 3 = 768 bytes)
```

If `palette_flags` bit 1:
```
 ?       1    num_changed          Number of changed palette entries (u8)
 ?     4*N    palette_entries      Array of {index(u8), r(u8), g(u8), b(u8)}
```

### 4.4 Cursor Section (bit 2)

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0       2    cursor_x             Column (u16 LE)
 2       2    cursor_y             Row (u16 LE)
 4       1    cursor_visible       0=hidden, 1=visible
 5       1    cursor_style         0=block, 1=bar, 2=underline
 6       1    cursor_blinking      0=steady, 1=blinking
 7       1    password_input       0=normal, 1=password mode detected
```

**Cursor behavior during CJK composition**: When `preedit_active=true` (Section 4.5), the server overrides `cursor_style` to block (0) and `cursor_blinking` to steady (0) for the duration of composition. The pre-composition cursor style is restored when composition ends. During composition, `cursor_x` and `cursor_y` MUST equal `preedit_cursor_x` and `preedit_cursor_y` from the Preedit Section — the block cursor visually encloses the composing character. When composition commits, `cursor_x` advances past the committed character to the normal insertion point.

### 4.5 Preedit Section (bit 3)

Present when preedit state is active or transitions from active to inactive.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0       1    preedit_active       0=inactive (composition ended), 1=active
 1       2    preedit_cursor_x     Cursor column for preedit overlay (u16 LE)
 3       2    preedit_cursor_y     Cursor row for preedit overlay (u16 LE)
 5       2    preedit_text_len     Length of preedit text in bytes (u16 LE)
 7       N    preedit_text         UTF-8 encoded preedit string
```

When `preedit_active=0`, the client clears its preedit overlay. The `preedit_text_len` is 0 and `preedit_text` is absent.

The preedit text is rendered as an overlay at the specified cursor position, typically with an underline decoration. The client draws it on top of the terminal grid after the main cell rendering pass.

**Capability interaction**: The preedit section is part of the visual render state and is always included in FrameUpdate when preedit is active, regardless of whether the client negotiated `CJK_CAP_PREEDIT`. Any client that can render cells can also render the preedit overlay. The `CJK_CAP_PREEDIT` capability controls only the dedicated preedit messages (PreeditStart/Update/End/Sync in the 0x0400 range, see doc 05), which provide composition metadata for state tracking, observer UIs, and conflict resolution.

### 4.6 DirtyRows Section (bit 4)

Contains the actual cell data for rows that changed.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0       2    num_dirty_rows       Count of dirty rows (u16 LE)
```

Followed by `num_dirty_rows` entries of `RowData`:

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0       2    y                    Row index (u16 LE)
 2       1    selection_flags      Bit 0: has selection
 3       2    selection_start      Start column of selection (u16 LE, if bit 0)
 5       2    selection_end        End column of selection (u16 LE, if bit 0)
 ?       2    num_cells            Number of cell entries (u16 LE)
```

Followed by `num_cells` entries of `CellData`.

**Note**: `num_cells` may be less than `cols` when trailing cells are default/empty. The client fills remaining cells with the default background.

### 4.7 CellData Encoding

Each cell in a dirty row is encoded as follows:

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
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
───   ────
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

### 4.8 MouseState Section (bit 5)

Informs the client whether the terminal application has enabled mouse tracking.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0       1    mouse_tracking       0=off, 1=button, 2=any (motion), 3=sgr
 1       1    mouse_format         0=normal, 1=sgr, 2=urxvt
```

When `mouse_tracking=0`, the client handles mouse events locally (selection, scrollback). When non-zero, the client forwards mouse events to the server.

### 4.9 TerminalModes Section (bit 6)

Communicates relevant terminal mode changes.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0       2    mode_flags           Bitflags (u16 LE)
```

```
Bit  Mode
───  ────
 0   bracketed_paste_enabled
 1   focus_reporting_enabled
 2   application_cursor_keys
 3   application_keypad
 4   kitty_keyboard_flags (bits 4-7, 4-bit value)
```

---

## 5. RenderState: Run-Length Encoding Optimization

For rows with many consecutive cells sharing the same style (common for blank lines, monochrome text), an optional RLE encoding reduces bandwidth.

### RLE Cell Encoding

When a row uses RLE (indicated by a flag in the row header), cells are encoded as runs:

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
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

The client does not hold scrollback data. All scrollback access is request/response through the server.

### 6.1 ScrollRequest (type = 0x0301)

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]             type=0x0301, payload_len=10
16       4    pane_id              (u32 LE)
20       1    direction            0=up, 1=down, 2=top, 3=bottom
21       1    reserved             Must be 0
22       4    lines                Number of lines to scroll (u32 LE)
                                   Ignored for direction=top/bottom
```

**Server response**: A FrameUpdate with `dirty=full` showing the scrolled viewport.

### 6.2 ScrollPosition (type = 0x0302)

Server -> client notification of current scroll position (sent with or after FrameUpdate).

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]             type=0x0302, payload_len=16
16       4    pane_id              (u32 LE)
20       4    viewport_top         Top line of viewport (u32 LE, 0=most recent)
24       4    total_lines          Total lines in scrollback (u32 LE)
28       4    viewport_rows        Number of visible rows (u32 LE)
```

This allows the client to render a scrollbar indicator.

### 6.3 SearchRequest (type = 0x0303)

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]             type=0x0303, payload_len=8+N
16       4    pane_id              (u32 LE)
20       1    direction            0=forward, 1=backward
21       1    flags                Bit 0: case_sensitive
                                   Bit 1: regex
                                   Bit 2: wrap_around
22       2    query_len            Length of search query (u16 LE)
24       N    query                UTF-8 search string
```

### 6.4 SearchResult (type = 0x0304)

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]             type=0x0304, payload_len=variable
16       4    pane_id              (u32 LE)
20       4    total_matches        Total match count (u32 LE, 0=none found)
24       4    current_match        Index of highlighted match (u32 LE)
28       2    match_row            Row of current match in viewport (u16 LE)
30       2    match_start_col      Start column of match (u16 LE)
32       2    match_end_col        End column of match (u16 LE)
```

The server also sends a FrameUpdate scrolling the viewport to show the match and highlighting the matched range in the selection.

### 6.5 SearchCancel (type = 0x0305)

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]             type=0x0305, payload_len=4
16       4    pane_id              (u32 LE)
```

---

## 7. FrameUpdate Dirty Modes

The `dirty` field in FrameUpdate controls what sections are present:

### 7.1 dirty=0 (None)

Nothing changed in the terminal grid. This is sent when only non-grid state changes (e.g., cursor blink toggle via timer).

**Required sections**: Only those indicated by section_flags (typically just Cursor).
**Typical size**: 16 (header) + 20 (frame header) + 8 (cursor) = **44 bytes**.

### 7.2 dirty=1 (Partial)

Some rows changed. Common for keystroke echo (1-2 rows), scrolling (a few rows), command output.

**Required sections**: Cursor (always), DirtyRows, optionally Preedit.
**Typical size for 2 changed rows (80 cols)**:

```
Header:          16 bytes
Frame header:    20 bytes
Cursor:           8 bytes
DirtyRows header: 2 bytes
Row 0 header:     7 bytes
Row 0 cells:   ~80 * 20 = 1,600 bytes
Row 1 header:     7 bytes
Row 1 cells:   ~80 * 20 = 1,600 bytes
─────────────────────────────
Total:         ~3,260 bytes
```

With RLE (mostly empty rows): **~400-800 bytes**.

### 7.3 dirty=2 (Full)

Everything changed. Sent on resize, screen switch (primary/alternate), initial attach, scroll-to-position.

**Required sections**: Dimensions, Colors, Cursor, DirtyRows (all rows), TerminalModes, MouseState.
**Typical size for 80x24 terminal**:

```
Header:          16 bytes
Frame header:    20 bytes
Dimensions:       4 bytes
Colors:        ~780 bytes (fg+bg+cursor+palette)
Cursor:           8 bytes
TerminalModes:    2 bytes
MouseState:       2 bytes
DirtyRows header: 2 bytes
24 rows * ~1,607 bytes per row = ~38,568 bytes
─────────────────────────────
Total:         ~39,402 bytes (worst case, all unique styles)
```

With typical styling (most cells default): **~8,000-12,000 bytes**.
With RLE: **~3,000-5,000 bytes**.

---

## 8. Bandwidth Analysis

### 8.1 Scenario Estimates

| Scenario | Message Size | Frequency | Bandwidth |
|----------|-------------|-----------|-----------|
| Cursor-only move | ~44 B | Up to 60/s | ~2.6 KB/s |
| Preedit update (Korean composition) | ~90 B | Per keystroke (~5/s) | ~0.4 KB/s |
| Single row change (keystroke echo) | ~1.7 KB | Per keystroke (~5/s) | ~8.5 KB/s |
| Partial update (2 rows, command output) | ~3.3 KB | ~30/s | ~99 KB/s |
| Full frame (80x24, typical) | ~8 KB | Occasional (resize, attach) | N/A |
| Full frame (80x24, worst case) | ~39 KB | Rare | N/A |
| Scrolling (24 rows dirty) | ~8 KB | ~30/s during active scroll | ~240 KB/s |
| Heavy output (e.g., `cat large_file`) | ~8 KB | 60/s (rate limited) | ~480 KB/s |

### 8.2 Bandwidth Budget

- **Unix domain socket**: >1 GB/s throughput, <0.1ms latency
- **LAN (iOS -> macOS)**: ~100 MB/s, 1-5ms latency
- **WAN**: 1-10 MB/s, 20-100ms latency

**Conclusion**: All scenarios are well within bandwidth limits, even over WAN. The bottleneck over WAN is latency, not bandwidth.

### 8.3 Server-Side Rate Limiting

The server rate-limits FrameUpdate output:
- **Target**: 60 fps maximum
- **Coalescing**: If multiple PTY output events arrive within one frame interval (~16ms), the server sends a single FrameUpdate covering all changes
- **Idle suppression**: If nothing changes, no FrameUpdate is sent (the client continues rendering the last frame)

---

## 9. Compression

### 9.1 Negotiation

Compression support is negotiated during handshake via capability flags. Both sides must agree.

### 9.2 Zstd Compression

When compression is enabled (header flags bit 0 = 1):
- The payload (everything after the 16-byte header) is zstd-compressed
- The `payload_len` field in the header reflects the compressed payload size
- A 4-byte uncompressed length (u32 LE) is prepended to the compressed payload

```
[header 16B] [uncompressed_len 4B] [zstd-compressed payload]
```

**When to compress**:
- Full frames (dirty=2): Always compress (saves ~60-70%)
- Partial frames with >4 dirty rows: Compress
- Small messages (<256 bytes): Do NOT compress (overhead exceeds savings)

### 9.3 Pre-shared Dictionary

**Open question**: A pre-shared zstd dictionary trained on terminal output patterns could improve compression ratios for small frames. This is a potential optimization for v2.

---

## 10. Message Type Summary

### Input Messages (Client -> Server): 0x0200-0x02FF

| Type | Name | Size (typical) | Description |
|------|------|----------------|-------------|
| `0x0200` | KeyEvent | 24 B | Raw HID keycode + modifiers |
| `0x0201` | TextInput | 16+6+N | Direct UTF-8 text insertion |
| `0x0202` | MouseButton | 32 B | Mouse button press/release |
| `0x0203` | MouseMove | 30 B | Mouse motion (rate limited) |
| `0x0204` | MouseScroll | 32 B | Scroll wheel / trackpad |
| `0x0205` | PasteData | 16+8+N | Clipboard paste (chunked) |
| `0x0206` | FocusEvent | 21 B | Window focus gained/lost |

### RenderState Messages (Server -> Client): 0x0300-0x03FF

| Type | Name | Size (typical) | Description |
|------|------|----------------|-------------|
| `0x0300` | FrameUpdate | 44 B - 40 KB | Terminal viewport state (delta or full) |
| `0x0301` | ScrollRequest | 26 B | Client requests scroll (client -> server) |
| `0x0302` | ScrollPosition | 32 B | Current scroll position |
| `0x0303` | SearchRequest | 16+8+N | Search in scrollback (client -> server) |
| `0x0304` | SearchResult | 34 B | Search match result |
| `0x0305` | SearchCancel | 20 B | Cancel active search (client -> server) |

**Note**: ScrollRequest, SearchRequest, and SearchCancel are client -> server messages that use the 0x0300 range because they are conceptually part of the render state subsystem (they trigger FrameUpdate responses).

---

## 11. Open Questions

1. **Cell deduplication**: Should the server maintain a cell style palette (assign IDs to unique style combinations) and send style IDs per cell instead of inline PackedColor+flags? This could reduce per-cell size from 20 bytes to ~10 bytes but adds complexity.

2. **Image protocol**: Sixel and Kitty image protocol support is not covered here. Image data is potentially large and may need a dedicated message type with out-of-band transfer. Deferred to a future spec.

3. **Selection protocol**: Text selection is currently encoded as a range per row in DirtyRows. Should there be dedicated SelectionStart/SelectionUpdate/SelectionEnd messages for multi-client selection sync?

4. **Hyperlink data**: OSC 8 hyperlinks in cell data are not currently encoded in CellData. They may need an extension field or a separate hyperlink table.

5. **FrameUpdate acknowledgment**: Should the client acknowledge FrameUpdate messages? This could enable flow control (server pauses if client falls behind). Currently not specified — the server sends at its own rate. May be needed for slow WAN connections.

6. **Notification coalescing**: When multiple panes have updates in the same frame interval, should they be batched into a single message or sent as separate FrameUpdate messages? Separate messages are simpler; batching reduces syscall overhead.

---

## Appendix A: Example FrameUpdate Hex Dump

A partial update: cursor moved to (5, 10), one row changed, no preedit.

```
Offset  Hex                                       Description
──────  ───                                       ───────────
0000    49 54                                     magic "IT"
0002    01                                        version 1
0003    00                                        flags (no compression)
0004    00 03                                     type 0x0300 (FrameUpdate)
0006    00 00                                     reserved
0008    XX XX XX XX                               payload_len (varies)
000C    XX XX XX XX                               sequence

0010    01 00 00 00                               session_id = 1
0014    01 00 00 00                               pane_id = 1
0018    2A 00 00 00 00 00 00 00                   frame_sequence = 42
0020    01                                        dirty = partial
0021    00                                        screen = primary
0022    14 00                                     section_flags = 0x0014 (Cursor + DirtyRows)

        -- Cursor Section --
0024    05 00                                     cursor_x = 5
0026    0A 00                                     cursor_y = 10
0028    01                                        visible = true
0029    00                                        style = block
002A    01                                        blinking = true
002B    00                                        password_input = false

        -- DirtyRows Section --
002C    01 00                                     num_dirty_rows = 1

        -- Row 0 --
002E    0A 00                                     y = 10
0030    00                                        selection_flags = 0 (no selection, no RLE)
0031    04 00                                     selection_start (ignored)
0033    04 00                                     selection_end (ignored)
0035    05 00                                     num_cells = 5

        -- Cell 0: 'H' --
0037    48 00 00 00                               codepoint = 0x48 ('H')
003B    00                                        extra_count = 0
003C    00                                        wide = narrow
003D    00 00 00 00                               fg = default
0041    00 00 00 00                               bg = default
0045    00 00 00 00                               underline_color = default
0049    01 00                                     flags = bold

        -- Cell 1: 'e' --
004B    65 00 00 00                               codepoint = 0x65 ('e')
004F    00                                        extra_count = 0
0050    00                                        wide = narrow
0051    00 00 00 00                               fg = default
0055    00 00 00 00                               bg = default
0059    00 00 00 00                               underline_color = default
005D    01 00                                     flags = bold

        ... (cells 2-4 follow same pattern) ...
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
