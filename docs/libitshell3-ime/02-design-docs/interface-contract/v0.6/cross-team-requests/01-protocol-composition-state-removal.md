# Remove `composition_state` from ImeResult

**Date**: 2026-03-06
**Source team**: protocol
**Source version**: Protocol v0.7
**Source resolution**: Protocol v0.7 review note `04-composition-state-removal.md`
**Target docs**: IME Interface Contract v0.6 (Sections 3.2, 3.7, 6)
**Status**: open

---

## Context

During protocol v0.7 owner review, the `composition_state` field in PreeditUpdate (0x0401) was determined to have no practical consumer. No component uses this value for rendering, branching, or decision-making — rendering uses `preedit_text` via FrameUpdate, not `composition_state`.

A PoC (`poc/libhangul-states/probe.c`) additionally confirmed that the documented composition states have factual errors:

1. `ko_vowel_only` IS reachable in 2-set (contrary to doc claim that implicit ㅇ prevents it)
2. `ko_double_tail` is not distinguishable from `ko_syllable_with_tail` via libhangul's public API
3. 3-set keyboards produce `cho=0, jung=0, jong=1` (jongseong-only), a state with no corresponding constant

The protocol team is removing `composition_state` from PreeditUpdate and PreeditSync, and removing Section 3 (Korean Composition State Machine) entirely.

## Required Changes

1. **Remove `composition_state` field from `ImeResult`** (Section 3.2)
   - Current: `composition_state: ?[]const u8 = null` with doc comment referencing `HangulImeEngine.CompositionStates`
   - Change: Remove the field entirely
   - Rationale: No protocol consumer; server has no reason to produce this value

2. **Remove `CompositionStates` struct from `HangulImeEngine`** (Section 3.7)
   - Current: `pub const CompositionStates = struct { ... }` with 5 string constants (`leading_jamo`, `vowel_only`, `syllable_no_tail`, `syllable_with_tail`, `double_tail`)
   - Change: Remove the struct entirely
   - Rationale: Constants were only used for `ImeResult.composition_state`

3. **Remove `composition_state` column from scenario matrix** (Section 3.2)
   - Current: Scenario matrix has a `composition_state` column with values like `"ko_leading_jamo"`, `"ko_syllable_no_tail"`
   - Change: Remove the column
   - Rationale: Field no longer exists

4. **Remove `composition_state` memory model note** (Section 6)
   - Current: "Points to static string literals. Valid indefinitely — not invalidated by any method call."
   - Change: Remove this note
   - Rationale: Field no longer exists

5. **Update naming convention note** (Section 3.7)
   - Current: References `ko_` prefix for composition state constants
   - Change: Remove composition-state-specific naming convention. Retain input method identifier naming convention if still applicable.
   - Rationale: `ko_` prefix was specifically for `CompositionStates` strings

## Summary Table

| Target Doc | Section/Message | Change Type | Source Resolution |
|-----------|----------------|-------------|-------------------|
| IME Contract v0.6 | Section 3.2 `ImeResult` | Remove field | Protocol v0.7 review note 04 |
| IME Contract v0.6 | Section 3.2 scenario matrix | Remove column | Protocol v0.7 review note 04 |
| IME Contract v0.6 | Section 3.7 `CompositionStates` | Remove struct | Protocol v0.7 review note 04 |
| IME Contract v0.6 | Section 3.7 naming convention | Update note | Protocol v0.7 review note 04 |
| IME Contract v0.6 | Section 6 memory model | Remove note | Protocol v0.7 review note 04 |
