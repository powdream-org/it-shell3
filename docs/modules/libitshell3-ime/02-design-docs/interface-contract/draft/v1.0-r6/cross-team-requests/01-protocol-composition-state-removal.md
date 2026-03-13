# Remove `composition_state` from ImeResult and Simplify Preedit Model

**Date**: 2026-03-06 (initial), 2026-03-07 (expanded)
**Source team**: protocol
**Source version**: Protocol v0.7
**Source resolution**: Protocol v0.7 review note `04-preedit-protocol-overhaul.md`
**Target docs**: IME Interface Contract v0.6 (Sections 3.2, 3.7, 6)
**Status**: open

---

## Context

During protocol v0.7 owner review, two related decisions were made:

**1. `composition_state` removal (review note 04):** The `composition_state` field in PreeditUpdate (0x0401) has no practical consumer. No component uses this value for rendering, branching, or decision-making. A PoC (`poc/04-libhangul-states/probe.c`) confirmed factual errors in the documented states:
- `ko_vowel_only` IS reachable in 2-set (contrary to doc claim)
- `ko_double_tail` is not distinguishable from `ko_syllable_with_tail` via libhangul's public API
- 3-set keyboards produce `(0,0,1)` jongseong-only state with no corresponding constant

**2. Preedit rendering model change (review note 05, revised 2026-03-07):** A visual PoC (`poc/05-preedit-visual/`) confirmed that ghostty's Metal renderer handles preedit rendering (block cursor, positioning, width) when `ghostty_surface_preedit()` is called. In the daemon-client architecture, the server calls this on its own surface and serializes preedit as cell data in I/P-frames. The client does not know what is preedit. The FrameUpdate preedit JSON section, dual-channel design, and ring buffer bypass are all removed. `cursor_x`, `cursor_y`, `display_width` are removed from all preedit protocol messages.

The IME contract's `ImeResult` and `HangulImeEngine` need corresponding changes.

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
   - Current: References `ko_` prefix for composition state constants and includes a table of language prefixes
   - Change: Remove composition-state-specific naming convention entirely (the `ko_` prefix table, the `zh_pinyin_`/`zh_bopomofo_`/`zh_cangjie_` prefix table). Retain input method identifier naming convention if still applicable.
   - Rationale: `ko_` prefix was specifically for `CompositionStates` strings

6. **Update `setActiveInputMethod` return value description** (Section 3.6)
   - Current: Return value examples include `.composition_state = null`
   - Change: Remove `composition_state` from all `ImeResult` examples in Section 3.6
   - Rationale: Field no longer exists

## Summary Table

| Target Doc | Section/Message | Change Type | Source Resolution |
|-----------|----------------|-------------|-------------------|
| IME Contract v0.6 | Section 3.2 `ImeResult` | Remove field | Protocol v0.7 review note 04 (preedit overhaul) |
| IME Contract v0.6 | Section 3.2 scenario matrix | Remove column | Protocol v0.7 review note 04 (preedit overhaul) |
| IME Contract v0.6 | Section 3.7 `CompositionStates` | Remove struct | Protocol v0.7 review note 04 (preedit overhaul) |
| IME Contract v0.6 | Section 3.7 naming convention | Remove note | Protocol v0.7 review note 04 (preedit overhaul) |
| IME Contract v0.6 | Section 3.6 return value examples | Remove field refs | Protocol v0.7 review note 04 (preedit overhaul) |
| IME Contract v0.6 | Section 6 memory model | Remove note | Protocol v0.7 review note 04 (preedit overhaul) |
