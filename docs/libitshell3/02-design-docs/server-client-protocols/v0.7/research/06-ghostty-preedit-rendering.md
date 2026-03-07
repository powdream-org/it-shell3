# Research: ghostty Preedit Rendering

**Date**: 2026-03-07
**Source**: ghostty (https://github.com/ghostty-org/ghostty)
**Git SHA (source reading)**: `2502ca294efe5aa9722c36e25b2252b0150054e9` (reference repo `~/dev/git/references/ghostty/`)
**Git SHA (pre-built binary)**: `76b7704783e411d035c6ab3036ecaa0454e3f7de` (it-shell v1 fork, `GhosttyKit.xcframework/macos-arm64_x86_64/libghostty.a`)
**Verified by**: `poc/preedit-visual/preedit-visual.m`

---

## Context

Protocol doc 05 proposed a preedit rendering model where the server sends `lines[]`, `segments[]`, and style information, and the client draws the preedit overlay. This research investigates what ghostty actually renders when `ghostty_surface_preedit()` is called, to determine whether custom rendering is needed.

## Source Files Analyzed (code reading)

- `src/Surface.zig:2477-2546` — `preeditCallback()`: receives UTF-8, converts to codepoints with `unicode.table.get(cp).width`
- `src/renderer/generic.zig:3313-3353` — `addPreeditCell()`: renders preedit cells
- `src/renderer/generic.zig:2445-2468` — cursor rendering during preedit
- `src/renderer/State.zig:46-123` — `Preedit` struct: `codepoints: []const Codepoint` where `Codepoint = { codepoint: u21, wide: bool }`
- `src/renderer/cursor.zig:47-50` — cursor style during preedit
- `include/ghostty.h:1091` — `void ghostty_surface_preedit(ghostty_surface_t, const char*, uintptr_t)`

## Source Code Analysis vs Actual Rendering

Source code reading suggested:
- `addPreeditCell()` uses foreground color + single underline, no background color
- Cursor is suppressed during preedit (`if (preedit != null) break :cursor`)

**The visual PoC contradicts both findings.**

## Findings (from visual PoC)

### 1. Preedit renders as block cursor

Actual rendering shows a **solid block cursor** over the preedit character. Not underline, not reverse video, not foreground-only. All Korean characters tested:

| Preedit text | Cell width | Rendering |
|---|---|---|
| `ㄱ` (U+3131) | 2-cell | 2-cell block cursor |
| `ㅏ` (U+314F) | 2-cell | 2-cell block cursor |
| `ㅎ` (U+314E) | 2-cell | 2-cell block cursor |
| `가` (U+AC00) | 2-cell | 2-cell block cursor |
| `하` (U+D558) | 2-cell | 2-cell block cursor |
| `한` (U+D55C) | 2-cell | 2-cell block cursor |

### 2. Terminal cursor is NOT suppressed during preedit

A **vertical bar cursor blinks** alongside the preedit block cursor. Two visual elements are simultaneously present:
- Block cursor: covers the preedit character
- Vertical bar cursor: blinking, at or near the preedit position

This contradicts the source code path `if (preedit != null) break :cursor` which suggests cursor suppression. The discrepancy is likely because the source reading was done on upstream ghostty (`2502ca29`) while the PoC binary was built from the it-shell v1 fork (`76b77047`) — these are different commits with potentially different renderer behavior.

### 3. All Korean preedit characters are 2-cell wide

Both compatibility jamo (U+3131-U+3163) and precomposed syllables (U+AC00-U+D7A3) are East Asian Wide (UAX #11 property W). ghostty's `unicode.table.get(cp).width` returns 2 for all of them. There is no 1-cell Korean preedit case.

### 4. ghostty handles positioning automatically

`ghostty_surface_preedit()` places the preedit overlay at the current terminal cursor position. No external position calculation is needed. Tested sequences:
- After committed Korean text: correct position
- After ASCII text: correct position
- After line break (Enter): correct position on new line

### 5. Preedit clearing restores normal cursor

`ghostty_surface_preedit(surface, NULL, 0)` removes the block cursor overlay. The normal terminal cursor reappears in its previous style.

### 6. ghostty_surface_preedit() API

```c
void ghostty_surface_preedit(ghostty_surface_t surface, const char* utf8, uintptr_t len);
```

- Input: flat UTF-8 string. No styling, no segment information, no width hints.
- Clear: pass `NULL, 0`.
- ghostty does NOT auto-clear preedit on `ghostty_surface_key()`. Explicit clear required.

### 7. Preedit is NOT in the terminal grid

In ghostty's internal architecture, preedit is stored in `renderer.State.preedit` — separate from `Terminal.Screen` (the cell grid). During rendering, `addPreeditCell()` adds preedit cells as an overlay on top of the grid cells. The preedit characters are NOT written into the terminal grid.

This means when serializing the terminal grid for FrameUpdate (RenderState protocol), the server must explicitly include preedit cells in the cell data — they will not appear naturally from the grid state alone.

## Trade-offs

- **ghostty's built-in preedit rendering is sufficient for Korean v1**: block cursor, automatic positioning, correct 2-cell width.
- **No per-segment styling API**: `ghostty_surface_preedit()` accepts only a flat string. Japanese IME per-segment decoration (reverse for active clause, underline for unconverted) cannot be expressed through this API. Would require ghostty API extension for v2.
- **No candidate window support**: ghostty has no API for candidate window positioning. v2 would need to track cursor cell position server-side and send it to the client as an anchor.

## Known Limitations

- Source code analysis (`2502ca29`, upstream) and PoC binary (`76b77047`, it-shell v1 fork) are different commits. Rendering behavior differences between the two are expected.
- Visual observation only — no programmatic pixel-level verification.
- Did not test non-Korean preedit (Japanese kana, Chinese pinyin).
- Did not test preedit wrapping at line boundary.
