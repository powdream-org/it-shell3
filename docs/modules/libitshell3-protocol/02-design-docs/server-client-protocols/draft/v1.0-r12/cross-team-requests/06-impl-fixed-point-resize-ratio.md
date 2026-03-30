# Fixed-Point Ratio for ResizePaneRequest

- **Date**: 2026-03-30
- **Source team**: impl (Plan 7 — Session & Pane Operations)
- **Source version**: daemon-architecture draft/v1.0-r8
- **Source resolution**: ADR 00062 (Fixed-Point Signed Ratio Delta for
  ResizePaneRequest)
- **Target docs**: server-client-protocols
  draft/v1.0-r12/03-session-pane-management.md
- **Status**: open

---

## Context

See ADR 00062 for full rationale. ResizePaneRequest changes from cell deltas to
signed fixed-point ratio deltas. Direction simplifies from 4-direction enum to
2-orientation + sign.

## Required Changes

Per ADR 00062, update:

1. Section 2.12 ResizePaneRequest — replace payload fields and semantics
2. Section 2.13 ResizePaneResponse — update status code descriptions
3. Section 3 Layout Tree Format — consider ratio type change for consistency

## Summary Table

| Target Doc                 | Section/Message         | Change Type     | Source Resolution |
| -------------------------- | ----------------------- | --------------- | ----------------- |
| 03-session-pane-management | 2.12 ResizePaneRequest  | Replace payload | ADR 00062         |
| 03-session-pane-management | 2.13 ResizePaneResponse | Update status   | ADR 00062         |
| 03-session-pane-management | 3 Layout Tree Format    | Ratio type      | ADR 00062         |
