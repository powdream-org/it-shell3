# Design Principles

Living document. Updated after each revision cycle as principles emerge or are reinforced. For the full context behind each principle, see the originating handover document.

---

## Protocol Design Principles

| # | Principle | Origin | Notes |
|---|-----------|--------|-------|
| P1 | **Shared state by default** | v0.7 | All clients see the same viewport, selection, scroll position. Per-client divergence requires explicit justification. Heuristic: "does tmux do this per-client?" If no, neither do we. |
| P2 | **One delivery path** | v0.7, reinforced v0.8 | Ring buffer is the canonical data path. The direct message queue (for small control messages like PreeditSync, LayoutChanged) is the sole exception. New features route through the ring unless strongly justified otherwise. |
| P3 | **Close early, design later** | v0.7 | Open questions with no concrete use case should be closed, not carried forward. They can be reopened when a real scenario demands it. |
| P4 | **Implementation details are not protocol concerns** | v0.7 | Clipboard policy, cursor blink timing, focus indicator rendering — these belong to the client app, not the wire protocol. |
| P5 | **ghostty is the rendering authority** | v0.8 | Cursor positioning, preedit cell width, decoration style — all determined by ghostty's renderer on the server side. The protocol carries cell data, not rendering instructions. If ghostty handles it internally, the protocol should not duplicate it. |
| P6 | **Capability gating is precise** | v0.8 | Each capability gates exactly one thing. `preedit_sync` gates only PreeditSync (0x0403). `preedit` gates PreeditStart/Update/End. Preedit cell data in FrameUpdate is never gated. Layers are independent. |

## Architectural Insights

| # | Insight | Origin | Impact |
|---|---------|--------|--------|
| A1 | **Preedit is cell data, not metadata** | v0.7 PoC, applied v0.8 | Server calls `ghostty_surface_preedit()`, injects preedit cells into I/P-frames. Client renders cells without knowing what is preedit. Eliminated dual-channel design, `composition_state`, FrameUpdate preedit JSON, ring buffer bypass. |
| A2 | **Globally singleton session model** | v0.7 | All clients share the same session state. No per-client independent viewports or scroll positions (post-v1 concern). |
| A3 | **Ring buffer resolves adjacent problems** | v0.7 | Flow control (cursor stagnation replaces explicit ack), notification coalescing (per-pane ring makes batching unnecessary), recovery unification (skip to latest I-frame), selection sync (shared state in RowData). Consider the ring buffer first before inventing alternatives. |

## Process Lessons

| # | Lesson | Origin | Detail |
|---|--------|--------|--------|
| L1 | **Normative table rows must be self-contained** | v0.8 (verification cascade) | When rows in a table describe variants of the same mechanism, each row must reference the authoritative section by number rather than paraphrasing its rules. Fixing one row can expose adjacent rows as inconsistent. Check all rows when any single row changes. |
| L2 | **Stop verification at diminishing returns** | v0.8 (11 rounds) | Stop when: (a) issues have declined to minor/marginal severity, (b) new issues are in the same file/section as the previous round's fix, and (c) at least 3/4 verifiers report CLEAN. |
| L3 | **Single-topic revision cycles converge faster** | v0.8 vs v0.7 | v0.8 (1 topic, 16 resolutions, 7/7 unanimous) converged faster than v0.7 (2 topics, more complex coordination). Scope discipline accelerates consensus. |

---

## Maintenance Rules

1. **When to update**: After completing a revision cycle's handover document. Review §2 (Insights) and §3 (Design Philosophy) of the new handover — if a principle is new, add it; if it reinforces an existing one, update the Origin column.
2. **Supersession**: If a later revision overturns a principle, do not delete it. Move it to a "Retired" section with a note explaining why and which principle replaced it.
3. **Scope**: Only principles that have been **validated through at least one revision cycle** belong here. Speculative ideas stay in handover documents until confirmed.
