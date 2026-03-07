# Protocol Doc 05 Changes Required (from IME v0.5 Revision)

> **Date**: 2026-03-05
> **Source**: IME interface contract v0.5 revision (Issues 2.1, 2.4, 2.5b)
> **Target**: Protocol doc 05 v0.6 revision team
> **File**: `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/05-cjk-preedit-protocol.md`

---

These changes were agreed during the IME v0.5 revision (3-0 unanimous: principal-architect, ime-expert, cjk-specialist) but belong in the protocol docs, not the IME contract. The v0.6 protocol team should apply them.

## Change 1: Remove `"non_korean"` from Section 3.1 (Issue 2.4)

Remove the `"non_korean"` row from the composition state table. Future CJK engines will define their own language-prefixed states (e.g., `ja_kana_composing`, `zh_pinyin_input`) — a generic placeholder is unnecessary.

## Change 2: Remove `"empty"` from Section 3.1 and update PreeditStart (Issue 2.5b)

- Remove the `"empty"` row from the composition state table in Section 3.1.
- In PreeditStart (Section 2.1): remove `"composition_state": "empty"` from the JSON example and field table. Add note: "The first PreeditUpdate carries the initial composition state."
- In Section 3.3 transition table: replace all `empty` state labels with `null`.
- In Section 11.1 error recovery: change "Reset composition state to `empty`" to "Reset composition state to `null` (no active composition)".
- When no composition is active, `composition_state` is `null` (omitted from JSON). This is the canonical representation.

## Change 3: Update Section 3.1 naming convention cross-reference (Issue 2.1)

Add a note referencing IME Interface Contract Section 3.7 for the normative naming convention:
- ISO 639-1 prefix for single-state-graph languages (`ko_`, `ja_`)
- `{iso639}_{method}_` for languages with distinct state graphs per input method (`zh_pinyin_`, `zh_bopomofo_`, `zh_cangjie_`)

Update `ko_vowel_only` description to note 2-set vs 3-set reachability difference.

## Change 4: Fix Section 15 Open Questions (Issue 2.1)

Open Question #1 uses unprefixed composition state names (`romaji_input`, `pinyin_input`) and says "enum values". Update to:
- Use prefixed names: `ja_kana_composing`, `ja_clause_segment`, `ja_candidate_selection`, `zh_pinyin_input`, `zh_pinyin_candidate_selection`, `zh_bopomofo_initial`, `zh_bopomofo_tone`, `zh_bopomofo_candidate_selection`
- Change "enum values" to "string constants"
- Change "composition_state enum" to "composition_state string"
