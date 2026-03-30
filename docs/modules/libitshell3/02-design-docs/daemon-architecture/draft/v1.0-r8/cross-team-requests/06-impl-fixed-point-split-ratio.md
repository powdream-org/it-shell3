# Fixed-Point Split Ratio Internal Representation

- **Date**: 2026-03-30
- **Source team**: impl (Plan 7 — Session & Pane Operations)
- **Source version**: daemon-architecture draft/v1.0-r8
- **Source resolution**: ADR 00062 (Fixed-Point Signed Ratio Delta for
  ResizePaneRequest), ADR 00063 (Text Zoom Handled as WindowResize)
- **Target docs**: daemon-architecture draft/v1.0-r8/02-state-and-types.md,
  impl-constraints/state-and-types.md
- **Status**: open

---

## Context

See ADR 00062 for the protocol change rationale. As a consequence, the internal
split ratio representation should change from `f32` to `u32` fixed-point. See
ADR 00063 for the cell grid model (border = 0 cells).

## Required Changes

Per ADR 00062 and ADR 00063, update:

1. SplitNodeData `ratio` type: `f32` → `u32` fixed-point (2 decimal places
   percentage, ×10^4, range 0–10000)
2. Cell grid model normative note per ADR 00063

## Summary Table

| Target Doc                       | Section/Type    | Change Type        | Source Resolution |
| -------------------------------- | --------------- | ------------------ | ----------------- |
| 02-state-and-types               | SplitNodeData   | ratio f32 → u32    | ADR 00062         |
| impl-constraints/state-and-types | SplitNodeData   | ratio f32 → u32    | ADR 00062         |
| 02-state-and-types               | Cell grid model | Add normative note | ADR 00063         |
