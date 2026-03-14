# IME Interface Contract v1.0-r9 TODO

> **Inputs:**
> - Review note 01: `draft/v1.0-r8/review-notes/01-surface-api-references-in-comments.md` (LOW)
> - Handover: `draft/v1.0-r8/handover/handover-to-v09.md`
> - CTR-02: `draft/v1.0-r8/cross-team-requests/01-behavior-team-extract-impl-content-from-v1.0.md`
> - CTR-03: `draft/v1.0-r8/cross-team-requests/02-behavior-team-editorial-policy-from-v1.0.md`
> - CTR-04: `draft/v1.0-r8/cross-team-requests/03-behavior-team-renumber-sections-from-v1.0.md`
>
> **Owner additional requirement:** Section numbering consistency comprehensive check
> (scope A: 5 interface-contract docs only).
>
> **Mandatory execution order (from CTR-03):** CTR-02 → CTR-04 → CTR-03

## Phase 1: Discussion & Consensus (3.2)

- [x] Team discusses all inputs; consensus reporter delivers unprompted

## Phase 2: Resolution Document (3.3)

- [x] Representative writes `design-resolutions/` doc
- [x] All members verify resolution
- [x] Team leader shuts down all agents (memory wipe)

## Phase 3: Assignment Negotiation (3.4)

- [x] Spawn fresh agents; negotiate doc ownership
- [x] Team leader confirms assignment; shuts down unassigned agents

## Phase 4: Document Writing (3.5)

Changes to apply (in order):

### CTR-02: Remove implementation content → cross-references

- [x] `01-overview.md` lines 57–67: Remove processKey() internal decision tree → cross-ref
      to `behavior/draft/v1.0-r1/01-processkey-algorithm.md`
- [x] `01-overview.md` lines 71–92: Remove hangul_ic_process() return-false handling → cross-ref
      to `behavior/draft/v1.0-r1/11-hangul-ic-process-handling.md`
- [x] `01-overview.md`: Remove `## 2. Processing Pipeline` heading (empty after above removals)
- [x] `02-types.md` lines 125–158: Remove scenario matrix + direct mode behavior → cross-ref
      to `behavior/draft/v1.0-r1/02-scenario-matrix.md`
- [x] `02-types.md` lines 160–186: Remove Modifier Flush Policy section body → cross-ref
      to `behavior/draft/v1.0-r1/03-modifier-flush-policy.md`
- [x] `03-engine-interface.md` lines 128–153: Keep observable spec; remove setActiveInputMethod
      internal steps → cross-ref to `behavior/draft/v1.0-r1/10-hangul-engine-internals.md` §4
- [x] `03-engine-interface.md` lines 159–248: Remove HangulImeEngine concrete struct entirely
      → cross-ref to `behavior/draft/v1.0-r1/10-hangul-engine-internals.md`
- [x] `03-engine-interface.md` line 145: Fix dangling "Section 3.7" reference
      → update to point to behavior doc canonical registry
- [x] `04-ghostty-integration.md` lines 17–31: Keep one-liner lifetime rule; remove buffer
      layout + sizing → cross-ref to `behavior/draft/v1.0-r1/10-hangul-engine-internals.md` §3

### Review note 01: Surface API references (LOW)

- [x] `02-types.md` line 118: Update/remove Surface API reference in comment
- [x] `03-engine-interface.md` line 289: Update/remove Surface API reference in comment

### CTR-04: Renumber sections (apply after CTR-02)

- [x] `01-overview.md`: Renumber all sections sequentially from 1; remove gaps (was 1,2,4)
- [x] `02-types.md`: Renumber 3.1–3.4 → 1, 1.1, 1.2, ... (per-document sequential)
- [x] `03-engine-interface.md`: Renumber 3.5–3.8 → 1, 1.1, 1.2, ... (per-document sequential)
- [x] `04-ghostty-integration.md`: Renumber 5,6 → 1, 2
- [x] `05-extensibility-and-deployment.md`: Renumber 7,8,9 → 1, 2, 3
- [x] All docs: Update all internal cross-references (section refs, anchor links)
- [x] `01-overview.md` Document Index table: Update section references

### CTR-03: Editorial policy scope statement (apply after CTR-04)

- [x] `01-overview.md` Document Index: Add scope statement (caller-facing only; impl details → `behavior/`)
- [x] Formalized editorial policy note added (for authors and reviewers)

## Phase 5: Verification (3.6–3.8)

- [x] **Round 1 (Phase 1):** Spawn consistency-verifier + semantic-verifier (fresh, Gemini)
  - Additional verification focus: section numbering consistency across all 5 interface-contract docs
- [x] **Round 1 (Phase 2):** Spawn history-guardian + issue-reviewer (fresh, Gemini)
  - 2 confirmed issues (C-MINOR-01, S-MINOR-01) → fix round applied
- [x] **Round 2 (Phase 1):** Spawn consistency-verifier + semantic-verifier (fresh, Gemini)
  - consistency-verifier: CLEAN; semantic-verifier: 1 issue (R2-MINOR-01)
- [x] **Round 2 (Phase 2):** Spawn history-guardian + issue-reviewer (fresh, Gemini)
  - R2-MINOR-01 CONTESTED → owner dismissed (MockImeEngine is non-normative)
- [x] CLEAN — proceed to commit

## Phase 6: Commit (3.9)

- [x] Commit `draft/v1.0-r9/`
- [x] Report to owner
