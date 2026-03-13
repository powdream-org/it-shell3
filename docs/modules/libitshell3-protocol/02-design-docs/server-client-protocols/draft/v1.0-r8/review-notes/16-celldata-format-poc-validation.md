# CellData Format: PoC-Validated 16-Byte FlatCell vs. 20-Byte Spec

**Date**: 2026-03-08
**Raised by**: owner (based on PoC 06–08 results)
**Severity**: HIGH
**Affected docs**: 04-input-and-renderstate.md (Section 4.4 CellData Encoding)
**Status**: open

---

## Problem

The current CellData encoding (doc 04 §4.4) specifies a **20-byte typical cell** with variable-length grapheme support:

```
codepoint:        4 bytes (u32 LE)
extra_count:      1 byte
extra_codepoints: 4*N bytes (variable)
wide:             1 byte
fg_color:         4 bytes (PackedColor)
bg_color:         4 bytes (PackedColor)
underline_color:  4 bytes (PackedColor)
flags:            2 bytes (u16 LE)
```

PoC 06–08 validated a **16-byte fixed-size FlatCell** that successfully drives the full GPU rendering pipeline (importFlatCells → RenderState → rebuildCells → Metal drawFrame):

```
codepoint:  4 bytes (u32 LE, lower 21 bits)
wide:       1 byte
flags:      2 bytes (u16 LE)
_padding:   1 byte
fg:         4 bytes (PackedColor)
bg:         4 bytes (PackedColor)
```

Key differences:
1. **No `underline_color`** — omitted from FlatCell; ghostty still renders underlines correctly using default color
2. **No `extra_count` / `extra_codepoints`** — grapheme clusters not tested in PoC; single-codepoint cells only
3. **Fixed 16-byte size** — enables O(1) random access, simpler parsing, better cache behavior

## Analysis

### Size impact

| Format | Single cell | 80×24 full frame | 300×80 full frame |
|--------|------------|------------------|-------------------|
| Spec CellData (20B typical) | 20 bytes | 38.4 KB | 480 KB |
| FlatCell (16B fixed) | 16 bytes | 30.7 KB | 384 KB |
| **Savings** | **20%** | **7.7 KB** | **96 KB** |

### `underline_color` trade-off

- `underline_color` is a distinct color from `fg_color` (set via SGR 58). It's used for colored underlines (e.g., LSP error squiggles in terminals like ghostty, kitty, WezTerm).
- In the PoC, omitting it caused no rendering issues because ghostty falls back to `fg_color` for underline color when no explicit underline color is set.
- **However**, for full terminal compatibility, colored underlines are important.
- **Option A**: Keep 16-byte FlatCell, send `underline_color` only when non-default (as a separate run-length-compressed side channel)
- **Option B**: Expand to 20-byte cell with `underline_color` always present (current spec)
- **Option C**: Use 16 bytes by default, expand to 20 bytes only for cells with `underline_color != default` (tagged variant)

### Variable-length grapheme clusters

The `extra_count` + `extra_codepoints` design makes cells variable-length. This complicates:
- Random access (cannot jump to cell N without scanning)
- RLE encoding (run prototypes must encode their full size)
- Buffer pre-allocation (unknown total size before encoding)

**Alternative**: Separate grapheme data from the cell array. Fixed-size cells contain only the base codepoint. A separate grapheme table (cell_index → extra codepoints) follows the cell array. Most cells (>99%) have zero extra codepoints, so the table is typically empty or very small.

### Performance evidence

PoC measured import at **~4 ns/cell** with the 16-byte format. The 20-byte format's variable-length nature would add branch prediction and memory access overhead for the grapheme field scan.

## Proposed Change

**Option A — Fixed 16-byte cell + separate grapheme table + conditional underline_color** (recommended):

```
CellData (16 bytes, fixed):
  Offset  Size  Field
  0       4     codepoint (u32 LE, lower 21 bits)
  4       1     wide (0-3)
  5       2     flags (u16 LE)
  7       1     cell_flags (bit 0: has_grapheme, bit 1: has_underline_color)
  8       4     fg_color (PackedColor)
  12      4     bg_color (PackedColor)

GraphemeTable (appended after cell array):
  num_graphemes: u16 LE
  entries: []{
    cell_index: u16 LE
    extra_count: u8
    extra_codepoints: [extra_count]u32 LE
  }

UnderlineColorTable (appended after grapheme table):
  num_entries: u16 LE
  entries: []{
    cell_index: u16 LE
    color: PackedColor (4 bytes)
  }
```

- Pro: O(1) cell access, PoC-validated base format, minimal size for common case
- Pro: Grapheme and underline_color data only when needed (rare)
- Con: Two-pass parsing for cells with graphemes or underline_color

**Option B — Keep current 20-byte variable-length CellData** (current spec):

- Pro: All data inline, single-pass parsing
- Con: Variable length complicates random access, 20% larger for common case
- Con: Not validated by PoC

## Owner Decision

{Pending}

## Resolution

{Pending}
