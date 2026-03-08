# Protocol v0.9 TODO

## Scope

Priority 0 only (PoC-validated items: review notes 16–21). All other review notes (01–15) carry over to v0.10.

## Phase 1: Pre-Discussion Research

- [x] ghostty grapheme cluster internals (for review note 16 — CellData format)
- [x] ghostty row metadata fields used by renderer (for review note 18 — row metadata wire format)

## Phase 2: Discussion & Consensus (review notes 16–21)

- [x] RN-16: CellData format — 16-byte FlatCell vs 20-byte spec, grapheme separation, underline_color
- [x] RN-17: Client rendering pipeline — importFlatCells() → rebuildCells() → drawFrame()
- [x] RN-18: Row metadata wire format — semantic_prompt, wrap flags
- [x] RN-19: Minimum terminal dimensions — server/client behavior
- [x] RN-20: Palette sync rendering correctness — colors REQUIRED in I-frames
- [x] RN-21: PoC performance baseline — replace estimates with measured data
- [x] Consensus reporter delivers final report

## Phase 3: Resolution Document & Verification

- [x] Representative writes design-resolutions document
- [x] All team members verify resolution against consensus (same agents) — 5/5 APPROVED
- [x] Disband discussion team

## Phase 4: Assignment Negotiation

- [x] Spawn fresh team, pass resolution document
- [x] Team negotiates document ownership
- [x] Shutdown unassigned agents

## Phase 5: Document Writing

- [x] Team leader gates writing start
- [x] Apply changes to doc 04 (primary target)
- [x] Changes applied to docs 01, 06 (propagation from doc 04 changes)
- [x] Writing complete

## Phase 6: Cross-Document Verification

- [x] Round 1: 5 issues found (4 critical, 1 minor) — all fixed
- [x] Round 2: 4 issues found (3 critical, 1 minor) — all fixed
- [x] Round 3: 3 issues found (all minor) — 2 in-scope fixed, 1 out-of-scope (R3-T01, doc 03) carried to v0.10
- [x] Cascading assessment: NOT cascading (regressions: 0 → 1 critical → 1 minor, converging)

## Phase 7: Commit & Report

- [x] Verification clean for v0.9 scope
- [ ] Commit v0.9 documents
- [ ] Report to owner

## Carryover to v0.10

- Review notes 01–15 (from v0.8 handover)
- R3-T01: Doc 03 §1.6/§1.14 — "frame_type=2" in attach sequence should be "frame_type=1 or frame_type=2"
