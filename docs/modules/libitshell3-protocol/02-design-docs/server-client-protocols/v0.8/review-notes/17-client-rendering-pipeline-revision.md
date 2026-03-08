# Client Rendering Pipeline: rebuildCells() Reuse Discovery

**Date**: 2026-03-08
**Raised by**: owner (based on PoC 08 GPU rendering verification)
**Severity**: HIGH
**Affected docs**: 04-input-and-renderstate.md (Section 3.2, Section 4.1 normative notes)
**Status**: open

---

## Problem

Doc 04 Section 3.2 ("Input Flow Summary") describes the client rendering path as:

```
Font subsystem (SharedGrid, Atlas)
    |
    v
Metal GPU render (CellText, CellBg shaders)
```

This implies the client manually resolves fonts, builds CellText/CellBg buffers, and drives the Metal shaders. The overview doc (03-render-state-protocol.md, before the PoC update) described a 6-step pipeline: receive → font resolution → glyph rasterization → GPU data assembly → Metal rendering.

**PoC 08 proved a fundamentally simpler path**: the client calls `importFlatCells()` to populate `RenderState` directly, then invokes ghostty's existing `rebuildCells()` which handles ALL of the font shaping, atlas management, and GPU buffer construction internally. The client does NOT manually construct CellText/CellBg.

```
PoC 08 Validated Pipeline:
wire → FlatCell[] → importFlatCells() → RenderState → rebuildCells() → Metal drawFrame()
```

## Analysis

### Architectural significance

This is the most significant finding from the PoC series. The client is NOT a custom renderer that consumes semantic cell data — it is a **thin RenderState populator** that delegates all rendering to ghostty's existing pipeline.

Implications:
1. **No custom font resolution code** on client — ghostty's `rebuildCells()` handles SharedGrid, CodepointResolver, Collection, Atlas
2. **No custom GPU buffer code** on client — ghostty's `rebuildCells()` builds CellText, CellBg, and manages Atlas textures
3. **No CellText/CellBg format dependency** in the protocol — the client never sees these GPU structs externally
4. **Client maintenance cost dramatically reduced** — when ghostty updates its renderer, the client automatically benefits

### Protocol impact

The protocol's normative notes should reflect that:
- CellData on the wire is **semantic data for RenderState population**, not GPU-ready data
- The existing normative note ("CellData is SEMANTIC") is correct in spirit but the surrounding description of the client pipeline is misleading
- The font subsystem independence section in the overview doc is still accurate but irrelevant — the client doesn't use font components directly

### Existing normative note alignment

Doc 04 §4.1 already says:
> "CellData is SEMANTIC: CellData carries semantic content [...] The client performs font shaping (HarfBuzz), glyph atlas lookup, and GPU buffer construction locally."

This should be revised: the client does not perform these steps individually. It populates RenderState and calls `rebuildCells()` which performs them internally.

## Proposed Change

1. **Doc 04 Section 3.2**: Update the client-side flow diagram to show:
   ```
   importFlatCells() → RenderState
         |
         v
   rebuildCells() (ghostty renderer — font shaping, atlas, GPU buffers)
         |
         v
   Metal drawFrame()
   ```

2. **Doc 04 §4.1 normative note**: Revise "CellData is SEMANTIC" to:
   > "CellData is SEMANTIC: CellData carries semantic content (codepoint, style attributes, colors, wide-char flag) for populating a RenderState on the client. The client calls `importFlatCells()` (or equivalent) to construct RenderState from CellData, then uses ghostty's existing `rebuildCells()` and `drawFrame()` pipeline for rendering. The client does NOT manually resolve fonts, build GPU buffers, or interact with CellText/CellBg structures."

3. **Add reference**: Note that this pipeline was validated by PoC 08 (actual Metal GPU rendering on macOS).

## Owner Decision

{Pending}

## Resolution

{Pending}
