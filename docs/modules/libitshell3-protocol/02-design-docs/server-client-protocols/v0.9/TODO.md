# Protocol v0.9 TODO

## Scope

Priority 0 only (PoC-validated items: review notes 16–21). All other review notes (01–15) carry over to v0.10.

## Phase 1: Pre-Discussion Research

- [ ] ghostty grapheme cluster internals (for review note 16 — CellData format)
- [ ] ghostty row metadata fields used by renderer (for review note 18 — row metadata wire format)

## Phase 2: Discussion & Consensus (review notes 16–21)

- [ ] RN-16: CellData format — 16-byte FlatCell vs 20-byte spec, grapheme separation, underline_color
- [ ] RN-17: Client rendering pipeline — importFlatCells() → rebuildCells() → drawFrame()
- [ ] RN-18: Row metadata wire format — semantic_prompt, wrap flags
- [ ] RN-19: Minimum terminal dimensions — server/client behavior
- [ ] RN-20: Palette sync rendering correctness — colors REQUIRED in I-frames
- [ ] RN-21: PoC performance baseline — replace estimates with measured data
- [ ] Consensus reporter delivers final report

## Phase 3: Resolution Document & Verification

- [ ] Representative writes design-resolutions document
- [ ] All team members verify resolution against consensus (same agents)
- [ ] Disband discussion team

## Phase 4: Assignment Negotiation

- [ ] Spawn fresh team, pass resolution document
- [ ] Team negotiates document ownership
- [ ] Shutdown unassigned agents

## Phase 5: Document Writing

- [ ] Team leader gates writing start
- [ ] Apply changes to doc 04 (primary target)
- [ ] Apply changes to other affected docs (01, 03 if needed)
- [ ] Writing complete

## Phase 6: Cross-Document Verification

- [ ] Spawn verification team (4 verifiers)
- [ ] Independent verification pass
- [ ] Issue cross-validation (verifiers debate)
- [ ] Fix cycle if needed (repeat 4→5→6)

## Phase 7: Commit & Report

- [ ] Clean verification pass achieved
- [ ] Commit v0.9 documents
- [ ] Report to owner
