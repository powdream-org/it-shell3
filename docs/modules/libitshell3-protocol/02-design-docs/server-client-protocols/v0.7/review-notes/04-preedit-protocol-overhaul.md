# Preedit Protocol Overhaul

**Date**: 2026-03-06 (initial), 2026-03-07 (expanded after visual PoC)
**Raised by**: owner
**Severity**: CRITICAL
**Affected docs**: doc 05 (CJK Preedit Protocol), doc 04 (Input and RenderState)
**Status**: open
**Cross-team**: IME Interface Contract v0.6 `cross-team-requests/01-protocol-composition-state-removal.md`

---

## Problem

Three related issues discovered during protocol v0.7 owner review. They must be applied together because they share the same root cause: the current preedit model treats preedit as metadata, but preedit should be cell data.

### Issue A: `composition_state` has no consumer

`composition_state` is a string field in PreeditUpdate (0x0401) and PreeditSync (0x0403). No component uses it for rendering, branching, or decision-making. Additionally, the documented state values have factual errors confirmed by PoC (`poc/04-libhangul-states/probe.c`, research `05-libhangul-composition-states.md`):

1. `ko_vowel_only` IS reachable in 2-set (doc claims it is not)
2. `ko_double_tail` not distinguishable from `ko_syllable_with_tail` via libhangul public API
3. 3-set keyboards produce `(cho=0, jung=0, jong=1)` — no corresponding constant

### Issue B: Preedit rendering model is wrong

The FrameUpdate preedit JSON (`cursor_x`, `cursor_y`, `text`, `display_width`) assumes the client renders preedit as a separate overlay. A visual PoC (`poc/05-preedit-visual/`, research `06-ghostty-preedit-rendering.md`) proved this is incorrect:

- ghostty renders preedit as a **2-cell block cursor** (not underline/reverse as source analysis suggested)
- Terminal cursor is **not suppressed** during preedit (vertical bar blinks alongside)
- ghostty handles positioning and width automatically

In the daemon-client architecture (research `07-ghostty-preedit-cell-serialization.md`):
- **Server** calls `ghostty_surface_preedit()` on its own surface
- Preedit is an overlay in ghostty's renderer state, separate from the terminal grid
- Server **injects preedit cells into frame cell data** when serializing FrameUpdate
- **Client** renders cells — does not know what is preedit, never calls `ghostty_surface_preedit()`

Therefore: preedit is **cell data**, delivered via I/P-frames through the ring buffer. The separate FrameUpdate preedit JSON section and dual-channel design are unnecessary.

### Issue C: Ring buffer bypass is unnecessary

Resolution 17 (`frame_type=0`, preedit bypass buffer) existed because preedit was a separate JSON section in FrameUpdate. With preedit as cell data in I/P-frames, bypass creates two delivery paths for the same thing (cells), causing ordering and consistency issues. Coalescing Tier 0 (IME input) already ensures immediate delivery.

## Proposed Changes

### 1. Remove `composition_state` (doc 05)

- Remove `composition_state` field from PreeditUpdate (Section 2.2) and PreeditSync (Section 2.4)
- Remove Section 3 entirely (Korean Composition State Machine — Sections 3.1 through 3.4, ~130 lines)
- Remove all `composition_state` references throughout doc 05
- Update Section 15 (Open Questions) — remove Q1 (Japanese/Chinese composition states)

### 2. Remove FrameUpdate preedit JSON section (doc 05 Section 1)

Current:
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

Remove entirely. Preedit is delivered as cell data in I/P-frames.

### 3. Remove dual-channel design (doc 05 Section 1)

Current: "FrameUpdate JSON (rendering) + PreeditUpdate (metadata)" with "Clients MUST use FrameUpdate's preedit JSON for rendering."

Replace with: Single path. Preedit rendering is through cell data in I/P-frames. PreeditUpdate (0x0401) is lifecycle/metadata only (composing owner, session tracking, multi-client coordination).

### 4. Remove cursor/width fields from preedit messages (doc 05)

| Message | Remove |
|---------|--------|
| PreeditStart (0x0400) | `cursor_x`, `cursor_y` |
| PreeditUpdate (0x0401) | `cursor_x`, `cursor_y`, `display_width` |
| PreeditSync (0x0403) | `cursor_x`, `cursor_y`, `display_width` |

Server's ghostty surface handles positioning and width.

### 5. Remove Section 10.1 cursor style rules (doc 05)

Remove "server MUST set cursor.style to block" and "client MUST NOT override cursor style." Preedit cell decoration is determined by ghostty's renderer.

### 6. Remove ring buffer bypass (doc 04 + doc 05)

| Item | Location |
|------|----------|
| `frame_type=0` (P-metadata) | doc 04 Section 4.1 |
| Resolution 17 (preedit bypass buffer) | doc 04 design-resolutions |
| "per-client preedit bypass buffer" concept | doc 04, doc 05 |
| Section 8.2 Rule 2 (preedit bypass) | doc 05 |
| Section 8.4 (paused client preedit bypass) | doc 05 |
| Resolution 20 reference (dedicated messages bypass) | doc 05 Section 14 |

`frame_type` values after removal:

| Value | Name |
|-------|------|
| 0 | P-partial |
| 1 | I-frame |
| 2 | I-unchanged |

### 7. Resulting PreeditUpdate (0x0401)

```json
{
  "pane_id": 1,
  "preedit_session_id": 42,
  "text": "한"
}
```

Lifecycle/metadata only. Not used for rendering.

### 8. v2 candidate window extension (additive)

```json
{
  "pane_id": 1,
  "preedit_session_id": 42,
  "text": "にほんご",
  "anchor": {"row": 10, "col": 5}
}
```

`anchor` provides cell coordinates for candidate window positioning. Client converts to pixels via `ghostty_surface_size()` cell dimensions. Per-segment styling (Japanese) deferred to v2 with ghostty API extension.

### 9. Cross-team: IME Interface Contract v0.6

Filed at `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.6/cross-team-requests/01-protocol-composition-state-removal.md`:
- Remove `ImeResult.composition_state` field
- Remove `CompositionStates` struct from `HangulImeEngine`
- Remove `composition_state` column from scenario matrix
- Remove `composition_state` memory model note
- Remove composition-state naming convention
- Update `setActiveInputMethod` return value examples

## Owner Decision

Owner initiated this review and revised after visual PoC (2026-03-07). Decision: preedit is cell data. Remove `composition_state`, FrameUpdate preedit JSON, dual-channel, cursor/width fields, Section 3, Section 10.1, and ring buffer bypass.

## Resolution

{Pending — to be applied in the next revision.}
