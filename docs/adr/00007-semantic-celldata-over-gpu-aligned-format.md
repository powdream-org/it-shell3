# 00007. Semantic CellData over GPU-Aligned Format

- Date: 2026-03-16
- Status: Accepted

## Context

The wire format for terminal cell data could either match the client's GPU
buffer layout (zero-copy rendering) or carry semantic content (codepoint, style,
colors) that the client transforms into GPU buffers.

## Decision

CellData is semantic, not GPU-aligned. GPU structs are 70%+ client-local data
(font atlas indices, shaped glyph positions, texture coordinates). Zero-copy
wire-to-GPU is impossible. CellData encodes codepoint + style + colors + wide
flag; the client does font shaping and GPU buffer construction via ghostty's
rendering pipeline.

## Consequences

- Client-side rendering pipeline (importFlatCells -> rebuildCells -> drawFrame)
  is required.
- Wire format is stable across GPU API changes (Metal, Vulkan, WebGPU).
- 16-byte fixed CellData enables O(1) random access and SIMD-friendly
  processing.
