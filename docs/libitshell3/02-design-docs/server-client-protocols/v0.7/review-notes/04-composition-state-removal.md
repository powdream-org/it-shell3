# Remove `composition_state` from Protocol

**Date**: 2026-03-06
**Raised by**: owner
**Severity**: HIGH
**Affected docs**: doc 05 (CJK Preedit Protocol), IME Interface Contract v0.6
**Status**: open

---

## Problem

`composition_state` is a string field in PreeditUpdate (0x0401) and PreeditSync (0x0403) that carries Korean composition state names like `"ko_leading_jamo"`, `"ko_syllable_with_tail"`, etc. This field has no practical consumer:

- **Rendering**: Clients MUST use FrameUpdate's preedit JSON, not PreeditUpdate. `composition_state` is not used for rendering.
- **Debug logging**: Any string would serve this purpose; a protocol-level field is not required.
- **Session snapshots**: v1 uses commit-on-restore — the exact composition state is discarded on restore.
- **Observer indicators**: `preedit.active: true/false` is sufficient.
- **Future composition resume**: Deferred to v2.

Additionally, the state values defined in the document have factual errors, confirmed by PoC (`poc/libhangul-states/probe.c`):

1. **`ko_vowel_only` reachability**: Doc 05 Section 3.1 claims this state is "not reachable in 2-set." PoC shows `has_choseong()=false, has_jungseong()=true` when typing a vowel key in 2-set. The implicit ㅇ is NOT reflected in `has_choseong()`.
2. **`ko_double_tail` distinguishability**: `has_jongseong()` returns the same value for single and compound jongseong. The public API cannot distinguish these without inspecting the actual jongseong codepoint. `ko_double_tail` as a separate state requires extra logic for zero practical benefit.
3. **Missing 3-set state**: In 3-set keyboards, `cho=0, jung=0, jong=1` (jongseong-only) is observable. This state is not defined in the document.

## Analysis

Section 3 of doc 05 (Korean Composition State Machine — ~300 lines including state diagram, transition table, backspace trace) exists to define the values and transitions of `composition_state`. If the field is removed, the entire section is removed.

The state machine duplicates libhangul's internal behavior. Since we wrap libhangul, the ground truth is `hangul_ic_process()` output, not our document. Maintaining a parallel state machine creates divergence risk with zero implementation value — no component implements against this state machine.

Cross-document impact: IME Interface Contract v0.6 defines `CompositionStates` constants in Section 3.7 (`HangulImeEngine`) and `composition_state` field in `ImeResult` (Section 3.2). Both would be removed. See companion review note in IME contract v0.6.

## Proposed Change

1. Remove `composition_state` field from PreeditUpdate (Section 2.2) and PreeditSync (Section 2.4).
2. Remove Section 3 entirely (Korean Composition State Machine — Sections 3.1 through 3.4).
3. Remove all `composition_state` references throughout doc 05.
4. Update Section 15 (Open Questions) — remove Q1 (Japanese/Chinese composition states), which is predicated on `composition_state` existing.

## Owner Decision

Owner initiated this review. Decision: remove `composition_state` and Section 3.

## Resolution

{Pending — to be applied in the next revision.}
