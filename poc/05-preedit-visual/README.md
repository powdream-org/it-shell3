# PoC: ghostty Preedit Visual Rendering

**Date**: 2026-03-07
**Triggered by**: Owner directive during protocol v0.7 review (review note 05)
**Question**: What does ghostty's Metal renderer actually draw for preedit text when called directly via `ghostty_surface_preedit()` without OS IME (NSTextInputClient)?

## Motivation

Review note 05 proposed a `lines[]` + `segments[]` preedit rendering model where the server pre-computes line wrapping, segment styling (`"reverse"`, `"underline"`), and display widths, and the client draws based on these instructions.

This design was based on source code analysis of ghostty's renderer, which suggested:
- Preedit uses foreground color + single underline, no background color
- Terminal cursor is completely suppressed during preedit (`if (preedit != null) break :cursor`)

However, source code reading alone could not confirm the actual visual output. A previous PoC (`poc/02-ime-ghostty-real`) validated the IME pipeline and text readback, but used `ghostty_surface_read_text()` (text extraction) — not visual observation of the Metal renderer output.

This PoC answers: **what does the human actually see?**

## What Was Tested

`preedit-visual.m` creates a **visible** NSWindow with a ghostty Metal surface, then calls `ghostty_surface_preedit()` directly (bypassing NSTextInputClient / OS IME entirely) with Korean preedit strings. Each scenario pauses for visual observation.

### Test scenarios

| # | Scenario | What was observed |
|---|----------|-------------------|
| 1 | Single jamo `ㄱ` | 2-cell block cursor |
| 2 | Full syllable `한` | 2-cell block cursor |
| 3 | Composition sequence `ㅎ` → `하` → `한` | Block cursor updates in-place, size stays 2-cell |
| 4 | Preedit after committed text (`한` + preedit `ㄱ`) | Block cursor at correct position after committed char |
| 5 | ASCII `hello` + preedit `ㅎ` | Block cursor at correct position after ASCII chars |
| 6 | Preedit clear → cursor restoration | Normal cursor reappears after preedit cleared |
| 7 | Live libhangul `r,k,s,k` → commit `간` + preedit `가` | Commit writes to terminal, new preedit appears after it |
| 8 | Vowel-only `ㅏ` | 2-cell block cursor (compatibility jamo U+314F is East Asian Wide) |
| 9 | `ab` + preedit `가` — alignment | Correct position after 1-cell ASCII chars |

### How it differs from `poc/02-ime-ghostty-real`

| | ime-ghostty-real | preedit-visual |
|---|---|---|
| Window | Off-screen (`orderBack:nil`) | **Visible** (`makeKeyAndOrderFront:nil`) |
| Verification | `ghostty_surface_read_text()` — text content | **Human visual observation** — Metal renderer output |
| Purpose | IME pipeline correctness | Preedit **rendering** behavior |
| NSRunLoop | Not used | Used — allows Metal to render frames |

## Build

```sh
./build.sh
```

Requires:
- Pre-built `libghostty.a` from `~/dev/git/powdream/cjk-compatible-terminal-for-ipad/ghostty/macos/GhosttyKit.xcframework/`
- libhangul source at `../ime-key-handling/libhangul/`

## Findings

### 1. Preedit renders as block cursor, not underline

**Contradicts source code analysis.** The analysis of `ghostty/src/renderer/generic.zig:addPreeditCell()` suggested foreground color + single underline with no background. Actual rendering shows a **solid block cursor** over the preedit character.

All Korean characters (jamo and syllable) render with the same block cursor style:
- `ㄱ`, `ㅏ`, `ㅎ` — 2-cell block cursor
- `가`, `하`, `한` — 2-cell block cursor

### 2. Terminal cursor is NOT suppressed during preedit

**Contradicts source code analysis.** The analysis found `if (preedit != null) break :cursor` in `generic.zig:2445`, suggesting cursor suppression. Actual observation: a **vertical bar cursor blinks** alongside the preedit block cursor.

Two visual elements are present simultaneously:
- Block cursor: covers the preedit character (2-cell wide)
- Vertical bar cursor: blinking, positioned at or near the preedit

### 3. All Korean preedit characters are 2-cell wide

Both compatibility jamo (U+3131–U+3163) and precomposed syllables (U+AC00–U+D7A3) are East Asian Wide. ghostty correctly renders all of them as 2-cell block cursors. There is no 1-cell Korean preedit case.

### 4. ghostty handles positioning automatically

`ghostty_surface_preedit()` places the preedit at the current terminal cursor position. No external position calculation is needed. After committed text (`한`), the cursor advances and the next preedit appears at the correct position.

### 5. Preedit clearing restores normal cursor

Calling `ghostty_surface_preedit(surface, NULL, 0)` removes the block cursor overlay and the normal terminal cursor reappears in its previous style.

## Impact on Design

### Protocol simplification

The `lines[]` + `segments[]` model from review note 05 is unnecessary. ghostty's built-in preedit rendering handles:
- Character positioning (at terminal cursor)
- Width calculation (2-cell for CJK)
- Visual decoration (block cursor)
- Cursor interaction (vertical bar blinking alongside)

**v1 PreeditUpdate reduces to a single field:**

```
preedit_text: ?[]const u8   // UTF-8 string, null = clear
```

Client action:
- `preedit_text != null` → `ghostty_surface_preedit(surface, text, len)`
- `preedit_text == null` → `ghostty_surface_preedit(surface, NULL, 0)`

**Removed from protocol:**
- `display_width` — ghostty calculates
- `cursor_x`, `cursor_y` — ghostty positions at terminal cursor
- `lines[]` — ghostty handles line wrapping
- `segments[]` — ghostty handles decoration
- `composition_state` — no consumer (see `poc/04-libhangul-states`)

### v2 candidate window anchor

For Japanese/Chinese candidate selection windows, the only additional data needed is the **anchor position in cell coordinates** `{row, col}`. The server knows cursor position from libghostty-vt terminal state. The client converts cell → pixel using `ghostty_surface_size()` cell dimensions.

### v2 segment styling limitation

Japanese IME per-segment styling (reverse for converting clause, underline for unconverted) cannot be supported through the current `ghostty_surface_preedit()` API, which accepts only a flat UTF-8 string. This would require either a ghostty API extension or a separate overlay mechanism. Deferred to v2.

## Known Limitations

- Visual observation only — no programmatic pixel-level verification of rendering style
- Tested with pre-built `libghostty.a` from it-shell v1 (may differ from latest ghostty)
- Did not test non-Korean preedit (Japanese kana, Chinese pinyin)
- Did not test preedit wrapping at line boundary (all test strings fit on one line)

## See Also

- `poc/04-libhangul-states/` — composition state observability PoC
- `poc/02-ime-ghostty-real/` — IME pipeline + text readback PoC
- Protocol v0.7 review note: `review-notes/05-preedit-rendering-model.md`
