# Research: ghostty Preedit and Cell Serialization

**Date**: 2026-03-07
**Source**: ghostty (https://github.com/ghostty-org/ghostty)
**Git SHA (source reading)**: `2502ca294efe5aa9722c36e25b2252b0150054e9` (reference repo `~/dev/git/references/ghostty/`)
**Git SHA (pre-built binary)**: `76b7704783e411d035c6ab3036ecaa0454e3f7de` (it-shell v1 fork, `GhosttyKit.xcframework/macos-arm64_x86_64/libghostty.a`)
**Cross-reference**: Research 06 (ghostty preedit rendering), `poc/02-ime-ghostty-real/FINDINGS.md`

---

## Context

In the daemon-client architecture, the server owns the ghostty surface and serializes RenderState (cell data) into FrameUpdate for the client. The client renders cells without knowing which cells are preedit. This research documents how ghostty separates preedit from the terminal grid internally, and what that means for FrameUpdate serialization.

## Source Files Analyzed

- `src/renderer/State.zig:46-123` — `Preedit` struct, separate from terminal grid
- `src/renderer/generic.zig:3313-3353` — `addPreeditCell()`: overlay rendering
- `src/renderer/generic.zig:2445-2468` — cursor suppression/modification during preedit
- `src/Surface.zig:2477-2546` — `preeditCallback()`: UTF-8 → codepoints + width

## Findings

### 1. Preedit storage is separate from the terminal grid

ghostty stores preedit in `renderer.State.preedit`:
```zig
pub const Preedit = struct {
    codepoints: []const Codepoint,
    pub const Codepoint = struct {
        codepoint: u21,
        wide: bool,
    };
};
```

The terminal grid (`Terminal.Screen`) has no preedit data. Preedit is purely a renderer-side overlay.

### 2. Preedit cells are added during rendering, not during VT processing

In `generic.zig`, `addPreeditCell()` is called during the render pass. It writes cells at the current cursor position with:
- The preedit character's codepoint
- Foreground color from the terminal's current color scheme
- Underline decoration (SGR 4)
- Width from `unicode.table.get(cp).width`

These cells exist only in the renderer's draw list, not in the terminal grid's cell storage.

### 3. Implication for FrameUpdate serialization

When the server serializes cell data for FrameUpdate:
- Reading from `Terminal.Screen` gives grid cells only — no preedit
- The server MUST inject preedit cells into the serialized cell data at the cursor position
- The server knows the preedit text (from `libitshell3-ime`) and the cursor position (from `Terminal.Screen.cursor`)
- Cell attributes for preedit cells (foreground color, decoration) should match what ghostty's renderer would produce

### 4. ghostty_surface_preedit() does NOT modify the grid

`ghostty_surface_preedit(surface, text, len)` stores the preedit in the renderer state. It does not:
- Write to any terminal grid cell
- Move the terminal cursor
- Trigger any VT sequence processing
- Modify the dirty row bitmap of the terminal grid

This means calling `ghostty_surface_preedit()` alone will NOT cause the preedit to appear in `ghostty_surface_read_text()` output (confirmed by `poc/02-ime-ghostty-real` — readback reads grid, not overlay).

### 5. macOS system IME overlay is separate from ghostty

When using ghostty's macOS app with the system Korean IME, the green-background preedit overlay is drawn by macOS via `NSTextInputClient`, NOT by ghostty's Metal renderer. ghostty's own preedit rendering (block cursor) is different from the macOS system overlay.

In our architecture, we bypass the system IME entirely (native Zig IME), so the macOS overlay never appears. Preedit rendering is entirely through the server's ghostty surface → cell serialization → client rendering path.

## Trade-offs

- **Server must explicitly inject preedit into cell data**: This adds complexity to the FrameUpdate serialization path, but keeps the client completely preedit-unaware.
- **Preedit cell attributes must be determined server-side**: The server must decide the foreground color, decoration style, and width for preedit cells. These should match the terminal's current color scheme for visual consistency.
- **Dirty tracking for preedit**: Since preedit is not in the grid, preedit changes do not naturally trigger dirty row marking. The server must mark the cursor row as dirty when preedit changes.

## Known Limitations

- Did not verify the exact cell attributes (foreground/background, decoration flags) that ghostty uses for preedit cells at the binary level.
- Did not test how ghostty handles preedit at the rightmost column (potential line-wrapping for wide characters).
- Analysis based on source code reading; actual cell serialization path depends on implementation.
