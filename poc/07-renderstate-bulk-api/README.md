# PoC 07: RenderState Bulk Copy API + Benchmark

**Date**: 2026-03-08
**Triggered by**: PoC 06 (extraction validated) — now proving bulk copy performance and module separation
**Question**: Can we bulk-copy RenderState cell data into a flat C-ABI buffer fast enough for real-time protocol use, and does the API work from a separate Zig module?

## Motivation

PoC 06 proved that RenderState cell data (codepoint, resolved style, wide flag) is accessible from a headless Terminal. But PoC 06 iterated cells one-by-one using internal Zig types. For the it-shell3 protocol, we need:

1. **Flat C-ABI buffer** — contiguous, fixed-size cells for wire serialization
2. **Bulk copy** — minimize lock hold time on the Terminal mutex
3. **Module separation** — the API must work from an external Zig module (simulating libitshell3)
4. **Performance measurement** — establish baseline for protocol throughput budgeting

## What Was Built

### FlatCell struct (16 bytes, C-ABI)

```zig
pub const FlatCell = extern struct {
    codepoint: u32,       // 4B — u21 primary codepoint (0 = empty)
    fg: PackedColor,      // 4B — tag(u8) + r,g,b
    bg: PackedColor,      // 4B — tag(u8) + r,g,b
    flags: u16,           // 2B — bold, italic, faint, blink, inverse, ...
    wide: u8,             // 1B — 0=narrow, 1=wide, 2=spacer_tail, 3=spacer_head
    content_tag: u8,      // 1B — 0=codepoint, 1=grapheme, 2=bg_palette, 3=bg_rgb
};  // Total: 16 bytes — power-of-2, SIMD-friendly
```

### Bulk export API

```zig
pub fn bulkExport(alloc, state: *RenderState, term: *Terminal) !ExportResult
pub fn freeExport(alloc, result: *ExportResult) void
```

`ExportResult` contains:
- `cells: [*]FlatCell` — flat buffer (`rows * cols` elements)
- `rows, cols` — dimensions
- `dirty_bitmap: [4]u64` — per-row dirty bits (up to 256 rows)
- `cursor_x, cursor_y` — cursor position
- `bg, fg` — terminal default colors
- `dirty_state` — 0=clean, 1=partial, 2=full

### Two-phase operation

1. `RenderState.update(alloc, terminal)` — copies from Terminal Page into RenderState (SoA format)
2. **Flatten** — transforms SoA `MultiArrayList(Cell)` into AoS `FlatCell[]` contiguous buffer

## Build

```sh
cd poc/06-renderstate-extraction/vendors/ghostty
~/.local/share/mise/installs/zig/0.15.2/zig build poc-bench
```

Built with `ReleaseFast` optimization to reflect production performance.

### Module separation

The benchmark executable (`poc/07-renderstate-bulk-api/src/main.zig`) is a **separate source file** outside the ghostty source tree. It imports `ghostty-vt` as an external Zig module via build.zig dependency, proving that the API works across module boundaries.

## Performance Results

**Machine**: Apple Silicon Mac, ReleaseFast, 1000 iterations after 100 warmup

### Full export (all rows dirty)

| Size | Cells | Buffer | update | flatten | total |
|------|-------|--------|--------|---------|-------|
| 80x24 (standard) | 1,920 | 30 KB | <1 µs | 22 µs | **22 µs** |
| 120x40 (large) | 4,800 | 76 KB | <1 µs | 49 µs | **49 µs** |
| 200x50 (wide) | 10,000 | 160 KB | <1 µs | 90 µs | **90 µs** |
| 300x80 (ultra) | 24,000 | 384 KB | <1 µs | 217 µs | **217 µs** |

### Incremental update (1 dirty row)

| Size | Dirty rows | total |
|------|-----------|-------|
| 200x50 | 1 row | **100 µs** |

### Analysis

- **RenderState.update()** is <1 µs when no rows are dirty (dirty flag check only)
- **Flatten throughput**: ~9 ns/cell (217 µs / 24,000 cells)
- **Buffer size**: 16 bytes/cell — 80x24 = 30 KB, 200x50 = 160 KB (fits in L2 cache)
- **Total latency**: even the largest terminal (300x80) completes in **217 µs**, well under 1 ms
- At 60 fps (16.6 ms budget), bulk export uses only **1.3%** of the frame budget (for 300x80)
- **Incremental export** is currently not faster than full — the flatten pass always copies all cells. Optimization: only copy dirty rows (tracked via `dirty_bitmap`)

## Findings

### 1. Bulk copy is fast enough for real-time use

Even the largest tested terminal (300x80, 384 KB) completes in 217 µs. For the typical 80x24 terminal, it's 22 µs. This is well within real-time protocol budgets.

### 2. The flatten pass dominates

`RenderState.update()` is effectively free when no dirty flags are set (already updated). The flatten (SoA → AoS transformation) is the bottleneck. Future optimization: use dirty bitmap to skip clean rows.

### 3. FlatCell is 16 bytes — good for SIMD

The 16-byte power-of-2 size aligns naturally for SIMD processing. Downstream serialization (e.g., delta compression before wire transmission) can process cells in 128-bit SIMD lanes.

### 4. Module separation works

The benchmark imports `ghostty-vt` as an external module and uses `render_export.bulkExport()` / `freeExport()`. This proves that libitshell3 can use the same pattern.

### 5. Style flattening adds no measurable overhead

Converting Style.Color tagged unions to PackedColor (4 bytes) is a switch + 3 byte copies. This is negligible compared to the memory access cost of iterating cells.

### 6. Dirty bitmap enables future optimization

The `dirty_bitmap` field in ExportResult records which rows changed. A protocol implementation can use this to:
- Only serialize dirty rows
- Only transmit dirty rows
- Skip flatten for clean rows (future)

## Impact on Design

### Protocol bandwidth estimation

| Scenario | Data per frame | At 60 fps |
|----------|---------------|-----------|
| 80x24 full frame | 30 KB | 1.8 MB/s |
| 80x24 1-row dirty | 1.3 KB | 78 KB/s |
| 200x50 full frame | 160 KB | 9.6 MB/s |
| 200x50 1-row dirty | 3.2 KB | 192 KB/s |

With delta compression (only dirty rows), typical throughput would be well under 1 MB/s for normal terminal usage.

### Next steps

1. **Delta-only export**: modify flatten to only copy dirty rows (using dirty_bitmap)
2. **Wire serialization**: add LZ4/zstd compression on the flat buffer
3. **PoC 08 (re-injection)**: feed deserialized FlatCell data back into a client-side Terminal → RenderState → GenericRenderer

## Known Limitations

- Benchmark measures flatten only, not serialization or network
- Incremental export currently copies all cells (dirty-only optimization not yet implemented)
- Grapheme cluster data (multi-codepoint) is not included in FlatCell — only the primary codepoint
- No concurrent access testing (single-threaded benchmark)
- ExportResult allocates a new buffer each call — production should reuse buffers

## See Also

- `poc/06-renderstate-extraction/` — RenderState extraction validation
- `poc/06-renderstate-extraction/vendors/ghostty/src/terminal/render_export.zig` — API implementation
- Protocol v0.8: `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/v0.8/04-input-and-renderstate.md`
