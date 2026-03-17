# Client-Side Rendering Pipeline: CellData Consumption and ghostty Integration

- **Date**: 2026-03-17
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: app client design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), two notes were removed from
Doc 04 §3.1 because they describe client implementation internals rather than
wire-observable protocol behavior. The protocol doc defines what CellData
contains (codepoint, style attributes, colors, wide-char flag); how the client
consumes it is an app concern. Both notes are transferred here in full.

Key context from PoC validation:

- `importFlatCells()` is **our own addition** to ghostty — it lives in
  `vendors/ghostty/src/terminal/render_export.zig` (added in PoC 08, not present
  in upstream ghostty). The client calls this to populate `RenderState` directly
  from wire `FlatCell` data without needing a `Terminal` instance.
- `rebuildCells()` and `drawFrame()` are **ghostty internal functions** — they
  are not part of the public C API. After `importFlatCells()` populates
  `RenderState`, ghostty's internal render thread calls these automatically via
  its timer/event loop.
- For production use, `importFlatCells()` (and `bulkExport()` on the server
  side) must be wrapped as C API functions in `ghostty.h`. See
  `docs/insights/ghostty-api-extensions.md` for the full PoC 06–08 API
  reference.

## Required Changes

1. **Document the client rendering pipeline**: When writing app client design
   docs, document the `FrameUpdate` rendering flow using the content in the
   Reference section below. The complete API specification (types, functions,
   performance measurements, known gaps) is in
   `docs/insights/ghostty-api-extensions.md` — reference it rather than
   duplicate it.

2. **Register `importFlatCells()` C API wrapping as a Phase 1 prerequisite**:
   `importFlatCells()` is currently a Zig-only function used in PoC. Before
   Phase 1 client implementation, it must be exposed as a C API function in
   `ghostty.h` (or libitshell3's abstraction layer).

## Summary Table

| Target Doc             | Section                   | Change Type | Source Resolution               |
| ---------------------- | ------------------------- | ----------- | ------------------------------- |
| App client design docs | Client rendering pipeline | Add         | owner review (v1.0-r12 cleanup) |
| App engineering reqs   | Phase 1 prerequisites     | Add         | owner review (v1.0-r12 cleanup) |

## Reference: Original Protocol Text (removed from Doc 04 §3.1)

### Normative block (removed)

```
> **Normative — CellData is SEMANTIC**: CellData carries semantic content
> (codepoint, style attributes, colors, wide-char flag) for populating a
> RenderState on the client. The client populates RenderState from wire CellData
> and delegates all rendering to the rendering pipeline (font shaping, atlas
> management, GPU buffer construction, draw). The client does NOT individually
> perform font shaping, glyph atlas lookup, or GPU buffer construction — these
> are internal to the rendering pipeline.
```

### Informative block (removed)

```
> **Informative — Reference implementation**: In ghostty, this pipeline
> corresponds to `importFlatCells()` (RenderState population from wire data)
> followed by `rebuildCells()` (font shaping and GPU buffer construction) and
> `drawFrame()` (Metal GPU rendering). See PoC 08 for validation.
```
