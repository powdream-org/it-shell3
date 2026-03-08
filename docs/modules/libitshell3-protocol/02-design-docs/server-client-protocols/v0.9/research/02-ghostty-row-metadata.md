# Research: ghostty Row Metadata Used by Renderer

**Date**: 2026-03-08
**Researcher**: ghostty-expert
**Source**: ghostty source (commit 472b926a4d7abbacad4deea17aa0a0c69ffc12d3)
**Requested by**: handover §7.6 (for review note 18)

## Findings

### 1. Row fields accessed by renderer

The `page.Row` struct is a `packed struct(u64)` defined at `src/terminal/page.zig:1866`. It contains these fields:

```zig
pub const Row = packed struct(u64) {
    cells: Offset(Cell),          // pointer to cell data
    wrap: bool = false,
    wrap_continuation: bool = false,
    grapheme: bool = false,
    styled: bool = false,
    hyperlink: bool = false,
    semantic_prompt: SemanticPrompt = .none,  // enum(u2): none/prompt/prompt_continuation
    kitty_virtual_placeholder: bool = false,
    dirty: bool = false,
    _padding: u23 = 0,
};
```

The RenderState copies the entire `page.Row` into `row_data.items(.raw)` at `src/terminal/render.zig:481`:
```zig
row_rows[y] = page_rac.row.*;
```

The renderer then accesses `row_raws` (the `.raw` field) in its main loop at `src/renderer/generic.zig:2523-2530`. However, **only a subset of fields are actually read by rendering code paths**:

| Field | Read by renderer? | Where |
|-------|------------------|-------|
| `cells` | No (renderer uses RenderState.Cell, not raw page cells) | — |
| `wrap` | No (not by renderer; used only by `RenderState.string()` for text serialization) | `render.zig:785` |
| `wrap_continuation` | No | — |
| `grapheme` | No | — |
| `styled` | No (used only by `RenderState.update()` as optimization gate: `render.zig:505`) | — |
| `hyperlink` | **Yes** — Overlay.zig uses it to skip non-hyperlink rows | `Overlay.zig:166` |
| `semantic_prompt` | **Yes** — used in two places | `row.zig:18`, `Overlay.zig:219,229` |
| `kitty_virtual_placeholder` | No | — |
| `dirty` | No (page-level `dirty` is used during `update()`, but the row's `dirty` flag is consumed and cleared during RenderState update, never read by the renderer itself; the RenderState has its own `dirty` field per row) | `render.zig:449,460` |
| `_padding` | No | — |

**Summary**: Only **2 out of 10** `page.Row` fields are read by the renderer: `semantic_prompt` and `hyperlink`.

### 2. Additional row-level flags beyond semantic_prompt and wrap

**`hyperlink`** is a row-level flag that the renderer reads. Specifically, `Overlay.zig:166` uses `row.hyperlink` as an early-exit optimization to skip rows that have no hyperlinked cells when drawing the hyperlink overlay:

```zig
for (row_raw, row_cells, 0..) |row, cells, y| {
    if (!row.hyperlink) continue;  // skip rows with no hyperlinks
    // ... iterate cells to find contiguous hyperlink runs
```

The `grapheme`, `styled`, and `kitty_virtual_placeholder` flags are not accessed by any renderer code path. They are only used internally by page/terminal operations.

### 3. neverExtendBg() analysis

**Location**: `src/renderer/row.zig:8-63`

**Purpose**: Determines whether a row's background color should be extended into the terminal padding area. This affects the visual appearance of the terminal window edges.

**How it uses `semantic_prompt`**:

```zig
pub fn neverExtendBg(
    row: terminal.page.Row,
    cells: []const terminal.page.Cell,
    styles: []const terminal.Style,
    palette: *const terminal.color.Palette,
    default_background: terminal.color.RGB,
) bool {
    switch (row.semantic_prompt) {
        .prompt, .prompt_continuation => return true,  // NEVER extend bg for prompts
        .none => {},  // continue checking cells
    }
    // ... then checks individual cells for default bg, powerline glyphs, etc.
```

**Exact conditions**:
- If `row.semantic_prompt` is `.prompt` or `.prompt_continuation`, return `true` immediately (never extend bg). Rationale: prompts often contain powerline formatting that looks bad when extended.
- If `row.semantic_prompt` is `.none`, proceed to per-cell checks (default bg color, powerline codepoints).

**Rendering effects**: `neverExtendBg` is called in `generic.zig:2756-2771` only when the config `padding_color` is `.extend`, and only for the **first row** (y==0, controls top padding) and **last row** (y==size.rows-1, controls bottom padding):

```zig
.extend => if (y == 0) {
    self.uniforms.padding_extend.up = !rowNeverExtendBg(row, ...);
} else if (y == self.cells.size.rows - 1) {
    self.uniforms.padding_extend.down = !rowNeverExtendBg(row, ...);
},
```

**Overlay usage of `semantic_prompt`**: `Overlay.zig:201-247` uses `row.semantic_prompt` to draw colored bars (prompt indicators) in the left margin. It iterates rows, identifies prompt + continuation spans, and draws highlight rectangles:

```zig
if (row_raw[y].semantic_prompt == .none) { y += 1; continue; }
// Find span of prompt + continuations
const start_y = y;
y += 1;
while (y < row_raw.len and row_raw[y].semantic_prompt == .prompt_continuation) { y += 1; }
// Draw highlight bar from start_y to y
```

### 4. wrap usage in rendering

**`wrap` is NOT used by the renderer's cell-building or GPU pipeline.** It does not affect pixel output.

The only place `wrap` appears in the rendering-adjacent code is `RenderState.string()` at `render.zig:785`:

```zig
if (!row.wrap) {
    try writer.writeAll("\n");
    // ...
}
```

This function serializes the viewport content to a UTF-8 string (used for text search, copy/paste). It uses `wrap` to decide whether to insert newlines between rows — if a row is soft-wrapped, no newline is emitted because the next row is a continuation of the same logical line.

**`wrap` does NOT affect**:
- Background color rendering
- Foreground glyph rendering
- Padding extension
- Font shaping
- Cursor rendering
- Overlay rendering

**`wrap_continuation`** is not read anywhere in the renderer or RenderState code.

## Raw References

- `src/terminal/page.zig:1866-1956` — `page.Row` packed struct definition (all fields)
- `src/terminal/render.zig:170-198` — `RenderState.Row` struct (wraps `page.Row` as `.raw`)
- `src/terminal/render.zig:481` — `row_rows[y] = page_rac.row.*` — full row copy into RenderState
- `src/terminal/render.zig:505` — `page_rac.row.managedMemory()` — uses `styled`, `hyperlink`, `grapheme` (optimization gate, not rendering)
- `src/terminal/render.zig:449,460` — `page_rac.row.dirty` — consumed and cleared during update, not passed to renderer
- `src/terminal/render.zig:785` — `row.wrap` used in `string()` for text serialization (search/copy)
- `src/renderer/generic.zig:2483` — `row_raws = row_data.items(.raw)` — how renderer accesses page.Row
- `src/renderer/generic.zig:2523-2530` — main rendering loop iterating rows
- `src/renderer/generic.zig:2756-2771` — `rowNeverExtendBg` call for padding extension (top/bottom rows only)
- `src/renderer/row.zig:8-63` — `neverExtendBg()` full implementation (reads `row.semantic_prompt`)
- `src/renderer/Overlay.zig:166` — `row.hyperlink` used to skip non-hyperlink rows
- `src/renderer/Overlay.zig:219,229` — `row.semantic_prompt` used for prompt bar overlay
