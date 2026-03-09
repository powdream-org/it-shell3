# Pane Limit and Fixed-Size Data Structure Optimization

**Date**: 2026-03-09
**Raised by**: owner
**Severity**: HIGH
**Affected docs**: 01-internal-architecture.md (Sections 3, 1.5), design-resolutions/01-daemon-architecture.md (R3)
**Status**: open

---

## Problem

The current design uses unbounded data structures for the session state tree:

- `SplitNode` uses heap-allocated pointer-based binary tree (`*SplitNode` children)
- Pane lookup uses `HashMap(PaneId, *Pane)` in `server/`
- Ring cursors use `HashMap(PaneId, RingCursor)` in `ClientState`
- Dirty pane tracking has no specified structure

These introduce per-node heap allocations (up to 31 for a full tree), pointer chasing on traversal, and hash overhead on lookup — all unnecessary given that practical pane counts are small.

Additionally, the single-threaded event loop's primary computational cost is `bulkExport()` (~11 ns/cell, ~250 us for a 374x74 terminal). While per-session total cell count is bounded by screen area (not multiplied by pane count), the design lacks an explicit upper bound on panes per session.

## Analysis

### UX bound on pane count

Splitting a session into more panes makes each pane smaller. On a 374x74 terminal:

| Panes | Approx size per pane | Usability |
|-------|---------------------|-----------|
| 4 | 187x37 | Comfortable |
| 8 | 187x18 | Usable on large monitors |
| 16 | 93x18 | Minimum viable |
| 32 | 93x9 | Unusable — 9 rows is too few for any real work |

16 is the practical UX ceiling.

### Fixed-size optimization enabled by 16-pane limit

A full binary tree with 16 leaves has exactly 15 internal nodes = **31 total nodes**. This enables array-based binary tree representation:

- **Tree**: `node_pool: [31]?SplitNodeData` — index arithmetic for parent/child (`parent(i) = (i-1)/2`, `left(i) = 2*i+1`, `right(i) = 2*i+2`). No pointers, no heap allocation per node.
- **Pane lookup**: `[16]?*Pane` — O(1) direct indexing, zero hash overhead.
- **Dirty tracking**: `u16` bitmap — `@ctz` for next-dirty-pane iteration.
- **Ring cursors**: `[16]?RingCursor` — fixed array, no HashMap.

### Memory analysis

`SplitNodeData` as tagged union:

| Component | Size |
|-----------|------|
| Tag (discriminant) | 1 byte |
| Payload (max: orientation + ratio = 1 + 4) | 5 bytes |
| Padding (align to 4) | 2 bytes |
| **Total per node** | **8 bytes** |

31 nodes x 8 bytes = **248 bytes** for the entire tree, fitting in 4 L1 cache lines (64 bytes each).

Comparison:

| Approach | Per-node size | 31 nodes | Allocations |
|----------|-------------|----------|-------------|
| Array-based | 8 bytes | 248 bytes, inline in Session | 0 (part of Session allocation) |
| Pointer-based | ~24 bytes (8 + 2 pointers) | 744 bytes + heap metadata | up to 31 separate heap allocations |

### Single-threaded event loop context

Per-session total export cost is bounded by screen area, not pane count (more panes = smaller panes = same total cells). The real scaling axis is simultaneous active sessions. For a 374x74 terminal (~250 us/session export):

| Active sessions | Export total | Frame budget (16.6 ms) |
|-----------------|-------------|----------------------|
| 5 | 1.25 ms | 7.5% |
| 10 | 2.5 ms | 15% |
| 20 | 5.0 ms | 30% |

The pane limit is not a performance fix for the single-threaded model — it is a UX-driven constraint that happens to unlock structural optimizations.

## Proposed Change

1. **Add `MAX_PANES_PER_SESSION = 16` constant** in `core/`.

2. **Replace SplitNode pointer tree** with array-based binary tree:
   ```zig
   // core/session.zig
   pub const MAX_PANES = 16;
   const MAX_TREE_NODES = MAX_PANES * 2 - 1; // 31

   pub const Session = struct {
       // ... existing fields ...
       tree_nodes: [MAX_TREE_NODES]?SplitNodeData,
       // root is always tree_nodes[0]
   };
   ```

3. **Replace `HashMap(PaneId, *Pane)`** in `server/` with `[MAX_PANES]?*Pane`.

4. **Add `dirty_mask: u16`** to pane tracking in `server/`.

5. **Replace `HashMap(PaneId, RingCursor)`** in `ClientState` with `[MAX_PANES]?RingCursor`.

6. **Document the 16-pane limit** as a design constraint with UX rationale (not performance rationale).

## Owner Decision

Limit is 16 panes per session. Adopt array-based binary tree and fixed-size data structures throughout.

## Resolution

(open)
