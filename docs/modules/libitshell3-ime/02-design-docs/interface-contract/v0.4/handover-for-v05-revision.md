# Handover: IME Interface Contract v0.4 -> v0.5 Revision

> **Date**: 2026-03-05
> **Author**: ime-expert
> **Target**: v0.5 revision team
> **Prerequisite reading**: `review-notes-01.md` (same directory)

---

## 1. What v0.4 Accomplished

v0.4 applied two batches of changes on top of v0.3:

**Batch 1 -- Cross-review resolutions (v0.3 -> v0.4-pre):**
Applied 10 changes from the cross-document review between Protocol v0.4 and IME Contract v0.3. Key additions: `HID_KEYCODE_MAX` constant, wire-to-KeyEvent mapping cross-reference, CapsLock/NumLock intentional omission note, `composition_state` field in ImeResult, `CompositionStates` string constants with `ko_` prefix, scenario matrix expansion, discard-and-switch pattern, session persistence fields. See Appendix E in the contract for full details.

**Batch 2 -- Identifier consensus (v0.4-pre -> v0.4):**
Resolved the `LanguageId` enum + `layout_id` pair vs. single protocol string inconsistency. 10 consensus decisions, 25 edits applied. Key results: `LanguageId` enum removed from public API, `layout_id` removed from public API, vtable methods renamed (`getActiveInputMethod`/`setActiveInputMethod`), canonical input method registry table added to Section 3.7, session persistence simplified to single `input_method` field. See Appendix F in the contract and `handover-identifier-consensus.md` for full details.

**Bug fixed:** The `"korean_3set_390" -> "3f"` mapping error (should be `"39"`) was eliminated by moving the mapping into the engine's `libhangulKeyboardId()` function.

---

## 2. Open Items for v0.5

### 2.1 Composition State Prefix Convention (review-notes-01, Issue 01) -- NEEDS TEAM DISCUSSION

**Priority: Medium -- must resolve before adding any Chinese or Japanese composition states**

The current contract uses ISO 639-1 two-letter codes as composition state prefixes (e.g., `ko_leading_jamo`). Chinese has two major IME families (Pinyin for `zh-CN`, Bopomofo for `zh-TW`) with entirely different composition state graphs. Using `zh_` for both would cause namespace collision.

Four options were identified in review-notes-01:

| Option | Approach | Korean impact |
|--------|----------|---------------|
| A | ISO 639-1 throughout (`ko_`, `zh_`, `ja_`) | None, but Chinese collides |
| B | BCP 47 throughout (`ko-KR_`, `zh-CN_`, `zh-TW_`) | Rename all `ko_` constants |
| C | ISO 639-1 default, BCP 47 where ambiguous | `ko_` unchanged, Chinese uses `zh-CN_`/`zh-TW_` |
| D | Language-plus-method prefix (`ko_2set_`, `zh_pinyin_`) | Rename all `ko_` constants |

**Constraints:**
- The `ko_` prefix is a settled decision. Any rename requires explicit justification.
- `composition_state` is `?[]const u8` compared by string equality. Prefix changes affect all callers.

**Participants needed:** ime-expert, principal-architect, cjk-specialist.

**Decision questions:**
1. Which option strikes the right balance?
2. If Option B or D is chosen, is the rename cost justified?
3. Are there languages beyond Chinese where ISO 639-1 is insufficient before v2?

### 2.2 ImeResult Doc Comment Missing `deactivate()` (review-notes-01, Issue 02)

**Priority: Medium -- correctness issue**

The ImeResult doc comment (Section 3.2, line ~193) lists invalidating calls as: `processKey()`, `flush()`, `reset()`, `setActiveInputMethod()`. It is missing `deactivate()`. Section 6 (Memory Ownership) correctly includes `deactivate()` in the same list.

**Fix:** Add `deactivate()` to the ImeResult doc comment. This is mechanical -- no design discussion needed.

### 2.3 Broken Cross-Reference in Appendix E.9 (review-notes-01, Issue 03)

**Priority: Low -- broken anchor only**

Appendix E.9 links to `[F.6](#f6-session-persistence-simplified)` but session persistence simplification is actually in F.5. F.6 is "setActiveInputMethod String Parameter Ownership."

**Fix:** Change the link to `[F.5](#f5-session-persistence-simplified)`. Mechanical fix.

### 2.4 `"non_korean"` in Protocol Doc 05 but Not in IME Contract (review-notes-01, Issue 04)

**Priority: Low -- cross-doc issue, no v1 runtime impact**

Protocol doc 05 Section 3.1 defines 7 composition state values, including `"non_korean"`. The IME contract's `CompositionStates` struct defines only 6 -- `"non_korean"` is absent. No v1 engine produces this value.

**Options:**
1. Add `"(reserved, v2+)"` annotation in protocol doc 05.
2. Remove `"non_korean"` from protocol doc 05 -- future CJK engines will define language-prefixed states (e.g., `ja_hiragana_pending`), making a generic placeholder unnecessary.

**Note:** The fix belongs in protocol doc 05, not in the IME contract. Coordinate with the protocol team.

### 2.5 `ko_vowel_only` and `CompositionStates.empty` Defined but Unreachable (review-notes-01, Issue 05)

**Priority: Negligible -- spec hygiene**

Two defined constants never appear as target states in any transition table:

1. **`ko_vowel_only`**: The transition `empty + vowel` goes directly to `ko_syllable_no_tail` (libhangul inserts implicit leading `ㅇ`), skipping `ko_vowel_only`. This may be reachable in edge cases not covered by the simplified transition table.

2. **`CompositionStates.empty`**: Defined as `"empty"` but the ImeResult spec consistently uses `null` for "no active composition." The distinction between `"empty"` and `null` is undocumented.

**Decision needed:**
1. Are these intentionally reserved for edge cases?
2. Should `CompositionStates.empty` be clarified as engine-internal only, with a note that `ImeResult.composition_state` uses `null` for "no composition"?

### 2.6 Section 10 Open Questions (carried forward from v0.3)

Four open questions remain in Section 10 of the contract. These do not block v0.5 but should be reviewed for any scope changes:

1. **Hanja key in Korean** -- deferred beyond v1 (uses candidate callback from Section 7)
2. **Dead keys for European languages** -- deferred (separate engine implementation)
3. **Multiple simultaneous modes (per-pane vs global)** -- per-pane only for v1
4. **macOS client OS IME suppression** -- client-app concern, documented for completeness

No action required unless the team wants to promote any of these into v1 scope.

---

## 3. Recommended v0.5 Workflow

1. **Mechanical fixes first** (Issues 2.2, 2.3): Apply the two trivial corrections before any discussion.
2. **Team discussion on prefix convention** (Issue 2.1): This is the substantive design question. Have the three-person team (ime-expert, principal-architect, cjk-specialist) debate the four options and reach consensus.
3. **Cross-doc coordination** (Issue 2.4): Once prefix convention is decided, coordinate with the protocol team on `"non_korean"` disposition.
4. **Spec hygiene** (Issue 2.5): Clarify or remove unreachable states based on the prefix convention outcome.
5. **Cross-verification round**: After all changes are applied, run a fresh cross-doc verification pass with the protocol v0.5 docs.

---

## 4. File Locations

### IME Contract

| Document | Path |
|----------|------|
| IME contract v0.4 (current) | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.4/01-interface-contract.md` |
| Review notes (open issues) | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.4/review-notes-01.md` |
| Identifier consensus handover | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.4/handover-identifier-consensus.md` |
| This handover | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.4/handover-for-v05-revision.md` |

### Protocol Docs (v0.5, cross-reference targets)

| Document | Path |
|----------|------|
| Protocol doc 04 (input/renderstate) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.5/04-input-and-renderstate.md` |
| Protocol doc 05 (CJK preedit) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.5/05-cjk-preedit-protocol.md` |
| Protocol doc 06 (flow control) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.5/06-flow-control-and-auxiliary.md` |

### Earlier Review Artifacts

| Document | Path |
|----------|------|
| v0.3 cross-review notes (IME side) | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.3/review-notes-cross-review.md` |
| v0.3 cross-review notes (protocol side) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/review-notes-cross-review-ime.md` |
| v0.3 review report | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.3/review-report.md` |
| v0.3 handover | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.3/handover-for-v04-revision.md` |

### PoC

| Document | Path |
|----------|------|
| PoC source | `poc/ime-ghostty-real/poc-ghostty-real.m` |
| PoC findings | `poc/ime-ghostty-real/FINDINGS.md` |
