# Simplify Phase 1 Subgraph in Daemon Architecture Diagram

**Date**: 2026-03-14
**Source team**: ime-behavior
**Source version**: IME behavior draft/v1.0-r1
**Source resolution**: [PLAN.md](../../../../../../libitshell3-ime/02-design-docs/behavior/draft/v1.0-r1/PLAN.md) Section 4, CTR-01
**Target docs**: `01-internal-architecture.md` (Section 1.2, 3-phase input pipeline diagram)
**Status**: open

---

## Context

The IME behavior team has moved the `processKey()` internal decision tree
(modifier check → printable check → libhangul dispatch → ImeResult construction)
into a dedicated behavior document:
`libitshell3-ime/02-design-docs/behavior/draft/v1.0-r1/01-processkey-algorithm.md`.

The daemon's Phase 1 subgraph in `01-internal-architecture.md` currently
replicates this internal decision tree with detailed nodes (modifier check,
printable check, libhangul feed, `hangul_ic_process()` return handling). This
creates a maintenance burden — changes to the engine's internal algorithm require
updates in two places. The daemon should treat the IME engine as a black box:
`processKey(KeyEvent) → ImeResult`.

## Required Changes

### 1. Replace Phase 1 subgraph in 3-phase input pipeline diagram

- **Current** (lines 94–112 of `01-internal-architecture.md`): Phase 1 subgraph
  contains 8 internal nodes (`P1_process`, `P1_mod`, `P1_print`, `P1_hangul`,
  `P1_ic`, `P1_flush_mod`, `P1_flush_np`, `P1_flush_rej`) plus `P1_result`,
  showing the engine's internal decision tree.

- **After**: Replace with a black-box subgraph containing only the entry point
  and result:

```mermaid
subgraph P1["Phase 1: IME Engine (libitshell3-ime)"]
    P1_process["processKey(KeyEvent)"]
    P1_result(["ImeResult"])
    P1_process --> P1_result
end
```

- **Rationale**: The daemon calls `processKey(KeyEvent)` and receives `ImeResult`.
  What happens inside the engine is defined by the IME behavior docs, not the
  daemon architecture. The daemon's diagram should reflect its integration
  boundary — the engine is opaque.

### 2. Add cross-reference to behavior doc

After the diagram (or in the existing explanatory paragraph at line 126), add a
cross-reference:

> For the internal `processKey()` decision algorithm (modifier handling, printable
> key dispatch, libhangul composition), see
> [IME behavior: processKey algorithm](../../../../../../libitshell3-ime/02-design-docs/behavior/draft/v1.0-r1/01-processkey-algorithm.md).

### 3. Preserve Phase 0 and Phase 2 subgraphs

No changes to Phase 0 (global shortcut check) or Phase 2 (ghostty integration).
Only Phase 1's internal nodes are affected.

### 4. Preserve explanatory text

The "Why IME runs before keybindings" paragraph (line 126) and Phase 0/Phase 1
module placement note (line 128) remain unchanged — they describe daemon-level
architectural decisions, not engine internals.

## Summary Table

| Target Doc | Section | Change Type | Source Resolution |
|-----------|---------|-------------|-------------------|
| `01-internal-architecture.md` | §1.2 Phase 1 subgraph (lines 94–112) | Simplify to black-box `processKey → ImeResult`; remove internal decision nodes | PLAN.md CTR-01 |
| `01-internal-architecture.md` | §1.2 post-diagram text | Add cross-reference to behavior doc 01 | PLAN.md CTR-01 |
