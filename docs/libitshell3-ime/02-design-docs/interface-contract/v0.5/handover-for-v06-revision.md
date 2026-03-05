# Handover: IME Interface Contract v0.5 -> v0.6 Revision

> **Date**: 2026-03-05
> **Author**: principal-architect
> **Target**: v0.6 revision team
> **Prerequisite reading**: `review-notes-01.md` (in `v0.4/` directory -- the issues that drove this revision)

---

## 1. What v0.5 Accomplished

v0.5 resolved all 5 open issues from the v0.4 review notes, plus an owner-raised follow-up on Traditional vs Simplified Chinese. Three required team discussion (3-0 unanimous consensus on all); two were mechanical fixes.

### 1.1 Composition State Prefix Convention Formalized (Issue 2.1)

**Decision: Hybrid C/D -- ISO 639-1 default, method-based where state graphs diverge.**

Normative rule added to Section 3.7: when a language has exactly one composition state graph shared by all its input method variants, use ISO 639-1 prefix (`ko_`, `ja_`). When a language has multiple input methods with distinct composition state graphs, use `{iso639}_{method}_` prefix (`zh_pinyin_`, `zh_bopomofo_`, `zh_cangjie_`). The discriminating factor is the composition model, not the region or locale.

Concrete application table added:

| Language | Prefix | Rationale |
|----------|--------|-----------|
| Korean | `ko_` (unchanged) | One state graph for all variants (2-set, 3-set, romaja, etc.) |
| Japanese | `ja_` | One state graph expected |
| Chinese Pinyin | `zh_pinyin_` | Distinct state graph from Bopomofo/Cangjie |
| Chinese Bopomofo | `zh_bopomofo_` | Distinct state graph |
| Chinese Cangjie | `zh_cangjie_` | Distinct state graph |

**Traditional vs Simplified clarification** (owner follow-up): When the same input method supports multiple character sets (e.g., Pinyin for both Traditional and Simplified Chinese), the composition state prefix reflects the state graph, not the character set. Character set selection is a configuration parameter of the engine, distinguished by the `input_method` identifier (e.g., `"chinese_pinyin_traditional"` vs `"chinese_pinyin_simplified"`), not by the composition state prefix.

Key evidence: libhangul's `HangulInputContext` uses the same 3-slot buffer (choseong/jungseong/jongseong) regardless of keyboard layout -- layout only changes the key-to-jamo mapping table. Chinese Pinyin/Bopomofo/Cangjie have genuinely distinct state vocabularies (zero shared states). Pinyin-Traditional and Pinyin-Simplified share the same state graph (only the candidate dictionary differs).

**Impact**: Zero `ko_` constants renamed. Settled decision preserved.

### 1.2 `"non_korean"` Removed from Protocol Doc 05 (Issue 2.4)

Removed the `"non_korean"` row from protocol doc 05 Section 3.1. A generic placeholder contradicts the method-based prefix convention -- future engines will define their own prefixed composition states (`ja_kana_composing`, `zh_pinyin_input`, etc.), never a catch-all `"non_korean"`.

### 1.3 `ko_vowel_only` Reachability Documented (Issue 2.5a)

Added reachability note to Section 3.7: `ko_vowel_only` is produced in 3-set (Sebeolsik) layouts where consonant and vowel keys are physically separated. In 2-set (Dubeolsik, v1 default), libhangul inserts an implicit leading consonant, producing `ko_syllable_no_tail` instead. The scenario matrix illustrates 2-set behavior and is not exhaustive.

### 1.4 `CompositionStates.empty` Removed (Issue 2.5b)

Removed `pub const empty = "empty"` from `CompositionStates`. `ImeResult.composition_state = null` is the canonical representation for no active composition. Having both `null` and `"empty"` was a bug surface (callers would need to check both). Also removed `"empty"` from protocol doc 05 Section 3.1 state table, PreeditStart JSON example, Section 3.3 transition table, and Section 11.1 error recovery prose.

### 1.5 Mechanical Fixes (Issues 2.2, 2.3)

- **Issue 2.2**: Added `deactivate()` to the ImeResult doc comment invalidation list (Section 3.2, line 195). Was already present in Section 6 (Memory Ownership).
- **Issue 2.3**: Fixed broken cross-reference in Appendix E.9: `[F.6]` corrected to `[F.5]` (Session Persistence Simplified).

### 1.6 Verification Fixes (found during cross-verification)

Three additional issues found and fixed during the cross-verification round:
- **V-1**: Broken anchor in Section 3.7 `ko_vowel_only` note: `#32-imeresult-orthogonality-scenario-matrix` corrected to `#32-imeresult-output-from-ime`.
- **V-2**: Protocol doc 05 Section 11.1: residual `empty` reference in error recovery prose corrected to `null`.
- **V-3**: Protocol doc 05 Section 15 Open Questions: unprefixed state names and "enum" terminology updated to use prefixed names per the naming convention and "string constants" terminology.

All changes documented in Appendix G of the contract.

---

## 2. Open Items for v0.6

### 2.1 Section 10 Open Questions (carried forward)

Four open questions remain in Section 10 of the contract. None block v1 implementation:

1. **Hanja key in Korean** -- deferred beyond v1 (uses candidate callback from Section 7)
2. **Dead keys for European languages** -- deferred (separate engine implementation)
3. **Multiple simultaneous modes (per-pane vs global)** -- per-pane only for v1
4. **macOS client OS IME suppression** -- client-app concern, documented for completeness

No action required unless the team wants to promote any of these into v1 scope.

### 2.2 No New Design Issues Surfaced

The v0.5 review cycle resolved all outstanding issues cleanly. No new design questions were raised during discussion or cross-verification. The contract is stable for implementation.

### 2.3 Potential Future Review Triggers

These are not open items but situations that would trigger a v0.6 revision:

- **Implementation begins**: Actual Zig code may reveal edge cases not covered by the spec (e.g., libhangul buffer behavior under rapid keystroke bursts, exact preedit_changed semantics for compound operations).
- **3-set layout support**: When 3-set keyboard layouts are implemented (Phase 7), verify that `ko_vowel_only` transitions behave as documented.
- **Chinese/Japanese engine design**: When Chinese or Japanese engines are designed, the composition state prefix convention and candidate callback design (Section 7) will need to be exercised against real requirements.

---

## 3. Protocol Doc Coordination Note

Protocol doc 05 (`05-cjk-preedit-protocol.md`) was updated as part of this revision round:

| Change | Location | Issue |
|--------|----------|-------|
| `"non_korean"` row removed | Section 3.1 state table | Issue 2.4 |
| `"empty"` row removed | Section 3.1 state table | Issue 2.5b |
| PreeditStart `composition_state` field removed | Section 2.1 | Issue 2.5b |
| Transition table `empty` -> `null` | Section 3.3 | Issue 2.5b (verification fix V-2) |
| Error recovery `empty` -> `null` | Section 11.1 | Issue 2.5b (verification fix V-2) |
| Naming convention cross-reference added | Section 3.1 | Issue 2.1 |
| `ko_vowel_only` 2-set/3-set note added | Section 3.1 | Issue 2.5a |
| Open Questions prefixed names + terminology | Section 15 | Verification fix V-3 |

The protocol team should be aware that protocol doc 05 v0.5 now references IME contract Section 3.7 as the normative source for composition state naming conventions.

---

## 4. File Locations

### IME Contract

| Document | Path |
|----------|------|
| IME contract v0.5 (current) | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.5/01-interface-contract.md` |
| Review notes (resolved) | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.4/review-notes-01.md` |
| This handover | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.5/handover-for-v06-revision.md` |

### Protocol Docs (v0.5, cross-reference targets)

| Document | Path |
|----------|------|
| Protocol doc 05 (CJK preedit) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/05-cjk-preedit-protocol.md` |
| Protocol doc 04 (input/renderstate) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/04-input-and-renderstate.md` |
| Protocol doc 06 (flow control) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/06-flow-control-and-auxiliary.md` |

### Earlier Artifacts

| Document | Path |
|----------|------|
| v0.4 contract | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.4/01-interface-contract.md` |
| v0.4 handover | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.4/handover-for-v05-revision.md` |
| v0.4 identifier consensus handover | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.4/handover-identifier-consensus.md` |
| v0.3 cross-review notes (IME side) | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.3/review-notes-cross-review.md` |
| v0.3 cross-review notes (protocol side) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.4/review-notes-cross-review-ime.md` |

### PoC

| Document | Path |
|----------|------|
| PoC source | `poc/ime-ghostty-real/poc-ghostty-real.m` |
| PoC findings | `poc/ime-ghostty-real/FINDINGS.md` |
