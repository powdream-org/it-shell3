# 00041. Length-Only Preedit Dirty Tracking

- Date: 2026-03-23
- Status: Accepted

## Context

`HangulImeEngine.processKey()` must set `preedit_changed` accurately so the
daemon can skip redundant preedit updates to clients. The obvious approach is
content-based comparison: store the previous preedit bytes in a
`prev_preedit_buf` and compare byte-by-byte after each keystroke.

A simpler approach is length-only comparison using `prev_preedit_len`, with a
shortcut rule: any non-null → non-null preedit transition is always marked as
changed. This avoids a 64-byte buffer copy and memcmp per keystroke.

The concern with length-only tracking is that two different Korean syllables can
have the same UTF-8 byte length. For example, "ㄱ" (U+3131) and "가" (U+AC00)
are both 3 bytes in UTF-8. If the engine tracked only length, a ㄱ→가 transition
would report `preedit_changed = false` — a silent rendering bug.

The question is whether the non-null → non-null shortcut (always report changed)
is correct for all cases.

## Decision

Use length-only tracking (`prev_preedit_len`) with the invariant: **every
consumed keystroke changes preedit content**.

This relies on a behavioral guarantee of libhangul's composition engine:

- `hangul_ic_process()` consumes a key only when it advances composition state
  (adds choseong, jungseong, or jongseong, or triggers a syllable break). Each
  of these produces a different Unicode codepoint in the preedit string.
- `hangul_ic_backspace()` consumes a key only when it removes a jamo from the
  buffer, which always changes the resulting preedit codepoint (or empties the
  composition entirely).
- Neither function has a "consume but leave preedit unchanged" path.

Therefore, any non-null → non-null preedit transition after a consumed key
always means the content changed. The `prev_preedit_buf` content comparison is
unnecessary.

Verified by test N4 in `hangul_engine_test.zig`: composing ㄱ (3 bytes) then
adding a vowel to get 가 (3 bytes) correctly reports `preedit_changed = true`
despite identical byte lengths.

## Consequences

- Zero per-keystroke buffer copy overhead for dirty tracking. The engine stores
  only `prev_preedit_len: usize` (8 bytes) instead of `prev_preedit_buf: [64]u8`
  - `prev_preedit_len: usize` (72 bytes).
- The correctness of `preedit_changed` depends on the libhangul invariant that
  consumed keystrokes always change preedit content. If a future libhangul
  version introduces a "consume but no-op" path, this optimization would break.
  This is unlikely — the invariant is fundamental to how Hangul composition
  works (every jamo input changes the syllable).
- A future non-libhangul engine (e.g., Japanese) must satisfy the same invariant
  for this optimization to remain valid. If a future engine can consume a key
  without changing preedit content, it must use content-based tracking instead.
  This is an engine-specific implementation choice, not an interface contract
  requirement.
- The design doc `10-hangul-engine-internals.md` (v1.0-r2) specifies
  content-based tracking with `prev_preedit_buf`. The doc is incorrect — the
  implementation's length-only approach is the intended design. The doc should
  be updated to match (see review note 02).
