# Research: ghostty Grapheme Cluster Internals

**Date**: 2026-03-08
**Researcher**: ghostty-expert
**Source**: ghostty source (commit 472b926a4)
**Requested by**: handover §7.4 (for review note 16)

## Findings

### 1. GraphemeData storage in page.Cell

**Cell struct** (`page.zig:1962`): `page.Cell` is a `packed struct(u64)` — exactly 8 bytes. The grapheme-related fields are:

```zig
pub const Cell = packed struct(u64) {
    content_tag: ContentTag = .codepoint,   // u2
    content: packed union {
        codepoint: u21,                      // base codepoint
        color_palette: u8,
        color_rgb: RGB,
    } = .{ .codepoint = 0 },
    style_id: StyleId = 0,
    wide: Wide = .narrow,                    // u2
    protected: bool = false,
    hyperlink: bool = false,
    semantic_content: SemanticContent = .output, // u2
    _padding: u16 = 0,
};
```

**ContentTag enum** (`page.zig:2004`):
```zig
pub const ContentTag = enum(u2) {
    codepoint = 0,
    codepoint_grapheme = 1,   // signals extra codepoints exist
    bg_color_palette = 2,
    bg_color_rgb = 3,
};
```

When `content_tag == .codepoint_grapheme`, the cell's `content.codepoint` still holds the **first (base) codepoint**. The additional codepoints are stored **outside the cell** in a separate side table.

**GraphemeData storage** (`page.zig:29-40`, `124-135`): The Page struct contains two separate structures for grapheme data:

1. **`grapheme_alloc: GraphemeAlloc`** — A bitmap allocator that stores the actual `u21` codepoint arrays. Allocates in chunks of 4 codepoints (16 bytes per chunk). This is where the extra codepoints physically reside.

2. **`grapheme_map: GraphemeMap`** — An `AutoOffsetHashMap(Offset(Cell), Offset(u21).Slice)` that maps cell offsets to slices into `grapheme_alloc`. The key is the cell's offset within the page's memory block; the value is an `{offset, len}` pair pointing to the extra codepoints.

**Lookup path** (`page.zig:1546-1551`):
```zig
pub inline fn lookupGrapheme(self: *const Page, cell: *const Cell) ?[]u21 {
    const cell_offset = getOffset(Cell, self.memory, cell);
    const map = self.grapheme_map.map(self.memory);
    const slice = map.get(cell_offset) orelse return null;
    return slice.slice(self.memory);
}
```

The returned `[]u21` contains only the **additional** codepoints (not the base). For example, a ZWJ emoji "👨‍🦰" with base U+1F468 would have the base in `cell.content.codepoint` and `[0x200D, 0x1F9B0]` in the grapheme table.

**Row-level flag** (`page.zig:1878-1882`):
```zig
grapheme: bool = false,  // on Row struct
```
A fast-path optimization: if `row.grapheme == false`, no cells in that row have multi-codepoint graphemes. Set to `true` when any cell in the row gains grapheme data; cleared lazily by `updateRowGraphemeFlag()`.

**Default capacity** (`page.zig:1746`): `grapheme_bytes = 8192` (production), `512` (test). The chunk size is 4 codepoints × 4 bytes = 16 bytes per chunk, so 8192 bytes = 512 chunks = 512 unique cells with grapheme data per page (if each uses exactly one chunk). Standard page capacity is 215×215 = 46,225 cells, so grapheme storage is provisioned for ~1.1% of cells.

### 2. Multi-codepoint frequency

ghostty provides no runtime statistics or counters for grapheme frequency. However, several source-level indicators reveal the developers' frequency assumptions:

**Explicit "rare" comments:**
- `page.zig:126-127`: *"This is where any cell that has more than one codepoint will be stored. This is **relatively rare** (typically only emoji) so this defaults to a very small size and we force page realloc when it grows."*
- `page.zig:133`: *"Grapheme data is **relatively rare** so this is considered a **slow path**."*
- `page.zig:29-34`: *"We use a chunk size of 4 codepoints... most skin-tone emoji are <= 4 codepoints, letter combiners are usually <= 4 codepoints"*

**Branch hints in render path:**
- `render.zig:521-528`: The `.codepoint` case uses `@branchHint(.likely)`, while `.codepoint_grapheme` uses `@branchHint(.unlikely)`. This is the CPU branch prediction hint telling the compiler that grapheme cells are expected to be rare.

**Allocation ratio:** Default grapheme storage (8192 bytes) can support ~512 grapheme cells out of 46,225 total cells per page — approximately 1.1%. This ratio was set "based on vibes" per the comment at line 34, not empirical measurement.

**What triggers multi-codepoint cells:**
- Emoji with skin tone modifiers (e.g., 👩🏽 = U+1F469 + U+1F3FD)
- Emoji with ZWJ sequences (e.g., 👨‍👩‍👧 = U+1F468 + U+200D + U+1F469 + U+200D + U+1F467)
- Combining characters / diacritics (e.g., é composed as U+0065 + U+0301)
- Presentation selectors (U+FE0E text, U+FE0F emoji)

### 3. Separability from cell array

**Current architecture: already separated.** At the `page.Page` level, grapheme data is already stored in a separate side table (`grapheme_map` + `grapheme_alloc`), completely decoupled from the cell array. The cell array stores only the base codepoint in each `Cell`; extra codepoints are in the map. This is exactly the "separate grapheme table" pattern.

**RenderState copies grapheme data out of the page.** In `render.zig:525-532`, during `RenderState.update()`, grapheme data is duplicated into a per-row arena:
```zig
.codepoint_grapheme => {
    @branchHint(.unlikely);
    cells_grapheme[x] = try arena_alloc.dupe(
        u21,
        p.lookupGrapheme(page_cell) orelse &.{},
    );
},
```
The resulting `RenderState.Cell` has a `grapheme: []const u21` field — a separate slice, not embedded in the cell struct.

**Current FlatCell export drops grapheme data.** In `render_export.zig:149-156`, `bulkExport()` copies `raw.codepoint()` and `raw.content_tag` to `FlatCell`, but does NOT export the extra codepoints:
```zig
dest[x] = .{
    .codepoint = raw.codepoint(),       // base only
    .content_tag = @intFromEnum(raw.content_tag),  // tag preserved
    // no grapheme field in FlatCell
};
```

And in `importFlatCells()` at line 281:
```zig
cells_grapheme[x] = &.{};  // always empty — grapheme data is lost
```

The `content_tag` is round-tripped (so the client knows a cell *had* grapheme data), but the actual extra codepoints are discarded. This means:
- The font shaper on the client side sees `content_tag == .codepoint_grapheme` but gets an empty grapheme slice
- Presentation selectors (U+FE0E/U+FE0F) in grapheme data are lost
- ZWJ sequences cannot be reconstructed
- The shaper's `indexForCell` function (which needs all codepoints to find the right font) will fail to match composite glyphs

**Can a separate grapheme table work for `importFlatCells()`?** Yes, architecturally this is straightforward because:

1. `importFlatCells()` already populates `cells_grapheme[x]` separately from `cells_raw[x]` — they are independent fields in the `MultiArrayList(Cell)`
2. The grapheme field is a simple `[]const u21` slice, not tied to any page allocator
3. A wire-level `(cell_index, []u21)` table could be used to set `cells_grapheme[x]` instead of the current `&.{}`
4. The `content_tag` is already preserved in the FlatCell, so the client knows which cells need grapheme lookup

**Reconstruction code path (what would need to change):**
In `importFlatCells()`, instead of:
```zig
cells_grapheme[x] = &.{};
```
It would become something like:
```zig
cells_grapheme[x] = grapheme_table.get(cell_index) orelse &.{};
```
No other changes are needed — the rest of the import path (raw cell, style) is independent.

## Raw References

- `page.zig:29-40` — grapheme_chunk_len, GraphemeAlloc, GraphemeMap type definitions
- `page.zig:84-135` — Page struct with grapheme_alloc, grapheme_map fields
- `page.zig:1443-1481` — `setGraphemes()`: initial grapheme assignment
- `page.zig:1483-1541` — `appendGrapheme()`: adding codepoints to existing grapheme
- `page.zig:1546-1551` — `lookupGrapheme()`: cell → extra codepoints lookup
- `page.zig:1574-1597` — `clearGrapheme()`: removing grapheme data
- `page.zig:1599-1607` — `updateRowGraphemeFlag()`: row-level flag maintenance
- `page.zig:1746` — `std_capacity.grapheme_bytes = 8192` (production default)
- `page.zig:1878-1882` — `Row.grapheme` bool field
- `page.zig:1962-2018` — Cell packed struct, ContentTag enum
- `render.zig:209-223` — `RenderState.Cell` with `grapheme: []const u21` field
- `render.zig:519-533` — grapheme data copy in `RenderState.update()`
- `render_export.zig:26-51` — FlatCell struct (no grapheme field)
- `render_export.zig:149-156` — `bulkExport()` drops extra codepoints
- `render_export.zig:264-281` — `importFlatCells()` sets grapheme to empty
- `font/shaper/run.zig:50` — shaper reads grapheme slice from cells
- `font/shaper/run.zig:162-166` — presentation selector check from grapheme data
- `font/shaper/run.zig:270-281` — all grapheme codepoints fed to shaper

All paths are under:
`/Users/heejoon.kang/dev/git/powdream/it-shell3/poc/06-renderstate-extraction/vendors/ghostty/src/`
