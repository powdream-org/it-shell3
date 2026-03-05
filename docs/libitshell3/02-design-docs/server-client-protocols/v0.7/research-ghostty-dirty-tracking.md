# Research: ghostty Dirty Tracking and Frame Generation

**Date**: 2026-03-05
**Researcher**: ghostty-expert
**Purpose**: Prior-art evidence for I-frame/P-frame design discussion (Issues 22-24)

## 1. Dirty Tracking Mechanism

ghostty implements a **three-level dirty tracking hierarchy**: Terminal-level, Page-level, and Row-level. There is no per-cell dirty tracking.

### 1.1 Row-Level Dirty Flag

Each row carries a single `dirty: bool` flag within the `Row` packed struct.

**File**: `src/terminal/page.zig`, lines 1866-1932

```zig
pub const Row = packed struct(u64) {
    cells: Offset(Cell),
    wrap: bool = false,
    wrap_continuation: bool = false,
    grapheme: bool = false,
    styled: bool = false,
    hyperlink: bool = false,
    semantic_prompt: SemanticPrompt = .none,
    kitty_virtual_placeholder: bool = false,
    dirty: bool = false,
    _padding: u23 = 0,
    // ...
};
```

The `Row` struct is exactly 64 bits (8 bytes). The `dirty` flag is one bit within this packed struct. The doc comment states:

> "Dirty tracking may have false positives but should never have false negatives. A false negative would result in a visual artifact on the screen."

### 1.2 Page-Level Dirty Flag

Each page carries its own `dirty: bool` flag used for bulk operations that dirty all rows in a page at once.

**File**: `src/terminal/page.zig`, lines 110-117

```zig
/// Set to true when an operation is performed that dirties all rows in
/// the page. See `Row.dirty` for more information on dirty tracking.
///
/// NOTE: A value of false does NOT indicate that
///       the page has no dirty rows in it, only
///       that no full-page-dirtying operations
///       have occurred since it was last cleared.
dirty: bool,
```

The `Page.isDirty()` method checks both levels:

```zig
pub inline fn isDirty(self: *const Page) bool {
    if (self.dirty) return true;
    for (self.rows.ptr(self.memory)[0..self.size.rows]) |row| {
        if (row.dirty) return true;
    }
    return false;
}
```

### 1.3 Terminal-Level and Screen-Level Dirty Flags

At the highest level, two packed structs track "global" dirty conditions.

**File**: `src/terminal/Terminal.zig`, lines 152-165

```zig
pub const Dirty = packed struct {
    palette: bool = false,       // Color palette modified
    reverse_colors: bool = false, // Reverse colors mode toggled
    clear: bool = false,         // Screen clear / erase display
    preedit: bool = false,       // Pre-edit state changed
};
```

**File**: `src/terminal/Screen.zig`, lines 84-92

```zig
pub const Dirty = packed struct {
    selection: bool = false,       // Selection set or unset
    hyperlink_hover: bool = false, // OSC8 hyperlink hover state change
};
```

These are checked as packed integers (cast to backing int and compared to zero) for fast path optimization in the RenderState update.

### 1.4 How Dirty Flags Are Set

Row-level dirty is set by `Screen.cursorMarkDirty()`:

**File**: `src/terminal/Screen.zig`, lines 1206-1209

```zig
pub inline fn cursorMarkDirty(self: *Screen) void {
    self.cursor.page_row.dirty = true;
}
```

This is called before each cell write. For example, in `Terminal.print()` (lines 611, 645, 652):

```zig
// Single cell width:
self.screens.active.cursorMarkDirty();
@call(.always_inline, printCell, .{ self, c, .narrow });

// Wide character:
self.screens.active.cursorMarkDirty();
self.printCell(c, .wide);
```

Page-level dirty is set for bulk operations such as scroll, insert/delete lines, and erase display. For example, in `Screen.zig` line 953:

```zig
// Technically we only need to mark from the cursor row to the
// end but this is a hot function, so we want to minimize work.
page.dirty = true;
```

### 1.5 How Dirty Flags Are Cleared

Dirty flags are consumed and cleared by `RenderState.update()`. The clearing happens at multiple points:

- **Row dirty**: Cleared immediately when the row is processed: `page_rac.row.dirty = false` (render.zig line 460)
- **Page dirty**: Cleared after all rows are iterated: `last_dirty_page.dirty = false` (render.zig line 643)
- **Terminal dirty**: Cleared at the end of `update()`: `t.flags.dirty = .{}` (render.zig line 646)
- **Screen dirty**: Cleared at the end of `update()`: `s.dirty = .{}` (render.zig line 647)

### 1.6 Summary: No Cell-Level Dirty Tracking

ghostty does NOT track dirty at cell granularity. When any cell in a row changes, the entire row is marked dirty via `page_row.dirty = true`. There is no bitmask of dirty cells within a row.

## 2. Full Redraw vs Partial Redraw

ghostty has a clear distinction between full and partial redraw, expressed through the `RenderState.Dirty` enum.

### 2.1 The Dirty Enum

**File**: `src/terminal/render.zig`, lines 226-238

```zig
pub const Dirty = enum {
    /// Not dirty at all. Can skip rendering if prior state was
    /// already rendered.
    false,

    /// Partially dirty. Some rows changed but not all. None of the
    /// global state changed such as colors.
    partial,

    /// Fully dirty. Global state changed or dimensions changed. All rows
    /// should be redrawn.
    full,
};
```

### 2.2 What Triggers Full Redraw

In `RenderState.update()` (render.zig lines 269-303), a full redraw (`redraw = true`) is triggered by any of:

1. **Screen key change** (primary to alternate or vice versa)
2. **Terminal dirty flags** (palette, reverse_colors, clear, preedit)
3. **Screen dirty flags** (selection, hyperlink_hover)
4. **Dimension change** (rows or cols differ)
5. **Viewport pin change** (scroll position changed)

When `redraw` is true, the final dirty state is set to `.full` (line 634).

### 2.3 What Triggers Partial Redraw

When `redraw` is false, individual rows are checked for dirty status through a cascade:

**File**: `src/terminal/render.zig`, lines 433-453

```zig
dirty: {
    if (redraw) break :dirty;
    if (p == last_dirty_page) break :dirty;
    if (p.dirty) {
        if (last_dirty_page) |last_p| last_p.dirty = false;
        last_dirty_page = p;
        break :dirty;
    }
    if (page_rac.row.dirty) break :dirty;
    // Not dirty!
    continue;
}
```

If any row is dirty but no global state changed, the result is `.partial` (line 639).

### 2.4 How the Renderer Uses These States

In `generic.zig` `rebuildCells()` (lines 2338-2425):

```zig
const rebuild = state.dirty == .full or grid_size_diff;
if (rebuild) {
    // Full rebuild: clear entire cell buffer
    self.cells.reset();
    // ...
}

for (...) |y_usize, row, *cells, *dirty, selection, *highlights| {
    if (!rebuild) {
        // Partial: only rebuild dirty rows
        if (!dirty.*) continue;
        self.cells.clear(y);
    }
    dirty.* = false;
    self.rebuildRow(...);
}
```

On a `.full` dirty, ALL rows are rebuilt. On `.partial`, only rows where `dirty == true` are cleared and rebuilt. On `.false`, the loop still runs but every row is skipped.

### 2.5 Periodic Full Redraws (Keyframe Analog)

ghostty has a mechanism analogous to periodic keyframes. Every 100,000 frames, the renderer fully deinitializes and resets the terminal state:

**File**: `src/renderer/generic.zig`, lines 1143-1148

```zig
const max_terminal_state_frame_count = 100_000;
if (self.terminal_state_frame_count >= max_terminal_state_frame_count) {
    self.terminal_state.deinit(self.alloc);
    self.terminal_state = .empty;
}
self.terminal_state_frame_count += 1;
```

At 120 FPS, this is approximately every 12 minutes. The purpose is to prevent unbounded memory retention from a single large frame. When `terminal_state` is reset to `.empty`, the next `update()` call will trigger a full redraw because the dimensions will mismatch (`self.rows != s.pages.rows`).

Additionally, `markDirty()` can force a full redraw at any time:

```zig
pub inline fn markDirty(self: *Self) void {
    self.terminal_state.dirty = .full;
}
```

## 3. VT Output to Render Frame Pipeline

### 3.1 Architecture Overview

ghostty uses a multi-threaded architecture with three key threads:

1. **IO thread** (`src/termio/Thread.zig`): Reads from PTY, feeds VT parser, modifies terminal state
2. **Renderer thread** (`src/renderer/Thread.zig`): Reads terminal state, builds GPU data, triggers draws
3. **App/UI thread**: Handles window system events (on macOS, this is the main thread)

### 3.2 State Sharing and Synchronization

The IO thread and renderer thread share the terminal state through `renderer.State` which wraps a `*Terminal` behind a mutex:

**File**: `src/renderer/State.zig`, lines 10-17

```zig
/// The mutex that must be held while reading any of the data in the
/// members of this state. Note that the state itself is NOT protected
/// by the mutex and is NOT thread-safe, only the members values of the
/// state (i.e. the terminal, devmode, etc. values).
mutex: *std.Thread.Mutex,
terminal: *terminalpkg.Terminal,
```

The IO thread holds this mutex while processing VT data. The renderer acquires it briefly during `updateFrame()` to snapshot the terminal state into its local `RenderState`.

### 3.3 Event-Driven Rendering (Not Timer-Based)

The renderer does NOT poll on a timer for terminal changes. Instead, it uses an **async wakeup** mechanism. When the IO thread finishes processing a batch of VT data, it signals the renderer:

**File**: `src/termio/stream_handler.zig`, lines 101-106

```zig
pub inline fn queueRender(self: *StreamHandler) !void {
    try self.renderer_wakeup.notify();
}
```

**File**: `src/termio/Thread.zig`, lines 357-361

```zig
// Trigger a redraw after we've drained so we don't waste cycles
// messaging a redraw.
if (redraw) {
    try io.renderer_wakeup.notify();
}
```

### 3.4 Wakeup Handling and Coalescing

When the renderer thread receives a wakeup, it immediately performs both `updateFrame` and `drawFrame`:

**File**: `src/renderer/Thread.zig`, lines 513-552

```zig
fn wakeupCallback(...) xev.CallbackAction {
    // Drain the mailbox
    t.drainMailbox() catch |err| ...;

    // Render immediately
    _ = renderCallback(t, undefined, undefined, {});

    return .rearm;
}
```

The `renderCallback` calls `updateFrame` then `drawFrame`:

```zig
fn renderCallback(...) xev.CallbackAction {
    t.renderer.updateFrame(t.state, t.flags.cursor_blink_visible) catch |err| ...;
    t.drawFrame(false);
    return .disarm;
}
```

There is commented-out code showing a **previous timer-based coalescing** design that was abandoned:

```zig
// The below is not used anymore but if we ever want to introduce
// a configuration to introduce a delay to coalesce renders, we can
// use this.
//
// // If the timer is already active then we don't have to do anything.
// if (t.render_c.state() == .active) return .rearm;
//
// // Timer is not active, let's start it
// t.render_h.run(&t.loop, &t.render_c, 10, Thread, t, renderCallback);
```

Natural coalescing still occurs because `xev.Async.notify()` is idempotent -- multiple rapid notifications result in a single wakeup callback.

### 3.5 Draw Timer (Separate from Render)

There is a separate draw timer at 8ms intervals (120 FPS) used **only for animations** (custom shaders). This timer calls `drawFrame` but NOT `updateFrame`, meaning it redraws the same GPU data without re-reading terminal state:

**File**: `src/renderer/Thread.zig`, lines 19, 572-594

```zig
const DRAW_INTERVAL = 8; // 120 FPS

fn drawCallback(...) xev.CallbackAction {
    t.drawFrame(false);
    if (t.draw_active) {
        t.draw_h.run(&t.loop, &t.draw_c, DRAW_INTERVAL, Thread, t, drawCallback);
    }
    return .disarm;
}
```

The draw timer is only active when `hasAnimations()` returns true and focus conditions are met.

### 3.6 Display Link (macOS vsync)

On macOS, ghostty uses `CVDisplayLink` for vsync-synchronized drawing. When active, the display link fires `draw_now` callbacks aligned to the display refresh rate, which trigger `drawFrame(true)`. The render thread checks `hasVsync()` and only draws via display link when it is running:

**File**: `src/renderer/generic.zig`, lines 1020-1024

```zig
pub fn hasVsync(self: *const Self) bool {
    if (comptime DisplayLink == void) return false;
    const display_link = self.display_link orelse return false;
    return display_link.isRunning();
}
```

The display link is stopped when the terminal loses focus and restarted when it regains focus (generic.zig lines 1037-1047).

### 3.7 Synchronized Output Mode

ghostty supports DEC Private Mode 2026 (synchronized output). When active, `updateFrame()` returns immediately without reading terminal state:

```zig
if (state.terminal.modes.get(.synchronized_output)) {
    log.debug("synchronized output started, skipping render", .{});
    return;
}
```

This is the VT-level mechanism for batching output. The mode is reset either by the application or by a safety timer after a timeout.

## 4. Screen State Authority

### 4.1 Terminal as Single Source of Truth

The `Terminal` struct is the authoritative owner of all screen state. It contains a `ScreenSet` which holds both primary and alternate screens:

**File**: `src/terminal/Terminal.zig`

The `Terminal` contains `screens: ScreenSet` and the active screen is accessed via `t.screens.active`.

### 4.2 Screen Contains Pages

Each `Screen` contains a `PageList` which is a linked list of `Page` objects. Each `Page` holds a contiguous block of rows and cells in a single allocation, using offset-based addressing.

**File**: `src/terminal/page.zig`, lines 100-108

```zig
rows: Offset(Row),
cells: Offset(Cell),
```

Rows and cells are stored within the page's memory allocation and accessed via offset arithmetic. This is a custom arena-style allocator where the entire page (rows, cells, styles, graphemes, hyperlinks) lives in a single contiguous allocation.

### 4.3 RenderState as Renderer-Local Snapshot

The `RenderState` (in `src/terminal/render.zig`) is NOT the authoritative state. It is a **renderer-local snapshot** that is incrementally updated from the authoritative `Terminal` state on each frame.

**File**: `src/terminal/render.zig`, lines 24-47

```
/// Contains the state required to render the screen, including optimizing
/// for repeated render calls and only rendering dirty regions.
///
/// Previously, our renderer would use `clone` to clone the screen within
/// the viewport to perform rendering. This worked well enough that we kept
/// it all the way up through the Ghostty 1.2.x series, but the clone time
/// was repeatedly a bottleneck blocking IO.
///
/// Rather than a generic clone that tries to clone all screen state per call
/// (within a region), a stateful approach that optimizes for only what a
/// renderer needs to do makes more sense.
```

This comment explicitly describes the evolution from full-clone (I-frame equivalent) to incremental update (P-frame equivalent).

### 4.4 Mutex Protocol

The IO thread holds `renderer.State.mutex` while modifying the terminal. The renderer acquires the same mutex briefly during `updateFrame()` to read terminal state into its local `RenderState`. The renderer releases the mutex as quickly as possible to minimize IO blocking. All GPU buffer manipulation happens AFTER the mutex is released.

## 5. Cell Data Structure

### 5.1 Terminal Cell (`page.Cell`)

The authoritative cell representation is `page.Cell`, a 64-bit packed struct:

**File**: `src/terminal/page.zig`, lines 1958-2002

```zig
pub const Cell = packed struct(u64) {
    content_tag: ContentTag = .codepoint,    // 2 bits
    content: packed union {
        codepoint: u21,                       // 21 bits (primary codepoint)
        color_palette: u8,                    // 8 bits (bg color index)
        color_rgb: RGB,                       // 24 bits (bg color RGB)
    } = .{ .codepoint = 0 },
    style_id: StyleId = 0,                   // 16 bits (u16, index into style table)
    wide: Wide = .narrow,                     // 2 bits
    protected: bool = false,                  // 1 bit
    hyperlink: bool = false,                  // 1 bit
    semantic_content: SemanticContent = .output, // 2 bits
    _padding: u16 = 0,                       // 16 bits
};
```

Total: exactly 64 bits (8 bytes). The zero value is a valid empty cell.

### 5.2 Content Tag Variants

```zig
pub const ContentTag = enum(u2) {
    codepoint = 0,           // Single codepoint cell
    codepoint_grapheme = 1,  // Multi-codepoint grapheme cluster
    bg_color_palette = 2,    // Background-only cell (palette color)
    bg_color_rgb = 3,        // Background-only cell (RGB color)
};
```

When `content_tag == .codepoint_grapheme`, additional codepoints are stored in a separate `grapheme_alloc` within the page. This indirection keeps the common case (single codepoint) at exactly 8 bytes.

### 5.3 Wide Character (CJK) Representation

```zig
pub const Wide = enum(u2) {
    narrow = 0,         // Normal 1-cell width
    wide = 1,           // Wide character, occupies 2 cells
    spacer_tail = 2,    // Right half of wide character (do not render)
    spacer_head = 3,    // End-of-line spacer before wide char wraps
};
```

A CJK character occupies two adjacent cells:
- The first cell has `wide = .wide` and contains the codepoint
- The second cell has `wide = .spacer_tail` with codepoint 0

The `spacer_head` variant handles the special case where a wide character at the end of a line wraps to the next line -- the last cell of the row is marked `spacer_head` and the actual character appears at the start of the next row.

### 5.4 Style Storage

Styles are NOT stored inline in cells. Each cell carries a 16-bit `style_id` that indexes into a per-page `StyleSet` (a reference-counted set). The `Style` struct itself is:

**File**: `src/terminal/style.zig`, lines 20-41

```zig
pub const Style = struct {
    fg_color: Color = .none,
    bg_color: Color = .none,
    underline_color: Color = .none,
    flags: Flags = .{},

    const Flags = packed struct(u16) {
        bold: bool = false,
        italic: bool = false,
        faint: bool = false,
        blink: bool = false,
        inverse: bool = false,
        invisible: bool = false,
        strikethrough: bool = false,
        overline: bool = false,
        underline: sgr.Attribute.Underline = .none,
        _padding: u5 = 0,
    };
};
```

The `Style.Color` is a tagged union of `none`, `palette(u8)`, or `rgb(RGB)`.

### 5.5 RenderState Cell

The renderer's copy of cell data is a separate struct that bundles the raw cell with resolved style and grapheme data:

**File**: `src/terminal/render.zig`, lines 209-223

```zig
pub const Cell = struct {
    raw: page.Cell,             // 8 bytes, copied from page
    grapheme: []const u21,      // Extra codepoints (only valid for grapheme cells)
    style: Style,               // Resolved style (only valid for styled cells)
};
```

This is stored in a `MultiArrayList(Cell)` for cache-friendly access to individual fields across rows.

### 5.6 GPU Cell Structures

The GPU has its own distinct cell types that differ significantly from the terminal cell:

**File**: `src/renderer/cell.zig`, lines 12-31

```zig
pub const Key = enum {
    bg,               // Background color cells
    text,             // Text/glyph cells
    underline,        // Underline decoration cells
    strikethrough,    // Strikethrough decoration cells
    overline,         // Overline decoration cells
};
```

Background cells (`CellBg`) are a flat array indexed by `[row * cols + col]`. Foreground cells (`CellText`) are stored in per-row `ArrayListCollection` entries (row index offset by 1 for cursor). The GPU cell types are defined in shader-specific code (Metal/OpenGL) and include fields like `atlas`, `grid_pos`, `color`, glyph coordinates, etc.

## Summary

### Key Patterns Relevant to I-frame/P-frame Discussion

1. **ghostty already implements a P-frame model internally**. The `RenderState` acts as a "decoder ring" -- it maintains persistent state that is incrementally updated via dirty tracking. The transition from `Screen.clone()` (full-copy per frame, equivalent to I-frames) to `RenderState.update()` (incremental, equivalent to P-frames) was a deliberate performance optimization documented in code comments.

2. **Three-tier dirty hierarchy**. Row-level dirty flags (1 bit per row) are the primary mechanism. Page-level flags accelerate bulk operations. Terminal/Screen-level flags trigger full redraws when global state changes (palette, selection, dimensions, viewport scroll). There is NO per-cell dirty tracking.

3. **Full redraw is triggered by global state changes, not by a timer**. Dimensional changes, screen switches, palette changes, viewport scroll, and selection changes all cause full redraws. This is analogous to forced I-frames on state discontinuity.

4. **Periodic state reset exists**. Every 100,000 frames (~12 minutes at 120 FPS), the `RenderState` is fully deinitialized and rebuilt from scratch. This prevents memory retention issues but also serves as a periodic "keyframe." This is a safety mechanism, not a correctness requirement.

5. **Rendering is event-driven with natural coalescing**. The IO thread signals the renderer via `xev.Async.notify()`, which is idempotent. Multiple VT events between render frames are naturally coalesced into a single `updateFrame()` call. There is no fixed-FPS timer for content updates.

6. **Synchronized output (DEC 2026) is the VT-level batching mechanism**. When active, `updateFrame()` returns immediately, deferring all rendering until the mode is disabled.

7. **Cell data is compact but style-indirect**. The 8-byte `page.Cell` stores codepoint + width + style_id. Styles are looked up from a per-page table. Graphemes beyond the first codepoint are stored in a separate allocator. This indirection means a "CellData" wire format must decide whether to inline resolved styles or send style IDs with a separate style table.

8. **Wide character tracking is per-cell, not per-codepoint**. The `Wide` enum on each cell explicitly marks wide characters and their spacer tails. Any wire protocol must preserve this two-cell structure for CJK characters.

### Files Examined

| File | Lines Read | Content |
|------|-----------|---------|
| `src/terminal/page.zig` | 100-150, 1620-1640, 1850-2100 | Page struct, Row packed struct, Cell packed struct, dirty flags |
| `src/terminal/render.zig` | 1-880 (full) | RenderState struct, Dirty enum, update() method, row iteration |
| `src/terminal/Terminal.zig` | 145-170, 302-668, 670-840 | Terminal.Dirty, print(), printCell(), cursorMarkDirty() calls |
| `src/terminal/Screen.zig` | 80-92, 788-953, 1206-1210, 1350-1355 | Screen.Dirty, dirty flag setters, cursorMarkDirty() |
| `src/terminal/style.zig` | 1-100 | Style struct, Color union, Id type |
| `src/terminal/size.zig` | 12-50 | CellCountInt (u16), StyleCountInt, Offset type |
| `src/renderer/State.zig` | 1-123 (full) | Renderer state wrapper, Preedit struct, mutex documentation |
| `src/renderer/Thread.zig` | 1-715 (full) | Render thread, wakeup/draw/render callbacks, timer intervals |
| `src/renderer/generic.zig` | 1-200, 980-1050, 1123-1530, 2307-2510 | Renderer impl, updateFrame, drawFrame, rebuildCells |
| `src/renderer/cell.zig` | 1-680 (full) | GPU cell Contents struct, Key enum, row-wise clear |
| `src/termio/stream_handler.zig` | 95-174 | queueRender(), renderer_wakeup.notify() |
| `src/termio/Thread.zig` | 340-380 | IO thread render wakeup after drain |
| `src/termio/Termio.zig` | 500-580 | Resize wakeup, synchronized output reset |
