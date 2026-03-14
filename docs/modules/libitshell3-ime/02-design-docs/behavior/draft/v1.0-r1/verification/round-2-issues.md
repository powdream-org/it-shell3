# Verification Round 2 — Issue List

**Cycle**: libitshell3-ime behavior v1.0-r1
**Date**: 2026-03-14
**Phase 1 verifiers**: consistency-verifier, semantic-verifier
**Phase 2 reviewers**: history-guardian, issue-reviewer (opus cross-verification)

---

## Confirmed Issues

### ISSUE-A [minor] Section 4 truth table bundles "false / true" in one preedit_changed cell

**File**: `behavior/draft/v1.0-r1/02-scenario-matrix.md` (Section 4)

**Description**: The row `non-null | null | null | false / true` conflates two distinct
sub-cases in a single `preedit_changed` cell:
- Direct mode printable → `preedit_changed = false` (no composition ever existed)
- Switch with active composition → `preedit_changed = true` (flush transitions preedit from non-null to null)

An implementor reading only Section 4 could misinterpret `false` as valid for flush scenarios.
Section 3's per-scenario tables correctly separate these cases; Section 4 should too.

**Fix**: Split the `non-null | null | null` row into two separate rows — one for direct mode
printable (preedit_changed=false) and one for switch with active composition (preedit_changed=true).

---

### ISSUE-F [minor] CTR-03 does not reference CTR-04 ordering dependency

**File**: `interface-contract/inbox/cross-team-requests/02-behavior-team-editorial-policy-from-v1.0.md`

**Description**: CTR-03 says "apply after CTR-02" but does not mention CTR-04. CTR-04 specifies
the authoritative execution sequence: CTR-02 → CTR-04 → CTR-03. A team reading only CTR-03 would
not know about CTR-04's required intermediate step (section renumbering must complete before the
editorial policy is finalized), and could apply the editorial policy against a section structure
that subsequently changes.

**Fix**: Add a reference to CTR-04 in CTR-03's execution ordering instructions, making the
dependency explicit: "Apply after CTR-02 and CTR-04 (renumbering must complete first)."

---

### ISSUE-R2-2 [major] CTR-02 missing instruction: update Section 3.6 cross-reference after Section 3.7 removal

**File**: `interface-contract/inbox/cross-team-requests/01-behavior-team-extract-impl-content-from-v1.0.md`

**Description**: CTR-02 Item 6 requests removal of Section 3.7 (`HangulImeEngine` concrete struct)
from `interface-contract/draft/v1.0-r8/03-engine-interface.md`. However, Section 3.6 of the same
document (line 145) contains: "The server MUST only send input method strings from the canonical
registry (Section 3.7)." After CTR-02 removes Section 3.7, this cross-reference becomes dangling.
CTR-02 as filed does not include an instruction to update or remove this reference.

**Fix**: Add a row to the CTR-02 required-changes table instructing the interface-contract team
to update Section 3.6 line 145's reference to Section 3.7, redirecting it to the canonical
registry location that survives after Section 3.7 is removed (e.g., IME contract Section 3.7 in
an earlier version or the behavior doc's registry reference).

---

### ISSUE-R2-6 [minor] Behavior doc source attribution will become stale after CTR-02 applied

**File**: `behavior/draft/v1.0-r1/02-scenario-matrix.md` (line 6)

**Description**: Line 6 reads:
`**Source**: [interface-contract 02-types.md §3.2](...) — ImeResult scenario matrix + direct mode behavior`

CTR-02 Item 3 will replace the scenario matrix in `interface-contract/02-types.md §3.2` with a
cross-reference stub pointing back to this behavior doc. After that change, the "Source"
attribution in this behavior doc will point to a section that no longer contains the original
content — making the attribution misleading.

Since this is fixable in our own document now, we address it proactively.

**Fix**: Change the attribution from a live "Source" link to a static "Extracted from" note that
remains accurate after CTR-02 is applied:
`**Extracted from**: interface-contract/draft/v1.0-r8/02-types.md §3.2 — content moved to this document; §3.2 will cross-reference back here after CTR-02 is applied`

---

## Dismissed Issues

| Issue | Reason |
|-------|--------|
| B (major) | CTR-02 items 5-6 already target this content for removal — open work order, not a defect |
| C (major) | CTR-02 items 1-2 already target this content for replacement — open work order |
| D (minor) | CTR-02 item 7 already targets this content — open work order |
| E (minor) | Covered by CTR-02 item 5 which targets Section 3.6 for reduction to observable behavior |
| R2-1 (major) | Stale links in interface-contract source docs — interface-contract team's responsibility; deferred until daemon reaches stable |
| R2-3 (minor) | Internal editorial consistency — behavior doc consistently uses "key" suffix throughout |
| R2-4 (minor) | Internal editorial convention — behavior doc uses consistent title case for key names |
| R2-5 (minor) | CTR-01 is an open work order for the daemon team — expected state |

---

## Summary

| # | Severity | Status | Brief Title |
|---|----------|--------|-------------|
| A | minor | confirmed | Section 4 truth table "false/true" bundled in one row |
| F | minor | confirmed | CTR-03 missing CTR-04 ordering dependency |
| R2-2 | major | confirmed | CTR-02 missing Section 3.6 dangling reference fix |
| R2-6 | minor | confirmed | Source attribution will become stale — fix proactively |
| B, C, D, E | major/minor | dismissed | Source docs not updated per CTRs — open work orders |
| R2-1 | major | dismissed | Stale links in source docs — deferred to daemon stable |
| R2-3, R2-4 | minor | dismissed | Cosmetic naming differences — editorial convention |
| R2-5 | minor | dismissed | Daemon CTR-01 open — expected state |

**Confirmed**: 4 (1 major, 3 minor)
**Dismissed**: 8
