# Research: libhangul Observable Composition States

**Date**: 2026-03-06
**Source**: libhangul (https://github.com/libhangul/libhangul)
**Git SHA**: `a34aef73378c0992316861bbf13fc914ee7577d9` (cloned in `poc/01-ime-key-handling/libhangul/`)
**Verified by**: `poc/04-libhangul-states/probe.c`

---

## Context

Protocol doc 05 Section 3 defines 5 Korean composition states (`ko_leading_jamo`, `ko_vowel_only`, `ko_syllable_no_tail`, `ko_syllable_with_tail`, `ko_double_tail`). This research verifies what states are actually observable from libhangul's public API across keyboard layouts.

## Source Files Analyzed

- `hangul/hangulinputcontext.c` — `hangul_ic_process()`, `hangul_ic_get_preedit_string()`, `hangul_ic_get_commit_string()`
- `hangul/hangul.h` — public API: `hangul_buffer_has_choseong()`, `hangul_buffer_has_jungseong()`, `hangul_buffer_has_jongseong()`, `hangul_buffer_is_empty()`

## Findings

### 1. Observable state combinations

The public API exposes 3 boolean flags (`has_choseong`, `has_jungseong`, `has_jongseong`). The observable combinations from the PoC:

| cho | jung | jong | Observed in | Notes |
|-----|------|------|-------------|-------|
| 0 | 0 | 0 | All layouts | Empty (no composition) |
| 1 | 0 | 0 | All layouts | Consonant only |
| 0 | 1 | 0 | 2-set, 3-set | Vowel only |
| 0 | 0 | 1 | 3-set only | Jongseong only (left-hand keys in 3-set Final) |
| 1 | 1 | 0 | All layouts | Initial + vowel |
| 1 | 1 | 1 | All layouts | Full syllable (single or compound jongseong) |

Not observed: `(1,0,1)`, `(0,1,1)`.

### 2. `ko_vowel_only` IS reachable in 2-set

Doc 05 Section 3.1 and IME contract v0.5 note G.4 state that `ko_vowel_only` is "not reachable in 2-set" because "libhangul inserts an implicit ㅇ leading consonant."

PoC result: typing vowel key `'k'` in 2-set produces:
```
cho=0 jung=1 jong=0 empty=0  preedit=ㅏ
```

`has_choseong()` returns `false`. The implicit ㅇ is NOT reflected in `has_choseong()`. The preedit string is the standalone vowel `ㅏ`, not `ㅇ+ㅏ`.

### 3. Single vs compound jongseong is NOT distinguishable

```
갈 (single jong ㄹ):  cho=1 jung=1 jong=1
갉 (compound jong ㄺ): cho=1 jung=1 jong=1
```

`has_jongseong()` returns `true` for both. The public API provides no way to distinguish single from compound jongseong without inspecting the preedit string and decomposing the Unicode syllable.

### 4. 3-set produces a state not in our documents

3-set Final (`"3f"`) has dedicated jongseong keys (left hand). Typing one produces:
```
cho=0 jung=0 jong=1  preedit=ㅇ  (key='a')
cho=0 jung=0 jong=1  preedit=ㅅ  (key='q')
cho=0 jung=0 jong=1  preedit=ㄴ  (key='s')
```

This `(0,0,1)` state has no corresponding `CompositionStates` constant in our protocol or IME contract.

### 5. Romaja inserts implicit ㅇ immediately

```
'a' -> cho=1 jung=1 jong=0  preedit=아
```

Unlike 2-set, romaja produces `has_choseong()=true` for a standalone vowel input. The implicit ㅇ IS reflected in the API. Behavior differs between keyboard layouts.

### 6. Options affect state reachability but not the set of states

- `COMBI_ON_DOUBLE_STROKE`: Enables `ㄱ+ㄱ=ㄲ` within `cho=1,jung=0,jong=0` state. No new states.
- `AUTO_REORDER`: Vowel-first input (`'k'` then `'r'`) produces `(0,1,0)` then `(1,1,0)`. Same states, different transition path.

## Trade-offs

- **libhangul's public API is intentionally minimal** — 3 booleans + preedit string. It does not expose a named state enum. Any composition state tracking beyond these booleans requires reverse-engineering the preedit string.
- **Preedit string is the reliable ground truth** — it always accurately reflects what the user sees. The boolean flags are a coarse approximation.

## Known Limitations

- Only tested lowercase a-z keys. Shift variants tested selectively.
- Did not test `"2y"`, `"3s"`, `"3y"`, `"ahn"` keyboard layouts.
- Did not test extended/historical jamo (`JAMO_YET`, `JASO_YET` keyboard types).
