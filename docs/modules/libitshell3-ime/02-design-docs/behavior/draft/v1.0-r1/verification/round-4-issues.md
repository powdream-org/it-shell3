# Verification Round 4 — Issue List

**Cycle**: libitshell3-ime behavior v1.0-r1
**Date**: 2026-03-14
**Phase 1 verifiers**: consistency-verifier, semantic-verifier
**Phase 2 reviewers**: history-guardian, issue-reviewer

---

## Confirmed Issues (Deferred)

### ISSUE-R4-sem-1 [critical] Backspace incorrectly grouped with flush/forward-path keys in Step 2 note

**File**: `behavior/draft/v1.0-r1/01-processkey-algorithm.md` Section 2.1 Step 2 (lines 66–72)

**Description**: The note added in Round 3 to clarify the `isPrintablePosition()` range lists HID
0x2A (Backspace) alongside 0x28 (Enter), 0x29 (Escape), 0x2B (Tab), and 0x2C (Space), then
states: "All of these are non-printable for composition purposes and **must be routed to the
flush/forward path**."

This directly contradicts:
- `03-modifier-flush-policy.md` Section 2 policy table: Backspace → **IME handles** (language-specific
  undo via `hangul_ic_backspace()`; forward to terminal only if composition is empty)
- `02-scenario-matrix.md` Section 3.2: Backspace during composition produces an undo result
  (modified preedit), not a flush

Backspace is not a flush trigger. It has a distinct third path: the composition engine's undo
handler. The blanket statement "all of these → flush/forward" is incorrect for Backspace and
contradicts the normative policy in the other two documents.

**Root cause**: Cascade introduced by the Round 3 fix for R3-sem-1. The note correctly identifies
Backspace as non-printable, but then incorrectly assigns it to the flush/forward group.

**Fix (deferred to v1.0-r2)**: Separate Backspace (0x2A) from the flush/forward group in the
Step 2 note. The note should enumerate Enter, Escape, Tab, and Space as flush/forward keys, and
state Backspace separately as a key handled by the composition engine's undo path (see
`03-modifier-flush-policy.md` Section 2.3).

**Owner decision**: Deferred to v1.0-r2. Does not block current revision.

---

## Dismissed Issues

| Issue | Reason |
|-------|--------|
| R4-cons-1 (minor) | `**Status**: Draft v1.0-r1` vs `**Version**: v1.0-r1` is a cosmetic header variation with no semantic consequence — version identity is consistent across all documents |

---

## Summary

| # | Severity | Status | Brief Title |
|---|----------|--------|-------------|
| R4-sem-1 | critical | confirmed, deferred to v1.0-r2 | Backspace grouped with flush/forward keys in Step 2 note |
| R4-cons-1 | minor | dismissed | Header field name cosmetic variation |

**Confirmed (deferred)**: 1 (1 critical)
**Dismissed**: 1
