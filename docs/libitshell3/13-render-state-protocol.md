# Render State Protocol: Server-Side Terminal, Client-Side Display

## The Architecture (Confirmed Feasible)

```
libitshell3 Server (macOS)              libitshell3 Client (macOS/iOS)
┌─────────────────────────┐             ┌──────────────────────────┐
│                         │             │                          │
│  PTY ← shell process    │             │  Raw key events ────────►│──┐
│   │                     │             │                          │  │
│   ▼                     │             │                          │  │
│  libghostty-vt Terminal │  rendered   │  Font subsystem          │  │
│   │ (VT parse, grid,    │  state      │  (SharedGrid, Atlas,     │  │
│   │  scrollback, modes) │ ─────────►  │   HarfBuzz shaping)      │  │
│   │                     │             │         │                │  │
│   ▼                     │             │         ▼                │  │
│  RenderState.update()   │             │  Metal GPU renderer      │  │
│   │ (cells, styles,     │             │  (CellText + CellBg      │  │
│   │  cursor, colors,    │             │   + Atlas textures)       │  │
│   │  dirty tracking)    │             │         │                │  │
│   │                     │             │         ▼                │  │
│  IME processing         │             │  Screen                  │  │
│  (NSTextInputContext)   │  preedit    │                          │  │
│   │                     │ ─────────►  │                          │  │
│   ▼                     │             │                          │  │
│  Preedit state          │             │                          │  │
│                         │             │                          │  │
└─────────────────────────┘             └──────────────────────────┘
         ▲ key events                              │
         └─────────────────────────────────────────┘
```

**Key principle**: The server IS the terminal emulator. The client is a remote keyboard + GPU display.

---

## Server Side: What RenderState Provides

libghostty-vt's `RenderState` (in `terminal/render.zig`) was **explicitly designed** for this use case. The source code comment says:

> *"Developer note: this is in src/terminal and not src/renderer because the goal is that this remains generic to multiple renderers. This can aid specifically with libghostty-vt with converting terminal state to a renderable form."*

### RenderState Structure

```
RenderState
├── rows: u16                          // viewport height
├── cols: u16                          // viewport width
├── screen: .primary | .alternate      // which screen buffer
├── dirty: .false | .partial | .full   // what changed
├── colors: Colors
│   ├── background: RGB                // terminal default bg
│   ├── foreground: RGB                // terminal default fg
│   ├── cursor: ?RGB                   // cursor color
│   └── palette: [256]RGB             // full 256-color palette
├── cursor: Cursor
│   ├── x, y                           // viewport position
│   ├── visible, blinking              // visibility
│   ├── visual_style: block|bar|underline
│   ├── password_input: bool           // password mode detected
│   └── style: Style                   // resolved style at cursor
└── row_data: [rows]Row
    ├── dirty: bool                    // did this row change?
    ├── selection: ?[start_x, end_x]   // selection highlight range
    └── cells: [cols]Cell
        ├── raw: page.Cell             // 8 bytes packed:
        │   ├── codepoint: u21
        │   ├── wide: narrow|wide|spacer_tail|spacer_head
        │   ├── content_tag: codepoint|codepoint_grapheme|bg_color_*
        │   └── style_id: u16
        ├── grapheme: []u21            // extra codepoints (multi-codepoint clusters)
        └── style: Style (RESOLVED)    // no lookup needed
            ├── fg_color: none|palette(u8)|rgb(r,g,b)
            ├── bg_color: none|palette(u8)|rgb(r,g,b)
            ├── underline_color: none|palette(u8)|rgb(r,g,b)
            └── flags: bold|italic|faint|blink|inverse|invisible|
                       strikethrough|overline|underline(none|single|double|curly|dotted|dashed)
```

### Dirty Tracking (Built-in Delta Support)

`RenderState` tracks what changed:
- `dirty == .false`: Nothing changed. Client can skip update.
- `dirty == .partial`: Some rows changed. Each `row.dirty` flag indicates which.
- `dirty == .full`: Everything changed (resize, screen switch, etc.).

This means the server can send **only changed rows** for most updates. A typical keystroke changes 1-2 rows.

---

## Wire Protocol: Render State Messages

### Frame Update Message

```
FrameUpdate {
    // Header
    session_id: u32,
    pane_id: u32,
    sequence: u64,              // monotonic frame counter
    dirty: u8,                  // 0=none, 1=partial, 2=full

    // Terminal dimensions (only on full update)
    cols: u16,
    rows: u16,

    // Colors (only on full update or color change)
    fg: RGB,                    // default foreground
    bg: RGB,                    // default background
    cursor_color: ?RGB,
    palette: ?[256]RGB,         // only if palette changed

    // Cursor
    cursor_x: u16,
    cursor_y: u16,
    cursor_visible: bool,
    cursor_style: u8,           // 0=block, 1=bar, 2=underline
    cursor_blinking: bool,
    password_input: bool,

    // Preedit (IME composition state)
    preedit_active: bool,
    preedit_text: []u8,         // UTF-8
    preedit_cursor_x: u16,
    preedit_cursor_y: u16,

    // Changed rows
    num_dirty_rows: u16,
    dirty_rows: []{
        y: u16,                 // row index
        selection_start: ?u16,  // selection highlight
        selection_end: ?u16,
        cells: [cols]CellData,
    },
}

CellData {
    codepoint: u21,             // primary codepoint (0 = empty)
    extra_codepoints: []u21,    // grapheme cluster extensions (usually empty)
    wide: u2,                   // 0=narrow, 1=wide, 2=spacer_tail, 3=spacer_head
    fg: PackedColor,            // 4 bytes: tag(1) + data(3)
    bg: PackedColor,
    underline_color: PackedColor,
    flags: u16,                 // bold|italic|faint|blink|inverse|invisible|
                                // strikethrough|overline|underline_style(3 bits)
}

PackedColor {                   // 4 bytes total
    tag: u8,                    // 0=default, 1=palette, 2=rgb
    data: [3]u8,                // palette: [index, 0, 0] | rgb: [r, g, b]
}
```

### Data Size Estimates

| Scenario | Size | Notes |
|----------|------|-------|
| Full frame (80×24, all styled) | ~35 KB | Every cell has unique style (worst case) |
| Full frame (80×24, typical) | ~8 KB | Most cells default-styled, pack efficiently |
| Partial update (2 rows changed) | ~600 B | Header + 2 rows of cell data |
| Cursor-only move | ~50 B | Header with cursor fields, no dirty rows |
| Preedit update | ~100 B | Header + preedit text + cursor |

At 60 updates/second worst case: ~480 KB/s (well within Unix socket bandwidth). Typical: ~10 KB/s.

---

## Client Side: Rendering Without a Terminal

### What the Client Does NOT Have

- No VT parser
- No Terminal state machine
- No Screen/Page/PageList
- No PTY
- No IME

### What the Client DOES Have

The client uses libghostty's **font subsystem** (which is fully independent of Terminal):

```
Client Rendering Pipeline:

1. Receive FrameUpdate from server
       │
2. For each CellData:
       │
       ▼
3. Font Resolution
   SharedGrid.getIndex(codepoint, style) → font_index
   (SharedGrid, CodepointResolver, Collection — all terminal-independent)
       │
       ▼
4. Glyph Rasterization
   SharedGrid.renderGlyph(font_index, glyph_index) → Glyph
   (CoreText renders glyph bitmap into Atlas texture)
       │
       ▼
5. GPU Data Assembly
   Build CellText { glyph_pos, glyph_size, bearings, grid_pos, color, atlas }
   Build CellBg   { rgba per cell }
       │
       ▼
6. Metal Rendering
   Upload Atlas textures + CellText buffer + CellBg buffer + Uniforms
   Draw background pass → Draw text pass
   (Can reuse ghostty's Metal shaders directly)
```

### Font Subsystem Independence (Verified)

These ghostty components have **zero terminal dependency**:

| Component | File | What It Does |
|-----------|------|-------------|
| `SharedGrid` | `font/SharedGrid.zig` | Codepoint → font → glyph → atlas. Fully standalone. |
| `CodepointResolver` | `font/CodepointResolver.zig` | Maps codepoints to font faces with fallback. |
| `Collection` | `font/Collection.zig` | Font face collection by style (regular/bold/italic). |
| `Atlas` | `font/Atlas.zig` | Texture atlas with bin-packing. CPU-side. |
| `Face` (CoreText) | `font/face/coretext.zig` | CoreText/CoreGraphics glyph rasterization. |

### Metal Shader Reuse

Ghostty's Metal shaders (`shaders.metal`) are self-contained. They expect:
- `CellText` instances (32 bytes each: atlas coords, bearings, grid pos, color)
- `CellBg` array (4 bytes per cell: RGBA)
- `Uniforms` buffer (projection matrix, cell/grid sizes, padding, colors)

These structs have no terminal dependency. The client can construct them from server-provided cell data + locally rasterized glyphs.

---

## Alternative: VT Re-serialization (Simpler but Redundant)

libghostty-vt also has a `TerminalFormatter` that can serialize the full terminal state as VT escape sequences:

```zig
var formatter: TerminalFormatter = .init(&terminal, .vt);
formatter.extra = .all;
try formatter.format(&writer);
// Produces: \x1b[0m\x1b[1;32mGreen bold text\x1b[0m\r\n...
```

The client could feed this VT stream into a local libghostty Terminal for rendering. This would be:

```
Server: PTY → Terminal (VT parse) → TerminalFormatter (VT serialize) → wire
Client: wire → Terminal (VT parse again) → Renderer
```

**Pros**: Simpler client (just create a Terminal + Surface, feed bytes)
**Cons**: Redundant parse→serialize→parse cycle, no dirty tracking, larger payload

**Verdict**: Not recommended as the primary approach, but useful for debugging and as a fallback.

---

## Scrollback Handling

The server holds the full scrollback in its PageList. The client displays only the viewport (rows × cols). Scrollback access:

| Action | Protocol |
|--------|----------|
| Client scrolls up | `ScrollRequest { pane_id, direction: up, lines: N }` |
| Server responds | `FrameUpdate` with `dirty: full`, showing the scrolled viewport |
| Client scrolls to bottom | `ScrollRequest { direction: bottom }` |
| Search in scrollback | `SearchRequest { pane_id, query, direction }` → `SearchResult { matches, viewport_update }` |

The client never holds scrollback data. It always requests from the server.

---

## Preedit Rendering

Preedit (IME composition) is NOT part of libghostty-vt's Terminal — it lives in the renderer/surface layer. In the server-side IME architecture:

1. Server receives raw key event from client
2. Server feeds it through `NSTextInputContext.interpretKeyEvents:`
3. `setMarkedText:` callback fires → server captures preedit text
4. Server sends preedit state in `FrameUpdate` message
5. Client renders preedit overlay at the specified cursor position

The preedit rendering on the client is simple: draw the preedit text (with underline) at `(preedit_cursor_x, preedit_cursor_y)`, overlaying the terminal grid. This is independent of the cell rendering pipeline.

---

## Summary: Why This Works

| Question | Answer |
|----------|--------|
| Can libghostty-vt run without GPU? | **Yes** — Terminal, Screen, Page, RenderState are all CPU-only |
| Does RenderState provide enough data? | **Yes** — fully resolved styles, graphemes, cursor, dirty tracking |
| Can the font subsystem work without Terminal? | **Yes** — SharedGrid, Atlas, CodepointResolver are independent |
| Can Metal shaders be reused? | **Yes** — they consume simple flat structs (CellText, CellBg) |
| Is bandwidth acceptable? | **Yes** — ~8 KB typical frame, ~600 bytes partial, ~50 bytes cursor-only |
| Is preedit handled? | **Yes** — server tracks it separately, sends in FrameUpdate |
| Is dirty tracking built-in? | **Yes** — per-row dirty flags in RenderState |
