# Consistency Review Notes: IME Interface Contract v0.5

> **Status**: CLEAN — all minor, deferred to v0.6
> **Date**: 2026-03-05
> **Reviewers**: 3 fresh-context agents (no prior knowledge of changes)
> **Rounds**: 2 (first round with fix application + second round with fresh agents)

---

## Verdict

The document passed fresh-context verification. 7 minor/cosmetic issues found, no structural or correctness problems. All deferred to v0.6 polish pass.

## Minor Issues (deferred to v0.6)

### A-1: Ctrl+C vs Cmd+C confusion (Section 2, line ~92)

Example describes forwarding Ctrl+C but then says "If Cmd+C is bound to 'copy', it fires." Should stay consistent with Ctrl+C.

### A-2: Scenario matrix column header brevity (Section 3.2)

Column headers use `committed` and `preedit` while struct fields are `committed_text` and `preedit_text`. Acceptable table brevity but noted.

### IME-1: Missing ko_double_tail scenario matrix row (Section 3.2)

`ko_double_tail` is defined in CompositionStates but never appears in the scenario matrix. Unlike `ko_vowel_only` (which has a 3-set disclaimer), `ko_double_tail` IS reachable in 2-set (e.g., "없" with ㅂㅅ double tail).

**Fix**: Add a scenario row OR add a disclaimer similar to the `ko_vowel_only` note.

### IME-2: Generic backspace row name (Section 3.2, line ~272)

"Backspace mid-composition" shows one specific case (한→하). Other backspace cases produce different states. Very low severity — the specific preedit value makes the case clear.

### IME-3: Missing .composition_state in setActiveInputMethod Case 1 (Section 3.6, line ~455)

ImeResult example omits `.composition_state = null`. Functionally correct (null is default) but inconsistent with the document's explicit-fields pattern.

### CJK-1: Stale v0.4 reference in protocol doc 04 v0.6 (cross-doc)

Protocol doc 04 v0.6 line ~132 says "See IME Interface Contract **v0.4**, Section 3.1" — should say v0.5 or be versionless. This is a protocol doc issue, not an IME contract issue.

### CJK-2: display_width not in Responsibility Matrix (Section 4)

UAX #11 / display_width computation is not explicitly assigned. Implicitly covered by server responsibility but an explicit row would clarify.

---

## Verified Clean Areas (25 items)

All internal cross-references, struct definitions, vtable methods, composition state constants, null usage, terminology, section numbering, appendix accuracy, superseded references, memory ownership, modifier handling, processKey pipeline, flush/reset/deactivate lifecycle, libhangul API references, cross-doc references, naming convention, design principles, Korean text examples, and future CJK extensibility — all verified correct.
