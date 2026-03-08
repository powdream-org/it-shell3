# PoC 08: RenderState Direct Population → GPU Rendering (No Terminal on Client)

**Date**: 2026-03-08
**Triggered by**: PoC 07 (bulk export validated) — now proving the client can populate RenderState directly from FlatCell[] without ever creating a Terminal
**Question**: Can FlatCell[] data be imported directly into a RenderState (bypassing Terminal), such that the renderer (`rebuildCells()`) can consume it for **actual GPU rendering via Metal**?

## Motivation

The it-shell3 protocol splits the rendering pipeline:

```
Server: Terminal → update() → RenderState → bulkExport() → FlatCell[] → wire
Client: wire → FlatCell[] → importFlatCells() → RenderState → rebuildCells() → GPU
```

The key insight: **the renderer reads from RenderState, NOT from Terminal.** If we can populate RenderState directly from wire data, the client never needs a Terminal instance. This eliminates:
- Terminal allocation/management on the client
- The entire VT parser/state machine on the client
- The `update()` call (which copies from Terminal's Page)

## What Was Built

### `importFlatCells()` — Direct RenderState population

Added to `render_export.zig`, this function constructs a valid `RenderState` from `ExportResult` data:

```zig
pub fn importFlatCells(
    alloc: Allocator,
    state: *RenderState,
    result: *const ExportResult,
) !void
```

For each cell, it:
1. Constructs a `page.Cell` (packed u64) with codepoint, wide, content_tag
2. Sets `style_id = 1` for styled cells (so `hasStyling()` returns true)
3. Sets the resolved `Style` directly (fg_color, bg_color, flags) — no StyleSet lookup
4. Sets grapheme to empty slice (single-codepoint cells only)

Row management follows the same `resize()` + `set()` pattern as `RenderState.update()`.

### `flattenExport()` — RenderState to FlatCell[] without Terminal

```zig
pub fn flattenExport(
    alloc: Allocator,
    state: *const RenderState,
) !ExportResult
```

Same flatten logic as `bulkExport()` but skips the `state.update()` call. Used when RenderState was populated via `importFlatCells()` rather than `update()`.

### `toStyleColor()` — PackedColor to Style.Color conversion

```zig
pub fn toStyleColor(pc: PackedColor) Style.Color
```

Reverse of `PackedColor.fromStyleColor()`. Converts tag+RGB/palette back to ghostty's `Style.Color` tagged union.

## Build

```sh
cd poc/06-renderstate-extraction/vendors/ghostty
~/.local/share/mise/installs/zig/0.15.2/zig build poc-reinject
```

Built with `ReleaseFast` optimization.

## Results

### Correctness — ALL CELLS MATCH

```
Server: 80x24 = 1920 cells exported
Client: RenderState populated directly (no Terminal)

Total: 1920  Empty: 1814  Match: 106  Mismatch: 0
*** ALL CELLS MATCH — Direct population PASSED ***
```

Verified cell types:

| Row | Content | Verified |
|-----|---------|----------|
| 0 | Plain ASCII | codepoint match |
| 1 | Korean wide chars (한글 테스트) | codepoint + wide=1 + spacer_tail=2 |
| 2 | Bold + red fg (RGB 255,0,0) | flags.bold + fg.rgb |
| 3 | Italic + green fg + blue bg | flags.italic + fg.rgb + bg.rgb |
| 4 | Orange fg + Korean mix | fg.rgb + wide chars |
| 5 | Palette colors (fg=196, bg=21) | fg.palette + bg.palette |

### Performance

**Machine**: Apple Silicon Mac, ReleaseFast, 100 warmup + 1000 bench iterations

| Size | Cells | import µs | flatten µs | total µs |
|------|-------|-----------|------------|----------|
| 80x24 (standard) | 1,920 | 12 | 25 | **37** |
| 120x40 (large) | 4,800 | 25 | 49 | **74** |
| 200x50 (wide) | 10,000 | 44 | 100 | **144** |
| 300x80 (ultra) | 24,000 | 96 | 228 | **324** |

### Analysis

- **Import is ~4 ns/cell** (96 µs / 24,000 cells). This is the cost of constructing `page.Cell` + `Style` from FlatCell and writing to the MultiArrayList.
- **RenderState reuse works**: The same RenderState is reused across all benchmark iterations. No Terminal init/deinit per frame.
- **Total round-trip**: 80×24 = 37 µs = **0.22%** of 16.6 ms frame budget at 60 fps.
- **vs print() approach**: 37 µs vs 158 µs — direct population is **4.3× faster** because it bypasses Terminal's cursor management, style dedup, and wrap logic.

## Findings

### 1. Terminal is NOT needed on the client

The renderer (`rebuildCells()`) reads only from `RenderState`:
- `cell.raw.codepoint()`, `cell.raw.wide`, `cell.raw.hasStyling()`, `cell.raw.content_tag`
- `cell.style.fg_color`, `cell.style.bg_color`, `cell.style.flags`
- `cell.grapheme` (for multi-codepoint clusters)
- `state.colors`, `state.cursor`, `state.dirty`

None of these require a Terminal. We construct them directly from FlatCell data.

### 2. style_id trick: set to 1 for styled cells

`page.Cell.hasStyling()` checks `style_id != 0`. The renderer uses this to decide whether to read `cell.style`. By setting `style_id = 1` for any cell with non-default styling, the renderer correctly reads the resolved style we provide. No actual StyleSet or style deduplication is needed.

### 3. Row management matches update() pattern

Using `row_data.resize()` + `slice().set()` for growing, and `shrinkRetainingCapacity()` after deiniting arenas/cells for shrinking. This is the exact pattern from `RenderState.update()`, ensuring memory safety.

### 4. Grapheme clusters need arena allocation

For this PoC, `cell.grapheme` is set to `&.{}` (empty). Multi-codepoint graphemes would need their data allocated in the per-row arena (`row.arena`). This is a future enhancement.

### 5. FlatCell round-trips perfectly

`FlatCell → importFlatCells() → RenderState → flattenExport() → FlatCell` produces identical output. The PackedColor ↔ Style.Color conversion is lossless for none, palette, and RGB variants.

## Impact on Protocol Design

### Client architecture confirmed

```
Client Process
┌─────────────────────────────────────────────┐
│                                             │
│  wire → FlatCell[] → importFlatCells()      │
│                           ↓                 │
│                     RenderState             │
│                           ↓                 │
│                   rebuildCells()             │
│                     (font shaping)          │
│                           ↓                 │
│                   Metal drawFrame()         │
│                                             │
│  NO Terminal, NO VT parser, NO Page/Screen  │
└─────────────────────────────────────────────┘
```

The client is a thin rendering frontend. All terminal logic stays on the server.

### Performance budget (updated)

| Operation | 80×24 µs | 300×80 µs | Notes |
|-----------|----------|-----------|-------|
| Server: bulkExport() | 22 | 217 | From PoC 07 |
| Wire: serialize+send | TBD | TBD | Network overhead |
| Client: importFlatCells() | 12 | 96 | This PoC |
| Client: rebuildCells() | ~200 | ~800 | Estimated (font shaping) |
| Client: drawFrame() | ~500 | ~2000 | Estimated (Metal GPU) |
| **Total** | **~734** | **~3113** | Well within 16.6 ms |

The import step is a small fraction of the total frame budget. The bottleneck will be font shaping and GPU rendering, both of which are client-local and already optimized by ghostty.

### GPU Rendering — VERIFIED

The full rendering pipeline was tested by modifying `generic.zig`'s `updateFrame()` to intercept `terminal_state` after `update()` and overwrite it with FlatCell data via `importFlatCells()`. The modified ghostty macOS app was built and run successfully.

**What the screen showed** (verified visually):

| Row | Content | Rendering |
|-----|---------|-----------|
| 0 | `Hello, it-shell3! importFlatCells() -> GPU rendering!` | Plain white ASCII ✓ |
| 1 | `한글 테스트` | Wide chars with correct 2-cell width ✓ |
| 2 | `Bold Red (RGB 255,0,0)` | Bold weight + red RGB foreground ✓ |
| 3 | `Italic Green on Blue` | Italic + green fg + blue bg ✓ |
| 5 | `Palette fg=196 bg=21` | 256-palette colors (red on blue) ✓ |

The complete pipeline: **FlatCell[] → importFlatCells() → RenderState → rebuildCells() (font shaping) → Metal drawFrame() → GPU → screen pixels**.

**Build notes**: Built with `zig build run` on macOS (Xcode 16.4). Required minor patches to ghostty's Swift code for Xcode compatibility (Tahoe-era APIs gated by `#if compiler(>=6.2)`, SwiftUI type-check timeout fix).

**Interception point**: `src/renderer/generic.zig` line ~1203, after `self.terminal_state.update(self.alloc, state.terminal)`. The PoC override constructs inline FlatCell data and calls `importFlatCells()` to overwrite `self.terminal_state` every frame.

## Known Limitations

- **No grapheme cluster support**: Only single-codepoint cells. Multi-codepoint graphemes need arena allocation.
- **No underline_color**: FlatCell doesn't carry underline_color. Would need a 20-byte FlatCell or separate field.
- **Row metadata not transferred**: `page.Row` flags (wrap, semantic_prompt) are not in FlatCell/ExportResult.
- **Colors/palette not transferred**: `RenderState.colors` (default bg/fg, 256-palette) initialized from defaults, not from server. Would need separate message.
- **Minimum size guard**: importFlatCells() should skip very small terminal sizes during initialization (rows < 6 or cols < 60) to avoid index-out-of-bounds in rebuildRow() font shaping.

## New API Surface

Three functions added to `render_export.zig`:

| Function | Direction | Purpose |
|----------|-----------|---------|
| `bulkExport()` | Terminal → FlatCell[] | Server-side (existing) |
| `importFlatCells()` | FlatCell[] → RenderState | Client-side (new) |
| `flattenExport()` | RenderState → FlatCell[] | Verification only (new) |
| `toStyleColor()` | PackedColor → Style.Color | Helper (new) |

## See Also

- `poc/07-renderstate-bulk-api/` — Bulk export performance
- `poc/06-renderstate-extraction/` — RenderState extraction validation
- `poc/06-renderstate-extraction/vendors/ghostty/src/terminal/render_export.zig` — Full API
