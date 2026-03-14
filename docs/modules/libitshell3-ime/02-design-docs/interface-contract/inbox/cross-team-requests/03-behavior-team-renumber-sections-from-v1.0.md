# Renumber Section Ordering Across All Interface-Contract Documents

**Date**: 2026-03-14
**Source team**: ime-behavior
**Source version**: IME behavior draft/v1.0-r1
**Source resolution**: [behavior PLAN.md §4, CTR-04](../../../../behavior/draft/v1.0-r1/PLAN.md)
**Target docs**: 01-overview.md, 02-types.md, 03-engine-interface.md, 04-ghostty-integration.md, 05-extensibility-and-deployment.md
**Status**: open

---

## Context

The current section numbering across the interface-contract design docs uses a single continuous sequence spanning multiple files (e.g., Section 3 starts in `02-types.md` and continues through `03-engine-interface.md`). This creates several problems:

1. **Cross-file section spans**: Section 3 ("Interface Types") spans two files (`02-types.md` §3.1–3.4 and `03-engine-interface.md` §3.5–3.8). Adding or removing subsections in one file shifts numbers in the other.
2. **Numbering gaps**: `01-overview.md` jumps from Section 2 to Section 4 (no Section 3). `04-ghostty-integration.md` jumps from Section 5 to Section 6 without matching the file's position in the document set.
3. **Post-CTR-02 gaps**: After CTR-02 removes implementation content (e.g., `03-engine-interface.md` §3.7 `HangulImeEngine` removed entirely), the remaining sections will have additional numbering holes.

Each document should have its own independent, sequential section numbering starting from 1. This makes documents self-contained and eliminates cross-file numbering dependencies.

## Required Changes

### 1. Renumber `01-overview.md`

**Current numbering**: 1, 2, 4
**Target**: Renumber all top-level and nested sections sequentially from 1.

After CTR-02 removes the Phase 1 algorithm block (lines 57–67) and hangul_ic_process() return-false section (lines 71–92), the remaining sections should be renumbered to fill gaps.

### 2. Renumber `02-types.md`

**Current numbering**: 3.1, 3.2, 3.3, 3.4
**Target**: Renumber to 1, 1.1, 1.2, 1.3, 1.4 (or appropriate sequential scheme per final structure).

After CTR-02 removes the scenario matrix from §3.2 and the modifier flush policy from §3.3, renumber the remaining sections.

### 3. Renumber `03-engine-interface.md`

**Current numbering**: 3.5, 3.6, 3.7, 3.8
**Target**: Renumber to 1, 1.1, 1.2, 1.3 (or appropriate sequential scheme per final structure).

After CTR-02 removes §3.7 (`HangulImeEngine`) entirely and reduces §3.6 to observable behavior only, renumber remaining sections.

### 4. Renumber `04-ghostty-integration.md`

**Current numbering**: 5, 6
**Target**: Renumber to 1, 2 (or appropriate sequential scheme per final structure).

After CTR-02 removes the buffer layout content from §6, renumber the remaining sections.

### 5. Renumber `05-extensibility-and-deployment.md`

**Current numbering**: 7, 8, 9
**Target**: Renumber to 1, 2, 3 (or appropriate sequential scheme per final structure).

### 6. Update all internal cross-references

After renumbering, update every cross-reference within and across documents:
- Section references: `§ 3.2`, `see Section 4.1`, `Section 3.3`, etc.
- Anchor links: `#3-interface-types`, `#35-imeengine`, etc.
- Index/TOC entries in `01-overview.md` Document Index table.

## Constraints

- **Apply after CTR-02**: This CTR must be applied after CTR-02 (content removal) is complete, so renumbering reflects the final document structure.
- **Apply before CTR-03**: The editorial policy (CTR-03) references section structure; renumbering should stabilize before the policy is formalized.
- **Execution order**: CTR-02 (remove content) -> CTR-04 (renumber) -> CTR-03 (editorial policy, ongoing).

## Summary Table

| Target Doc | Section/Message | Change Type | Source Resolution |
|-----------|----------------|-------------|-------------------|
| `01-overview.md` | All sections | Renumber sequentially from 1 | PLAN.md §4, CTR-04 |
| `02-types.md` | All sections | Renumber sequentially from 1 | PLAN.md §4, CTR-04 |
| `03-engine-interface.md` | All sections | Renumber sequentially from 1 | PLAN.md §4, CTR-04 |
| `04-ghostty-integration.md` | All sections | Renumber sequentially from 1 | PLAN.md §4, CTR-04 |
| `05-extensibility-and-deployment.md` | All sections | Renumber sequentially from 1 | PLAN.md §4, CTR-04 |
| All docs | Internal cross-references | Update to match new numbers | PLAN.md §4, CTR-04 |
| `01-overview.md` | Document Index table | Update section references | PLAN.md §4, CTR-04 |
