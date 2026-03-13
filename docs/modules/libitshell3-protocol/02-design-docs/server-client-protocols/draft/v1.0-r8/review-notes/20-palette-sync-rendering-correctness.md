# Palette/Colors Sync Is Required for Rendering Correctness

**Date**: 2026-03-08
**Raised by**: owner (based on PoC 08 + ghostty renderer source analysis)
**Severity**: MEDIUM
**Affected docs**: 04-input-and-renderstate.md (Section 4.2 colors field, Section 7.2 I-frame)
**Status**: open

---

## Problem

Doc 04 §4.2 presents the `colors` JSON metadata field as optional ("only changed or required fields are included"). The current wording suggests colors are informational metadata similar to cursor or mouse state.

PoC 08 and ghostty source analysis reveal that `colors` (specifically `default_background` and the 256-palette) are **required for rendering correctness**, not optional metadata:

1. **`neverExtendBg()` in `renderer/row.zig`**: Compares each cell's background against `default_background`. If they match, background is NOT extended into padding. Without the correct `default_background`, this comparison fails and padding rendering is wrong.

2. **Palette-indexed cells**: CellData uses `PackedColor` with `tag=0x01` (palette index). The client must resolve palette[index] → RGB for rendering. Without the palette, palette-colored cells render incorrectly.

3. **Default color cells**: CellData uses `PackedColor` with `tag=0x00` (default). The client must know `default_fg` and `default_bg` to render these cells. Without them, the client can only guess.

## Analysis

### Current behavior in PoC

PoC 08 initialized `RenderState.colors` from defaults (hard-coded white fg, black bg, standard 256-palette). This worked because the test data used explicit RGB colors. Real terminal sessions with palette colors or custom themes would render incorrectly.

### I-frame completeness

Doc 04 §4.1 states I-frames are "self-contained keyframes." If `colors` is omitted from an I-frame, it is NOT self-contained — a client that joins mid-session and receives only this I-frame will have wrong colors.

### Frequency of change

Terminal palette changes are rare (only OSC 10/11/12/4 sequences). The cost of including `colors` in every I-frame is:
- `fg` + `bg`: 6 bytes (2 × [r,g,b])
- `cursor_color`: 3 bytes (optional)
- `palette`: 768 bytes (256 × 3 bytes) — significant but sent only once or on change

## Proposed Change

1. **Elevate `colors` to REQUIRED in I-frames**: I-frames (`frame_type=1`) MUST include the `colors` section with at least `fg` and `bg`. The full `palette` MUST be included in the first I-frame sent to a newly attached client and on any I-frame where palette has changed.

2. **Add normative note to §4.2**:
   > "Normative note — Colors are rendering-critical: The `colors` section is not informational metadata. The client's renderer uses `bg` as the `default_background` for padding extension decisions and as the fallback for cells with `PackedColor tag=0x00`. Palette entries are required to resolve cells with `PackedColor tag=0x01`. I-frames MUST include `fg` and `bg`. The full `palette` MUST be included at least on initial attach and when any entry changes."

3. **P-frame palette_changes**: The existing `palette_changes` field (delta updates) is sufficient for P-frames. No change needed.

## Owner Decision

{Pending}

## Resolution

{Pending}
