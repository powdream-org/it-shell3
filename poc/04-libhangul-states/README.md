# PoC: libhangul Observable Composition States

**Date**: 2026-03-06
**Triggered by**: Owner directive during protocol v0.7 / IME contract v0.6 review
**Question**: What composition states are actually observable from libhangul's public API (`has_choseong`, `has_jungseong`, `has_jongseong`) across keyboard layouts?

## Motivation

Protocol doc 05 Section 3 defines a Korean composition state machine with 5 named states (`ko_leading_jamo`, `ko_vowel_only`, `ko_syllable_no_tail`, `ko_syllable_with_tail`, `ko_double_tail`). During review, the question arose: does anyone actually need these states? To answer that, we first needed to verify what libhangul actually produces — are the documented states correct?

## What Was Tested

`probe.c` creates `HangulInputContext` instances for each keyboard layout and feeds keystroke sequences, logging `has_choseong()` / `has_jungseong()` / `has_jongseong()` / `is_empty()` after each key.

### Test matrix

| Group | Keyboard | What was tested |
|-------|----------|----------------|
| 1a-1k | 2-set ("2") | Consonant only, vowel only, C+V, C+V+C, compound jongseong, jamo reassignment, backspace decomposition, invalid jongseong (ㅃ) |
| 2a-2b | 3-set Final ("3f") | Standalone vowel, standalone jongseong, choseong scan |
| 3a | 3-set 390 ("39") | Standalone vowel scan |
| 4a-4b | Romaja ("ro") | Vowel alone, consonant+vowel |
| 5a | 2-set + COMBI_ON_DOUBLE_STROKE | Double consonant via repeated keystroke |
| 5b | 2-set + AUTO_REORDER | Vowel-then-consonant reordering |
| Exhaustive | 2-set all a-z | Every lowercase key from empty state |

## Build

```sh
cc -o probe probe.c ../ime-key-handling/libhangul/hangul/hangulctype.c \
   ../ime-key-handling/libhangul/hangul/hangulinputcontext.c \
   ../ime-key-handling/libhangul/hangul/hangulkeyboard.c \
   ../ime-key-handling/libhangul/hangul/hanja.c \
   -I ../ime-key-handling/libhangul -std=c99
```

## Findings

### 1. Observable state combinations

| cho | jung | jong | Observed in | Notes |
|-----|------|------|-------------|-------|
| 0 | 0 | 0 | All layouts | Empty (no composition) |
| 1 | 0 | 0 | All layouts | Consonant only |
| 0 | 1 | 0 | 2-set, 3-set | Vowel only |
| 0 | 0 | 1 | 3-set only | Jongseong only (left-hand keys in 3-set) |
| 1 | 1 | 0 | All layouts | Initial + vowel |
| 1 | 1 | 1 | All layouts | Full syllable (single or compound jongseong) |

Not observed: `(1,0,1)`, `(0,1,1)`.

### 2. `ko_vowel_only` IS reachable in 2-set

**Contradicts current documentation.** Doc 05 Section 3.1 and IME contract v0.5 note G.4 state that `ko_vowel_only` is "not reachable in 2-set" because "libhangul inserts an implicit ㅇ leading consonant."

PoC result: typing vowel key `'k'` in 2-set produces:
```
cho=0 jung=1 jong=0 empty=0  preedit=ㅏ
```

`has_choseong()` returns `false`. The implicit ㅇ is NOT reflected in the `has_choseong()` return value. The preedit string is the standalone vowel `ㅏ`, not `ㅇ+ㅏ`.

### 3. Single vs compound jongseong is NOT distinguishable

```
갈 (single jong ㄹ):  cho=1 jung=1 jong=1
갉 (compound jong ㄺ): cho=1 jung=1 jong=1
```

`has_jongseong()` returns `true` for both. The public API provides no way to distinguish single from compound jongseong without inspecting the preedit string and decomposing the syllable.

### 4. 3-set produces a state not in the document

3-set Final ("3f") has dedicated jongseong keys (left hand). Typing one produces:
```
cho=0 jung=0 jong=1  preedit=ㅇ  (key='a')
cho=0 jung=0 jong=1  preedit=ㅅ  (key='q')
cho=0 jung=0 jong=1  preedit=ㄴ  (key='s')
```

This `(0,0,1)` state has no corresponding `CompositionStates` constant.

### 5. Romaja inserts implicit ㅇ immediately

```
'a' -> cho=1 jung=1 jong=0  preedit=아
```

Unlike 2-set, romaja produces `has_choseong()=true` for a standalone vowel input. The implicit ㅇ IS reflected in the API.

### 6. Options affect state reachability

- `COMBI_ON_DOUBLE_STROKE`: Enables `ㄱ+ㄱ=ㄲ` within `cho=1,jung=0,jong=0` state. No new states.
- `AUTO_REORDER`: Vowel-first input (`'k'` then `'r'`) produces `(0,1,0)` then `(1,1,0)`. Same states, different transition path.

## Known Limitations

- Only tested lowercase a-z keys. Shift variants (uppercase) tested selectively.
- Did not test `"2y"`, `"3s"`, `"3y"`, `"ahn"` keyboard layouts.
- Did not test extended/historical jamo (`JAMO_YET`, `JASO_YET` keyboard types).
- libhangul version: whatever is cloned in `poc/01-ime-key-handling/libhangul/` (main branch).

## Impact on Design

These findings led to the decision to remove `composition_state` from the protocol and IME interface:

1. **No practical consumer**: No component uses `composition_state` for rendering, branching, or decision-making.
2. **Documented states are incorrect**: `ko_vowel_only` reachability in 2-set is wrong. Missing 3-set state. `ko_double_tail` requires extra logic for no benefit.
3. **Libhangul is the ground truth**: Maintaining a parallel state machine in our docs creates divergence risk.

See review notes:
- Protocol v0.7: `review-notes/04-composition-state-removal.md`
- Protocol v0.7: `review-notes/05-preedit-rendering-model.md`
- IME contract v0.6: `cross-team-requests/01-protocol-composition-state-removal.md`
