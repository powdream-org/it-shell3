# Fixed-Point Resize Handling Procedure

- **Date**: 2026-03-30
- **Source team**: impl (Plan 7 — Session & Pane Operations)
- **Source version**: daemon-behavior draft/v1.0-r8
- **Source resolution**: ADR 00062 (Fixed-Point Signed Ratio Delta for
  ResizePaneRequest)
- **Target docs**: daemon-behavior draft/v1.0-r8/03-policies-and-procedures.md
- **Status**: open

---

## Context

See ADR 00062 for full rationale. The resize handling procedure must be updated
to reflect the new wire format (signed fixed-point ratio delta instead of cell
delta).

## Required Changes

Per ADR 00062, update the resize handling procedure to reflect the new wire
format and integer arithmetic.

## Summary Table

| Target Doc                 | Section/Procedure | Change Type           | Source Resolution |
| -------------------------- | ----------------- | --------------------- | ----------------- |
| 03-policies-and-procedures | Resize handling   | Update to fixed-point | ADR 00062         |
