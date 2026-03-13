# PoC 06: RenderState Extraction

**Date**: 2026-03-08
**Triggered by**: Protocol v0.8 design — validating the server-client RenderState split point
**Question**: Can we extract terminal cell data (codepoint + resolved style) from ghostty's RenderState without Surface/App/PTY?

## Motivation

it-shell3's architecture splits the rendering pipeline between server (daemon) and client (app):

```
Server: Terminal → RenderState.update()  →  [serialize over wire]
Client:                                      [deserialize] → GenericRenderer → GPU
```

The protocol v0.8 design assumes cell data can be extracted from ghostty's internal RenderState and transmitted to the client. This PoC validates the extraction half — proving that Terminal and RenderState can operate headlessly (without Surface, App, or PTY) and that resolved cell data is accessible.

## What Was Tested

`poc/extract_renderstate.zig` creates a Terminal directly via `Terminal.init(alloc, .{ .cols = 80, .rows = 24 })`, feeds three types of content, snapshots via `RenderState.update()`, and iterates over extracted cells.

### Test scenarios

| # | Content | What was verified |
|---|---------|-------------------|
| 1 | ASCII `"Hello, it-shell3!"` | Codepoints extracted correctly, no styling |
| 2 | Korean `한글 테스트` (pre-composed Hangul) | Wide flag = `.wide` for all 5 characters, codepoints correct |
| 3 | SGR styled `"Bold Red Text"` (bold + RGB fg) | `style.flags.bold = true`, `style.fg_color = .rgb`, 11 styled cells |

### Output

```
=== PoC 06: RenderState Extraction ===
Terminal created: 80x24

RenderState updated. dirty=full, rows=24, cols=80

--- Row-by-row extraction ---
Row  0 [dirty=Y]: "Hello, it-shell3!"
Row  1 [dirty=Y]: "한글 테스트"
Row  2 [dirty=Y]: "Bold Red Text"
  [ 0] U+0042 fg=rgb bold=true wide=narrow
  [ 1] U+006F fg=rgb bold=true wide=narrow
  ...
  [12] U+0074 fg=rgb bold=true wide=narrow

=== Extraction Summary ===
Total non-empty cells: 32
Total styled cells:    11
Total wide cells:      5
Cursor position: (13, 2)
Background color: RGB(0, 0, 0)

=== PoC 06 PASSED ===
```

## Build

```sh
cd poc/06-renderstate-extraction/vendors/ghostty
~/.local/share/mise/installs/zig/0.15.2/zig build poc
```

Requires:
- Zig 0.15.2 (ghostty main HEAD requires this version)
- ghostty clone at `vendors/ghostty/` (main HEAD, commit `472b926a4`)

### How it works

The PoC is built as a custom executable inside ghostty's build system. `build.zig` has an added `poc` step that creates an executable importing the `ghostty-vt` Zig module (internal API, not the C API).

Modified files in the ghostty clone:
- `build.zig` — added `poc` build step (+18 lines)
- `poc/extract_renderstate.zig` — new file (PoC source)

## Findings

### 1. Terminal operates fully headless

`Terminal.init()` requires only an allocator and `Options { .cols, .rows }`. No Surface, App, PTY, or app runtime needed. This confirms that the server daemon can own Terminal instances directly.

```zig
var term = try Terminal.init(alloc, .{ .cols = 80, .rows = 24 });
```

### 2. RenderState.update() works standalone

`RenderState.update()` takes only an allocator and a `*Terminal`. No mutex, no renderer, no GPU context required. The server can snapshot terminal state independently.

```zig
var render_state: RenderState = .empty;
try render_state.update(alloc, &term);
```

### 3. Resolved styles are accessible per-cell

After `update()`, each `RenderState.Cell` contains:
- `raw: page.Cell` — packed u64 with codepoint (u21), wide flag (u2), style_id (u16)
- `style: Style` — **resolved** style (fg/bg Color union, Flags packed u16)
- `grapheme: []const u21` — extra codepoints for grapheme clusters

Style resolution happens during `update()` — the caller does not need access to the page's style set. Colors remain as tagged unions (`none | palette(u8) | rgb(RGB)`); final RGB resolution against the palette is deferred to the renderer.

### 4. Row-level dirty tracking works

`RenderState.dirty` is `.full` on first update, `.partial` on subsequent updates where only some rows changed. Per-row `dirty: bool` flags indicate which rows need re-rendering. This maps directly to the protocol's incremental update design.

### 5. Wide character detection is correct

All Korean Hangul characters (both compatibility jamo and precomposed syllables) are detected as `cell.wide == .wide`, confirming that ghostty's width tables handle CJK correctly. Each wide character occupies 2 cell positions (the next cell is `spacer_tail`).

### 6. No new C API was added

This PoC uses the `ghostty-vt` Zig module directly (internal API). For actual it-shell3 integration via `libghostty.a` + `ghostty.h`, C API functions would need to be added to expose RenderState data. Two design options from research:

| Approach | Description | Trade-off |
|----------|-------------|-----------|
| Lock/Get/Unlock | Lock mutex, iterate cells, unlock | Flexible but risk of long lock |
| Bulk copy | Copy all cells to flat buffer in one call | Simple, minimal lock time, extra memory |

## Impact on Design

### Confirmed: RenderState is the correct cut point

The data available in `RenderState.Cell` (codepoint + resolved style + wide flag + dirty tracking) is exactly what the protocol needs. The cut between `RenderState.update()` (server) and `GenericRenderer.rebuildCells()` (client) is clean:

- **Server produces**: codepoint, resolved fg/bg/underline Color, style flags (bold/italic/etc.), wide flag, dirty flags, cursor state, terminal colors
- **Client consumes**: same data → font shaping (HarfBuzz) → GPU cells → Metal draw

### Color resolution is split

Styles are stored with Color tagged unions (`none | palette | rgb`), not final RGB values. The server must transmit the palette alongside cell data so the client can resolve `palette(u8)` → `RGB`. The global terminal colors (default bg/fg, cursor color) are in `render_state.colors`.

### Next step: client-side re-injection (PoC 07)

The extraction side is validated. The next PoC should prove the reverse: feeding deserialized cell data into a client-side Terminal or RenderState, then running `GenericRenderer.rebuildCells()` to produce GPU-ready data.

Research findings suggest **Option A** (populate a client-side Terminal, let `update()` + `rebuildCells()` work normally) is the most architecturally compatible path.

## Known Limitations

- Uses internal Zig module API, not the C API boundary
- Terminal content was written via `Terminal.print()` (one codepoint at a time), not bulk cell population
- Did not test grapheme clusters (multi-codepoint characters)
- Did not test alternate screen, scrollback, or selection
- Did not test incremental updates (second `update()` call after partial changes)
- ghostty main HEAD (`472b926a4`) — API may change

## See Also

- `poc/05-preedit-visual/` — preedit rendering behavior PoC
- `poc/02-ime-ghostty-real/` — IME pipeline + text readback PoC
- Protocol v0.8: `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/draft/v1.0-r8/04-input-and-renderstate.md`
