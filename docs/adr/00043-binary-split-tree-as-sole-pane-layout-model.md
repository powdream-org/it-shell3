# 00043. Binary Split Tree as Sole Pane Layout Model

- Date: 2026-03-23
- Status: Proposed

## Context

Terminal multiplexers use different layout models for pane arrangement:

- **tmux** uses a tree with three node types (`LAYOUT_LEFTRIGHT`,
  `LAYOUT_TOPBOTTOM`, `LAYOUT_WINDOWPANE`). Each internal node can have an
  arbitrary number of children, making the tree n-ary.
- **zellij** uses a constraint-based tiled layout plus a separate floating pane
  layer with explicit coordinates, z-ordering, and overlap resolution.
- **cmux** uses a binary split tree via its Bonsplit library — each split
  produces exactly two children (horizontal or vertical).
- **ghostty** exposes a binary split API for its terminal surfaces.

it-shell3 needs a pane layout model that is simple to implement, serialize, and
navigate, while covering standard terminal multiplexer workflows. The project
has a hard 16-pane-per-session limit (ADR 00008) and targets v1 with a
single-threaded daemon architecture (ADR 00033).

Floating panes (zellij-style overlays) have no concrete use case in v1. No user
workflow requires detachable or overlay pane positioning for the initial
release.

## Decision

Use a **binary split tree** as the sole pane layout model for v1. Each internal
node stores an orientation (horizontal or vertical) and a split ratio. Each leaf
stores a pane slot index. The tree is represented as a compile-time-bounded
array (`[31]?SplitNodeData`) using implicit index arithmetic (parent = (i-1)/2,
left child = 2i+1, right child = 2i+2).

No floating panes, no constraint-based layout, no n-ary trees. Floating panes
are deferred to post-v1 (see `99-post-v1-features.md` §8 in the protocol docs).

## Consequences

**What gets easier:**

- Implementation: subtree relocation during split/close is a bounded memcpy (~15
  node copies maximum). No rebalancing, no constraint solving.
- Serialization: the tree maps directly to a recursive JSON structure for
  session persistence. No separate coordinate system to serialize.
- Navigation: parent/child relationships are pure index arithmetic with no
  pointer chasing.
- Bounds checking: with 16 panes and a binary tree, the maximum array size (31
  nodes) is known at compile time. No dynamic allocation for layout state.

**What gets harder:**

- Layouts that don't decompose into nested binary splits (e.g., a 3-column equal
  split) require two split operations instead of one. This is a UX
  inconvenience, not a capability gap — tmux has the same limitation.
- Adding floating panes post-v1 will require a separate overlay coordinate
  system, z-ordering logic, and protocol extensions. The binary split tree
  itself won't need modification — floating panes would be an independent layer.

**Obligations:**

- The `SplitNodeData` union and `[31]?SplitNodeData` array are structural
  commitments in the daemon architecture. Changing the layout model post-v1
  would require a session format migration.
