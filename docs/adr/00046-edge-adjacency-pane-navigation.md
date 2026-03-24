# 00046. Edge Adjacency Pane Navigation with Overlap Filtering

- Date: 2026-03-24
- Status: Accepted

## Context

Pane navigation (move focus up/down/left/right) requires an algorithm to
determine which pane is "next" in a given direction from the currently focused
pane. The pane layout is a binary split tree with geometric positions computed
from split ratios.

Two algorithmic approaches were considered:

- **Center-point distance**: Compute center coordinates for each pane, find the
  nearest center in the requested direction. Simple but produces unintuitive
  results — a pane diagonally offset with no edge alignment can be selected over
  a pane that is directly adjacent.
- **Edge adjacency with overlap filtering**: Find panes whose adjacent edge
  touches the focused pane's edge, filtered to only those with perpendicular
  overlap. Matches tmux's `window_pane_choose_best()` approach.

tmux uses edge adjacency. zellij uses edge adjacency. No major terminal
multiplexer uses center-point distance for directional navigation.

## Decision

Use edge adjacency with overlap filtering for pane navigation:

1. **Compute geometric rectangles** from the binary split tree (stack-allocated,
   bounded to MAX_PANES=16).
2. **Direction filter**: Collect panes whose relevant edge is beyond the focused
   pane's edge in the requested direction.
3. **Overlap filter**: Keep only candidates whose perpendicular span overlaps
   with the focused pane's perpendicular span (e.g., for up/down navigation,
   horizontal ranges must overlap).
4. **Nearest selection**: Pick the candidate with shortest edge distance.
   Tie-break by most recently focused (MRU).
5. **Wrap-around**: If no candidate found, search the opposite direction for the
   furthest overlapping pane.

The algorithm lives in `core/` (pure geometry, no I/O) and is reused for both
explicit `NavigatePaneRequest` and post-pane-close focus transfer.

No geometry caching in v1 — recomputing 16 rectangles per request is trivially
fast (bounded O(n), L1-cache-hot).

## Consequences

- **Intuitive navigation**: Users get the pane they visually expect, matching
  tmux muscle memory. Diagonal panes with no edge alignment are correctly
  excluded.
- **MRU tie-break**: When multiple panes are equidistant, the most recently
  focused one wins. Provides predictable behavior for common layouts (e.g.,
  evenly split grid).
- **Wrap-around always on**: Navigation wraps at screen edges (e.g., "up" from
  topmost pane goes to bottommost). Non-configurable in v1 — matches tmux and
  zellij behavior, avoids a settings surface with no known user demand.
- **Reusable for focus transfer**: The same `findPaneInDirection()` function
  handles both user-initiated navigation and automatic focus selection after
  pane close.
- **No caching overhead**: Simplifies the implementation — no invalidation logic
  needed on split, close, or resize. Can add caching post-v1 if profiling shows
  a need (unlikely with MAX_PANES=16).
