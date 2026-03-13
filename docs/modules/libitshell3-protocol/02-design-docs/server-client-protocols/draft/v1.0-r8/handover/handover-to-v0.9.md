# Handover: Protocol v0.8 to v0.9 Revision

> **Date**: 2026-03-08 (updated from 2026-03-07)
> **Author**: team-lead (with owner review)
> **Scope**: Preedit protocol overhaul — cross-team revision with IME Contract v0.7; **PoC 06–08 findings added 2026-03-08**
> **Prerequisite reading**: All files in `draft/v1.0-r8/review-notes/` (01–21), `draft/v1.0-r8/design-resolutions/01-preedit-overhaul.md`, PoC READMEs (`poc/06-renderstate-extraction/`, `poc/07-renderstate-bulk-api/`, `poc/08-renderstate-reinjection/`)

---

## 1. What v0.8 Accomplished

### 1.1 Preedit Protocol Overhaul

Single-topic cross-team revision. The "preedit is cell data, not metadata" insight (from the v0.7 visual PoC) was applied across 7 protocol docs and 4 IME contract files. Produced `design-resolutions/01-preedit-overhaul.md` (16 resolutions, 7/7 unanimous consensus). Key removals:

- `composition_state` field from protocol and IME contract (no consumer)
- FrameUpdate preedit JSON section (preedit renders through cell data)
- Dual-channel design (ring buffer + preedit bypass → single ring path)
- Ring buffer bypass infrastructure (`frame_type=0` P-metadata, bypass buffer, 3-level socket priority)
- `cursor_x`, `cursor_y`, `display_width` from preedit messages (ghostty-internal)
- Section 3 Korean Composition State Machine (~130 lines, factual errors confirmed by PoC)
- Section 10.1 cursor style normative rules (ghostty-internal rendering)

### 1.2 frame_type Simplification

Renumbered from 4 values {0=P-metadata, 1=P-partial, 2=I-frame, 3=I-unchanged} to 3 values {0=P-partial, 1=I-frame, 2=I-unchanged}. All frames go through the ring. `frame_sequence` increments for every frame (no exceptions).

### 1.3 Socket Write Priority Simplification

Dropped from 3-level to 2-level: (1) direct message queue, (2) ring buffer frames. PreeditSync stays in the direct queue to preserve "context before content" — recovering clients get composition metadata before the I-frame containing preedit cells.

### 1.4 Verification (11 rounds)

- **Rounds 1–5**: 5 true alarms (cross-reference consistency, stale ordering, stale labels). Routine fixes.
- **Rounds 6–10**: 7 true alarms. Rounds 8–10 exhibited a cascade pattern in doc 02 Section 10.1's `preedit_sync` fallback table — fixing one row exposed the adjacent row as inconsistent with Section 5.1's normative principles. Each fix was locally correct but shifted the inconsistency.
- **Round 11**: 3/4 verifiers reported CLEAN. Owner stopped the loop. 1 marginal issue (R11-T01: "per pane" qualifier on `preedit_session_id` in doc 05 §2.1) was out of preedit-overhaul scope.

Total: 12 true alarms fixed, 12 dismissed.

### 1.5 IME Contract v0.7

Applied simultaneously as part of the cross-team revision. Removed `composition_state` from `ImeResult`, scenario matrix, `CompositionStates` struct, naming convention, `setActiveInputMethod` examples, and memory model note. Added `itshell3_preedit_cb` revision note.

---

## 2. Insights and New Perspectives

### 2.1 Verification cascade in tightly-coupled normative tables

The doc 02 Section 10.1 `preedit_sync` fallback table went through 3 consecutive fix rounds (V8-01 → V9-01 → V10-01). Each row's language implicitly referenced neighboring rows' semantics. Fixing row 1's "preedit overlays" → "preedit cell data" made row 2's "only the composing client sees its own preedit" visibly wrong. Fixing row 2 made row 3's "opts out of preedit broadcast" wrong.

**Lesson**: When writing normative tables where rows describe variants of the same mechanism, each row must be self-contained — reference the authoritative section by number rather than paraphrasing its rules. Future writers should check all rows in a table when any single row changes.

### 2.2 Verification loop convergence requires scope discipline

The terminology-verifier raised issues from the same file/section repeatedly because each fix introduced new wording that became a fresh target. The root cause was not verifier quality but the cascade effect (§2.1). After 11 rounds, the owner correctly stopped the loop — diminishing returns had set in, and the remaining marginal issue was out of scope.

**Lesson**: The owner should consider stopping the verification loop when (a) issues have declined to minor/marginal severity, (b) new issues are in the same file/section as the previous round's fix, and (c) at least 3/4 verifiers report CLEAN. Perfection in normative wording is asymptotic.

### 2.3 Single-topic revision cycles are efficient

v0.8 was scoped to exactly one topic (preedit overhaul) and its mechanical consequences. This made the 7-person discussion team converge quickly (unanimous on all 16 resolutions) and kept the writing/verification cycle focused. Compare with v0.7 which covered two topics (ring buffer + per-session IME) and required more complex coordination.

---

## 3. Design Philosophy

- **One delivery path, minimal exceptions.** The preedit bypass removal validated the principle from v0.7: the ring buffer is the canonical data path. The only remaining non-ring path is the direct message queue for small control messages (PreeditSync, LayoutChanged, etc.). New features should route through the ring unless there is a strong justification for a separate path.

- **ghostty is the rendering authority.** Cursor positioning, preedit cell width, decoration style — all determined by ghostty's renderer on the server side. The protocol carries cell data, not rendering instructions. This extends to future CJK features: if ghostty handles it internally, the protocol should not duplicate it.

- **Capability gating is precise.** The `preedit_sync` fallback table incident reinforced that capabilities must gate exactly what they claim. `preedit_sync` gates only PreeditSync (0x0403). PreeditStart/Update/End are gated by `"preedit"`. Preedit cell data in FrameUpdate is never gated. Each layer is independent.

---

## 4. Owner Priorities

v0.9 review notes should be processed in the following order. **PoC-validated items (16–21) are highest priority** because they align the protocol spec with proven implementation reality.

### Priority 0: PoC-VALIDATED (highest — align spec with proven reality)

> These items are backed by working code (PoC 06–08) with actual GPU rendering on macOS. They are not speculative design — they describe what has been proven to work.

1. **`16-celldata-format-poc-validation`** [HIGH] — CellData format revision. PoC validated 16-byte fixed-size FlatCell; current spec is 20-byte variable-length. Fixed-size enables O(1) access, 20% bandwidth reduction. Design discussion needed: grapheme cluster separation, underline_color handling.
2. **`17-client-rendering-pipeline-revision`** [HIGH] — Fundamental architectural update. Client uses `importFlatCells()` → RenderState → `rebuildCells()` → `drawFrame()`, reusing ghostty's entire renderer. Doc 04 §3.2 and §4.1 normative notes need rewriting.
3. **`18-row-metadata-wire-format`** [MEDIUM] — `semantic_prompt` and `wrap` flags missing from RowData. `neverExtendBg()` needs `semantic_prompt` for correct padding rendering. Proposed: repurpose bits in existing `selection_flags` byte.
4. **`20-palette-sync-rendering-correctness`** [MEDIUM] — Colors/palette must be REQUIRED in I-frames, not optional. `neverExtendBg()` uses `default_background`; palette-indexed cells need palette for resolution.
5. **`19-minimum-terminal-dimensions`** [MEDIUM] — PoC crashed in `rebuildRow()` with small dimensions. Protocol should specify minimum rendering dimensions and server/client behavior.
6. **`21-poc-performance-baseline`** [LOW] — Replace size estimates with measured data (34 µs export+import for 80×24, ~4 ns/cell).

### Priority 1: CRITICAL (from original v0.8 review)

7. **`01-scroll-delivery-design`** — Revert incorrect V2-04 text. Scroll I-frames go through ring buffer. Affects doc 04 §6.1. This is a correctness issue from v0.7 that was deferred through v0.8 (single-topic scope).

### Priority 2: HIGH (from original v0.8 review)

8. **`02-preeditend-reason-cleanup`** — Remove `"input_method_changed"` as a PreeditEnd reason. Use `"cancelled"` for `commit_current=false`, `"committed"` for `commit_current=true`. Affects doc 05 §4.1, §7.9.

### Priority 3: MEDIUM (design discussion needed)

9. **`03-mouse-preedit-interaction`** — Direction decided: MouseButton commits preedit, MouseScroll does not. Needs spec text.
10. **`04-zoom-split-interaction`** — Open discussion, no pre-selected direction.
11. **`05-pane-auto-close-on-exit`** — Direction decided: auto-close on process exit, cascade to session destroy. Needs spec text.
12. **`06-hyperlink-celldata-encoding`** — Open discussion. Pre-discussion research needed (ghostty hyperlink representation).

### Priority 4: LOW (confirm-and-close)

13. **`07-resolution-doc-text-fixes`** — Text corrections in v0.7 resolution doc.
14. **`08` through `15`** — 8 confirm-and-close items with owner-approved direction. Apply mechanically to spec docs. See each review note for the specific change.

### Owner note on scope

v0.8 was intentionally single-topic. v0.9 now has **21 review notes** (6 PoC-validated + 15 original) spanning CRITICAL to LOW across multiple docs. The owner may choose to:
- (a) Process PoC items (16–21) as a focused "PoC alignment" revision cycle (v0.9), then remaining items in v0.10
- (b) Process all in one revision cycle (large scope, longer verification)
- (c) Split by priority: v0.9 = Priority 0 + Priority 1, v0.10 = Priority 2–4
- (d) Batch confirm-and-close items (08–15) as mechanical changes with a lighter verification pass

**Recommended**: Option (a) — the PoC items are cohesive (all affect doc 04, specifically CellData/FrameUpdate/rendering pipeline), and aligning the spec with proven reality should take priority over theoretical design discussions.

---

## 5. PoC 06–08 Findings Summary (2026-03-08)

> Added post-v0.8 review. These findings are the primary driver for review notes 16–21.

### 5.1 Full rendering pipeline validated

The complete pipeline was proven with actual Metal GPU rendering on macOS:

```
Server: Terminal → RenderState.update() → bulkExport() → FlatCell[]
  ↓ wire
Client: FlatCell[] → importFlatCells() → RenderState → rebuildCells() → Metal drawFrame() → GPU → pixels
```

All cell types rendered correctly: ASCII, Korean wide chars (한글), bold/italic, RGB colors, 256-palette colors.

### 5.2 Key discovery: client reuses ghostty's entire renderer

The client does NOT need to manually resolve fonts, build CellText/CellBg buffers, or drive Metal shaders. By populating `RenderState` via `importFlatCells()`, the client calls ghostty's existing `rebuildCells()` which handles all rendering internally. This dramatically simplifies the client and means the protocol carries **semantic cell data for RenderState population**, not GPU-ready data.

### 5.3 Performance budget confirmed

| Operation | 80×24 | 300×80 |
|-----------|-------|--------|
| Server export | 22 µs | 217 µs |
| Client import | 12 µs | 96 µs |
| **Total** | **34 µs** | **313 µs** |
| % of 16.6 ms (60fps) | 0.2% | 1.9% |

Wire serialization is NOT the bottleneck. Font shaping and GPU rendering are.

### 5.4 FlatCell 16-byte format works

The PoC used a 16-byte fixed-size FlatCell (codepoint + wide + flags + fg + bg). No underline_color, no grapheme clusters. This was sufficient for all tested rendering scenarios. The current spec's 20-byte variable-length CellData may need revision.

### 5.5 Missing data identified

- Row metadata (`semantic_prompt`, `wrap`) not in wire format — needed by `neverExtendBg()`
- Palette/colors must be sent for rendering correctness (not optional)
- Minimum terminal size guard needed (crash at rows < 6 or cols < 60)
- Grapheme clusters (multi-codepoint) not tested — need arena allocation in importFlatCells()

### 5.6 Impact on design philosophy

Reinforces the v0.8 principle "ghostty is the rendering authority" — now with empirical proof. The client is a thin RenderState populator, not a custom renderer. All rendering decisions (font shaping, padding, cursor decoration) are made by ghostty's code running on the client, fed by server-provided semantic data.

---

## 6. New Conventions and Procedures

### 6.1 Verification loop termination criteria

Added to operational knowledge (not yet formalized in conventions): the owner may stop the verification loop when issues have declined to minor severity, new issues are cascading from the same section, and a supermajority (3/4) of verifiers report CLEAN. This should be considered for formalization in `docs/work-styles/03-design-workflow.md`.

### 6.2 Cross-team revision workflow

v0.8 demonstrated the full cross-team revision workflow for the first time:
- Phase 1: 7-person cross-team discussion (protocol + IME members)
- Phase 2: Assignment negotiation with fresh team, shutdown of unneeded agents
- Phase 3: Parallel document writing across both document sets
- Phase 4: Iterative verification/fix cycles (11 rounds)

This workflow is documented in the v0.8 TODO.md and can serve as a template for future cross-team revisions.

---

## 7. Pre-Discussion Research Tasks

### 7.1 For `06-hyperlink-celldata-encoding`

Research needed (carried forward from v0.7 handover): how does ghostty internally represent OSC 8 hyperlinks in its cell/page structure? Specifically:
- What is the hyperlink ID type and lifecycle?
- How are URIs stored and deduplicated?
- What data is available through the public API for serialization?

Source: `vendors/ghostty/`, look for `hyperlink` in the terminal page/cell structures.

### 7.2 For `01-scroll-delivery-design`

No research needed. The owner decision is clear: scroll I-frames go through the ring buffer. The fix is a revert of V2-04 text plus replacement wording. The review note contains the exact proposed change.

### 7.3 For `04-zoom-split-interaction`

Research may help: how do tmux and zellij handle zoom + split interactions? What happens when a zoomed pane's parent is split? What happens when a split target is inside a zoomed subtree?

Source: `~/dev/git/references/tmux/`, `~/dev/git/references/zellij/`.

### 7.4 For `16-celldata-format-poc-validation`

Research needed: how does ghostty internally handle grapheme clusters in `page.Cell`? Specifically:
- How is `content_tag = codepoint_grapheme` stored (page-level GraphemeData)?
- What is the frequency of multi-codepoint cells in real-world terminal output?
- Can grapheme data be separated from the cell array without breaking `importFlatCells()`?

This informs the decision between fixed-size CellData (with separate grapheme table) vs. variable-length CellData (current spec).

Source: `poc/06-renderstate-extraction/vendors/ghostty/src/terminal/page.zig`, `src/terminal/render.zig`.

### 7.5 For `17-client-rendering-pipeline-revision`

No research needed. PoC 08 proves the pipeline. The change is to update doc 04 §3.2 and §4.1 normative notes to match the validated architecture.

### 7.6 For `18-row-metadata-wire-format`

Research may help: which `page.Row` fields does ghostty's renderer actually read? Beyond `semantic_prompt` and `wrap`, are there other row-level flags that affect rendering? Check `src/renderer/generic.zig` for row-level accesses.

Source: `poc/06-renderstate-extraction/vendors/ghostty/src/renderer/`.
