# Ghostty API Extensions (PoC 06–08)

Interfaces added to ghostty during PoC validation. These live in our vendor copy (`poc/06-renderstate-extraction/vendors/ghostty/`) and are recorded in `ghostty-modifications.patch`. They are candidates for upstream contribution or for wrapping behind libitshell3's abstraction layer.

**Last updated**: 2026-03-08

---

## New File

**`src/terminal/render_export.zig`** — All new types and functions are in this single file. No existing ghostty files were modified for API purposes (only PoC interception and build hooks).

---

## Types

| Type | Size | ABI | Purpose |
|------|------|-----|---------|
| `FlatCell` | 16 bytes | `extern struct` | Wire-friendly fixed-size cell. Contains codepoint (u32), fg/bg (PackedColor × 2), flags (u16), wide (u8), content_tag (u8). Power-of-2 for SIMD alignment. |
| `PackedColor` | 4 bytes | `extern struct` | Wire-friendly color. tag (u8: 0=default, 1=palette, 2=rgb) + r, g, b (u8 × 3). Lossless round-trip with ghostty's `Style.Color` tagged union. |
| `ExportResult` | ~56 bytes | Zig struct | Bulk export container. Holds `cells: [*]FlatCell` (rows×cols), dimensions, `dirty_bitmap: [4]u64` (up to 256 rows), cursor position, terminal default colors, dirty state. |

---

## Functions

### Server-side (Terminal → wire)

| Function | Signature | PoC | Purpose |
|----------|-----------|-----|---------|
| `bulkExport()` | `fn(Allocator, *RenderState, *Terminal) !ExportResult` | 07 | Main export API. Calls `state.update(alloc, terminal)` then flattens SoA `MultiArrayList(Cell)` into AoS `FlatCell[]`. Copies dirty bitmap, cursor, colors. |
| `freeExport()` | `fn(Allocator, *ExportResult) void` | 07 | Frees the FlatCell buffer allocated by `bulkExport()`. |

### Client-side (wire → RenderState)

| Function | Signature | PoC | Purpose |
|----------|-----------|-----|---------|
| `importFlatCells()` | `fn(Allocator, *RenderState, *const ExportResult) !void` | 08 | Populates RenderState directly from FlatCell data. Constructs `page.Cell` (packed u64) + resolved `Style` per cell. Sets `style_id=1` for styled cells so `hasStyling()` returns true. **No Terminal needed.** |

### Helpers

| Function | Signature | PoC | Purpose |
|----------|-----------|-----|---------|
| `flattenExport()` | `fn(Allocator, *const RenderState) !ExportResult` | 08 | RenderState → FlatCell[] without calling `state.update()`. Used for round-trip verification (export → import → re-export, check equality). |
| `toStyleColor()` | `fn(PackedColor) Style.Color` | 08 | Reverse of `PackedColor.fromStyleColor()`. Converts tag+data back to ghostty's `Style.Color` tagged union. Lossless for none, palette, rgb variants. |

---

## Data Flow

```
SERVER                                          CLIENT
──────                                          ──────

Terminal
  │
  ▼
RenderState.update(alloc, terminal)    ──── ghostty existing API
  │
  ▼
bulkExport(alloc, state, terminal)     ──── NEW (render_export.zig)
  │
  ├─► ExportResult { cells: [*]FlatCell, dirty_bitmap, cursor, colors }
  │
  ▼
[serialize to wire]
  │                                    [deserialize from wire]
  │                                       │
  │                                       ▼
  │                                    importFlatCells(alloc, state, result) ── NEW
  │                                       │
  │                                       ▼
  │                                    RenderState (populated, no Terminal)
  │                                       │
  │                                       ▼
  │                                    rebuildCells()  ──── ghostty existing API
  │                                       │
  │                                       ▼
  │                                    Metal drawFrame() ── ghostty existing API
```

---

## Performance (Apple Silicon, ReleaseFast)

| Operation | 80×24 | 300×80 | Per-cell |
|-----------|-------|--------|----------|
| `bulkExport()` (update + flatten) | 22 µs | 217 µs | ~11 ns |
| `importFlatCells()` | 12 µs | 96 µs | ~4 ns |
| **Round-trip total** | **34 µs** | **313 µs** | — |
| % of 16.6 ms frame budget (60fps) | 0.2% | 1.9% | — |

---

## Key Design Decisions

1. **Fixed 16-byte FlatCell**: No variable-length grapheme data in the cell itself. Multi-codepoint graphemes would need a separate table (not yet implemented). This enables O(1) random access and SIMD-friendly processing.

2. **`style_id = 1` trick**: `page.Cell.hasStyling()` checks `style_id != 0`. By setting `style_id = 1` for any cell with non-default styling, the renderer correctly reads the resolved style. No actual StyleSet or style deduplication needed on the client.

3. **Row management via `resize()` + `set()`**: Same pattern as `RenderState.update()` — `row_data.resize()` for growing, `shrinkRetainingCapacity()` for shrinking. Ensures memory safety.

4. **ExportResult owns its buffer**: `bulkExport()` allocates, caller frees via `freeExport()`. Production should reuse buffers.

---

## The "Flattening" Concept

ghostty's internal representation uses **indirection** for styling:

```
ghostty internal:  page.Cell (8B packed u64)
                     ├── codepoint (u21)
                     ├── content_tag (2 bits)
                     ├── wide (2 bits)
                     └── style_id ──► RefCountedSet lookup ──► Style { fg_color, bg_color, flags }
```

The wire FlatCell **resolves this indirection** ("flattens" it) by inlining the style data:

```
wire FlatCell (16B):  codepoint (u32) + wide (u8) + content_tag (u8)
                      + flags (u16)    ← from Style.Flags, inlined
                      + fg_color (4B)  ← from Style.fg_color, inlined
                      + bg_color (4B)  ← from Style.bg_color, inlined
```

The 8-byte Cell becomes 16 bytes because the style data (behind a `style_id` pointer in ghostty) is now **inline** — no lookup table needed on the client.

**Key consequence**: server export is slower than client import (22 µs vs 12 µs for 80x24) because the server must dereference `style_id` via `RefCountedSet` lookup for each styled cell. The client reconstructs `RenderState.Cell` directly from flat data — no style set indirection needed.

**SSH compression synergy**: The flat 16-byte layout produces highly compressible patterns — empty cells are mostly zeros, consecutive cells share colors/flags. SSH's `zlib@openssh.com` (persistent dictionary across packets) achieves estimated 10-20x compression for typical terminal screens, 3-5x for dense colored output.

---

## Known Gaps (PoC → v0.9 Status)

| Gap | PoC Status | v0.9 Resolution | Protocol Section |
|-----|-----------|-----------------|------------------|
| No grapheme cluster support | Base codepoint only | **Resolved**: per-row GraphemeTable side table (content_tag=1 triggers lookup) | Doc 04 §4.5 |
| No `underline_color` | Default color | **Resolved**: per-row UnderlineColorTable side table (16B FlatCell + side tables, not 20B) | Doc 04 §4.5 |
| No row metadata | No semantic_prompt/wrap | **Resolved**: `row_flags` byte — semantic_prompt (2 bits), hyperlink (1 bit); wrap deferred (YAGNI) | Doc 04 §4.3 |
| No palette in ExportResult | Client can't resolve palette colors | **Resolved**: full 768-byte palette REQUIRED in every I-frame | Doc 04 §4.2, §7.2 |
| Minimum size guard | Crash at rows<6/cols<60 | **Resolved**: server MUST suppress FrameUpdate below cols<2/rows<1 | Doc 04 §4.1 |

---

## Build Integration

Three build steps added to ghostty's `build.zig`:

| Step | Executable | Source |
|------|-----------|--------|
| `poc` | PoC 06 extraction test | `poc/extract_renderstate.zig` |
| `poc-bench` | PoC 07 bulk export benchmark | `poc/07-renderstate-bulk-api/src/main.zig` |
| `poc-reinject` | PoC 08 re-injection + round-trip | `poc/poc_reinject.zig` |

All use the `ghostty-vt` internal Zig module (not the C API). For libitshell3 production use, these would be wrapped behind C API functions in `ghostty.h`.

---

## See Also

- `poc/06-renderstate-extraction/README.md` — Extraction validation
- `poc/07-renderstate-bulk-api/README.md` — Bulk export + benchmark
- `poc/08-renderstate-reinjection/README.md` — Re-injection + GPU rendering verification
- `poc/06-renderstate-extraction/ghostty-modifications.patch` — All changes as a patch file
- Review notes 16–21 in `docs/modules/libitshell3-protocol/.../v1.0-r8/review-notes/`
