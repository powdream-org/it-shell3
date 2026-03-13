# SplitNode Remnants in v0.1 Resolution Doc

**Date**: 2026-03-10
**Raised by**: verification team
**Severity**: LOW
**Affected docs**: `v0.1/design-resolutions/01-daemon-architecture.md` — R1 (line 23), R3 (line 80)
**Status**: open

---

## Problem

V1-03 fix updated code blocks and rationale text in the v0.1 resolution doc but missed two narrative lines:

- R1 line 23: still says `SplitNode (tree shape, leaf = PaneId)` — should be `SplitNodeData (tree shape, leaf = PaneSlot)`
- R3 line 80: still says "Each Session directly owns a SplitNode tree (binary split)." — should reference `SplitNodeData` tree or `tree_nodes` array

All other locations across all five documents use `SplitNodeData` and `PaneSlot`.

## Analysis

Mechanical residual from the V1-03 fix cycle. The v0.1 resolution doc is living normative text (confirmed by V1-03 precedent — R2 was applied to it). These stale terms could confuse a reader cross-referencing with v0.2 specs.

Low severity because the code blocks in the same resolutions already use the correct v0.2 types, so the intent is clear in context.

## Proposed Change

- R1 line 23: Replace `SplitNode (tree shape, leaf = PaneId)` with `SplitNodeData (tree shape, leaf = PaneSlot)`
- R3 line 80: Replace "SplitNode tree" with "`SplitNodeData` tree" or "`tree_nodes` array"

## Owner Decision

Left to designers for resolution.

## Resolution

