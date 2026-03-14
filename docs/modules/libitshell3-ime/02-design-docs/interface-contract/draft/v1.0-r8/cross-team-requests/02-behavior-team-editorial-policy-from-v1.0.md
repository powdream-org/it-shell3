# Editorial Policy: Keep Interface-Contract Caller-Facing Only

**Date**: 2026-03-14
**Source team**: ime-behavior
**Source version**: behavior draft/v1.0-r1
**Source resolution**: PLAN.md Section 4, CTR-03
**Target docs**: all interface-contract documents (current and future revisions)
**Status**: open

---

## Context

The behavior team has created a new `behavior/` topic (`behavior/draft/v1.0-r1/`) to house IME engine implementation details that were previously mixed into the interface-contract documents. CTR-02 (filed separately) removes the specific implementation content from the current interface-contract docs.

This CTR establishes a **normative editorial policy** to prevent implementation internals from re-entering the interface contract in future revisions. The interface contract is the caller-facing API spec consumed by the server/daemon team. It must not contain content that only the IME engine implementor needs -- that content belongs in `behavior/`.

## Required Changes

### 1. Add scope statement to document index

- **Target**: `01-overview.md` (Document Index section) or `00-index.md` if one is created
- **Current**: No explicit scope statement about what the interface contract covers
- **After**: Add a one-line scope statement immediately after the Document Index table:

  > **Scope**: This document set covers the caller-facing API only. For engine implementation details (internal algorithms, libhangul API usage, buffer layout, struct fields), see `behavior/`.

- **Rationale**: Readers and future authors need an upfront statement of what belongs here vs. in `behavior/`

### 2. Establish normative editorial policy for all future revisions

- **Target**: All interface-contract documents, current and future
- **Policy rule** (normative):

  > The interface contract MUST NOT include:
  > - Internal implementation details of any `ImeEngine` concrete type (struct fields, buffer layout, allocation strategy, algorithmic decision trees).
  > - Language-specific internals (libhangul API call sequences, `hangul_ic_process()` handling, keyboard ID mapping, etc.).
  >
  > All such content belongs in the corresponding `behavior/` document. The interface contract MAY cross-reference behavior docs for implementors, but MUST remain self-contained for callers who do not read behavior docs.

- **Enforcement**: Authors must apply this policy at authoring time. Reviewers must flag violations during review.
- **Rationale**: The interface contract and behavior docs serve different audiences. Mixing concerns makes both harder to maintain and creates duplication that leads to inconsistency.

## Constraints

- **Apply after CTR-02**: CTR-02 (content removal) must be applied first so that the interface-contract documents contain only caller-facing content.
- **Apply after CTR-04**: CTR-04 (section renumbering) must be applied second so that the section structure is stable before this editorial policy is formalized against it.
- **Execution order**: CTR-02 (remove content) → CTR-04 (renumber sections) → CTR-03 (editorial policy).

## Summary Table

| Target Doc | Section/Message | Change Type | Source Resolution |
|-----------|----------------|-------------|-------------------|
| `01-overview.md` (or `00-index.md`) | Document Index | Add scope statement | PLAN.md CTR-03 |
| All interface-contract docs | All future revisions | Enforce editorial policy at authoring and review time | PLAN.md CTR-03 |
