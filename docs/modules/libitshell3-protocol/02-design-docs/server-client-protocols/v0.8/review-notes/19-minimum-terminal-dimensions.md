# Minimum Terminal Dimensions Requirement

**Date**: 2026-03-08
**Raised by**: owner (based on PoC 08 runtime crash)
**Severity**: MEDIUM
**Affected docs**: 04-input-and-renderstate.md (Section 4.1), 03-session-pane-management.md (pane resize)
**Status**: open

---

## Problem

PoC 08 crashed with "index out of bounds: index 2, len 2" in ghostty's `rebuildRow()` font shaping when the terminal was very small during initialization (rows < 6 or cols < 60). The crash occurred because `rebuildRow()` assumes minimum working space for font shaping calculations.

The PoC fix was a guard: `if (rows < 6 or cols < 60) break :poc_override;`

The protocol (doc 04) does not specify:
1. Minimum terminal dimensions for FrameUpdate
2. Server behavior when a pane is resized below minimum
3. Client behavior when receiving a FrameUpdate with very small dimensions

## Analysis

### Root cause

ghostty's `rebuildCells()` → `rebuildRow()` performs font shaping that accesses cell arrays with assumptions about minimum width. When the grid is too small (e.g., 2×2 during a split animation), array index calculations overflow.

### Scope

This affects:
- **Initial pane creation**: Pane may start with small dimensions before the client reports actual size
- **Pane split with small parent**: Splitting a 20-column pane into two 10-column panes
- **Aggressive resize**: User rapidly resizing the window during rendering

### Existing reference: review note 08 (pane-minimum-size)

Note 08 already addresses minimum pane size from a session management perspective. This note addresses the rendering-side implication: what happens to FrameUpdate when dimensions are below the rendering minimum.

## Proposed Change

1. **Doc 04 §4.1**: Add normative note:
   > "Minimum rendering dimensions: The server MUST NOT send FrameUpdate with `cols < 2` or `rows < 1`. When a pane's dimensions fall below these minimums (e.g., during resize animation), the server MUST suppress FrameUpdate for that pane until dimensions meet the minimum. The server SHOULD use a practical minimum of `cols >= 10, rows >= 2` for producing renderable output; below this threshold, it MAY send I-frames with only empty cells."

2. **Doc 04 §4.2 dimensions field**: Add note:
   > "The client SHOULD validate `cols` and `rows` from the dimensions field before calling importFlatCells() or equivalent. If dimensions are below the client's rendering minimum, the client SHOULD display a placeholder (e.g., solid background color) instead of attempting to render cells."

3. **Link to review note 08**: Cross-reference the session management minimum pane size with the rendering minimum.

## Owner Decision

{Pending}

## Resolution

{Pending}
