# PreeditUpdate is a Control Channel Message, Not Frame Data

- **Date**: 2026-04-16
- **Source team**: implementation (Plan 9 owner review)
- **Source version**: ADR 00065, PoC 09 (import-plus-preedit)
- **Source resolution**: ADR 00065 — Preedit as GPU Overlay, Not Cell Data
- **Target docs**: `04-input-and-renderstate.md`, `05-cjk-preedit-protocol.md`
- **Status**: open

---

## Context

ADR 00065 retired Design Principle A1 ("preedit is cell data"). The protocol
spec may contain references to preedit being embedded in frame cell data
(FrameUpdate / RenderStateUpdate). This is architecturally impossible — ghostty
renders preedit only in GPU vertex buffers, never in terminal cell data.

The correct model: PreeditUpdate is a control channel message delivered via the
direct queue (Phase 1), independent of frame data delivered via the ring buffer
(Phase 2). The client receives them on the same socket but dispatches to
different APIs:
- Frame → `importFlatCells()` → RenderState
- Preedit → `ghostty_surface_preedit()` → GPU overlay

## Required Changes

1. **Clarify PreeditUpdate delivery**: PreeditUpdate (and PreeditClear) are
   control channel messages delivered via the direct queue, not via the ring
   buffer. They are independent of frame delivery — a preedit change does not
   require a new frame.

2. **Frame data never contains preedit**: FrameUpdate / RenderStateUpdate /
   FlatCell[] payloads contain terminal cell data only. Preedit text is never
   embedded in cell data. Any language suggesting preedit appears in frame
   cells should be removed.

3. **Client-side rendering note**: The protocol should note that the client
   calls `ghostty_surface_preedit()` with the UTF-8 text from PreeditUpdate.
   The renderer merges preedit with cell data at GPU render time via
   `rebuildCells()`. This is an implementation note, not a wire format change.

## Summary Table

| Target Doc                   | Section/Message       | Change Type | Source Resolution |
| ---------------------------- | --------------------- | ----------- | ----------------- |
| 04-input-and-renderstate.md  | Frame payload content | Clarify     | ADR 00065         |
| 05-cjk-preedit-protocol.md  | PreeditUpdate         | Clarify     | ADR 00065         |
| 05-cjk-preedit-protocol.md  | Delivery channel      | Clarify     | ADR 00065         |
