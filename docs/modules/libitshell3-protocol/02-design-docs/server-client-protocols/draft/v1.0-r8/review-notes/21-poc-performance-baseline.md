# PoC Performance Baseline: Replace Estimates with Measured Data

**Date**: 2026-03-08
**Raised by**: owner (based on PoC 06–08 benchmarks)
**Severity**: LOW
**Affected docs**: 04-input-and-renderstate.md (Section 7.1, 7.2 size estimates)
**Status**: open

---

## Problem

Doc 04 §7.1 and §7.2 contain **estimated** frame sizes and bandwidth projections. PoC 06–08 provide **measured** performance data that should supplement or replace these estimates.

### Current estimates in doc 04

- Typical P-frame (2 changed rows, 80 cols): ~3,332 bytes (with RLE: ~400-800 bytes)
- Typical I-frame (80×24): ~8,000-12,000 bytes (with RLE: ~3,000-5,000 bytes)
- Metadata-only P-frame: ~100 bytes

### PoC-measured data (Apple Silicon, ReleaseFast)

| Operation | 80×24 (1,920 cells) | 300×80 (24,000 cells) |
|-----------|--------------------|-----------------------|
| Server: `bulkExport()` | 22 µs | 217 µs |
| Client: `importFlatCells()` | 12 µs | 96 µs |
| **Total (export + import)** | **34 µs** | **313 µs** |
| % of 16.6 ms frame budget (60fps) | 0.2% | 1.9% |

- Import cost: ~4 ns/cell
- Export cost: ~11 ns/cell
- Round-trip validation (export → import → re-export): bit-identical output confirmed

## Analysis

The PoC data validates that the protocol's bandwidth estimates are in the right ballpark, but adds critical **latency** data that the spec does not currently include. The export+import latency (34 µs for 80×24) is a small fraction of the frame budget, confirming that wire serialization/deserialization is NOT the bottleneck — font shaping and GPU rendering are.

This data also validates the design decision to use semantic CellData rather than GPU-ready data: the 34 µs cost of semantic → RenderState conversion is trivial, and the bandwidth savings (16-byte semantic cells vs. 32-byte CellText GPU structs) are significant.

## Proposed Change

Add a "Performance Validation" subsection to doc 04 Section 7 or as a new Section 8:

> **Measured Performance (PoC 06–08, Apple Silicon, ReleaseFast)**
>
> | Metric | 80×24 | 300×80 | Notes |
> |--------|-------|--------|-------|
> | Export latency | 22 µs | 217 µs | Server: RenderState → CellData serialization |
> | Import latency | 12 µs | 96 µs | Client: CellData → RenderState population |
> | Total wire overhead | 34 µs | 313 µs | 0.2% / 1.9% of 16.6 ms frame budget |
> | Per-cell import cost | ~4 ns | ~4 ns | Consistent across sizes |
>
> The rendering bottleneck is font shaping (rebuildCells, est. ~200 µs for 80×24) and GPU draw (drawFrame, est. ~500 µs). Wire serialization overhead is negligible.

## Owner Decision

{Pending}

## Resolution

{Pending}
