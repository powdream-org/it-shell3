# Correct Maximum Tree Depth from 16 to 4

- **Date**: 2026-03-27
- **Source team**: impl (Plan 5.5 Spec Alignment Audit)
- **Source version**: libitshell3 implementation Plans 1-5
- **Source resolution**: ADR 00043 (Binary Split Tree as Sole Pane Layout
  Model), daemon-architecture v1.0-r8 `02-state-and-types.md`
- **Target docs**: `03-session-pane-management.md` §3.4
- **Status**: open

---

## Context

The protocol spec states "The server enforces a maximum tree depth of 16
levels." This value confuses `MAX_PANES = 16` (the pane count limit) with tree
depth.

ADR 00043 established the binary split tree model with `MAX_PANES = 16` and
`MAX_TREE_NODES = 31` (16 leaves + 15 internal nodes). The daemon-architecture
spec (`02-state-and-types.md`) explicitly states: "with `MAX_PANES = 16` and a
binary split tree, the maximum depth is 4."

The code (`core/types.zig`) correctly defines `MAX_TREE_DEPTH: u3 = 4`.

## Required Changes

1. **`03-session-pane-management.md` §3.4 — Fix maximum tree depth value.**
   - **Current**: "The server enforces a maximum tree depth of 16 levels."
   - **After**: "The server enforces a maximum tree depth of 4 levels
     (`MAX_TREE_DEPTH = 4`), derived from the 16-pane limit (`MAX_PANES = 16`)
     in a binary split tree."
   - **Rationale**: A complete binary tree with 16 leaves has depth 4. The value
     16 in the original text is the pane count, not the tree depth. See ADR
     00043 and daemon-architecture `02-state-and-types.md`.

## Summary Table

| Target Doc                      | Section/Message | Change Type | Source Resolution |
| ------------------------------- | --------------- | ----------- | ----------------- |
| `03-session-pane-management.md` | §3.4 tree depth | Fix value   | ADR 00043         |
