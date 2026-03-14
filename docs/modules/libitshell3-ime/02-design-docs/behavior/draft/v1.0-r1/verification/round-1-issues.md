# Verification Round 1 — Issue List

**Cycle**: libitshell3-ime behavior v1.0-r1
**Date**: 2026-03-14
**Phase 1 verifiers**: consistency-verifier, semantic-verifier
**Phase 2 reviewers**: history-guardian, issue-reviewer

---

## Confirmed Issues

### ISSUE-1 [critical] `composition_state` ghost field in `02-scenario-matrix.md`

**Files**: `behavior/draft/v1.0-r1/02-scenario-matrix.md` (lines 18, 30)
**vs**: `interface-contract/draft/v1.0-r8/02-types.md` (current canonical ImeResult)

**Description**: `02-scenario-matrix.md` declares `ImeResult` with five fields including
`composition_state: ?[]const u8 = null` (line 30) and refers to "five ImeResult fields" (line 18).
The current canonical `ImeResult` in `interface-contract/v1.0-r8/02-types.md` defines only four
fields (`committed_text`, `preedit_text`, `forward_key`, `preedit_changed`). `composition_state`
was removed in v0.6 (Appendix I.1, Resolution 15 Change 1). The behavior doc introduces a field
that does not exist in the current interface contract.

Additionally, line 18 directs readers to `interface-contract 02-types.md` for `composition_state`
semantics — pointing them to a field that no longer exists there.

**Fix**: Remove `composition_state` from the struct definition; change "five fields" to "four
fields"; remove the cross-reference to `composition_state` semantics.

---

### ISSUE-2 [major] Stale v1.0-r3 daemon links in `10-hangul-engine-internals.md`

**Files**: `behavior/draft/v1.0-r1/10-hangul-engine-internals.md` (lines 158, 206)

**Description**: Both cross-references point to `daemon/draft/v1.0-r3/02-integration-boundaries.md`.
The current daemon design doc is v1.0-r4. The v1.0-r3 files exist so there is no 404, but the
links target a superseded revision.

**Fix**: Update both links to `daemon/draft/v1.0-r4/02-integration-boundaries.md`.

---

### ISSUE-3 [major] Daemon PTY consumption order in engine behavior doc

**Files**: `behavior/draft/v1.0-r1/03-modifier-flush-policy.md` (Section 3.2)
**vs**: `behavior/draft/v1.0-r1/01-processkey-algorithm.md` (Section 4)

**Description**: `03-modifier-flush-policy.md` Section 3.2 "Daemon Consumption Order" describes
Phase 2 daemon behavior (PTY write sequence: committed_text → preedit cache → forward_key).
`01-processkey-algorithm.md` Section 4 "Engine Isolation" explicitly states the engine has
"No Phase 2 knowledge: The engine does not know about PTY writes, ghostty key encoding, or
preedit overlay rendering." Engine behavior docs describing daemon's Phase 2 consumption order
contradict the stated scope and the isolation principle in `01-processkey-algorithm.md`.

**Fix**: Move the Section 3.2 daemon consumption order content out of `03-modifier-flush-policy.md`
(an engine behavior doc) to an appropriate daemon-side document, or remove it entirely if it
duplicates existing daemon docs. Replace with a note that daemon consumption order is out of scope
for the engine behavior docs.

---

### ISSUE-5 [minor] CTR-02 does not address disposition of `## 2. Processing Pipeline` heading

**File**: `interface-contract/inbox/cross-team-requests/01-behavior-team-extract-impl-content-from-v1.0.md`

**Description**: CTR-02 items 1 and 2 both target content under `## 2. Processing Pipeline` in
`01-overview.md`, removing all body content. After removal, the section heading would remain but
with no body. The CTR does not specify whether to keep the heading (as a section anchor stub) or
remove it entirely.

**Fix**: Add a clarification row or note to the CTR-02 change table specifying the heading's
disposition after content removal.

---

## Contested Issues (owner decision required)

### ISSUE-4 [major] PLAN.md CTR-02 table references "behavior doc 04"

**Files**: `PLAN.md` Section 4 CTR-02 rows 6–7
**vs**: `interface-contract/inbox/cross-team-requests/01-behavior-team-extract-impl-content-from-v1.0.md`

**Phase 2 split**: history-guardian CONFIRM / issue-reviewer DISMISS
**Dismiss reasoning**: PLAN.md is a planning artifact explicitly scheduled for deletion at commit
time. "behavior doc 04" is shorthand that maps to the 4th entry in PLAN.md Section 2's creation
table (`10-hangul-engine-internals.md`). The filed CTR-02 correctly uses `10-hangul-engine-internals.md`
throughout. No inconsistency exists in any normative document.
**Confirm reasoning**: PLAN.md is the resolution document for this cycle; its CTR-02 table and
the filed CTR-02 are inconsistent in their cross-reference labels.

**Owner decision needed**: Accept dismiss (PLAN.md is a planning artifact) or accept confirm
(fix PLAN.md before deletion)?

---

### ISSUE-6 [minor] CTR-04 adds `05-extensibility-and-deployment.md` not in PLAN.md explicit table

**Files**: `interface-contract/inbox/cross-team-requests/03-behavior-team-renumber-sections-from-v1.0.md`
**vs**: `PLAN.md` Section 4 CTR-04 table

**Phase 2 split**: history-guardian CONFIRM / issue-reviewer DISMISS
**Dismiss reasoning**: PLAN.md CTR-04's catch-all row "Any remaining docs" explicitly covers
`05-extensibility-and-deployment.md`. The filed CTR listing it explicitly is a permitted
refinement, not an inconsistency.
**Confirm reasoning**: The explicit table in PLAN.md only lists four targets; adding a fifth
could be seen as unauthorized scope expansion.

**Owner decision needed**: Accept dismiss (catch-all covers it) or accept confirm (update CTR-04)?

---

### ISSUE-7 [minor] `preedit_changed` column absent from `02-scenario-matrix.md` Section 4 truth table

**File**: `behavior/draft/v1.0-r1/02-scenario-matrix.md` (Section 4)

**Phase 2 split**: history-guardian CONFIRM / issue-reviewer DISMISS
**Dismiss reasoning**: Section 4 is explicitly a "Field Combination Summary" for the three
variable-content fields; `preedit_changed` semantics are fully covered in Sections 3.1–3.3
per-scenario tables and Section 5's transition table. The omission from Section 4 is intentional.
**Confirm reasoning**: Section 5 calls `preedit_changed` orthogonal and mandatory; the truth
table in Section 4 claims to show all valid field combinations but omits `preedit_changed`.
An implementor reading only Section 4 would not know what value to set.

**Owner decision needed**: Accept dismiss (intentional omission, covered elsewhere) or accept
confirm (add `preedit_changed` column to Section 4 table)?

---

## Summary

| # | Severity | Status | Brief Title |
|---|----------|--------|-------------|
| 1 | critical | confirmed | `composition_state` ghost field in `02-scenario-matrix.md` |
| 2 | major    | confirmed | Stale v1.0-r3 daemon links in `10-hangul-engine-internals.md` |
| 3 | major    | confirmed | Daemon PTY consumption order in engine behavior doc |
| 4 | major    | dismissed | PLAN.md "behavior doc 04" — planning artifact, filed CTR-02 is correct |
| 5 | minor    | confirmed | CTR-02 heading disposition gap |
| 6 | minor    | dismissed | CTR-04 scope — "Any remaining docs" catch-all covers it |
| 7 | minor    | confirmed | `preedit_changed` absent from Section 4 truth table |

**Confirmed (to fix)**: 5 (1 critical, 2 major, 2 minor)
**Dismissed**: 2 (ISSUE-4, ISSUE-6 — owner decision)
