# Research Report: ghostty Dirty Tracking and Frame Generation

> **Date**: 2026-03-05
> **Researcher**: ghostty-expert
> **Scope**: How ghostty tracks dirty state and generates render frames internally
> **Purpose**: Evidence for Issues 22-24 (I-frame/P-frame model, shared ring buffer, P-frame diff base)

---

## 1. Dirty Tracking Architecture

ghostty uses a **three-level dirty tracking system**: terminal-level flags, page-level flags, and row-level flags. There is no cell-level dirty tracking.

### 1.1 Row-Level Dirty Bit

Each row carries a single boolean dirty flag.

**File**: `src/terminal/page.zig:1866-1930`

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
    dirty: bool = false,     // <-- row dirty flag
    _padding: u23 = 0,
};
```

The `Row` struct is a packed 64-bit integer. The `dirty` flag occupies a single bit. The documentation at lines 1919-1929 states:

- Set to `true` by any operation that modifies the row's contents or position.
- Consumers are expected to clear it after redraw.
- **May have false positives but never false negatives.** A false negative would cause a visual artifact.
- Only tracks visual changes — non-visual changes (e.g., internal metadata) may not set dirty.

Dirty is set at numerous points throughout the terminal engine:
- `Screen.cursorMarkDirty()` — marks the cursor's current row dirty (`src/terminal/Screen.zig:1208-1209`)
- Every character write via `Terminal.print()` marks the current row dirty (`src/terminal/Terminal.zig:1978-1979`)
- Scroll operations mark moved rows dirty (`src/terminal/Screen.zig:1353`)
- Erase operations mark affected rows dirty

### 1.2 Page-Level Dirty Flag

Each page (a memory region holding multiple rows) has a separate dirty boolean.

**File**: `src/terminal/page.zig:110-117`

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

The page dirty flag is an **optimization hint**, not a complete tracker. When `page.dirty` is true, the consumer can assume all rows in that page are dirty without checking individual row flags. When false, individual rows must still be checked.

Page dirty is set on bulk operations like `Screen.eraseRows()` (`src/terminal/Screen.zig:949-953, 1018-1019, 1034-1038`).

**Page dirty check** (`src/terminal/page.zig:1631-1638`):

```zig
pub inline fn isDirty(self: *const Page) bool {
    if (self.dirty) return true;
    for (self.rows.ptr(self.memory)[0..self.size.rows]) |row| {
        if (row.dirty) return true;
    }
    return false;
}
```

### 1.3 Terminal-Level Dirty Flags

The Terminal struct maintains a `Dirty` packed struct for global state changes that affect the entire display.

**File**: `src/terminal/Terminal.zig:146-165`

```zig
pub const Dirty = packed struct {
    palette: bool = false,        // Color palette modified
    reverse_colors: bool = false, // Reverse colors mode changed
    clear: bool = false,          // Screen clear / screen change
    preedit: bool = false,        // Pre-edit (IME) state modified
};
```

These flags represent terminal-wide state changes that require a full redraw (every row, not just visually-changed ones). For example, a palette change requires re-rendering all cells even though no individual row's content changed.

### 1.4 Screen-Level Dirty Flags

The Screen struct has its own `Dirty` flags independent of the terminal flags.

**File**: `src/terminal/Screen.zig:80-92`

```zig
pub const Dirty = packed struct {
    selection: bool = false,       // Selection set/unset
    hyperlink_hover: bool = false, // OSC8 hyperlink hover changed
};
```

---

## 2. RenderState: The Snapshot Mechanism

ghostty's renderer does **not** read terminal state directly during draw calls. Instead, it maintains a **renderer-local snapshot** called `RenderState` that is updated from the terminal state under a mutex.

**File**: `src/terminal/render.zig:24-47`

The comment explains the design rationale:

> Previously, our renderer would use `clone` to clone the screen within the viewport to perform rendering. This worked well enough [...] but the clone time was repeatedly a bottleneck blocking IO.

The `RenderState` is a stateful cache that optimizes for only what the renderer needs:

```zig
pub const RenderState = struct {
    rows: size.CellCountInt,
    cols: size.CellCountInt,
    colors: Colors,
    cursor: Cursor,
    row_data: std.MultiArrayList(Row),  // per-row snapshots
    dirty: Dirty,                        // overall dirty level
    screen: ScreenSet.Key,
    viewport_pin: ?PageList.Pin = null,
    selection_cache: ?SelectionCache = null,
};
```

### 2.1 RenderState.Dirty Enum (Three Levels)

**File**: `src/terminal/render.zig:225-238`

```zig
pub const Dirty = enum {
    false,    // Not dirty. Can skip rendering entirely.
    partial,  // Some rows changed but not all. Global state unchanged.
    full,     // Global state changed or dimensions changed. Full redraw.
};
```

This three-level dirty state is the key to ghostty's partial-vs-full redraw decision.

### 2.2 RenderState.Row

Each row in the render state has its own dirty flag, cell snapshot, and selection data.

**File**: `src/terminal/render.zig:170-198`

```zig
pub const Row = struct {
    arena: ArenaAllocator.State,     // per-row heap allocations
    pin: PageList.Pin,               // source pin in page list
    raw: page.Row,                   // raw row metadata
    cells: std.MultiArrayList(Cell), // cell data snapshot
    dirty: bool,                     // renderer-local dirty flag
    selection: ?[2]size.CellCountInt,
    highlights: std.ArrayList(Highlight),
};
```

### 2.3 RenderState.Cell

**File**: `src/terminal/render.zig:209-223`

```zig
pub const Cell = struct {
    raw: page.Cell,          // 64-bit packed cell (codepoint, style_id, wide, etc.)
    grapheme: []const u21,   // extra codepoints if multi-codepoint grapheme
    style: Style,            // resolved style (from style_id lookup)
};
```

---

## 3. The `update()` Method: Terminal State → RenderState

This is the core function that converts mutable terminal state to a renderer-safe snapshot. It runs under the `state.mutex` lock.

**File**: `src/terminal/render.zig:258-648`

### 3.1 Full Redraw Detection

The method first determines whether a **full rebuild** is required (`redraw` flag):

```zig
const redraw = redraw: {
    // Screen key changed (e.g., primary <-> alternate)
    if (t.screens.active_key != self.screen) break :redraw true;

    // Terminal-level dirty flags (palette, reverse_colors, clear, preedit)
    {
        const Int = @typeInfo(Terminal.Dirty).@"struct".backing_integer.?;
        const v: Int = @bitCast(t.flags.dirty);
        if (v > 0) break :redraw true;
    }

    // Screen-level dirty flags (selection, hyperlink_hover)
    {
        const Int = @typeInfo(Screen.Dirty).@"struct".backing_integer.?;
        const v: Int = @bitCast(t.screens.active.dirty);
        if (v > 0) break :redraw true;
    }

    // Dimensions changed
    if (self.rows != s.pages.rows or self.cols != s.pages.cols) break :redraw true;

    // Viewport pin changed (user scrolled)
    if (self.viewport_pin) |old| {
        if (!old.eql(viewport_pin)) break :redraw true;
    }

    break :redraw false;
};
```

Any terminal-level or screen-level dirty flag set → full redraw. Dimension change → full redraw. Viewport scroll → full redraw.

### 3.2 Row-by-Row Dirty Check

When `redraw` is false (partial update), the method iterates viewport rows and checks dirty at three levels:

```zig
dirty: {
    if (redraw) break :dirty;                        // full redraw: always dirty
    if (p == last_dirty_page) break :dirty;          // page already known dirty
    if (p.dirty) {                                   // page-level dirty
        if (last_dirty_page) |last_p| last_p.dirty = false;
        last_dirty_page = p;
        break :dirty;
    }
    if (page_rac.row.dirty) break :dirty;            // row-level dirty
    continue;                                        // NOT dirty, skip row
}
```

For each dirty row, it:
1. Clears the row's dirty flag on the page (`page_rac.row.dirty = false`)
2. Resets the row's arena allocator (retaining capacity)
3. Copies raw cell data via `fastmem.copy`
4. Resolves managed memory (styles, graphemes) for cells that have them
5. Marks `row_dirties[y] = true` in the render state

### 3.3 Dirty Clearing

After the row iteration, the method clears all source dirty flags:

```zig
// Handle dirty state.
if (redraw) {
    self.screen = t.screens.active_key;
    self.dirty = .full;
} else if (any_dirty and self.dirty == .false) {
    self.dirty = .partial;
}

// Finalize our final dirty page
if (last_dirty_page) |last_p| last_p.dirty = false;

// Clear our dirty flags
t.flags.dirty = .{};
s.dirty = .{};
```

**Critical observation**: Dirty flags are **consumed** by `update()`. After the call, all terminal/screen/page/row dirty flags are cleared. This is a single-consumer model — there is exactly one renderer reading and clearing dirty state.

---

## 4. Frame Generation: updateFrame → rebuildCells → drawFrame

The renderer thread has a two-phase frame pipeline:

### 4.1 `updateFrame()` — State Synchronization (CPU)

**File**: `src/renderer/generic.zig:1122-1419`

This method:
1. Locks the `state.mutex` (shared with IO thread)
2. Checks `synchronized_output` mode — if active, skips the frame entirely
3. Calls `self.terminal_state.update(self.alloc, state.terminal)` to snapshot terminal state
4. Extracts preedit, scrollbar, mouse state, Kitty images, and OSC8 links
5. Unlocks the mutex (minimizing critical section time)
6. Calls `self.rebuildCells()` to convert the snapshot into GPU cell data

### 4.2 `rebuildCells()` — GPU Cell Generation (CPU)

**File**: `src/renderer/generic.zig:2307-2443`

This method distinguishes between full and partial rebuild:

```zig
const rebuild = state.dirty == .full or grid_size_diff;
if (rebuild) {
    self.cells.reset();  // Clear entire cell buffer
    // ... reset padding extension
}
```

Then iterates rows:

```zig
for (...) |y_usize, row, *cells, *dirty, selection, *highlights| {
    if (!rebuild) {
        if (!dirty.*) continue;     // Skip non-dirty rows
        self.cells.clear(y);        // Clear only this row's GPU cells
    }
    dirty.* = false;                // Clear render-state dirty
    self.rebuildRow(y, row, cells, ...);  // Generate GPU cells for row
}
```

**Observation**: The partial rebuild path skips non-dirty rows entirely, reading only dirty rows. Each row's GPU cells are independently generated.

### 4.3 `drawFrame()` — GPU Submission

**File**: `src/renderer/Thread.zig:492-511`

The actual GPU draw call. This is separate from `updateFrame()`:

```zig
fn drawFrame(self: *Thread, now: bool) void {
    if (!self.flags.visible) return;
    if (!now and self.renderer.hasVsync()) return;
    // ... submit draw call via renderer impl or app mailbox
}
```

---

## 5. Event-Driven Frame Scheduling

ghostty uses an **event-driven, wakeup-based** model for frame scheduling. There is no fixed FPS timer for normal rendering.

### 5.1 IO Thread → Renderer Wakeup

**File**: `src/termio/Termio.zig:687-689`

When PTY output arrives, the IO thread calls `processOutput()`, which:
1. Locks `renderer_state.mutex`
2. Calls `queueRender()` which does `self.renderer_wakeup.notify()` (an async wakeup)
3. Processes the VT byte stream into terminal state
4. Unlocks the mutex

The wakeup is sent **before** processing the data — the renderer is notified even while the IO thread is still processing.

### 5.2 Renderer Wakeup Handling

**File**: `src/renderer/Thread.zig:513-552`

```zig
fn wakeupCallback(...) xev.CallbackAction {
    // Drain the mailbox
    t.drainMailbox() catch ...;
    // Render immediately
    _ = renderCallback(t, undefined, undefined, {});
    return .rearm;
}
```

On wakeup, the renderer immediately calls `renderCallback`, which calls `updateFrame()` + `drawFrame()`. There is **no coalescing timer** for normal renders — each wakeup triggers an immediate render.

However, the code contains a commented-out coalescing timer (lines 534-549):

```zig
// The below is not used anymore but if we ever want to introduce
// a configuration to introduce a delay to coalesce renders, we can
// use this.
//
// t.render_h.run(... 10, ... renderCallback);
```

This confirms ghostty previously considered a 10ms coalescing timer but removed it in favor of immediate rendering on wakeup.

### 5.3 Implicit Coalescing via Async Semantics

The `xev.Async` wakeup mechanism provides implicit coalescing: if multiple `notify()` calls happen between event loop iterations, only one wakeup callback fires. This means if the IO thread calls `processOutput()` multiple times in rapid succession (e.g., reading multiple buffers from the PTY), the renderer only wakes up once per event loop tick.

### 5.4 Draw Timer (Animations Only)

**File**: `src/renderer/Thread.zig:19`

```zig
const DRAW_INTERVAL = 8; // 120 FPS
```

The draw timer (`draw_h`) runs at 8ms intervals (120 FPS) but is **only active when custom shader animations are enabled** (`syncDrawTimer()` at line 295). Normal terminal rendering does not use this timer.

### 5.5 VSync / DisplayLink (macOS)

On macOS, when vsync is enabled, ghostty uses a `CVDisplayLink` to trigger draw calls at the display refresh rate:

```zig
fn displayLinkCallback(_: *macos.video.DisplayLink, ud: ?*xev.Async) void {
    const draw_now = ud orelse return;
    draw_now.notify() catch ...;
}
```

The DisplayLink triggers `draw_now` (which calls `drawFrame` directly, without `updateFrame`), while `updateFrame` is still triggered by the wakeup async. This separates state update frequency from draw frequency.

### 5.6 RenderState Periodic Reset

**File**: `src/renderer/generic.zig:1138-1148`

```zig
const max_terminal_state_frame_count = 100_000;
if (self.terminal_state_frame_count >= max_terminal_state_frame_count) {
    self.terminal_state.deinit(self.alloc);
    self.terminal_state = .empty;
}
self.terminal_state_frame_count += 1;
```

Every 100,000 frames (~12 minutes at 120Hz), the entire render state is destroyed and rebuilt from scratch. This prevents memory bloat from accumulated allocations (arenas retain peak capacity). When the state is reset, the next frame is effectively a full redraw since all rows must be re-populated.

---

## 6. Cell Data Layout

### 6.1 Terminal Cell (Source of Truth)

**File**: `src/terminal/page.zig:1958-2002`

```zig
pub const Cell = packed struct(u64) {
    content_tag: ContentTag = .codepoint,  // 2 bits
    content: packed union {                // 21 bits
        codepoint: u21,
        color_palette: u8,
        color_rgb: RGB,                    // 24 bits (r8, g8, b8)
    } = .{ .codepoint = 0 },
    style_id: StyleId = 0,                 // via ref-counted style set
    wide: Wide = .narrow,                  // 2 bits
    protected: bool = false,
    hyperlink: bool = false,
    semantic_content: SemanticContent = .output, // 2 bits
    _padding: u16 = 0,
};
```

Total: 64 bits (8 bytes) per cell. Styles are indirect via `style_id` (reference into a per-page style set). Graphemes beyond the first codepoint are stored in a separate grapheme map.

### 6.2 Wide Character Representation

Wide characters (including CJK) use two cells:
- First cell: `wide = .wide` with the codepoint
- Second cell: `wide = .spacer_tail` with no content

At line ends, `spacer_head` indicates a wide character was wrapped to the next line.

---

## 7. Key Observations for libitshell3 Protocol Design

### 7.1 Single-Consumer Dirty Model

ghostty's dirty tracking is designed for exactly one consumer. The `update()` method **clears dirty flags as it reads them** (lines 460, 643-647). This is fundamentally a single-consumer pattern. There is no mechanism for multiple independent consumers to track their own dirty state against the same terminal.

### 7.2 No Dirty Bitmask

ghostty does not use a bitmask for dirty tracking. It uses individual boolean flags on each row (1 bit in a packed struct). The page-level dirty is also a simple boolean, not a row bitmask. There is no concept of a "dirty row set" or "dirty bitmap" at the wire level — it is purely internal.

### 7.3 Full Redraw Is Triggered by Global State Changes

Full redraw (`RenderState.Dirty.full`) happens when:
- Screen switches (primary ↔ alternate)
- Color palette changes
- Reverse colors mode changes
- Screen clear
- Preedit changes
- Selection changes
- Hyperlink hover changes
- Viewport scrolls
- Dimension changes

Partial redraw (`RenderState.Dirty.partial`) happens when only individual rows have their dirty bits set.

### 7.4 No Inter-Frame Dependency

Each `updateFrame()` call produces a complete, self-contained state for the GPU. The renderer does not depend on the previous frame's GPU state being correct. If a row is dirty, it is fully rebuilt from the terminal state. If a row is not dirty, the renderer keeps its **cached GPU cells** from the last time that row was rebuilt. This is conceptually similar to the I-frame/P-frame Option B model: the "reference" is always the last known-good state per row, and dirty rows are independently updatable.

### 7.5 Event-Driven, Not Timer-Based

Normal rendering is purely event-driven. The IO thread notifies the renderer via an async wakeup, and the renderer immediately processes the update. Coalescing happens implicitly through the event loop's async notification semantics (multiple notifies between loop ticks collapse to one callback). There is no explicit FPS cap for normal rendering.

### 7.6 Synchronized Output Mode

ghostty supports DEC private mode 2026 (synchronized output). When active, `updateFrame()` returns early without updating state:

```zig
if (state.terminal.modes.get(.synchronized_output)) {
    log.debug("synchronized output started, skipping render", .{});
    return;
}
```

This causes the renderer to hold its previous frame until the application signals output is complete. Dirty flags accumulate during this period and are consumed on the next frame that actually runs.

---

## 8. Files Examined

| File | Lines | Content |
|------|-------|---------|
| `src/terminal/page.zig` | 100-260, 1615-1675, 1860-2110 | Page struct, Row struct (packed u64), Cell struct (packed u64), dirty flags, isDirty() |
| `src/terminal/Terminal.zig` | 110-165 | Terminal.Dirty packed struct (palette, reverse_colors, clear, preedit) |
| `src/terminal/Screen.zig` | 76-106, 1206-1210 | Screen.Dirty packed struct (selection, hyperlink_hover), cursorMarkDirty() |
| `src/terminal/render.zig` | 1-720 | RenderState struct, Dirty enum (false/partial/full), update() method, Row/Cell snapshot types |
| `src/terminal/PageList.zig` | 4990-5100 | clearDirty(), isDirty(), Pin.markDirty(), Pin.isDirty() |
| `src/renderer/generic.zig` | 1-60, 690-750, 980-1000, 1100-1420, 2290-2450 | updateFrame(), markDirty(), rebuildCells(), terminal_state field, periodic state reset |
| `src/renderer/Thread.zig` | 1-320, 480-640 | DRAW_INTERVAL, render_h/draw_h timers, wakeupCallback (immediate render), renderCallback, drawFrame |
| `src/renderer/State.zig` | 1-80 | Shared render state (mutex-protected terminal pointer, preedit, mouse) |
| `src/termio/Termio.zig` | 678-738 | processOutput() — locks mutex, calls queueRender, processes VT stream |
| `src/termio/stream_handler.zig` | 39-106 | renderer_wakeup async handle, queueRender() implementation |
| `src/termio/Exec.zig` | 1310-1390 | PTY read loop — reads into 1KB buffer, calls processOutput per read |
| `src/Surface.zig` | 2408-2416 | queueRender() → renderer_thread.wakeup.notify() |

All file paths are relative to `~/dev/git/references/ghostty/`.

---

## 9. Caveats

1. **ghostty is a single-consumer system.** Its dirty tracking is designed for one renderer per terminal. There is no multi-consumer dirty tracking. The protocol's multi-client scenario is architecturally different.

2. **RenderState is a recent optimization.** The comment at `render.zig:26-31` says the previous approach was a full `clone()` of the screen, which was "repeatedly a bottleneck." The RenderState approach was introduced to optimize this. The dirty tracking is a performance optimization, not a correctness requirement — a full rebuild every frame would still work, just slower.

3. **No versioning or sequencing.** ghostty's render frames have no sequence numbers, frame IDs, or any concept of frame ordering. Each frame is simply "the current state." This is fine for a single-consumer model but provides no basis for multi-consumer replay or catch-up.

4. **The 100,000-frame periodic reset** is relevant to libitshell3's keyframe concept. ghostty effectively does a forced full rebuild every ~12 minutes, conceptually similar to a periodic keyframe, though for memory management rather than state synchronization.
