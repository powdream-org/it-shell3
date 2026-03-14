# hangul_ic_process() Return-False Handling

**Status**: Draft v1.0-r1
**Date**: 2026-03-14
**Scope**: Algorithm for handling `hangul_ic_process()` returning `false` (key rejected by libhangul), including correct call sequence for commit/preedit string extraction.

> This document describes **implementation behavior** of the `HangulImeEngine` when libhangul rejects a key. For the caller-facing API contract, see [interface-contract](../../interface-contract/draft/v1.0-r8/01-overview.md).

---

## 1. When Does hangul_ic_process() Return False?

When `hangul_ic_process()` returns `false`, libhangul rejected the key -- it is not a valid jamo for the current keyboard layout. This occurs with:

- Punctuation (`.`, `,`, `!`, `?`, etc.)
- Certain number keys (depending on keyboard layout)
- Other characters libhangul does not recognize as jamo

Returning `false` does NOT mean "nothing happened." libhangul may still update its internal commit and preedit buffers as a side effect (e.g., a syllable break triggered by the rejected character).

---

## 2. Correct Handling Algorithm

```
1. Call hangul_ic_process(hic, ascii).

2. REGARDLESS of return value:
   Check hangul_ic_get_commit_string(hic).
   Check hangul_ic_get_preedit_string(hic).
   (libhangul may update these even when returning false.)

3. IF hangul_ic_process() returned false:
   a. If composition was non-empty, flush remaining composition
      via hangul_ic_flush(hic).
   b. Forward the rejected key to the terminal.

4. Populate ImeResult with:
   - Any committed text (from step 2 + step 3a)
   - Updated preedit (from step 2, or null if flushed)
   - The forwarded key (from step 3b, or null if consumed)
```

### 2.1 Critical: Always Check Buffers Regardless of Return Value

The most common mistake is to skip buffer checks when `hangul_ic_process()` returns `false`. libhangul may produce committed text even on a rejected key. For example, if the composition state triggers a syllable break before rejecting the character, `hangul_ic_get_commit_string()` will contain the completed syllable.

The correct pattern is:

1. Call `hangul_ic_process(hic, ascii)`.
2. **Always** read `hangul_ic_get_commit_string()` and `hangul_ic_get_preedit_string()`.
3. **Then** check the return value to decide whether to flush and forward.

---

## 3. Worked Example

**Scenario**: User types "ㅎ" (leading consonant) then "." (period).

1. `hangul_ic_process(hic, '.')` returns `false` -- period is not a jamo.
2. Check buffers:
   - `hangul_ic_get_commit_string()` returns empty (no syllable break triggered by period).
   - `hangul_ic_get_preedit_string()` still returns "ㅎ" (still composing).
3. Since `hangul_ic_process()` returned false:
   - Composition was non-empty ("ㅎ" in preedit), so flush via `hangul_ic_flush()` -- produces committed text "ㅎ".
   - Forward "." to the terminal.
4. Final `ImeResult`:

```
ImeResult{
    .committed_text = "ㅎ",
    .preedit_text = null,
    .forward_key = '.',
    .preedit_changed = true,
}
```

The user sees "ㅎ" committed to the terminal, followed by the period.

---

## 4. Edge Cases

### 4.1 Return-False with Empty Composition

If `hangul_ic_process()` returns `false` and no composition is in progress (engine is empty), there is nothing to flush. The key is simply forwarded.

```
ImeResult{
    .committed_text = null,
    .preedit_text = null,
    .forward_key = rejected_key,
    .preedit_changed = false,
}
```

### 4.2 Return-False with Syllable Break

Some keys may trigger a syllable break (producing committed text via `hangul_ic_get_commit_string()`) AND then be rejected (return `false`). In this case:

1. Committed text from the syllable break is captured in step 2.
2. Any remaining preedit is flushed in step 3a.
3. The rejected key is forwarded in step 3b.
4. All three pieces of information are combined into a single `ImeResult`.

---

## 5. PoC Validation

This algorithm was verified by PoC (`poc/02-ime-ghostty-real/poc-ghostty-real.m` lines 298-324).
