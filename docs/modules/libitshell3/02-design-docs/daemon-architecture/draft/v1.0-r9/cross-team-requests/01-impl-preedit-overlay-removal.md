# Remove preedit_overlay Module, Adopt Two-Channel Delivery

- **Date**: 2026-04-16
- **Source team**: implementation (Plan 9 owner review)
- **Source version**: ADR 00065, PoC 09 (import-plus-preedit)
- **Source resolution**: ADR 00065 — Preedit as GPU Overlay, Not Cell Data
- **Target docs**: daemon-architecture `01-module-structure.md`,
  `03-integration-boundaries.md`
- **Status**: open

---

## Context

ADR 00065 retired Design Principle A1 ("preedit is cell data"). The
`preedit_overlay.zig` module was built on this false premise — it injects
preedit characters into FlatCell[] data before ring buffer insertion. ghostty
never puts preedit into terminal cell data; preedit exists only in GPU vertex
buffers.

The correct architecture is two-channel delivery:
- **Control channel** (direct queue, Phase 1): commands, PreeditUpdate,
  metadata
- **Frame channel** (ring buffer, Phase 2): FlatCell[] from `bulkExport()`
  (never contains preedit)

## Required Changes

1. **Remove `preedit_overlay.zig`** from the module structure. This module
   applies preedit to FlatCell[] data, which is architecturally wrong. All
   references in the module diagram and dependency list must be removed.

2. **Two-channel delivery model**: The architecture should describe two
   delivery channels sharing the same Unix socket:
   - Phase 1: `ControlChannelWriter.flush(conn)` — control messages including
     PreeditUpdate
   - Phase 2: `deliverPendingFrames(conn, ...)` — FlatCell[] via ring buffer
   Frame data never contains preedit. Preedit is always a control message.

3. **ghostty integration boundary**: The spec should clarify that
   `bulkExport()` produces cell data WITHOUT preedit. The client calls
   `ghostty_surface_preedit()` separately to render preedit as a GPU overlay.

## Summary Table

| Target Doc                    | Section/Message          | Change Type | Source Resolution |
| ----------------------------- | ------------------------ | ----------- | ----------------- |
| 01-module-structure.md        | Module list / diagram    | Remove      | ADR 00065         |
| 03-integration-boundaries.md  | ghostty preedit boundary | Update      | ADR 00065         |
| 03-integration-boundaries.md  | Delivery model           | Update      | ADR 00065         |
