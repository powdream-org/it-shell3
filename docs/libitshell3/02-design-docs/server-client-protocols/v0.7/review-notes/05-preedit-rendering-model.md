# Redesign Preedit Rendering Model

**Date**: 2026-03-06
**Raised by**: owner
**Severity**: CRITICAL
**Affected docs**: doc 05 (CJK Preedit Protocol), doc 04 (Input and RenderState)
**Status**: open

---

## Problem

The current FrameUpdate preedit JSON uses a flat model:

```json
{
  "preedit": {
    "active": true,
    "cursor_x": 5,
    "cursor_y": 10,
    "text": "한",
    "display_width": 2
  }
}
```

This model has several issues:

1. **No multi-line support**: Japanese preedit can be sentence-length (e.g., 28+ cells). If `cursor_x` is near the right edge, the preedit wraps to the next line. A single `(cursor_x, cursor_y, display_width)` cannot represent wrapped preedit.

2. **Line wrapping requires width computation**: Wrapping at line boundaries must handle 2-cell CJK characters that cannot be split mid-character, multi-codepoint emoji (ZWJ sequences, flag emoji), and grapheme cluster boundaries. The server (libghostty-vt) already has this logic. Forcing the client to duplicate it creates inconsistency risk.

3. **No segment styling**: Japanese IME needs per-segment decoration (reverse for converting clause, underline for unconverted text). Korean preedit needs a block cursor with blinking — which is also a segment style. The current model has no mechanism for this.

4. **`display_width` is redundant with segments**: If segments carry start/len (in cells), the total width is derivable. `display_width` as a separate field duplicates information.

5. **Cursor style coupling**: Section 10.1 requires the server to override `cursor.style` to block during composition, and mandates clients MUST NOT override cursor style. This couples preedit rendering to the terminal cursor section. Preedit styling should be self-contained in the preedit section.

## Analysis

### Design principles established

- **Server owns all width/layout computation**: The server has libghostty-vt with UAX#11, grapheme cluster, and emoji sequence handling. The client receives pre-computed rendering instructions and draws.
- **Client draws, does not compute**: No UAX#11, no line wrapping, no width calculation on the client side for preedit.
- **v1 structure must support v2 extension additively**: Adding Japanese/Chinese should not require breaking changes to the preedit JSON schema.

### ANSI terminal rendering analysis

Korean "block cursor over composing character" and Japanese "reverse video on converting clause" are the same SGR effect — **reverse** (SGR 7). ANSI terminals do not distinguish thin vs thick underlines in standard SGR. The segment style vocabulary can be minimal:

- `"reverse"`: foreground/background swap (Korean composing, Japanese active clause)
- `"underline"`: SGR 4 underline (Japanese unconverted text)

### Terminal cursor and preedit interaction

The preedit overlay is NOT in the terminal grid. The terminal cursor (`FrameUpdate.cursor`) does not know the width of preedit characters because they are not grid cells. Therefore, the terminal cursor alone cannot handle preedit block cursor rendering — segments must carry width information.

However, cursor **blinking** is a terminal-native feature. The server can position the terminal cursor at the preedit location with `cursor.style=block, cursor.blinking=true` to provide blinking, while segments handle the decoration/width.

## Proposed Change

### v1 FrameUpdate preedit JSON

```json
{
  "preedit": {
    "active": true,
    "lines": [
      { "x": 5, "y": 10, "text": "한" }
    ],
    "segments": [
      { "start": 0, "len": 2, "style": "reverse" }
    ]
  }
}
```

- `lines[]`: Server pre-computes line breaks. Each entry has `x`, `y` (screen coordinates) and `text` (UTF-8 string for that line). v1 Korean always has exactly 1 entry.
- `segments[]`: Rendering decoration. `start` and `len` are in cell units. `style` is an SGR-mapped string. v1 Korean always has exactly 1 entry with `"reverse"`.
- Terminal cursor: Server positions `cursor.x/y` at preedit location with `style=block, blinking=true` for blinking effect during composition. Restored on PreeditEnd.

### v2 extensions (additive, all optional)

```json
{
  "preedit": {
    "active": true,
    "lines": [
      { "x": 70, "y": 10, "text": "にほんご" },
      { "x": 0,  "y": 11, "text": "をべんきょう" }
    ],
    "segments": [
      { "start": 0, "len": 8, "style": "reverse" },
      { "start": 8, "len": 12, "style": "underline" }
    ],
    "cursor": { "x": 0, "y": 11 }
  },
  "candidates": {
    "items": ["日本語を", "二本後を"],
    "selected": 0,
    "page": 1,
    "total_pages": 3
  }
}
```

- `lines[]` grows to multiple entries (server handles wrapping with 2-cell/emoji boundary awareness).
- `segments[]` grows to multiple entries with mixed styles.
- `preedit.cursor`: In-preedit cursor position for Japanese clause navigation (separate from terminal cursor).
- `candidates`: Candidate window data (separate top-level object alongside preedit).

### Removals

- Remove `cursor_x`, `cursor_y`, `display_width` flat fields from preedit JSON.
- Remove Section 10.1 cursor style rules ("server MUST set cursor.style to block", "client MUST NOT override cursor style"). Replace with: server positions terminal cursor at preedit location for blinking; preedit decoration is defined by `segments`.
- Remove `display_width` from PreeditUpdate (Section 2.2) — superseded by `segments[].len`.

## Owner Decision

Owner initiated this review. Decision: adopt `lines[]` + `segments[]` model from v1.

## Resolution

{Pending — to be applied in the next revision.}
