# Design Resolution 01: PoC Alignment (Review Notes 16–21)

**Date**: 2026-03-08
**Team**: protocol-architect, system-sw-engineer, cjk-specialist, ime-expert, principal-architect
**Consensus**: 5/5 unanimous on all items
**Scope**: Align protocol spec (doc 04) with PoC 06–08 validated implementation reality

---

## Resolution 1: 16-byte fixed FlatCell with per-row side tables (RN-16)

**Consensus**: 5/5

**Decision**: Replace the current 20-byte variable-length CellData (doc 04 Section 4.4) with a 16-byte fixed-size FlatCell. Grapheme clusters and underline colors are carried in separate per-row side tables.

### Wire layout

```
CellData (16 bytes, fixed, power-of-2 aligned):
  Offset  Size  Field
  0       4     codepoint (u32 LE, lower 21 bits used)
  4       1     wide (u8: 0=narrow, 1=wide, 2=spacer_tail, 3=spacer_head)
  5       2     flags (u16 LE — style flags, same bit layout as current spec)
  7       1     content_tag (u8: bits 0-1 = ghostty ContentTag enum, bits 2-7 reserved)
  8       4     fg_color (PackedColor)
  12      4     bg_color (PackedColor)
```

**content_tag values (bits 0-1)**:
- 0 = codepoint (single codepoint, no grapheme data)
- 1 = codepoint_grapheme (base codepoint in cell, extra codepoints in grapheme table)
- 2 = bg_color_palette (cell carries background palette color)
- 3 = bg_color_rgb (cell carries background RGB color)

These match ghostty's `ContentTag` enum directly. No separate `cell_flags` byte — `content_tag == 1` signals grapheme table lookup. The underline color table is self-describing by cell_index.

### Per-row side tables

Side tables are appended after each row's cell array (per-row, not per-frame) to preserve P-frame row-level atomicity:

```
RowData format:
  RowHeader
  CellData[num_cells]        (16 bytes each, fixed)
  GraphemeTable               (per-row)
  UnderlineColorTable         (per-row)

GraphemeTable:
  u16 LE: num_entries         (0 for most rows)
  For each entry:
    u16 LE: col_index         (column within the row)
    u8:     extra_count
    [extra_count] u32 LE: extra codepoints

UnderlineColorTable:
  u16 LE: num_entries         (0 for most rows)
  For each entry:
    u16 LE: col_index         (column within the row)
    PackedColor (4 bytes)
```

### Rationale

1. **PoC-validated**: The 16-byte FlatCell drove the full GPU rendering pipeline in PoC 08 (importFlatCells -> RenderState -> rebuildCells -> Metal drawFrame). Proven with ASCII, Korean wide chars, bold/italic, RGB colors, palette colors.

2. **ghostty mirrors this architecture**: ghostty's `page.Cell` is a fixed 8-byte packed struct with grapheme data in a separate `GraphemeMap` side table. The wire format mirrors the source data layout.

3. **O(1) random access**: Fixed-size cells enable direct indexing (`buffer[col * 16]`). Critical for dirty-row extraction, RLE encoding, and future SIMD optimization. Variable-length cells require sequential scanning.

4. **20% bandwidth reduction**: 16 bytes vs 20 bytes per cell. For 80x24: 30.7 KB vs 38.4 KB per I-frame.

5. **Grapheme frequency is ~1.1%**: ghostty provisions grapheme storage for ~1.1% of cells and marks the grapheme code path with `@branchHint(.unlikely)`. A separate table for rare data avoids bloating every cell.

6. **Per-row preserves row atomicity**: P-frames carry individual dirty rows. Each RowData must be self-contained — per-row side tables ensure the receiver can process each row independently without buffering the entire frame. Per-row overhead for empty tables: 4 bytes (two u16 zero-count headers) per row. For 24 rows: 96 bytes, negligible.

7. **Korean preedit is always single-codepoint**: All Hangul syllables (precomposed, U+AC00-U+D7AF) and jamo are single codepoints. The grapheme table is never needed for Korean IME, confirming the 16-byte format covers 100% of CJK composition.

### Removed from current spec

- `extra_count` field (variable-length grapheme inline encoding)
- `extra_codepoints` inline array
- `underline_color` as a per-cell field (4 bytes saved for >99% of cells)

### Trade-offs

- **Two-pass parsing for grapheme/underline cells**: The receiver processes the cell array first, then patches cells from the side tables. This is a post-pass over a small number of entries (~1.1% graphemes, even fewer underline colors). Negligible cost.
- **Per-row overhead**: 4 bytes per row for empty side table headers. 96 bytes for 24 rows. Negligible vs ~30 KB cell data.

---

## Resolution 2: Client rendering pipeline revision (RN-17)

**Consensus**: 5/5

**Decision**: Update doc 04 Section 3.2 and Section 4.1 to reflect the PoC-validated pipeline. The client is a RenderState populator, not a custom renderer.

### Normative text revision for Section 4.1

Replace the current "CellData is SEMANTIC" normative note with:

> **Normative — CellData is SEMANTIC**: CellData carries semantic content (codepoint, style attributes, colors, wide-char flag) for populating a RenderState on the client. The client populates RenderState from wire CellData and delegates all rendering to ghostty's existing rendering pipeline (font shaping, atlas management, GPU buffer construction, draw). The client does NOT individually perform font shaping, glyph atlas lookup, or GPU buffer construction — these are internal to the rendering pipeline.

Add an informative note:

> **Informative — Reference implementation**: In ghostty, this pipeline corresponds to `importFlatCells()` (RenderState population from wire data) followed by `rebuildCells()` (font shaping and GPU buffer construction) and `drawFrame()` (Metal GPU rendering). See PoC 08 for validation.

### Section 3.2 flow diagram revision

Replace the client-side portion of the flow diagram:

```
OLD:
  Font subsystem (SharedGrid, Atlas)
      |
      v
  Metal GPU render (CellText, CellBg shaders)

NEW:
  CellData → RenderState population
      |
      v
  ghostty rendering pipeline (font shaping, atlas, GPU buffers)
      |
      v
  Metal drawFrame()
```

### Rationale

1. **PoC 08 proved this pipeline with actual GPU rendering on macOS**. All cell types rendered correctly: ASCII, Korean wide chars, bold/italic, RGB colors, palette colors.

2. **The client has no Terminal, no VT parser, no Page/Screen**. Its memory footprint is dramatically smaller (~3-5 MB for RenderState + font atlas + GPU buffers vs ~20+ MB for a full Terminal).

3. **Preedit cells follow the same pipeline** — no special case. This confirms the v0.8 preedit overhaul ("preedit is cell data, not metadata").

4. **Normative text should describe the semantic contract, not ghostty-internal function names**. Function names belong in informative notes. This future-proofs against ghostty API changes.

---

## Resolution 3: Row metadata in row_flags byte (RN-18)

**Consensus**: 5/5

**Decision**: Merge the existing `selection_flags` byte with new row metadata into a unified `row_flags` byte. Add `semantic_prompt` (2 bits) and `hyperlink` (1 bit). Defer `wrap` to a future revision.

### row_flags bit layout

```
row_flags (u8):
  Bit 0:    has_selection (existing, unchanged)
  Bit 1:    rle_encoded (existing, unchanged)
  Bits 2-3: semantic_prompt (0=none, 1=prompt, 2=prompt_continuation, 3=reserved)
  Bit 4:    hyperlink (row contains at least one hyperlinked cell)
  Bits 5-7: reserved (bit 5 anticipated for wrap in a future revision)
```

### Wire cost

Zero additional bytes. The existing `selection_flags` byte is renamed to `row_flags` and its unused bits are populated.

### Rationale

1. **`semantic_prompt` is rendering-critical**: Research confirms `renderer/row.zig:neverExtendBg()` reads `semantic_prompt` to prevent background color extension on prompt lines. Without it, Powerline-style prompts bleed into padding — a visible rendering artifact, especially noticeable during Korean composition at the prompt.

2. **`hyperlink` is a rendering optimization**: Research confirms `Overlay.zig:166` uses `row.hyperlink` to skip non-hyperlink rows during overlay rendering. Without it, the renderer scans every cell of every row for hyperlinks. Including it costs 0 bytes and enables the same optimization on the client.

3. **`wrap` is deferred (YAGNI)**: Research confirms `wrap` is NOT used by the renderer's cell-building or GPU pipeline. It is only used by `RenderState.string()` for text serialization (copy/paste). Copy/paste is not a v1 protocol requirement. Including `wrap` now would embed an assumption about the copy/paste architecture (client-side vs server-side text serialization) before that design exists. Bit 5 is reserved with an explicit anticipation note — when copy/paste is designed, `wrap` can be defined without a protocol version bump.

4. **Only rendering-relevant fields from `page.Row` are included**: Research analyzed all 10 `page.Row` fields. Only `semantic_prompt` and `hyperlink` are read by the renderer. `wrap`, `wrap_continuation`, `grapheme`, `styled`, `kitty_virtual_placeholder`, and `dirty` are not read by any renderer code path.

### Dissenting view (documented)

system-sw-engineer and protocol-architect initially preferred including `wrap` (1 bit, zero byte cost, data available on the server). They argued the marginal cost is zero and it enables future copy/paste. They accepted the reservation approach after the team converged on the principle that wire format bits should be normatively defined or reserved — an "informational" category creates ambiguity about sender obligation and receiver expectation. The reserved-bit approach provides the same forward-compatibility guarantee without present-day ambiguity.

---

## Resolution 4: Minimum terminal dimensions (RN-19)

**Consensus**: 5/5

**Decision**: Specify a protocol-level structural minimum for FrameUpdate dimensions. Do not embed renderer-specific crash thresholds as protocol constants.

### Normative text for doc 04 Section 4.1

> **Normative — Minimum rendering dimensions**: The server MUST NOT send FrameUpdate with `cols < 2` or `rows < 1`. When a pane's dimensions fall below these minimums (e.g., during resize animation or aggressive pane splitting), the server MUST suppress FrameUpdate for that pane and SHOULD send `frame_type=2` (I-unchanged) to maintain pane liveness. The server SHOULD suppress FrameUpdate when dimensions fall below its renderer's practical minimum and send `frame_type=2` instead.

> **Normative — PTY independence**: When the server suppresses FrameUpdate due to undersized pane dimensions, the PTY MUST continue operating normally (`TIOCSWINSZ` reflects actual size, I/O continues). Only the FrameUpdate rendering pipeline is suppressed. Applications running in the PTY (e.g., vim) will receive the actual dimensions and may adapt their output accordingly.

### Client-side normative text for doc 04 Section 4.2

> **Normative — Client dimension validation**: The client SHOULD validate `cols` and `rows` from the FrameUpdate dimensions field before processing cell data. If dimensions are below the client's rendering minimum, the client SHOULD display a placeholder (e.g., solid background using the session's `default_background`) instead of attempting to render cells.

### Rationale

1. **PoC 08 crashed at small dimensions**: `rebuildRow()` font shaping hit an index-out-of-bounds error at rows < 6 or cols < 60. This is a real crash, not a theoretical concern.

2. **Protocol minimum vs renderer minimum are separate concerns**: The protocol specifies a structural invariant (`cols >= 2, rows >= 1`) — below this, there is literally nothing to render. The renderer's practical minimum (which may be higher) is an implementation detail that may change across ghostty versions. The protocol should not hardcode renderer-specific thresholds.

3. **PTY continues during suppression**: The PTY layer and the rendering pipeline have different minimum requirements. The PTY does not crash at small sizes. Suppression applies only to FrameUpdate generation.

4. **Liveness during suppression**: The server must send `frame_type=2` (I-unchanged) when suppressing FrameUpdate, so the client knows the pane still exists. Silence could be misinterpreted as pane destruction.

### Related but out of scope

Preedit suppression below cols=2 (Korean wide characters need at least 2 columns) is an IME semantic concern. It belongs in doc 05 (CJK preedit protocol), not doc 04. The IME engine should commit-and-flush in-progress composition when a pane shrinks below the minimum width for the active input method.

---

## Resolution 5: Palette/colors REQUIRED in I-frames (RN-20)

**Consensus**: 5/5

**Decision**: Elevate the `colors` section from optional to REQUIRED in I-frames. Full palette MUST be included in every I-frame for strict self-containment.

### Normative text for doc 04 Section 4.2

> **Normative — Colors are rendering-critical**: The `colors` section is not informational metadata. The client's renderer uses `bg` as the `default_background` for padding extension decisions (`neverExtendBg()`) and as the fallback for cells with `PackedColor tag=0x00`. Palette entries are required to resolve cells with `PackedColor tag=0x01`. I-frames (`frame_type=1`) MUST include `fg`, `bg`, and the full `palette` (256 entries, 768 bytes). This ensures any I-frame is self-contained — a client that receives only this I-frame can render correctly.

### P-frame behavior (unchanged)

P-frames continue to use the existing `palette_changes` field for delta updates. If no palette entries have changed, `palette_changes` is omitted. No change needed.

### Rationale

1. **I-frame self-containment invariant**: Doc 04 Section 4.1 defines I-frames as "self-contained keyframes." If colors are omitted, this invariant is violated. A client joining mid-session would render with wrong colors — silent corruption with no error signal.

2. **`neverExtendBg()` needs `default_background`**: Research confirms `renderer/row.zig` compares cell backgrounds against `default_background`. Without the correct value, padding rendering is wrong for Powerline-style prompts.

3. **Palette-indexed cells need palette**: CellData uses `PackedColor` with `tag=0x01` (palette index). The client must resolve `palette[index]` to RGB. Without the palette, these cells render incorrectly.

4. **Cost is negligible**: `fg` + `bg` = 6 bytes. Full palette = 768 bytes. Total = 774 bytes per I-frame. At 1 I-frame/second, this is 774 bytes/second over a Unix socket — trivial.

5. **Simplicity over optimization**: Always including the full palette in I-frames eliminates conditional logic ("has this client received a palette?", "has the palette changed?"). Every I-frame is complete. Simple. How the server tracks palette changes internally (generation counter, dirty flag, comparison) is an implementation detail, not a protocol concern.

---

## Resolution 6: PoC performance baseline (RN-21)

**Consensus**: 5/5

**Decision**: Add measured PoC performance data to doc 04 Section 7 (or new Section 8). Include only measured values. Do not include estimated/unvalidated numbers.

### Measured data table (PoC 06-08, Apple Silicon, ReleaseFast)

| Metric | 80x24 | 300x80 | Notes |
|--------|-------|--------|-------|
| Server export (`bulkExport()`) | 22 us | 217 us | RenderState -> FlatCell[] serialization |
| Client import (`importFlatCells()`) | 12 us | 96 us | FlatCell[] -> RenderState population |
| **Total wire overhead** | **34 us** | **313 us** | 0.2% / 1.9% of 16.6 ms frame budget (60fps) |
| Per-cell import cost | ~4 ns | ~4 ns | Consistent across terminal sizes |
| Round-trip fidelity | bit-identical | bit-identical | export -> import -> re-export produces identical output |

### Qualitative statement

> Wire serialization/deserialization is NOT the rendering bottleneck. Font shaping and GPU rendering are the dominant costs in the frame pipeline. The measured wire overhead (0.2% of frame budget for a standard 80x24 terminal) validates the design decision to transmit semantic CellData rather than GPU-ready data.

### Rationale

1. **Measured data replaces estimates**: The current spec contains estimated frame sizes. PoC data provides actual measurements under realistic conditions (Apple Silicon, ReleaseFast, 1000 iterations after warmup).

2. **Only measured values are normative**: Estimated values for `rebuildCells()` (~200 us) and `drawFrame()` (~500 us) from the review note are NOT included because they are unvalidated guesses. Including them alongside precise measurements would undermine credibility. The qualitative statement about font shaping and GPU dominance is sufficient.

3. **Data is from the 16-byte FlatCell format**: These measurements use the 16-byte format proposed in Resolution 1, not the current 20-byte spec format. This is directly applicable since we are adopting the 16-byte format.

4. **Known gap**: Grapheme cluster cells were not tested in the PoC. Performance for frames with grapheme side table data is unmeasured but expected to be negligible (table typically contains a handful of entries).

---

## Summary of spec changes required

| Resolution | Affected sections | Change type |
|------------|-------------------|-------------|
| 1 (CellData format) | Doc 04 Section 4.4 (CellData Encoding) | Rewrite: 20-byte variable -> 16-byte fixed + per-row side tables |
| 2 (Pipeline revision) | Doc 04 Section 3.2 (flow diagram), Section 4.1 (normative note) | Rewrite: update client pipeline description |
| 3 (Row metadata) | Doc 04 Section 4.3 (DirtyRows/RowData) | Modify: rename `selection_flags` to `row_flags`, define new bits |
| 4 (Minimum dimensions) | Doc 04 Section 4.1 (new normative note), Section 4.2 (client validation) | Add: minimum dimension requirements and suppression behavior |
| 5 (Palette required) | Doc 04 Section 4.2 (colors field), Section 7.2 (I-frame) | Modify: elevate colors from optional to REQUIRED in I-frames |
| 6 (Performance baseline) | Doc 04 Section 7 or new Section 8 | Add: measured performance data subsection |
| (Mechanical) | Doc 04 Appendix A (hex dump), Appendix B (size analysis) | Update: reflect 16-byte CellData and new row_flags |

## Deferred items

| Item | Reason | When to revisit |
|------|--------|-----------------|
| `wrap` bit in `row_flags` | YAGNI — no consumer until copy/paste is designed | When copy/paste protocol is designed (bit 5 reserved) |
| Preedit suppression below cols=2 | IME semantic concern, not rendering | Doc 05 (CJK preedit protocol) revision |
| Grapheme cluster PoC validation | Not tested in PoC 06-08 | Before v1 ship — needs arena allocation in importFlatCells() |
