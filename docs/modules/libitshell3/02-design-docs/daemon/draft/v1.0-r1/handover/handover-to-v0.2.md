# Handover: Daemon Design v0.1 to v0.2

**Date**: 2026-03-09
**Author**: owner

---

## Insights and New Perspectives

### Total cell count per session is bounded by screen area, not pane count

The initial concern was that many panes would multiply `bulkExport()` cost. In fact, splitting a session into more panes makes each pane smaller — total visible cells remain constant (≈ screen area). For a 374×74 terminal: 27,676 cells regardless of whether it's 1 pane or 16 panes. The per-session export cost is ~250 µs, not ~250 µs × pane_count.

The real scaling axis is **simultaneous active sessions** (multiple clients attached to different sessions), not panes per session.

### 16-pane limit unlocks array-based binary tree

Fixing the maximum panes per session at 16 enables a fundamental data structure change: the SplitNode tree can be stored as a fixed array `[31]SplitNodeData` (16 leaves + 15 internal = 31 nodes × 8 bytes = 248 bytes) with index arithmetic for parent/child navigation (`left = 2*i+1`, `right = 2*i+2`). This eliminates all per-node heap allocations, pointer chasing, and HashMap lookups in favor of inline fixed-size arrays and bitmaps. The entire tree fits in 4 L1 cache lines.

This is a UX-driven constraint (16+ panes per session is unusable on any screen) that happens to enable significant structural optimization.

### Protocol library scope is broader than "message formats"

The daemon team's R5 decision placed Layer 4 Transport in the protocol library (Listener, Connection, socket path resolution, stale socket detection, peer credentials). Several places in the v0.1 docs still describe the protocol library as if it only defines message formats — this is stale language from before R5 was finalized.

### Internal module `libitshell3/ime/` naming collision with `libitshell3-ime`

The project has three separate libraries (`libitshell3`, `libitshell3-protocol`, `libitshell3-ime`), but the internal module `libitshell3/ime/` (Phase 0+1 key routing) is nearly identical in name to the external library `libitshell3-ime` (HangulImeEngine). The dependency diagram in Section 1.6 also omits `libitshell3-ime` as a top-level entry, making the confusion worse.

---

## Design Philosophy

### Fixed bounds enable zero-allocation data structures

The 16-pane limit is the first instance of a broader principle: choosing a practical upper bound allows replacing dynamic allocations with fixed-size inline structures. This trades theoretical generality for concrete performance and simplicity. The tradeoff is acceptable when the bound is already enforced by UX (no one uses 17 panes in a terminal session).

### Server is the single source of truth for resource limits

The pane limit is enforced server-side via ErrorResponse only. The client does not track pane counts or receive limits during handshake. This keeps the client thin and eliminates client-server counter synchronization. The pattern: client requests, server accepts or rejects, client handles the result.

### kqueue single-threaded model is sufficient for v1

The owner reviewed the single-threaded event loop (R2) with the flattening bottleneck in mind. The analysis showed that per-session export cost is bounded by screen area (~250 µs), and 10 simultaneous active sessions consume ~15% of the frame budget. This is well within acceptable range for v1. The deferred item "revisit if profiling proves otherwise" remains, but should include a concrete escape hatch (e.g., offloading `bulkExport()` to a worker thread) if v0.2 adds detail.

---

## Owner Priorities

### Efficiency at the data structure level matters

The owner asked detailed questions about memory layout, cache behavior, heap allocations, and shift optimizations. The v0.2 team should carry forward the fixed-size optimization mindset — prefer bounded arrays over HashMaps, bitmaps over sets, inline over heap.

### Naming clarity is non-negotiable

The `libitshell3/ime/` vs `libitshell3-ime` confusion was flagged immediately. Names that can be mistaken for each other across module boundaries must be disambiguated. The v0.2 team should resolve the internal module rename (candidates: `input/`, `key_routing/`, `ime_routing/`).

### Consistency between documents matters

The protocol library scope misstatement (Section 1.4 describing the library as "message formats only" when it owns Layer 4 Transport) was caught during review. Cross-references and scope descriptions must reflect the current design, not historical assumptions.

---

## New Conventions and Procedures

No new conventions were introduced during the daemon v0.1 review cycle. The cascaded re-raise monitoring rule and model selection rule were added during the revision cycle (pre-review) and are already documented in `docs/work-styles/03-design-workflow.md`.

---

## Pre-Discussion Research Tasks

### Review note resolution planning

Three open review notes need resolution in v0.2:

1. **01-pane-limit-and-fixed-size-optimization** (HIGH) — Apply 16-pane limit, replace pointer tree with array tree, replace HashMaps with fixed arrays, add dirty bitmap. Affects Sections 1.5, 3.2, 3.3 of doc 01 and R3/R9 of the resolution doc.
2. **02-ime-module-naming-confusion** (MEDIUM) — Add `libitshell3-ime` to dependency diagram, rename internal `ime/` module. Affects Sections 1.2, 1.6 of doc 01 and R1 of the resolution doc.
3. **03-protocol-library-scope-misstatement** (MEDIUM) — Fix Section 1.4 to accurately describe the protocol library's 4-layer scope. Localized fix.
