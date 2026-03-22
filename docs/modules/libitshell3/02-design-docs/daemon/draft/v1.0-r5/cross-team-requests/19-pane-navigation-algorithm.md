# Pane Navigation Algorithm

- **Date**: 2026-03-22
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

Protocol doc 03 (Session and Pane Management) Section 2.10 defines
`NavigatePaneRequest`, which moves focus to the nearest pane in a given
direction. The protocol spec currently contains geometric implementation detail
(layout tree traversal, center-based nearest-pane selection) that belongs in the
daemon design docs rather than the wire protocol specification. The wire spec
only needs to state the observable behavior (direction in, focused pane out,
wrap semantics).

This CTR requests that the daemon team document the navigation algorithm with
both a text description and a visual diagram. Text alone is insufficient for
this algorithm; a flowchart or sequence diagram is required for implementors to
understand the geometric computation.

## Required Changes

1. Add a **text description** of the pane navigation algorithm to the daemon
   design docs:
   - How geometric positions are computed from the session's layout tree (binary
     split tree with ratios)
   - How the "nearest pane in direction D" is determined from the center point
     of the currently focused pane
   - Wrap-around behavior when no pane exists in the requested direction
     (configurable — the algorithm must document the configuration point)

2. Add a **flowchart or sequence diagram** illustrating the algorithm. The
   visual must cover:
   - Layout tree to geometric position computation
   - Direction filtering (which panes are candidates in direction D)
   - Distance calculation and selection of the nearest candidate
   - Wrap-around path

## Summary Table

| Target Doc         | Section/Area    | Change Type | Source Resolution               |
| ------------------ | --------------- | ----------- | ------------------------------- |
| Daemon design docs | Pane navigation | Add         | owner review (v1.0-r12 cleanup) |

## Reference: Original Protocol Text (removed from Doc 03 §2.10)

### From Doc 03 §2.10 NavigatePaneRequest (0x0148)

**Navigation algorithm**: The server computes the geometric position of each
pane from the session's layout tree, then finds the nearest pane in the
requested direction from the center of the currently focused pane. If no pane
exists in that direction, the focus wraps around (configurable).
