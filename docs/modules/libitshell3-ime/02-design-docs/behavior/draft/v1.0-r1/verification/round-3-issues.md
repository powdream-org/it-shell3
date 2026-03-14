# Verification Round 3 — Issue List

**Cycle**: libitshell3-ime behavior v1.0-r1
**Date**: 2026-03-14
**Phase 1 verifiers**: consistency-verifier, semantic-verifier
**Phase 2 reviewers**: history-guardian, issue-reviewer

---

## Confirmed Issues

### ISSUE-R3-sem-1 [critical] `isPrintablePosition()` range contradicts behavioral non-printable classification

**Files**:
- `interface-contract/draft/v1.0-r8/02-types.md` Section 3.1 (`isPrintablePosition()`)
- `behavior/draft/v1.0-r1/01-processkey-algorithm.md` Section 2.1 Step 2, Section 3
- `behavior/draft/v1.0-r1/02-scenario-matrix.md` Section 3.1
- `behavior/draft/v1.0-r1/03-modifier-flush-policy.md` Section 2

**Description**: `isPrintablePosition()` is defined with range `hid_keycode >= 0x04 and
hid_keycode <= 0x38`. This range includes HID 0x28 (Enter), 0x29 (Escape), 0x2A
(Backspace), 0x2B (Tab), and 0x2C (Space). All three behavior documents classify these
as non-printable keys — `01-processkey-algorithm.md` lists "Enter, Tab, Escape" as
non-printable flush triggers; `02-scenario-matrix.md` Section 3.1 shows them forwarded
(not committed as text); `03-modifier-flush-policy.md` Section 2 lists Enter, Tab,
Escape as flush-triggering keys.

An implementor using `isPrintablePosition()` to implement the printability check in the
algorithm would misclassify these keys as printable and route them into the composition
engine instead of the flush/forward path — directly contradicting the scenario matrix.

**Fix**: Add a clarifying note in `01-processkey-algorithm.md` that "printable" in the
behavior doc context means HID-to-ASCII mappable (letters, digits, punctuation), and
that `isPrintablePosition()` from the interface contract MUST NOT be used as the
printability gate for the algorithm because its range includes non-printable control
keys (Enter, Escape, Backspace, Tab). The note should specify which HID codes are
printable for the purpose of this algorithm.

---

### ISSUE-R3-sem-2 [critical] `prev_preedit_len` (length-only) insufficient for `preedit_changed` semantics

**Files**:
- `behavior/draft/v1.0-r1/10-hangul-engine-internals.md` Section 1.1
- `behavior/draft/v1.0-r1/02-scenario-matrix.md` Section 5

**Description**: `10-hangul-engine-internals.md` Section 1.1 specifies `prev_preedit_len:
usize` — comparing byte lengths to determine `preedit_changed`. `02-scenario-matrix.md`
Section 5 requires `preedit_changed = true` when "non-null → different non-null",
regardless of length.

Length-only comparison fails when preedit content changes while byte length stays the
same. This is a concrete and common Korean 2-set case: consonant "ㄱ" (U+3131, 3 bytes
UTF-8) → syllable "가" (U+AC00, 3 bytes UTF-8) after pressing a vowel. The scenario
matrix row "Korean 가 (add vowel) → preedit_changed = true" (Section 3.2) is directly
violated — length-only tracking would produce `preedit_changed = false` for this
transition.

**Fix**: Replace `prev_preedit_len: usize` with content-based tracking in
`10-hangul-engine-internals.md` Section 1.1. The field should store the previous
preedit content (e.g., using the existing `preedit_buf` or a separate comparison
buffer) so that `preedit_changed` can be determined by content equality, not length.

---

## Dismissed Issues

| Issue | Reason |
|-------|--------|
| R3-cons-1 (minor) | Verification records reflect state at time of verification — expected to describe issues that subsequent fixes resolved |
| R3-cons-2 (minor) | Re-raise of dismissed ISSUE-4 (PLAN.md planning artifact, same principle) |

---

## Summary

| # | Severity | Status | Brief Title |
|---|----------|--------|-------------|
| R3-sem-1 | critical | confirmed | `isPrintablePosition()` range includes non-printable control keys |
| R3-sem-2 | critical | confirmed | `prev_preedit_len` length-only tracking violates `preedit_changed` semantics |
| R3-cons-1 | minor | dismissed | Stale verification records — historical false alarm |
| R3-cons-2 | minor | dismissed | PLAN.md label re-raise — same principle as ISSUE-4 |

**Confirmed**: 2 (2 critical)
**Dismissed**: 2
