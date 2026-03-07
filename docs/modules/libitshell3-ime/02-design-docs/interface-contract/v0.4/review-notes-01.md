# Review Notes 01: IME Interface Contract v0.4

> **Status**: Open — needs team discussion before next revision
> **Date**: 2026-03-05
> **Raised by**: spec-writer
> **Target version**: v0.5

---

## Issue 01: Composition State Prefix Convention — `ko_` vs BCP 47 (`ko-KR_`)

### Summary

The current contract uses ISO 639-1 two-letter language codes as prefixes for composition
state string constants (e.g., `ko_leading_jamo`, `ko_syllable_no_tail`). The design
explicitly anticipates future expansion to Chinese and Japanese. Chinese has significant
regional variants whose IME behaviors differ fundamentally. The choice of prefix convention
today will constrain or complicate that future expansion.

### Current Design

```zig
pub const CompositionStates = struct {
    pub const empty            = "empty";
    pub const leading_jamo     = "ko_leading_jamo";
    pub const vowel_only       = "ko_vowel_only";
    pub const syllable_no_tail = "ko_syllable_no_tail";
    pub const syllable_with_tail = "ko_syllable_with_tail";
    pub const double_tail      = "ko_double_tail";
};
```

The `ko_` prefix is ISO 639-1. No regional variant is encoded.

### Problem

Chinese has two major script/IME families with distinct composition states:

| Variant | Script | Primary input method | Composition model |
|---------|--------|---------------------|-------------------|
| `zh-CN` | Simplified | Pinyin | Syllable → tone → selection |
| `zh-TW` | Traditional | Zhuyin (Bopomofo) / Cangjie | Phoneme assembly or radical assembly |

These are not minor dialect differences — Pinyin and Bopomofo have entirely different
composition state graphs. If both use a `zh_` prefix, states from the two systems would
share a namespace and risk collision or ambiguity (e.g., `zh_syllable_pending` is
meaningless unless the caller knows which input method is active).

Japanese (`ja_`) also spans at least Hiragana and Katakana composition phases, but has
less regional divergence than Chinese.

Korean has no such regional ambiguity — `ko_` is unambiguous today and for the foreseeable
future.

### Options

**Option A — ISO 639-1 throughout** (`ko_`, `zh_`, `ja_`)

- Simpler and shorter.
- Works cleanly for Korean and Japanese (low regional variance in composition).
- Chinese variants would collide unless sub-namespaced by input method name
  (e.g., `zh_pinyin_syllable_pending` vs `zh_bopomofo_tone_pending`) — at which point the
  language prefix adds little value on its own.

**Option B — BCP 47 throughout** (`ko-KR_`, `zh-CN_`, `zh-TW_`, `ja-JP_`)

- Unambiguous for all current and anticipated variants.
- Verbose. Korean gains nothing from `ko-KR_` vs `ko_` since no other Korean locales
  exist with distinct IME behavior.
- Callers that match on these strings must track more granular identifiers.

**Option C — ISO 639-1 by default, BCP 47 only where ambiguous**

- `ko_` stays as-is (no regional variant ambiguity).
- `ja_` stays as-is (low regional IME divergence in practice).
- Chinese uses `zh-CN_` and `zh-TW_` (not `zh_`) to avoid cross-variant collision.
- Consistent rule: use ISO 639-1 unless two or more regional variants of the same language
  would otherwise share a prefix.

**Option D — Language-plus-method prefix** (e.g., `ko_2set_`, `zh_pinyin_`, `zh_bopomofo_`)

- Encodes the active input method rather than the regional locale.
- Aligns with how `setActiveInputMethod()` selects the engine (the method, not the region).
- Avoids the locale question entirely.
- Potentially more specific than necessary for Korean (there is only one 2-set composition
  state graph regardless of which 2-set variant is active).

### Constraints Carried Forward from Settled Decisions

- The `ko_` prefix itself is settled for Korean (see Settled Decisions in agent spec).
  Any resolution that renames existing `ko_` constants would require a dedicated revision
  and appendix entry — this should be avoided unless the benefit is clear.
- `composition_state` is `?[]const u8`. Callers compare by string equality. Any prefix
  change affects all call sites that switch on these values.

### Decision Needed

The team must answer:

1. Is Option C (ISO 639-1 by default, BCP 47 for Chinese) the right balance, or does
   uniformity (Option B) or method-centric naming (Option D) serve better?
2. If Option C or B is chosen: does `ko_` remain unchanged (given the settled decision),
   or do we accept a one-time rename to `ko-KR_` for consistency?
3. Are there languages other than Chinese for which ISO 639-1 would be insufficient before
   a hypothetical v2?

**Participants**: ime-expert (composition state graph authority), principal-architect
(contract architecture authority), cjk-specialist (Chinese/Japanese IME authority).

### Impact on Current v0.4 Contract

No immediate change required. Korean constants are not affected unless Option B is chosen
and the team accepts the rename cost. This is a forward-looking design question to resolve
before any Chinese or Japanese states are added to the contract.

---

## Issue 02: ImeResult Doc Comment Missing `deactivate()` in Invalidation List

### Summary

The ImeResult struct doc comment (Section 3.2, line ~193) lists the calls that invalidate
returned slices:

> "They are valid until the next call to processKey(), flush(), reset(), or
> setActiveInputMethod() on the SAME engine instance."

Section 6 (Memory Ownership, line ~954) correctly includes `deactivate()`:

> "Slices are valid until the next call to processKey(), flush(), reset(),
> **deactivate()**, or setActiveInputMethod() on the same engine instance."

`deactivate()` returns `ImeResult` and flushes composition (writing to `committed_buf` /
`preedit_buf`), so it DOES invalidate previous slices. The doc comment is incomplete.

### Impact

An implementor reading only the ImeResult doc comment might hold references across a
`deactivate()` call, causing use-after-write bugs.

### Fix

Add `deactivate()` to the ImeResult doc comment invalidation list:
`"...until the next call to processKey(), flush(), reset(), deactivate(), or
setActiveInputMethod()..."`

### Severity

Medium — correctness issue affecting memory safety guidance.

---

## Issue 03: Broken Cross-Reference in Appendix E.9

### Summary

Appendix E.9 (line ~1355) contains a "Superseded by" note linking to
`[F.6](#f6-session-persistence-simplified)`. The session persistence simplification is
actually in **F.5** (line ~1397). F.6 is "setActiveInputMethod String Parameter Ownership."

### Fix

Change `See [F.6](#f6-session-persistence-simplified)` to
`See [F.5](#f5-session-persistence-simplified)`.

### Severity

Low — broken Markdown anchor, no semantic impact.

---

## Issue 04: `"non_korean"` Composition State in Protocol but Not in IME Contract

### Summary

Protocol doc 05 Section 3.1 defines 7 composition state values, including `"non_korean"`
described as *"Non-Korean composition (future: Japanese, Chinese)"*. The IME contract's
`CompositionStates` struct (Section 3.7) defines only 6 values — `"non_korean"` is absent.

No v1 IME engine produces `"non_korean"`, so this is not a runtime inconsistency. However,
the protocol doc defines a wire value that no current engine can generate, which is unusual.

### Options

1. Add `"(reserved, v2+)"` annotation to `"non_korean"` in protocol doc 05.
2. Remove `"non_korean"` from protocol doc 05 entirely — future CJK engines will define
   their own language-prefixed states (e.g., `ja_hiragana_pending`), making a generic
   `"non_korean"` placeholder unnecessary.

### Note

This is a **cross-doc** issue. The fix belongs in protocol doc 05, not in the IME contract.

### Severity

Low — forward-looking placeholder, no v1 impact.

---

## Issue 05: `ko_vowel_only` and `CompositionStates.empty` Defined but Unreachable

### Summary

Two composition state constants are defined in both spec areas but never appear as target
states in any transition table:

1. **`ko_vowel_only`** — Defined in IME contract Section 3.7 and protocol doc 05 Section 3.1.
   Neither the IME scenario matrix (Section 3.2) nor the protocol transition table
   (doc 05 Section 3.3) produces this state. The transition `empty + vowel` goes to
   `ko_syllable_no_tail` (with implicit `ㅇ` leading), skipping `ko_vowel_only`.

2. **`CompositionStates.empty`** — Defined as `"empty"` in Section 3.7, but the ImeResult
   spec and scenario matrix consistently use `null` (not `"empty"`) for "no active
   composition". The document never explains when `"empty"` should be returned vs. `null`.

Both spec areas are internally consistent about this (neither uses these values in
transitions), but having defined-but-unreachable states is a spec hygiene concern.

### Decision Needed

1. Are these states intentionally reserved for edge cases (e.g., libhangul producing
   `ko_vowel_only` in scenarios not covered by the simplified transition table)?
2. Should `CompositionStates.empty` be clarified as engine-internal only, with a note
   that `ImeResult.composition_state` uses `null` for "no composition"?

### Severity

Negligible — no runtime impact, spec hygiene only.

---

_No other open issues at this time._
