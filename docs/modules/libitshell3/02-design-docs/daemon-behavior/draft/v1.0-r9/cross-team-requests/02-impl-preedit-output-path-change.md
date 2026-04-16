# Preedit Output Path: Control Channel, Not Frame Cells

- **Date**: 2026-04-16
- **Source team**: implementation (Plan 9 owner review)
- **Source version**: ADR 00065, PoC 09 (import-plus-preedit)
- **Source resolution**: ADR 00065 — Preedit as GPU Overlay, Not Cell Data
- **Target docs**: daemon-behavior `03-policies-and-procedures.md`
- **Status**: open

---

## Context

ADR 00065 retired Design Principle A1 ("preedit is cell data"). ghostty renders
preedit only in GPU vertex buffers via `addPreeditCell()`, never in terminal
cell data (Screen/Page). The daemon cannot embed preedit in FlatCell[] exports.

The daemon-behavior spec currently describes IME procedures where preedit is
applied to exported frame data via `preedit_overlay.zig`. This path is invalid.
Preedit must be delivered as a separate control channel message
(PreeditUpdate), and the client calls `ghostty_surface_preedit()` to render it.

## Required Changes

1. **IME preedit output path**: All IME procedures that produce preedit text
   must route preedit to the control channel (PreeditUpdate broadcast via
   direct queue), not to frame cell data. The daemon never calls
   `preedit_overlay` functions on exported FlatCell[].

2. **Two output paths for IME result**: When `ImeResult` contains both
   `committed_text` and `preedit`:
   - `committed_text` → `pty_ops.write(fd, text)` (existing path, unchanged)
   - `preedit` → `session.setPreedit(text)` → PreeditUpdate broadcast via
     control channel (existing path, already implemented correctly)

3. **Remove preedit overlay references**: Any procedure that references
   applying preedit to frame cells or calling preedit_overlay functions should
   be removed or updated to reference the control channel path.

## Summary Table

| Target Doc                    | Section/Message    | Change Type | Source Resolution |
| ----------------------------- | ------------------ | ----------- | ----------------- |
| 03-policies-and-procedures.md | IME procedures     | Update      | ADR 00065         |
| 03-policies-and-procedures.md | Frame export flow  | Update      | ADR 00065         |
